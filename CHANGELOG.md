## 1.1.0 (2025-07-06)

This release adds functionality around identifying outliers.

* the Statistex struct comes with more keys: `:lower_outlier_bound`, `:upper_outlier_bound` & `:outliers`,
along with the new public functions `:outliers/2` and `:outlier_bounds/2`.
* `statistics/2` now also accepts `exclude_outliers: true` to exclude the outliers from the calculation
of statistics.
* some functions have also been updated to accept more optional arguments such as `:sorted?` to avoid unnecessary extra work.

Huge thanks for these changes go to [@NickNeck](https://github.com/NickNeck)!

## 1.0.0 2019-07-05

Import of the initial functionality from [benchee](github.com/bencheeorg/benchee).

Dubbed 1.0 because many people had already been running this code indirectly through benchee.
