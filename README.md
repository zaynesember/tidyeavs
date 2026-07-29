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

The R package is in [`r/`](r/) — start with [its README](r/README.md) for
installation and usage.

The curated metadata is in [`metadata/`](metadata/): the catalog of downloadable
files, the cross-year variable crosswalk, and the jurisdiction table, as
committed CSV with a JSON type schema. It sits at the repo root rather than
inside `r/` because it is not R's to own. A Python implementation is planned but
not yet written, and when it arrives it will read these same files, so that a
correction to a variable code cannot land in one language and be missed in the
other. See [`metadata/README.md`](metadata/README.md) before editing anything
there, and read its warning about column types before parsing the CSVs.

## Data

Raw EAVS files are never committed here. They download on demand into a local
cache, each verified against a SHA-256 checksum recorded in the manifest, so a
given analysis pins a specific published version of each file. Data come from the
EAC's public releases at
<https://www.eac.gov/research-and-data/datasets-codebooks-and-surveys>. The EAC
re-releases revised versions of a cycle for some time after the first release;
when that happens the manifest is updated to match.

If you use EAVS, cite the EAC as the source of the data.
