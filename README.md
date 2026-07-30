# tidyeavs

Tidy access to the U.S. Election Assistance Commission's Election Administration
and Voting Survey (EAVS). Every two years the EAVS asks all of the roughly 6,500
local election jurisdictions in the United States how they ran the federal
election: voter registration, mail and military ballots, provisional ballots,
polling places, poll workers, and turnout by mode. tidyeavs downloads the
published files, decodes the survey's missing-value codes, and harmonizes
variable names across years so that jurisdictions can be compared over time. It
does not change the values jurisdictions reported.

## Where things are

There are two implementations, and neither wraps the other:

- [`r/`](r/) — the R package. See [its README](r/README.md).
- [`py/`](py/) — the Python package, returning pandas. See
  [its README](py/README.md).

The curated metadata is in [`metadata/`](metadata/): the catalog of downloadable
files, the cross-year variable crosswalk, and the jurisdiction table, as
committed CSV with a JSON type schema. It sits at the repo root rather than
inside either package because it belongs to neither. Both read it, so a
correction to a variable code cannot land in one language and be missed in the
other. The two were diffed against each other over all five survey years and
agree cell for cell.

See [`metadata/README.md`](metadata/README.md) before editing anything there, and
read its warning about column types before parsing the CSVs yourself — pandas
will silently turn a FIPS code into an integer if you let it guess.

## Data

Raw EAVS files are never committed here. They download on demand into a local
cache, each verified against a SHA-256 checksum recorded in the manifest, so a
given analysis pins a specific published version of each file. Data come from the
EAC's public releases at
<https://www.eac.gov/research-and-data/datasets-codebooks-and-surveys>. The EAC
re-releases revised versions of a cycle for some time after the first release;
when that happens the manifest is updated to match.

If you use EAVS, cite the EAC as the source of the data.
