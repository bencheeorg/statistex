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

  describe ".outliers_bounds/2" do
    test "returns outlier bounds for samples without outliers" do
      assert Statistex.outliers_bounds([200, 400, 400, 400, 500, 500, 500, 700, 900]) ==
               {200, 900.0}
    end

    test "returns outlier bounds for samples with outliers" do
      assert Statistex.outliers_bounds([50, 50, 450, 450, 450, 500, 500, 500, 600, 900]) ==
               {87.5, 787.5}
    end
  end

  describe ".statistics/2" do
    test "returns Statistex struct without outliers" do
      assert Statistex.statistics([200, 400, 400, 400, 500, 500, 500, 700, 900]) ==
               %Statistex{
                 total: 4500,
                 average: 500.0,
                 variance: 40000.0,
                 standard_deviation: 200.0,
                 standard_deviation_ratio: 0.4,
                 median: 500.0,
                 percentiles: %{25 => 400.0, 50 => 500.0, 75 => 600.0},
                 frequency_distribution: %{200 => 1, 400 => 3, 500 => 3, 700 => 1, 900 => 1},
                 mode: [500, 400],
                 minimum: 200,
                 maximum: 900,
                 outliers_bounds: {200, 900.0},
                 outliers: [],
                 sample_size: 9
               }
    end

    test "returns Statistex struct with outliers" do
      assert Statistex.statistics([50, 50, 450, 450, 450, 500, 500, 500, 600, 900]) ==
               %Statistex{
                 total: 4450,
                 average: 445.0,
                 variance: 61361.11111111111,
                 standard_deviation: 247.71175004652304,
                 standard_deviation_ratio: 0.5566556180820742,
                 median: 475.0,
                 percentiles: %{25 => 350.0, 50 => 475.0, 75 => 525.0},
                 frequency_distribution: %{50 => 2, 450 => 3, 500 => 3, 600 => 1, 900 => 1},
                 mode: [500, 450],
                 minimum: 50,
                 maximum: 900,
                 outliers_bounds: {87.5, 787.5},
                 outliers: [50, 50, 900],
                 sample_size: 10
               }
    end

    test "returns Statistex struct with excluded outliers once" do
      assert Statistex.statistics([50, 50, 450, 450, 450, 500, 500, 500, 600, 900],
               exclude_outliers: :once
             ) ==
               %Statistex{
                 total: 3450,
                 average: 492.85714285714283,
                 variance: 2857.142857142857,
                 standard_deviation: 53.452248382484875,
                 standard_deviation_ratio: 0.1084538372977954,
                 median: 500.0,
                 percentiles: %{25 => 450.0, 50 => 500.0, 75 => 500.0},
                 frequency_distribution: %{450 => 3, 500 => 3, 600 => 1},
                 mode: [500, 450],
                 minimum: 450,
                 maximum: 600,
                 outliers_bounds: {450, 575.0},
                 outliers: [600, 50, 50, 900],
                 sample_size: 7
               }
    end

    test "returns Statistex struct with excluded outliers repeatedly" do
      assert Statistex.statistics([50, 50, 450, 450, 450, 500, 500, 500, 600, 900],
               exclude_outliers: :repeatedly
             ) ==
               %Statistex{
                 total: 2850,
                 average: 475.0,
                 variance: 750.0,
                 standard_deviation: 27.386127875258307,
                 standard_deviation_ratio: 0.05765500605317538,
                 median: 475.0,
                 percentiles: %{25 => 450.0, 50 => 475.0, 75 => 500.0},
                 frequency_distribution: %{450 => 3, 500 => 3},
                 mode: [500, 450],
                 minimum: 450,
                 maximum: 500,
                 outliers_bounds: {450, 500},
                 outliers: [50, 50, 900, 600],
                 sample_size: 6
               }
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

      assert stats.sample_size >= 1
      assert stats.minimum <= stats.maximum

      assert stats.minimum <= stats.average
      assert stats.average <= stats.maximum

      assert stats.minimum <= stats.median
      assert stats.median <= stats.maximum

      assert stats.median == stats.percentiles[50]

      assert stats.variance >= 0
      assert stats.standard_deviation >= 0
      assert stats.standard_deviation_ratio >= 0

      # mode actually occurs in the samples
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

      # counts some up to sample_size
      count_sum =
        frequency_distribution
        |> Map.values()
        |> Enum.sum()

      assert count_sum == stats.sample_size
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
