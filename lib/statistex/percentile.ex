defmodule Statistex.Percentile do
  @moduledoc false

  import Statistex.Helper, only: [maybe_sort: 2]

  @spec percentiles(Statistex.samples(), number | [number, ...], keyword()) ::
          Statistex.percentiles()
  def percentiles(samples, percentiles, options \\ [])

  def percentiles([], _, _) do
    raise(
      ArgumentError,
      "Passed an empty list ([]) to calculate statistics from, please pass a list containing at least one number."
    )
  end

  def percentiles(samples, percentile_ranks, options) do
    number_of_samples = length(samples)
    sorted_samples = maybe_sort(samples, options)

    percentile_ranks
    |> List.wrap()
    |> Map.new(fn percentile_rank ->
      perc = percentile(sorted_samples, number_of_samples, percentile_rank)
      {percentile_rank, perc}
    end)
  end

  defp percentile(_, _, percentile_rank) when percentile_rank >= 100 or percentile_rank <= 0 do
    raise ArgumentError, "percentile must be between 0 and 100, got: #{inspect(percentile_rank)}"
  end

  defp percentile(sorted_samples, number_of_samples, percentile_rank) do
    percent = percentile_rank / 100
    rank = percent * (number_of_samples + 1)
    percentile_value(sorted_samples, rank)
  end

  # According to https://www.itl.nist.gov/div898/handbook/prc/section2/prc262.htm
  # the full integer of rank being 0 is an edge case and we simple choose the first
  # element. See clause 2, our rank is k there.
  defp percentile_value(sorted_samples, rank) when rank < 1 do
    [first | _] = sorted_samples
    first
  end

  defp percentile_value(sorted_samples, rank) do
    index = max(0, trunc(rank) - 1)
    {pre_index, post_index} = Enum.split(sorted_samples, index)
    calculate_percentile_value(rank, pre_index, post_index)
  end

  # The common case: interpolate between the two values after the split
  defp calculate_percentile_value(rank, _, [lower_bound, upper_bound | _]) do
    lower_bound + interpolation_value(lower_bound, upper_bound, rank)
  end

  # Nothing to interpolate toward: use the first value after the split
  defp calculate_percentile_value(_, _, [lower_bound]) do
    to_float(lower_bound)
  end

  # Interpolation implemented according to: https://www.itl.nist.gov/div898/handbook/prc/section2/prc262.htm
  #
  # "Type 6" interpolation strategy. There are many ways to interpolate a value
  # when the rank is not an integer (in other words, we don't exactly land on a
  # particular sample). Of the 9 main strategies, (types 1-9), types 6, 7, and 8
  # are generally acceptable and give similar results.
  #
  # R uses type 7, but you can change the strategies used in R with arguments.
  #
  # > quantile(c(9, 9, 10, 10, 10, 11, 12, 36), probs = c(0.25, 0.5, 0.75), type = 6)
  #   25%   50%   75%
  #  9.25 10.00 11.75
  # > quantile(c(9, 9, 10, 10, 10, 11, 12, 36), probs = c(0.25, 0.5, 0.75), type = 7)
  #   25%   50%   75%
  #  9.75 10.00 11.25
  #
  # For more information on interpolation strategies, see:
  # - https://stat.ethz.ch/R-manual/R-devel/library/stats/html/quantile.html
  # - http://www.itl.nist.gov/div898/handbook/prc/section2/prc262.htm
  defp interpolation_value(lower_bound, upper_bound, rank) do
    # in our source rank is k, and interpolation_weight is d
    interpolation_weight = rank - trunc(rank)
    interpolation_weight * (upper_bound - lower_bound)
  end

  defp to_float(maybe_integer) do
    :erlang.float(maybe_integer)
  end
end
