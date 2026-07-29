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

panel <- eavs_load(2016:2024)
```

The first call for a given year downloads the file (a few megabytes) and caches
it; later calls read from the cache. Because the columns are harmonized, the
years stack, and you can work with the result like any other tibble:

```r
library(dplyr)

panel |>
  filter(year == 2024) |>
  group_by(state_abbr) |>
  summarise(
    returned = sum(mail_returned, na.rm = TRUE),
    rejected = sum(mail_rejected, na.rm = TRUE)
  ) |>
  mutate(rejection_rate = rejected / returned)
```

A word of caution on that `na.rm = TRUE`: a jurisdiction that didn't report an
item is dropped from the sum, so a state total silently covers only the
jurisdictions that reported. When a large jurisdiction is missing—Cook County
in Illinois is the recurring example—a state total can be badly off. It's
worth checking coverage before trusting an aggregate (see `eavs_missing_status()`
below).

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

## Finding variables

The dictionary maps every year's raw codes to stable concept names, and
`eavs_items()` searches it. It answers the question you actually have in front
of a codebook—what is `C9a`, and is it `C9a` in every year?

```r
eavs_items("C9a")            # -> C9a is mail_rejected (in 2022 and 2024)
eavs_items("mail_rejected")  # the code for mail rejections in every year
eavs_items(section = "C")    # all mail-ballot concepts
```

Because the mapping is explicit, the renumbering traps become visible instead of
silent: `eavs_items("uocava_rejected")` shows that the code is `B24a` in 2024
but `B18a` in 2020—and that `B18a` in 2024 is a different item entirely.

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
carrying only its UOCAVA totals, Alaska and the territories file one row each,
and a handful of published codes are shared, padded, or otherwise irregular.
The bundled `eavs_jurisdictions` table lists every published row per year with
its type (county, municipality, statewide, territory), the county FIPS where
the published code embeds one, and a flag or note for each quirk—so you can
see them before they bite an aggregate or a join.

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

If you use EAVS, cite the EAC as the source of the data.
