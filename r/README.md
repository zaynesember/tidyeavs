<!-- badges: start -->
[![Lifecycle: experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
<!-- badges: end -->

# tidyeavs

Tidy access to the U.S. Election Assistance Commission's Election
Administration and Voting Survey (EAVS).

The EAVS is the most comprehensive source of data on how elections are actually
run in the United States. Every two years it asks all of the country's roughly
6,500 local election jurisdictions about voter registration, mail and military
ballots, provisional ballots, polling places, poll workers, and turnout by
mode. It's also tedious to work with. The files are spread across survey years
in formats that change from cycle to cycle, the variable codes are renumbered
between cycles, and missing values are marked with negative sentinel codes that
a plain `sum()` will happily add up. tidyeavs takes care of those mechanics so
you can get to the analysis.

The package does three things:

- **Downloads** published EAVS files from the EAC and caches them locally, each
  verified against a checksum so you get the exact version you expect.
- **Decodes** the survey's missing-value codes, keeping "does not apply"
  distinct from "data not available" rather than collapsing both to `NA`.
- **Harmonizes** variable names across years, so that mail ballots
  rejected—`C4a` in 2020, `C9a` in 2024—line up under one name.

It does not change the numbers jurisdictions reported. EAVS records what
election officials report, and tidyeavs hands you those values as published;
decoding missing codes and renaming variables is as far as it goes. Where the
survey has known quirks, the package documents them and gives you tools to see
them, but any corrections are yours to make.

## Installation

```r
# install.packages("pak")
pak::pak("zaynesember/tidyeavs/r")
```

The trailing `/r` is not a typo. The R package lives in the `r/` subdirectory of
the repository rather than at its root, so an install straight from GitHub has to
say where to look. With remotes instead of pak:

```r
remotes::install_github("zaynesember/tidyeavs", subdir = "r")
```

tidyeavs is not on CRAN yet.

## Getting started

`eavs_load()` downloads, decodes, and harmonizes a set of survey years into one
jurisdiction-year panel:

```r
library(tidyeavs)

panel <- eavs_load(c(2016, 2018, 2020, 2022, 2024))
```

The first call for a given year downloads the file (a few megabytes) and caches
it; later calls read from the cache. Because the columns are harmonized, the
years stack, and the result is an ordinary tibble.

The tempting way to get a state's mail rejection rate—sum `mail_rejected`,
sum `mail_returned`, divide—is wrong more often than you'd expect, because
whole states report one side and not the other. In 2020 all 67 Alabama counties
report returned ballots and none report rejections, so the naive division hands
you a clean-looking 0.0%. In 2024 Alabama reports rejections and no returns, so
the same code gives `Inf`. Which side a state leaves out changes from cycle to
cycle, and only one of those two mistakes is loud enough to notice. In 2022
Idaho the naive figure is 0.0008% where the defensible one is 0.21%.
`eavs_rate()` computes the rate the way the EAC's published rates are
computed, over the jurisdictions that reported both sides, and says what that
restriction kept:

```r
eavs_rate(panel, "mail_rejected", "mail_returned")
```

Read `n_both` (how many jurisdictions stand behind the rate) and `den_share`
(how much of the state's reported denominator they hold) before quoting a
number. Alabama comes back as `rate = NA` rather than a fake zero, with
`n_den_only = 67` in 2020 and `n_num_only = 67` in 2024, naming which side went
unreported.

A rate can pass both of those checks and still be one you should not quote.
Oregon's 2018 mail rejection rate has all 36 counties reporting and
`den_share = 1`, and is unusable anyway, because every county answered the
disposition items for a small subset of ballots that year. `known_anomaly` marks
the rows where a verified statewide reporting anomaly like that one is in play.

Totals have the same exposure in milder form: a jurisdiction that didn't
report an item is simply absent from a sum, so a state total silently covers
only the reporters. `eavs_aggregate()` reports each total alongside counts of
who reported and why the rest are absent, so under-coverage is visible instead
of silent. And for anything spanning years, run `eavs_flags()`—it flags sums
that don't reconcile, hard year-over-year swings, and the verified statewide
reporting anomalies that pass every arithmetic check (Oregon's 2018 mail
disposition numbers are the standing example).

It returns a lot of rows, 16,249 over all five cycles, and most of them are
ordinary reporting differences rather than anything you need to act on. Filter to
your concepts, then sort by `state_share` within one `kind`. That column is how
much of its state's total for that concept the flagged jurisdiction holds, which
is the thing to know when you are deciding whether a flag could move a number you
plan to publish. Sorting by `excess` instead ranks a large county's small
discrepancy above a small county's complete one.

Running all three checks is worth the trouble, because each one sees something
the others cannot. `eavs_rate()` reports whether enough jurisdictions reported
both sides of a ratio. `eavs_flags()` reports whether what they did report
reconciles. `eavs_missing_status()` is the only one that says why the absent
jurisdictions are absent. The `comparing-across-years` vignette works through all
three on one concept.

## Vignettes

Four, and the first one covers the task above in more depth. They are the
conceptual documentation, so they are worth reading before the help pages.

Note that `pak` and `remotes` do not build vignettes by default, so
`vignette("getting-started")` will report that it does not exist after an install
like the one above. They render with their output on GitHub, at
<https://github.com/zaynesember/tidyeavs/tree/main/r/vignettes>, or you can ask
for them at install time:

```r
remotes::install_github("zaynesember/tidyeavs", subdir = "r", build_vignettes = TRUE)
```

```r
vignette("getting-started", package = "tidyeavs")        # a mail rejection rate, end to end
vignette("missingness", package = "tidyeavs")            # coverage, and what a total is not
vignette("comparing-across-years", package = "tidyeavs") # flags triage, known anomalies
vignette("survey-structure", package = "tidyeavs")       # codes, jurisdictions, uncurated columns
```

## Missing values

From 2018 on, EAVS marks non-substantive responses with `-88` ("does not
apply"), `-99` ("data not available"), and `-77` ("valid skip"); 2016 and
earlier use `-888888` and `-999999`. `eavs_load()` decodes these to `NA`, but
the distinction between them often matters—a `0` mail-rejection count, a "does
not apply" from an all-in-person state, and a "data not available" are three
different things. `eavs_missing_status()` recovers the reason:

```r
raw <- eavs_read(2024)
eavs_missing_status(raw)   # each item value replaced by why it is (not) missing
```

One caution on reading those reasons. `does_not_apply` is not a stable signal
for a concept across cycles, so it will not carry the weight of an imputation.
Alabama's `mail_rejected` is coded `does_not_apply` for all 67 counties in 2016,
reported in 2018, `not_available` in 2020 and 2022, and reported again in 2024.
For a concept that reflects a yes-or-no state policy, "does not apply" plausibly
does mean zero; for a continuous administrative outcome like a rejection count it
usually does not, and the same code means different things in different cycles.
Whether to treat it as a zero is a judgment to make per concept, and to state in
your methods; the package will not make it for you.

For a cross-year status frame, bind with `dplyr::bind_rows()` rather than
`rbind()`. The years have different column counts, because a concept that was not
on that year's questionnaire produces no column at all rather than an all-`NA`
one, and `rbind()` fails on that with an opaque message:

```r
years <- c(2016, 2018, 2020, 2022, 2024)
status <- dplyr::bind_rows(lapply(years, function(y) {
  eavs_harmonize(eavs_missing_status(eavs_read(y, quiet = TRUE)), year = y)
}))
eavs_aggregate(panel, status = status)   # reason-aware coverage
```

## Finding variables

The dictionary maps every year's raw codes to stable concept names, and
`eavs_items()` searches it. It answers the question you actually have in front
of a codebook—what is `C9a`, and is it `C9a` in every year?

```r
eavs_items("C9a")            # -> C9a is mail_rejected (in 2022 and 2024)
eavs_items("mail_rejected")  # the code for mail rejections in every year
eavs_items("mail_rejected_") # the sixteen rejection-reason concepts
eavs_items(section = "C")    # all mail-ballot concepts
eavs_items("total registered")  # -> reg_eligible_total, the survey's own total
```

An exact concept name wins over a substring, so `eavs_items("mail_rejected")`
gives you that concept rather than it plus every `mail_rejected_*` reason.

Because the mapping is explicit, the renumbering traps become visible instead of
silent: `eavs_items("uocava_rejected")` shows that the code is `B24a` in 2024
but `B18a` in 2020—and that `B18a` in 2024 is a different item entirely. The
rejection-reason blocks are the worst of these. Between 2020 and 2022 the mail
reasons moved from `C4` to `C9`, and the letters were reshuffled along the way:
only `b` through `e` kept theirs, so "No Address" runs `C4j` then `C9l`, while
`C9j` is "Envelope Not Sealed". The provisional reasons moved from `E2` to `E3`,
and `E2` was reused for why a provisional was *cast*, so `E2e` reads "No ID" in
2020 and "Not Resident of Precinct" in 2024. Both columns are populated in both
cycles, so a series built by carrying the old code forward looks fine and is
wrong. Both blocks are crosswalked now, which is the reason to prefer the
crosswalk over tracking a code yourself.

Two things to know about the reasons. They are a curated subset, since the survey
also offers Other 1 through 3 (and, in 2018 and 2020, a missing election-official
signature), so they are expected to sum to less than `mail_rejected` and
`eavs_flags()` only checks that they do not exceed it. And 2016 collects no mail
rejection reasons at all, so those columns are absent from any panel that
includes it.

One more caution about looking for a concept. The survey's total registration
figure is `reg_eligible_total` (`A1a`, "Total Registered Voters", the same code in
all five years), and it is a question the survey asks rather than a sum you build
yourself. Adding `reg_active` and `reg_inactive` gets you a worse version of it,
because seven states and four territories report the active count and never the
inactive one. That is the same reporting asymmetry `eavs_rate()` exists to handle,
and it applies to a derived *sum* just as much as to a ratio.

## The pieces

`eavs_load()` is the composition of four steps you can also run yourself:

| Step | Function |
|------|----------|
| Download and cache a file | `eavs_download()` |
| Read one year as published | `eavs_read()` |
| Decode missing-value codes | `eavs_recode_missing()` |
| Rename to shared concepts | `eavs_harmonize()` |

`eavs_read()` returns the data exactly as published, every column as text, so
FIPS codes keep their leading zeros and nothing is coerced or lost. The later
steps add typing and structure on top of that faithful copy.

## Jurisdictions

EAVS jurisdictions are not a tidy geography: Wisconsin reports ~1,850
municipalities under non-geographic serial codes, Maine files a statewide row
carrying only its UOCAVA totals (military and overseas voters, after the
Uniformed and Overseas Citizens Absentee Voting Act), Alaska and the
territories file one row each,
and a handful of published codes are shared, padded, or otherwise irregular.
The bundled `eavs_jurisdictions` table lists every published row per year with
its type (county, municipality, statewide, territory), the county FIPS where
the published code embeds one, and a flag or note for each quirk—so you can
see them before they bite an aggregate or a join.

**Warning:** `fips_code` is not a unique key within a year, so please check for
duplicates before joining on it. Three Wisconsin town/village pairs share one
published code (`82575` and `84275` in 2020, `31550` in 2022), and a join fans
those rows out. Summing `partic_total` for Wisconsin in 2020 after a plain
`merge(panel, eavs_jurisdictions, by = c("year", "fips_code"))` gives 3,319,954
against a true 3,308,331, a 0.35% overstatement produced by four duplicated rows.
Base `merge()` gives no warning, and neither does pandas;
`dplyr::left_join()` is the only one of the three that says anything. The
`shared_code` column flags the affected rows, and `fips10` is unique wherever it
is not `NA`.

Joining the other way has the opposite problem. Maine's UOCAVA totals live in a
statewide row that carries no county FIPS, so a county-keyed join silently drops
all 6,309 of its 2024 counted UOCAVA ballots. `eavs_aggregate()` and
`eavs_rate()` handle both cases correctly, and `eavs_join()` is the safe way to
write the join yourself:

```r
# Attach county FIPS, structural type, and quirk flags to a panel.
# Stops on the Wisconsin fan-out; add the name to match the pairs exactly.
eavs_join(panel, by = c("year", "fips_code", "jurisdiction_name"))
```

It stops on a shared code rather than fanning the rows out, and reports the rows
a county-keyed join would drop instead of losing them. Base `merge()` and pandas
do neither on their own.

## Where the data lives

Files are cached under `tools::R_user_dir("tidyeavs", "cache")` by default. To
put them somewhere else—a project folder, say—set an option before you
download:

```r
options(tidyeavs.cache_dir = "data/eavs")
```

`eavs_cache_dir()` reports the current location, `eavs_cache_list()` shows
what's cached, and `eavs_cache_clear()` removes it.

## On EAVS data quality

EAVS is collected from thousands of independent jurisdictions that keep records
in different ways, so it carries the kinds of gaps and inconsistencies any
survey of that scale would: items some jurisdictions can't report, categories
that don't sum to their totals, occasional values that look off. None of this
makes it bad data—it is, by a wide margin, the best national picture of
election administration there is, and its careful users treat it accordingly.
The EAC publishes its own validation rules, revises datasets as corrections come
in, and cautions against decontextualized comparisons. tidyeavs aims to encode
the handling its careful users already apply, and to be honest about where care
is needed, without pretending the data is cleaner than it is.

## Data source and versions

Data come from the EAC's public releases at
<https://www.eac.gov/research-and-data/datasets-codebooks-and-surveys>. The EAC
re-releases revised versions of a cycle for some time after the first release;
tidyeavs pins a specific version of each file by checksum, recorded in
`eavs_manifest`, and reports which version you have. When the EAC issues a new
version, the package is updated to match.

So that a re-release doesn't break installed copies of the package in the
meantime, byte-identical copies of the pinned files are also published as
assets on a GitHub release, and `eavs_download()` tries those first before
falling back to eac.gov. Both are verified against the same checksum, so the
file you get is the same either way.

If you use EAVS, cite the EAC as the source of the data.
