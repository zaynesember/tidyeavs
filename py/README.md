# tidyeavs (Python)

Tidy access to the U.S. Election Assistance Commission's Election Administration
and Voting Survey (EAVS).

The EAVS is the most comprehensive source of data on how elections are actually
run in the United States. Every two years it asks all of the country's roughly
6,500 local election jurisdictions about voter registration, mail and military
ballots, provisional ballots, polling places, poll workers, and turnout by mode.
It's also tedious to work with. The files are spread across survey years in
formats that change from cycle to cycle, the variable codes are renumbered
between cycles, and missing values are marked with negative sentinel codes that a
plain `sum()` will happily add up. tidyeavs takes care of those mechanics so you
can get to the analysis.

The package does three things:

- **Downloads** published EAVS files from the EAC and caches them locally, each
  verified against a checksum so you get the exact version you expect.
- **Decodes** the survey's missing-value codes, keeping "does not apply" distinct
  from "data not available" rather than collapsing both to `NA`.
- **Harmonizes** variable names across years, so that mail ballots
  rejected—`C4a` in 2020, `C9a` in 2024—line up under one name.

It does not change the numbers jurisdictions reported. EAVS records what election
officials report, and tidyeavs hands you those values as published; decoding
missing codes and renaming variables is as far as it goes. Where the survey has
known quirks, the package documents them and gives you tools to see them, but any
corrections are yours to make.

This is a parallel implementation of the R package in the same repository, not a
binding to it. Both read the same crosswalk and file catalog from
[`metadata/`](../metadata), so a corrected variable code cannot land in one
language and be missed in the other.

## Installation

The package lives in the `py/` subdirectory of the repository, so an install
straight from GitHub has to say where to look:

```bash
pip install "tidyeavs @ git+https://github.com/zaynesember/tidyeavs.git#subdirectory=py"
```

Reading `.xlsx` files needs one extra dependency, which the `xlsx` extra pulls
in. tidyeavs is not on PyPI yet.

## Getting started

`load()` downloads, decodes, and harmonizes a set of survey years into one
jurisdiction-year panel:

```python
import tidyeavs

panel = tidyeavs.load([2016, 2018, 2020, 2022, 2024])
```

The first call for a given year downloads the file (a few megabytes) and caches
it; later calls read from the cache. Because the columns are harmonized, the
years stack, and the result is an ordinary DataFrame.

The tempting way to get a state's mail rejection rate—sum `mail_rejected`,
sum `mail_returned`, divide—is wrong more often than you'd expect, because
whole states report one side and not the other. All 67 Alabama counties report
returned ballots and none report rejections, so the naive division hands you a
clean-looking 0.0%; in 2022 Idaho it gives 0.0008% where the defensible figure
is 0.21%. `rate()` computes the rate the way the EAC's published rates are
computed—over the jurisdictions that reported both sides—and says what that
restriction kept:

```python
tidyeavs.rate(panel, "mail_rejected", "mail_returned")
```

