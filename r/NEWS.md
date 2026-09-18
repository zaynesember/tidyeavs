# tidyeavs 0.2.0

* New `eavs_join()` (Python: `tidyeavs.join()`), a checked left join for
  attaching jurisdiction-level tables to a panel. `fips_code` is not a unique
  key within a year: three Wisconsin town/village pairs share a serial, so a
  plain join fans their rows out (WI 2020 `partic_total` +0.35%), and Maine's
  statewide UOCAVA row has no county FIPS, so a county-keyed join drops it.
  Base `merge()` and pandas do both silently. `eavs_join()` stops on a key
  duplicated in `y` (naming the shared codes and, where it would resolve
  them, pointing at `jurisdiction_name`), reports rows that matched nothing
  instead of dropping them, and attaches only the columns `y` adds. Nothing
  is corrected.
* `eavs_rate()` documentation now says what `den_share` is for. It is a
  concentration diagnostic, not a usability filter: `NA` means no one
  reported the denominator, `0` means some did but never jointly with the
  numerator. The test for "no usable rate" is `n_both > 0` (equivalently
  `!is.na(rate)`), which catches both. No change to the values.
* `dplyr (>= 1.1.0)` is now required, for the `relationship` guard
  `eavs_join()` uses as a second check.

# tidyeavs 0.1.0

* First release. `eavs_load()` downloads, decodes, and harmonizes EAVS
  2016–2024 into a jurisdiction-year panel; the step functions
  (`eavs_download()`, `eavs_read()`, `eavs_recode_missing()`,
  `eavs_harmonize()`) expose each stage. `eavs_aggregate()` rolls up to
  state or county with reason-aware coverage, `eavs_rate()` computes rates
  over the jurisdictions reporting both sides of a pair, and `eavs_flags()`
  reports internal-consistency and year-over-year flags. Shipped data:
  `eavs_manifest`, `eavs_dictionary` (66 concepts), `eavs_jurisdictions`,
  `eavs_checks`, `eavs_known_anomalies`. A Python implementation with the
  same behavior lives in `py/`, sharing the metadata in `metadata/`.
