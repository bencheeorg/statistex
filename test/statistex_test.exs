defmodule Statistex.StatistexTest do
  use ExUnit.Case, async: true
  doctest Statistex

  use ExUnitProperties
  import Statistex
  import StreamData

  describe ".median/2" do
    test "if handed percentiles missing the median percentile still calculates it" do
      assert Statistex.median([1, 2, 3, 4, 5, 6, 8, 9], percentiles: %{}) == 4.5
    end
  end

  describe ".outlier_bounds/2" do
    # examples doubled up, maybe get rid of them?
    test "returns outlier bounds for samples without outliers" do
      assert Statistex.outlier_bounds([200, 400, 400, 400, 500, 500, 500, 700, 900]) ==
               {100.0, 900.0}
    end

    test "returns outlier bounds for samples with outliers" do
      assert Statistex.outlier_bounds([50, 50, 450, 450, 450, 500, 500, 500, 600, 900]) ==
               {87.5, 787.5}
    end
  end

  describe ".statistics/2" do
    test "all 0 values do what you think they would" do
      assert Statistex.statistics([0, 0, 0, 0]) == %Statistex{
               average: 0.0,
               variance: 0.0,
               standard_deviation: 0.0,
               standard_deviation_ratio: 0.0,
               median: 0.0,
               percentiles: %{25 => 0.0, 50 => 0.0, 75 => 0.0},
               frequency_distribution: %{0 => 4},
               mode: 0,
               minimum: 0,
               maximum: 0,
               sample_size: 4,
               total: 0,
               outliers: [],
               lower_outlier_bound: 0.0,
               upper_outlier_bound: 0.0
             }
    end

    test "returns Statistex struct without outliers" do
      assert Statistex.statistics([200, 400, 400, 400, 500, 500, 500, 700, 900]) ==
               %Statistex{
                 total: 4500,
                 average: 500.0,
                 variance: 40_000.0,
                 standard_deviation: 200.0,
                 standard_deviation_ratio: 0.4,
                 median: 500.0,
                 percentiles: %{25 => 400.0, 50 => 500.0, 75 => 600.0},
                 frequency_distribution: %{200 => 1, 400 => 3, 500 => 3, 700 => 1, 900 => 1},
                 mode: [500, 400],
                 minimum: 200,
                 maximum: 900,
                 lower_outlier_bound: 100.0,
                 upper_outlier_bound: 900.0,
                 outliers: [],
                 sample_size: 9
               }
    end

    test "returns Statistex struct with outliers" do
      assert Statistex.statistics([50, 50, 450, 450, 450, 500, 500, 500, 600, 900]) ==
               %Statistex{
                 total: 4450,
                 average: 445.0,
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
    end

    # https://www.youtube.com/watch?v=rZJbj2I-_Ek
    test "gets outliers from the sample right" do
      # One could argue that this is controversial, R comes up with these results (by default):
      # > summary(c(9, 9, 10, 10, 10, 11, 12, 36))
      #  Min. 1st Qu.  Median    Mean 3rd Qu.    Max.
      #  9.00    9.75   10.00   13.38   11.25   36.00
      #
      # R by default uses type 7 interpolation, we implemented type 6 interpolation though. Which
      # R can also use:
      # > quantile(c(9, 9, 10, 10, 10, 11, 12, 36), probs = c(0.25, 0.5, 0.75), type = 6)
      # 25%   50%   75%
      # 9.25 10.00 11.75
      # Which is our result.

      assert %Statistex{
               median: 10.0,
               percentiles: %{25 => 9.25, 50 => 10.0, 75 => 11.75},
               minimum: 9,
               maximum: 36,
               lower_outlier_bound: 5.5,
               upper_outlier_bound: 15.5,
               outliers: [36]
             } = Statistex.statistics([9, 9, 10, 10, 10, 11, 12, 36], exclude_outliers: false)
    end

    # https://en.wikipedia.org/wiki/Box_plot#Example_with_outliers
    test "another example with outliers" do
      data = [
        52,
        57,
        57,
        58,
        63,
        66,
        66,
        67,
        67,
        68,
        69,
        70,
        70,
        70,
        70,
        72,
        73,
        75,
        75,
        76,
        76,
        78,
        79,
        89
      ]

      assert %Statistex{
               median: 70.0,
               percentiles: %{25 => 66.0, 50 => 70.0, 75 => 75.0},
               # report interquantile range?
               lower_outlier_bound: 52.5,
               upper_outlier_bound: 88.5,
               outliers: [52, 89]
             } = Statistex.statistics(data, exclude_outliers: false)
    end

    # https://en.wikipedia.org/wiki/Interquartile_range#Data_set_in_a_table
    test "quartile example" do
      assert %Statistex{
               median: 87.0,
               percentiles: %{25 => 31.0, 50 => 87.0, 75 => 119.0}
             } =
               Statistex.statistics([7, 7, 31, 31, 47, 75, 87, 115, 116, 119, 119, 155, 177],
                 exclude_outliers: false
               )
    end
  end

  describe "property testing as we might get loads of data" do
    property "doesn't blow up no matter what kind of nonempty list of floats it's given" do
      check all(samples <- list_of(float(), min_length: 1)) do
        assert_statistics_properties(samples)
      end
    end

    # is milli seconds aka 90s
    @tag timeout: 90_000
    property "with a much bigger list properties still hold" do
      check all(samples <- big_list_big_floats()) do
        assert_statistics_properties(samples)
      end
    end

    defp assert_statistics_properties(samples) do
      stats = statistics(samples)

      assert_basic_statistics(stats)
      assert_mode_in_samples(stats, samples)
      assert_frequencies(stats, samples)
      assert_bounds_and_outliers(stats, samples)

      # shuffling values around shouldn't change the results
      shuffled_stats = samples |> Enum.shuffle() |> statistics()
      assert stats == shuffled_stats
    end

    defp assert_basic_statistics(stats) do
      assert stats.sample_size >= 1
      assert stats.minimum <= stats.maximum

      assert stats.minimum <= stats.average
      assert stats.average <= stats.maximum

      assert stats.minimum <= stats.median
      assert stats.median <= stats.maximum

      assert stats.median == stats.percentiles[50]

      assert stats.median >= stats.percentiles[25]
      assert stats.percentiles[75] >= stats.median

      assert stats.variance >= 0
      assert stats.standard_deviation >= 0
      assert stats.standard_deviation_ratio >= 0
    end

    defp assert_mode_in_samples(stats, samples) do
      case stats.mode do
        [_ | _] ->
          Enum.each(stats.mode, fn mode ->
            assert(mode in samples)
          end)

        # nothing to do there is no real mode
        nil ->
          nil

        mode ->
          assert mode in samples
      end
    end

    defp assert_frequencies(stats, samples) do
      frequency_distribution = stats.frequency_distribution
      frequency_entry_count = map_size(frequency_distribution)

      assert frequency_entry_count >= 1
      assert frequency_entry_count <= stats.sample_size

      # frequencies actually occur in samples
      Enum.each(frequency_distribution, fn {key, value} ->
        assert key in samples
        assert value >= 1
        assert is_integer(value)
      end)

      # all samples are in frequencies
      Enum.each(samples, fn sample -> assert Map.has_key?(frequency_distribution, sample) end)

      # counts of frequencies sum up to sample_size
      count_sum =
        frequency_distribution
        |> Map.values()
        |> Enum.sum()

      assert count_sum == stats.sample_size
    end

    defp assert_bounds_and_outliers(stats, samples) do
      Enum.each(stats.outliers, fn outlier ->
        assert outlier in samples
        assert outlier < stats.lower_outlier_bound || outlier > stats.upper_outlier_bound
      end)

      assert stats.lower_outlier_bound <= stats.percentiles[25]
      assert stats.upper_outlier_bound >= stats.percentiles[75]

      non_outlier_statistics = Statistex.statistics(samples, exclude_outliers: true)
      # outlier or not, outliers or bounds aren't changed
      assert non_outlier_statistics.outliers == stats.outliers
      assert non_outlier_statistics.lower_outlier_bound == stats.lower_outlier_bound
      assert non_outlier_statistics.upper_outlier_bound == stats.upper_outlier_bound

      if Enum.empty?(stats.outliers) do
        # no outliers? Then excluding outliers shouldn't change anything!
        assert non_outlier_statistics == stats
      else
        assert non_outlier_statistics.sample_size < stats.sample_size
        assert non_outlier_statistics.standard_deviation < stats.standard_deviation
        # property may not hold vor the std_dev ratio seemingly as values may be skewed too much

        frequency_occurrences = Map.keys(non_outlier_statistics.percentiles)

        # outliers don't make an appearances in the frequency occurrences
        assert MapSet.intersection(MapSet.new(stats.outliers), MapSet.new(frequency_occurrences)) ==
                 MapSet.new([])
      end
    end

    defp big_list_big_floats do
      sized(fn size ->
        resize(
          list_of(
            float(),
            min_length: 1
          ),
          size * 4
        )
      end)
    end

    property "percentiles are correctly related to each other" do
      check all(samples <- list_of(float(), min_length: 1)) do
        percies = percentiles(samples, [25, 50, 75, 90, 99, 99.9999])

        assert percies[25] <= percies[50]
        assert percies[50] <= percies[75]
        assert percies[75] <= percies[90]
        assert percies[90] <= percies[99]
        assert percies[99] <= percies[99.9999]
      end
    end
  end
end
