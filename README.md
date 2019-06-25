# Statistex

Statistex helps you do common statistics calculations. It focusses on two things:

* providing you a `statistics/2` function that just computes all statistics it know how to compute for a given data set, reusing previously already made calculation to not compute something again
* give you the opportunity to also pass known values to functions so that it doesn't need to compute more than it absolutely needs to

## Installation

```elixir
def deps do
  [
    {:statistex, "~> 1.0"}
  ]
end
```

## Usage

....

## Alternatives

TODO: talk about the statistics package etc

## Performance

Statistex is written in pure elixir. C-extensions and friends would surely be faster. The goal of statistex is to be as fast possible in pure elixir while providing correct results. Hence, the focus on reusing previously calculated values and providing that ability to users.

## History

Statistex was extracted from [benchee](github.com/bencheeorg/benchee) and as such it powers benchees statistics calculations. Its great ancestor (if you will) was first conceived in [this commit](https://github.com/bencheeorg/benchee/commit/60fba66f927e0da20c4d16379dbf7274f77e63b5#diff-9d500e7ee9bd945a93b7172cca013d64).