Read `n_both` (how many jurisdictions stand behind the rate) and `den_share`
(how much of the state's reported denominator they hold) before quoting a
number; Alabama comes back as a missing `rate` with `n_num_only = 67` instead
of a fake zero.

Totals have the same exposure in milder form: a jurisdiction that didn't
report an item is simply absent from a sum, so a state total silently covers
only the reporters. `aggregate()` reports each total alongside counts of who
reported and why the rest are absent, so under-coverage is visible instead of
silent. And for anything spanning years, run `flags()`—it flags sums that
don't reconcile, hard year-over-year swings, and the verified statewide
reporting anomalies that pass every arithmetic check (Oregon's 2018 mail
disposition numbers are the standing example).

## Longer guides

The conceptual guidance lives in the R package's vignettes, and it is about EAVS
rather than about R, so it applies here unchanged apart from function names
(`tidyeavs.rate()` for `eavs_rate()`, and so on). They are worth reading before
publishing anything:

- **Getting started** builds a state-level mail rejection rate and shows why the
  obvious way to compute it is wrong.
- **Missingness and coverage** covers the coverage columns and why a total over
  incomplete reporting is a lower bound.
- **Comparing across years safely** covers flag triage and the verified
  reporting anomalies that pass every arithmetic check.
- **Survey structure** covers renumbered codes, what a "jurisdiction" is, and
  how to work with the ~500 columns the crosswalk does not cover.

Read them at <https://github.com/zaynesember/tidyeavs/tree/main/r/vignettes>, or
from an R session with `vignette(package = "tidyeavs")`.

## Missing values

From 2018 on, EAVS marks non-substantive responses with `-88` ("does not apply"),
`-99` ("data not available"), and `-77` ("valid skip"); 2016 and earlier use
`-888888` and `-999999`. `load()` decodes these to `NA`, but the distinction
between them often matters. A `0` mail-rejection count, a "does not apply" from
an all-in-person state, and a "data not available" are three different things.
`missing_status()` recovers the reason:

```python
raw = tidyeavs.read(2024)
tidyeavs.missing_status(raw)   # each item value replaced by why it is (not) missing
```

Each item column comes back as an ordered categorical with the values
`reported`, `does_not_apply`, `not_available`, `valid_skip`, `other_missing`, and
`blank`, so counting coverage is a `value_counts()`.

## Finding variables

The crosswalk maps every year's raw codes to stable concept names, and `items()`
searches it. It answers the question you actually have in front of a codebook:
what is `C9a`, and is it `C9a` in every year?

```python
tidyeavs.items("C9a")            # -> C9a is mail_rejected (in 2022 and 2024)
tidyeavs.items("mail_rejected")  # the code for mail rejections in every year
tidyeavs.items(section="C")      # all mail-ballot concepts
```

Because the mapping is explicit, the renumbering traps become visible instead of
silent: `items("uocava_rejected")` shows that the code is `B24a` in 2024 but
`B18a` in 2020, and that `B18a` in 2024 is a different item entirely.

## The pieces

`load()` is the composition of four steps you can also run yourself:

| Step | Function |
|------|----------|
| Download and cache a file | `download()` |
| Read one year as published | `read()` |
| Decode missing-value codes | `recode_missing()` |
| Rename to shared concepts | `harmonize()` |

`read()` returns the data exactly as published, every column as a pandas
`string`, so FIPS codes keep their leading zeros and nothing is coerced or lost.
The later steps add typing and structure on top of that faithful copy.

## A note on dtypes

Reading everything as text is deliberate, and it is worth keeping in mind if you
write your own reader against these files. pandas parses `0100100000` as the
integer `100100000` and a column of `01001` as a float, either of which quietly
destroys a FIPS code. The bundled metadata ships a `schema.json` for exactly this
reason, and `tidyeavs` reads through it; if you load `metadata/*.csv` yourself,
pass those types as `dtype=` rather than letting pandas guess.

## Jurisdictions

EAVS jurisdictions are not a tidy geography. Wisconsin reports ~1,850
municipalities under non-geographic serial codes, Maine files a statewide row
carrying only its UOCAVA totals, Alaska and the territories file one row each,
and a handful of published codes are shared, padded, or otherwise irregular.
`jurisdictions()` returns every published row per year with its type (county,
municipality, statewide, territory), the county FIPS where the published code
embeds one, and a flag or note for each quirk, so you can see them before they
bite an aggregate or a join.

## Where the data lives

Files are cached in the per-user cache directory for your platform.
`cache_dir()` reports the current location, `cache_list()` shows what's cached,
and `cache_clear()` removes it. To put them somewhere else, set the
`TIDYEAVS_CACHE_DIR` environment variable, or call `set_cache_dir()` before
downloading:

```python
tidyeavs.set_cache_dir("data/eavs")
```

The R package honours `TIDYEAVS_CACHE_DIR` too, so setting it for both gives one
shared cache and a file downloaded from either language is reused by the other.

## On EAVS data quality

EAVS is collected from thousands of independent jurisdictions that keep records in
different ways, so it carries the kinds of gaps and inconsistencies any survey of
that scale would: items some jurisdictions can't report, categories that don't
sum to their totals, occasional values that look off. None of this makes it bad
data—it is, by a wide margin, the best national picture of election
administration there is, and its careful users treat it accordingly. The EAC
publishes its own validation rules, revises datasets as corrections come in, and
cautions against decontextualized comparisons. tidyeavs aims to encode the
handling its careful users already apply, and to be honest about where care is
needed, without pretending the data is cleaner than it is.

## Data source and versions

Data come from the EAC's public releases at
<https://www.eac.gov/research-and-data/datasets-codebooks-and-surveys>. The EAC
re-releases revised versions of a cycle for some time after the first release;
tidyeavs pins a specific version of each file by checksum, recorded in the shared
manifest, and reports which version you have. When the EAC issues a new version,
the package is updated to match.

So that a re-release doesn't break installed copies of the package in the
meantime, byte-identical copies of the pinned files are also published as assets
on a GitHub release, and `download()` tries those first before falling back to
eac.gov. Both are verified against the same checksum, so the file you get is the
same either way.

If you use EAVS, cite the EAC as the source of the data.
