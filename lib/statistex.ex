defmodule Statistex do
  @moduledoc """
  Calculate all the statistics for given samples.

  Works all at once with `statistics/1` or has a lot of functions that can be triggered individually.

  To avoid wasting computation, function can be given values they depend on as optional keyword arguments so that these values can be used instead of recalculating them. For an example see `average/2`.

  Most statistics don't really make sense when there are no samples, for that reason all functions except for `sample_size/1` raise `ArgumentError` when handed an empty list.
  It is suggested that if it's possible for your program to throw an empty list at Statistex to handle that before handing it to Staistex to take care of the "no reasonable statistics" path entirely separately.

  Limitations of ther erlang standard library apply (particularly `:math.pow/2` raises for VERY large numbers).
  """

  alias Statistex.{Mode, Percentile}
  require Integer

  import Statistex.Helper, only: [maybe_sort: 2]

  defstruct [
    :total,
    :average,
    :m2,
    :variance,
    :standard_deviation,
    :standard_deviation_ratio,
    :median,
    :percentiles,
    :frequency_distribution,
    :mode,
    :minimum,
    :maximum,
    :lower_outlier_bound,
    :upper_outlier_bound,
    :outliers,
    sample_size: 0
  ]

  @typedoc """
  All the statistics `statistics/1` computes from the samples.

  For a description of what a given value means please check out the function here by the same name, it will have an explanation.
  """
  @type t :: %__MODULE__{
          total: number,
          average: float,
          m2: float,
          variance: float,
          standard_deviation: float,
          standard_deviation_ratio: float,
          median: number,
          percentiles: percentiles,
          frequency_distribution: %{sample => pos_integer},
          mode: mode,
          minimum: number,
          maximum: number,
          lower_outlier_bound: number,
          upper_outlier_bound: number,
          outliers: [number],
          sample_size: non_neg_integer
        }

  @typedoc """
  The samples to compute statistics from.

  Importantly this list is not empty/includes at least one sample otherwise an `ArgumentError` will be raised.
  """
  @type samples :: [sample, ...]

  @typedoc """
  A single sample/
  """
  @type sample :: number

  @typedoc """
  The optional configuration handed to a lot of functions.

  Keys used are function dependent and are documented there.
  """
  @type configuration :: keyword

  @typedoc """
  Careful with the mode, might be multiple values, one value or nothing.😱 See `mode/1`.
  """
  @type mode :: [sample()] | sample() | nil

  @typedoc """
  The percentiles map returned by `percentiles/2`.
  """
  @type percentiles :: %{number() => float}

  @empty_list_error_message "Passed an empty list ([]) to calculate statistics from, please pass a list containing at least one number."

  @first_quartile 25
  @median_percentile 50
  @third_quartile 75
  # https://en.wikipedia.org/wiki/Interquartile_range#Outliers
  # https://builtin.com/articles/1-5-iqr-rule
  @iqr_factor 1.5

  @doc """
  Calculate all statistics Statistex offers for a given list of numbers.

  The statistics themselves are described in the individual samples that can be used to calculate individual values.

  `ArgumentError` is raised if the given list is empty.

  ## Options

  * `:percentiles`: percentiles to calculate (see `percentiles/2`).
  The percentiles 25th, 50th (median) and 75th are always calculated.
  * `:exclude_outliers` can be set to `true` or `false`. Defaults to `false`.
  If this option is set to `true` the outliers are excluded from the calculation
  of the statistics.
  * `:sorted?`: indicating the samples you're passing in are already sorted. Defaults to `false`. Only set this,
  if they are truly sorted - otherwise your results will be wrong.

  ## Examples

      iex> Statistex.statistics([50, 50, 450, 450, 450, 500, 500, 500, 600, 900])
      %Statistex{
        total: 4450,
        average: 445.0,
        m2: 552250.0,
        variance: 61_361.11111111111,
        standard_deviation: 247.71175004652304,
        standard_deviation_ratio: 0.5566556180820742,
        median: 475.0,
        percentiles: %{25 => 350.0, 50 => 475.0, 75 => 525.0},
        frequency_distribution: %{50 => 2, 450 => 3, 500 => 3, 600 => 1, 900 => 1},
        mode: [500, 450],
        minimum: 50,
        maximum: 900,
        lower_outlier_bound: 87.5,
        upper_outlier_bound: 787.5,
        outliers: [50, 50, 900],
        sample_size: 10
      }

      # excluding outliers changes the results
      iex> Statistex.statistics([50, 50, 450, 450, 450, 500, 500, 500, 600, 900], exclude_outliers: true)
      %Statistex{
        total: 3450,
        average: 492.85714285714283,
        m2: 17142.857142857145,
        variance: 2857.1428571428573,
        standard_deviation: 53.45224838248488,
        standard_deviation_ratio: 0.10845383729779542,
        median: 500.0,
        percentiles: %{25 => 450.0, 50 => 500.0, 75 => 500.0},
        frequency_distribution: %{450 => 3, 500 => 3, 600 => 1},
        mode: [500, 450],
        maximum: 600,
        minimum: 450,
        lower_outlier_bound: 87.5,
        upper_outlier_bound: 787.5,
        outliers: [50, 50, 900],
        sample_size: 7
      }

      iex> Statistex.statistics([])
      ** (ArgumentError) Passed an empty list ([]) to calculate statistics from, please pass a list containing at least one number.

  """
  @spec statistics(samples, configuration) :: t()
  def statistics(samples, configuration \\ [])

  def statistics([], _) do
    raise(ArgumentError, @empty_list_error_message)
  end

  def statistics(samples, configuration) do
    sorted_samples = maybe_sort(samples, configuration)

    percentiles = calculate_percentiles(sorted_samples, configuration)
    outlier_bounds = outlier_bounds(sorted_samples, percentiles: percentiles)

    # rest remains sorted here/it's an important property
    {outliers, rest} = outliers(sorted_samples, outlier_bounds: outlier_bounds)

    if exclude_outliers?(configuration) and Enum.any?(outliers) do
      # need to recalculate with the outliers removed
      percentiles = calculate_percentiles(rest, configuration)

      create_full_statistics(rest, percentiles, outliers, outlier_bounds)
    else
      create_full_statistics(sorted_samples, percentiles, outliers, outlier_bounds)
    end
  end

  defp exclude_outliers?(configuration) do
    Access.get(configuration, :exclude_outliers) == true
  end

  defp create_full_statistics(sorted_samples, percentiles, outliers, outlier_bounds) do
    total = total(sorted_samples)
    sample_size = length(sorted_samples)
    minimum = hd(sorted_samples)
    maximum = List.last(sorted_samples)

    average = average(sorted_samples, total: total, sample_size: sample_size)
    m2 = m2(sorted_samples)
    variance = variance(sorted_samples, sample_size: sample_size, m2: m2)

    frequency_distribution = frequency_distribution(sorted_samples)

    standard_deviation = standard_deviation(sorted_samples, variance: variance)

    standard_deviation_ratio =
      standard_deviation_ratio(sorted_samples, standard_deviation: standard_deviation)

    {lower_outlier_bound, upper_outlier_bound} = outlier_bounds

    %__MODULE__{
      total: total,
      average: average,
      m2: m2,
      variance: variance,
      standard_deviation: standard_deviation,
      standard_deviation_ratio: standard_deviation_ratio,
      median: median(sorted_samples, percentiles: percentiles),
      percentiles: percentiles,
      frequency_distribution: frequency_distribution,
      mode: mode(sorted_samples, frequency_distribution: frequency_distribution),
      minimum: minimum,
      maximum: maximum,
      lower_outlier_bound: lower_outlier_bound,
      upper_outlier_bound: upper_outlier_bound,
      outliers: outliers,
      sample_size: sample_size
    }
  end

  @doc """
  The total of all samples added together.

  `Argumenterror` is raised if the given list is empty.

  ## Examples

      iex> Statistex.total([1, 2, 3, 4, 5])
      15

      iex> Statistex.total([10, 10.5, 5])
      25.5

      iex> Statistex.total([-10, 5, 3, 2])
      0

      iex> Statistex.total([])
      ** (ArgumentError) Passed an empty list ([]) to calculate statistics from, please pass a list containing at least one number.
  """
  @spec total(samples) :: number
  def total([]), do: raise(ArgumentError, @empty_list_error_message)
  def total(samples), do: Enum.sum(samples)

  @doc """
  Number of samples in the given list.

  Nothing to fancy here, this just calls `length(list)` and is only provided for completeness sake.

  ## Examples

      iex> Statistex.sample_size([])
      0

      iex> Statistex.sample_size([1, 1, 1, 1, 1])
      5
  """
  @spec sample_size([sample]) :: non_neg_integer
  def sample_size(samples), do: length(samples)

  @doc """
  Calculate the average.

  It's.. well the average.
  When the given samples are empty there is no average.

  `Argumenterror` is raised if the given list is empty.

  ## Options
  If you already have these values, you can provide both `:total` and `:sample_size`. Should you provide both the provided samples are wholly ignored.

  ## Examples

      iex> Statistex.average([5])
      5.0

      iex> Statistex.average([600, 470, 170, 430, 300])
      394.0

      iex> Statistex.average([-1, 1])
      0.0

      iex> Statistex.average([2, 3, 4], sample_size: 3)
      3.0

      iex> Statistex.average([20, 20, 20, 20, 20], total: 100, sample_size: 5)
      20.0

      iex> Statistex.average(:ignored, total: 100, sample_size: 5)
      20.0

      iex> Statistex.average([])
      ** (ArgumentError) Passed an empty list ([]) to calculate statistics from, please pass a list containing at least one number.
  """
  @spec average(samples | :ignored, keyword) :: float
  def average(samples, options \\ [])
  def average([], _), do: raise(ArgumentError, @empty_list_error_message)

  def average(samples, options) do
    total = Keyword.get_lazy(options, :total, fn -> total(samples) end)
    sample_size = Keyword.get_lazy(options, :sample_size, fn -> sample_size(samples) end)

    total / sample_size
  end

  @doc """
  Calculate the running sum of squared differences from the current mean.

  This value is only used when trying to calculate the variance in a single pass, using Welford's online algorithm.

  `Argumenterror` is raised if the given list is empty.

  ## Options

  If are performing single-pass variance, you can calculate a new M2 for a single data point by providing your single data point, along with the previous `:sample_size`, `:m2`, and either the `:average` or `:total`. See `StatistexTest` for an example of how this can be done.

  If calculating M2 over your entire dataset, do supply any options (do not use `:total` or `:average` that were previously calculated) or your result will be wrong.

  ## Examples

      iex> Statistex.m2([10])
      0.0

      iex> Statistex.m2([10, 20])
      50.0

      iex> Statistex.m2([10, 20, 30])
      200.0

      iex> Statistex.m2(30, sample_size: 2, m2: 50.0, average: 15.0)
      200.0

      iex> Statistex.m2([])
      ** (ArgumentError) Passed an empty list ([]) to calculate statistics from, please pass a list containing at least one number.
  """
  @spec m2(samples | sample, keyword) :: float
  def m2(samples, options \\ [])
  def m2([], _), do: raise(ArgumentError, @empty_list_error_message)

  def m2(samples, options) when is_list(samples) do
    count = Keyword.get(options, :sample_size, 0)
    m2 = Keyword.get(options, :m2, 0.0)
    total = Keyword.get(options, :total, 0.0)

    mean =
      case {count, total} do
        {0, 0.0} ->
          0

        {0, 0} ->
          0

        _ ->
          Keyword.get_lazy(options, :average, fn ->
            average(:ignored, sample_size: count, total: total)
          end)
      end

    do_m2(samples, count, mean, m2)
  end

  def m2(sample, options) do
    m2([sample], options)
  end

  defp do_m2([], _, _, m2), do: m2

  defp do_m2([sample | rest], count, mean, m2) do
    count = count + 1
    delta = sample - mean
    mean = mean + delta / count
    delta2 = sample - mean
    m2 = m2 + delta * delta2
    do_m2(rest, count, mean, m2)
  end

  @doc """
  Calculate the variance.

  A measurement how much samples vary (the higher the more the samples vary). This is the variance of a sample and is hence in its calculation divided by sample_size - 1 (Bessel's correction).

  `Argumenterror` is raised if the given list is empty.

  ## Options
  If already calculated, the `:sample_size` and `:m2` options can be provided to avoid recalulating those values. Should you provide both the provided samples are wholly ignored.

  ## Examples

      iex> Statistex.variance([4, 9, 11, 12, 17, 5, 8, 12, 12])
      16.0

      iex> Statistex.variance([4, 9, 11, 12, 17, 5, 8, 12, 12], sample_size: 9, average: 10.0)
      16.0

      iex> Statistex.variance([42])
      0.0

      iex> Statistex.variance([1, 1, 1, 1, 1, 1, 1])
      0.0

      iex> Statistex.variance([])
      ** (ArgumentError) Passed an empty list ([]) to calculate statistics from, please pass a list containing at least one number.
  """
  @spec variance(samples | :ignored, keyword) :: float
  def variance(samples, options \\ [])
  def variance([], _), do: raise(ArgumentError, @empty_list_error_message)

  def variance(samples, options) do
    sample_size = Keyword.get_lazy(options, :sample_size, fn -> sample_size(samples) end)

    m2 = Keyword.get_lazy(options, :m2, fn -> m2(samples) end)

    do_variance(sample_size, m2)
  end

  defp do_variance(1, _m2), do: 0.0

  defp do_variance(sample_size, m2) do
    m2 / (sample_size - 1)
  end

  @doc """
  Calculate the standard deviation.

  A measurement how much samples vary (the higher the more the samples vary). It's the square root of the variance. Unlike the variance, its unit is the same as that of the sample (as calculating the variance includes squaring).

  ## Options
  If already calculated, the `:variance` option can be provided to avoid recalulating those values.

  `Argumenterror` is raised if the given list is empty.

  ## Examples

      iex> Statistex.standard_deviation([4, 9, 11, 12, 17, 5, 8, 12, 12])
      4.0

      iex> Statistex.standard_deviation(:dontcare, variance: 16.0)
      4.0

      iex> Statistex.standard_deviation([42])
      0.0

      iex> Statistex.standard_deviation([1, 1, 1, 1, 1, 1, 1])
      0.0

      iex> Statistex.standard_deviation([])
      ** (ArgumentError) Passed an empty list ([]) to calculate statistics from, please pass a list containing at least one number.
  """
  @spec standard_deviation(samples | :ignored, keyword) :: float
  def standard_deviation(samples, options \\ [])
  def standard_deviation([], _), do: raise(ArgumentError, @empty_list_error_message)

  def standard_deviation(samples, options) do
    variance = Keyword.get_lazy(options, :variance, fn -> variance(samples) end)
    :math.sqrt(variance)
  end

  @doc """
    Calculate the standard deviation relative to the average.

    This helps put the absolute standard deviation value into perspective expressing it relative to the average. It's what percentage of the absolute value of the average the variance takes.

    `Argumenterror` is raised if the given list is empty.

    ## Options
    If already calculated, the `:average` and `:standard_deviation` options can be provided to avoid recalulating those values.

    If both values are provided, the provided samples will be ignored.

    ## Examples

        iex> Statistex.standard_deviation_ratio([4, 9, 11, 12, 17, 5, 8, 12, 12])
        0.4

        iex> Statistex.standard_deviation_ratio([-4, -9, -11, -12, -17, -5, -8, -12, -12])
        0.4

        iex> Statistex.standard_deviation_ratio([4, 9, 11, 12, 17, 5, 8, 12, 12], average: 10.0, standard_deviation: 4.0)
        0.4

        iex> Statistex.standard_deviation_ratio(:ignored, average: 10.0, standard_deviation: 4.0)
        0.4

        iex> Statistex.standard_deviation_ratio([])
        ** (ArgumentError) Passed an empty list ([]) to calculate statistics from, please pass a list containing at least one number.
  """
  @spec standard_deviation_ratio(samples | :ignored, keyword) :: float
  def standard_deviation_ratio(samples, options \\ [])
  def standard_deviation_ratio([], _), do: raise(ArgumentError, @empty_list_error_message)

  def standard_deviation_ratio(samples, options) do
    average = Keyword.get_lazy(options, :average, fn -> average(samples) end)

    std_dev =
      Keyword.get_lazy(options, :standard_deviation, fn ->
        standard_deviation(samples, average: average)
      end)

    if average == 0 do
      0.0
    else
      abs(std_dev / average)
    end
  end

  defp calculate_percentiles(sorted_samples, configuration) do
    percentiles_configuration = Keyword.get(configuration, :percentiles, [])

    # median_percentile is manually added so that it can be used directly by median
    percentiles_configuration =
      Enum.uniq([
        @first_quartile,
        @median_percentile,
        @third_quartile | percentiles_configuration
      ])

    Percentile.percentiles(sorted_samples, percentiles_configuration, sorted: true)
  end

  @doc """
  Calculates the value at the `percentile_rank`-th percentile.

  Think of this as the value below which `percentile_rank` percent of the samples lie.
  For example, if `Statistex.percentile(samples, 99) == 123.45`,
  99% of samples are less than 123.45.

  Passing a number for `percentile_rank` calculates a single percentile.
  Passing a list of numbers calculates multiple percentiles, and returns them
  as a map like %{90 => 45.6, 99 => 78.9}, where the keys are the percentile
  numbers, and the values are the percentile values.

  Percentiles must be between 0 and 100 (excluding the boundaries).

  The method used for interpolation is [described here and recommended by NIST](https://www.itl.nist.gov/div898/handbook/prc/section2/prc262.htm).

  `Argumenterror` is raised if the given list is empty.

  ## Options

  * `:sorted?`: indicating the samples you're passing in are already sorted. Defaults to `false`. Only set this,
  if they are truly sorted - otherwise your results will be wrong.

  ## Examples

      iex> Statistex.percentiles([5, 3, 4, 5, 1, 3, 1, 3], 12.5)
      %{12.5 => 1.0}

      iex> Statistex.percentiles([1, 1, 3, 3, 3, 4, 5, 5], 12.5, sorted?: true)
      %{12.5 => 1.0}

      iex> Statistex.percentiles([5, 3, 4, 5, 1, 3, 1, 3], [50])
      %{50 => 3.0}

      iex> Statistex.percentiles([5, 3, 4, 5, 1, 3, 1, 3], [75])
      %{75 => 4.75}

      iex> Statistex.percentiles([5, 3, 4, 5, 1, 3, 1, 3], 99)
      %{99 => 5.0}

      iex> Statistex.percentiles([5, 3, 4, 5, 1, 3, 1, 3], [50, 75, 99])
      %{50 => 3.0, 75 => 4.75, 99 => 5.0}

      iex> Statistex.percentiles([5, 3, 4, 5, 1, 3, 1, 3], 100)
      ** (ArgumentError) percentile must be between 0 and 100, got: 100

      iex> Statistex.percentiles([5, 3, 4, 5, 1, 3, 1, 3], 0)
      ** (ArgumentError) percentile must be between 0 and 100, got: 0

      iex> Statistex.percentiles([], [50])
      ** (ArgumentError) Passed an empty list ([]) to calculate statistics from, please pass a list containing at least one number.
  """
  @spec percentiles(samples, number | [number(), ...]) ::
          percentiles()
  defdelegate percentiles(samples, percentiles, options), to: Percentile
  defdelegate percentiles(samples, percentiles), to: Percentile

  @doc """
  A map showing which sample occurs how often in the samples.

  Goes from a concrete occurence of the sample to the number of times it was observed in the samples.

  `Argumenterror` is raised if the given list is empty.

  ## Examples

      iex> Statistex.frequency_distribution([1, 2, 4.23, 7, 2, 99])
      %{
        2 => 2,
        1 => 1,
        4.23 => 1,
        7 => 1,
        99 => 1
      }

      iex> Statistex.frequency_distribution([])
      ** (ArgumentError) Passed an empty list ([]) to calculate statistics from, please pass a list containing at least one number.
  """
  @spec frequency_distribution(samples) :: %{required(sample) => pos_integer}
  def frequency_distribution([]), do: raise(ArgumentError, @empty_list_error_message)

  def frequency_distribution(samples) do
    Enum.reduce(samples, %{}, fn sample, counts ->
      Map.update(counts, sample, 1, fn old_value -> old_value + 1 end)
    end)
  end

  @doc """
  Calculates the mode of the given samples.

  Mode is the sample(s) that occur the most. Often one value, but can be multiple values if they occur the same amount of times. If no value occurs at least twice, there is no mode and it hence returns `nil`.

  `Argumenterror` is raised if the given list is empty.

  ## Options

  If already calculated, the `:frequency_distribution` option can be provided to avoid recalulating it.

  ## Examples

      iex> Statistex.mode([5, 3, 4, 5, 1, 3, 1, 3])
      3

      iex> Statistex.mode([1, 2, 3, 4, 5])
      nil

      # When a measurement failed and nils is reported as the only value
      iex> Statistex.mode([nil])
      nil

      iex> Statistex.mode([])
      ** (ArgumentError) Passed an empty list ([]) to calculate statistics from, please pass a list containing at least one number.

      iex> mode = Statistex.mode([5, 3, 4, 5, 1, 3, 1])
      iex> Enum.sort(mode)
      [1, 3, 5]
  """
  @spec mode(samples, keyword) :: mode
  def mode(samples, opts \\ []), do: Mode.mode(samples, opts)

  @doc """
  Calculates the median of the given samples.

  The median can be thought of separating the higher half from the lower half of the samples.
  When all samples are sorted, this is the middle value (or average of the two middle values when the number of times is even).
  More stable than the average.

  `Argumenterror` is raised if the given list is empty.

  ## Options
  * `:percentiles` - you can pass it a map of calculated percentiles to fetch the median from (it is the 50th percentile).
  If it doesn't include the median/50th percentile - it will still be computed.
  * `:sorted?`: indicating the samples you're passing in are already sorted. Defaults to `false`. Only set this,
  if they are truly sorted - otherwise your results will be wrong. Sorting only occurs when percentiles aren't provided.

  ## Examples

      iex> Statistex.median([1, 3, 4, 6, 7, 8, 9])
      6.0

      iex> Statistex.median([1, 3, 4, 6, 7, 8, 9], percentiles: %{50 => 6.0})
      6.0

      iex> Statistex.median([1, 3, 4, 6, 7, 8, 9], percentiles: %{25 => 3.0})
      6.0

      iex> Statistex.median([1, 3, 4, 6, 7, 8, 9], sorted?: true)
      6.0

      iex> Statistex.median([1, 2, 3, 4, 5, 6, 8, 9])
      4.5

      iex> Statistex.median([0])
      0.0

      iex> Statistex.median([])
      ** (ArgumentError) Passed an empty list ([]) to calculate statistics from, please pass a list containing at least one number.
  """
  @spec median(samples, keyword) :: number
  def median(samples, options \\ [])
  def median([], _), do: raise(ArgumentError, @empty_list_error_message)

  def median(samples, options) do
    percentiles = Access.get(options, :percentiles, %{})

    percentiles =
      case percentiles do
        %{@median_percentile => _} ->
          percentiles

        # missing necessary keys
        %{} ->
          Percentile.percentiles(samples, @median_percentile, options)
      end

    Map.fetch!(percentiles, @median_percentile)
  end

  @doc """
  Calculates the lower and upper bound for outliers.

  Any sample that is `<` as the lower bound and any sample `>` are outliers of
  the given `samples`.

  List passed needs to be non empty, otherwise an `ArgumentError` is raised.

  ## Options
  * `:percentiles` - you can pass it a map of calculated percentiles (25th and 75th are needed).
  If it doesn't include them - it will still be computed.
  * `:sorted?`: indicating the samples you're passing in are already sorted. Defaults to `false`. Only set this,
  if they are truly sorted - otherwise your results will be wrong. Sorting only occurs when percentiles aren't provided.

  ## Examples

      iex> Statistex.outlier_bounds([3, 4, 5])
      {0.0, 8.0}

      iex> Statistex.outlier_bounds([4, 5, 3])
      {0.0, 8.0}

      iex> Statistex.outlier_bounds([3, 4, 5], sorted?: true)
      {0.0, 8.0}

      iex> Statistex.outlier_bounds([3, 4, 5], percentiles: %{25 => 3.0, 75 => 5.0})
      {0.0, 8.0}

      iex> Statistex.outlier_bounds([1, 2, 6, 50, 50, 50, 50, 50, 50, 50, 50, 50, 50, 50])
      {22.5, 66.5}

      iex> Statistex.outlier_bounds([50, 50, 50, 50, 50, 50, 50, 50, 50, 50, 50, 99, 99, 99])
      {31.625, 80.625}

      iex> Statistex.outlier_bounds([])
      ** (ArgumentError) Passed an empty list ([]) to calculate statistics from, please pass a list containing at least one number.
  """
  @spec outlier_bounds(samples, keyword) :: {lower :: number, upper :: number}
  def outlier_bounds(samples, options \\ [])
  def outlier_bounds([], _), do: raise(ArgumentError, @empty_list_error_message)

  def outlier_bounds(samples, options) do
    percentiles = Access.get(options, :percentiles, %{})

    percentiles =
      case percentiles do
        %{@first_quartile => _, @third_quartile => _} ->
          percentiles

        # missing necessary keys
        %{} ->
          Percentile.percentiles(samples, [@first_quartile, @third_quartile], options)
      end

    q1 = Map.fetch!(percentiles, @first_quartile)
    q3 = Map.fetch!(percentiles, @third_quartile)
    iqr = q3 - q1
    outlier_tolerance = iqr * @iqr_factor

    {q1 - outlier_tolerance, q3 + outlier_tolerance}
  end

  @doc """
  Returns all outliers for the given `samples`, along with the remaining values.

  Returns: `{outliers, remaining_samples`} where `remaining_samples` has the outliers removed.

  ## Options
  * `:outlier_bounds` - if you already have calculated the outlier bounds.
  * `:percentiles` - you can pass it a map of calculated percentiles (25th and 75th are needed).
  If it doesn't include them - it will still be computed.
  * `:sorted?`: indicating the samples you're passing in are already sorted. Defaults to `false`. Only set this,
  if they are truly sorted - otherwise your results will be wrong. Sorting only occurs when percentiles aren't provided.

  ## Examples

      iex> Statistex.outliers([3, 4, 5])
      {[], [3, 4, 5]}

      iex> Statistex.outliers([1, 2, 6, 50, 50, 50, 50, 50, 50, 50, 50, 50, 50, 50])
      {[1, 2, 6], [50, 50, 50, 50, 50, 50, 50, 50, 50, 50, 50]}

      iex> Statistex.outliers([50, 50, 1, 50, 50, 50, 50, 50, 2, 50, 50, 50, 50, 6])
      {[1, 2, 6], [50, 50, 50, 50, 50, 50, 50, 50, 50, 50, 50]}

      iex> Statistex.outliers([50, 50, 50, 50, 50, 50, 50, 50, 50, 50, 50, 99, 99, 99])
      {[99, 99, 99], [50, 50, 50, 50, 50, 50, 50, 50, 50, 50, 50]}
  """
  @spec outliers(samples, keyword) :: {samples | [], samples}
  def outliers(samples, options \\ []) do
    {lower_bound, upper_bound} =
      Keyword.get_lazy(options, :outlier_bounds, fn ->
        outlier_bounds(samples, options)
      end)

    Enum.split_with(samples, fn sample -> sample < lower_bound || sample > upper_bound end)
  end

  @doc """
  The biggest sample.

  `Argumenterror` is raised if the given list is empty.

  ## Examples

      iex> Statistex.maximum([1, 100, 24])
      100

      iex> Statistex.maximum([])
      ** (ArgumentError) Passed an empty list ([]) to calculate statistics from, please pass a list containing at least one number.
  """
  @spec maximum(samples) :: sample
  def maximum([]), do: raise(ArgumentError, @empty_list_error_message)
  def maximum(samples), do: Enum.max(samples)

  @doc """
  The smallest sample.

  `Argumenterror` is raised if the given list is empty.

  ## Examples

      iex> Statistex.minimum([1, 100, 24])
      1

      iex> Statistex.minimum([])
      ** (ArgumentError) Passed an empty list ([]) to calculate statistics from, please pass a list containing at least one number.
  """
  @spec minimum(samples) :: sample
  def minimum([]), do: raise(ArgumentError, @empty_list_error_message)
  def minimum(samples), do: Enum.min(samples)
end
