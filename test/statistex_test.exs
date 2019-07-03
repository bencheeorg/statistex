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

      frequency_entry_count = map_size(stats.frequency_distribution)

      assert frequency_entry_count >= 1
      assert frequency_entry_count <= stats.sample_size

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

      # frequencies actually occur in samples
      Enum.each(stats.frequency_distribution, fn {key, value} ->
        assert key in samples
        assert value >= 1
        assert is_integer(value)
      end)
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
