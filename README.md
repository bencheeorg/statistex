# Statistex [![Build Status](https://travis-ci.org/bencheeorg/statistex.svg?branch=master)](https://travis-ci.org/bencheeorg/statistex) [![Coverage Status](https://coveralls.io/repos/github/bencheeorg/statistex/badge.svg?branch=master)](https://coveralls.io/github/bencheeorg/statistex?branch=master)

Statistex helps you do common statistics calculations. It focusses on two things:

* providing you a `statistics/2` function that just computes all statistics it knows for a given data set, reusing previously already made calculation to not compute something again (for instance standard deviation needs the average, so it first computes the average and then passes it on): `Statistex.statistics(samples)`
* give you the opportunity to also pass known values to functions so that it doesn't need to compute more than it absolutely needs to: `Statistex.standard_deviation(samples, average: computed_average)`

## Installation

```elixir
def deps do
  [
    {:statistex, "~> 1.0"}
  ]
end
```

## Usage

```
iex> samples = [1, 3.0, 2.35, 11.0, 1.37, 35, 5.5, 10, 0, 2.35]
# calculate all available statistics at once, efficiently reusing already calculated values
iex> Statistex.statistics(samples)
%Statistex{
  average: 7.156999999999999,
  maximum: 35,
  median: 2.675,
  minimum: 0,
  mode: 2.35,
  percentiles: %{50 => 2.675},
  sample_size: 10,
  standard_deviation: 10.47189577445799,
  standard_deviation_ratio: 1.46316833512058,
  total: 71.57
}
# or just calculate the value you need
iex> Statistex.average(samples)
7.156999999999999
# Calculate the value you want reusing values you already know
# (check the docs for what functions accepts what options)
iex> Statistex.average(samples, sample_size: 10)
7.156999999999999
```

## Alternatives

TODO: talk about the statistics package etc

## Performance

Statistex is written in pure elixir. C-extensions and friends would surely be faster. The goal of statistex is to be as fast possible in pure elixir while providing correct results. Hence, the focus on reusing previously calculated values and providing that ability to users.

## History

Statistex was extracted from [benchee](github.com/bencheeorg/benchee) and as such it powers benchees statistics calculations. Its great ancestor (if you will) was first conceived in [this commit](https://github.com/bencheeorg/benchee/commit/60fba66f927e0da20c4d16379dbf7274f77e63b5#diff-9d500e7ee9bd945a93b7172cca013d64).
