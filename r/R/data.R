#' Catalog of published EAVS files
#'
#' A table of the U.S. Election Assistance Commission's EAVS and Policy Survey
#' data files that tidyeavs can download, one row per file. It records each
#' file's version, source URL, and a SHA-256 checksum so downloads can be
#' verified. [eavs_download()] and [eavs_read()] use it to locate and check
#' files; you rarely need to touch it directly.
#'
#' The EAC re-releases revised versions of a cycle's data for some time after
#' the first release, so each row pins one version by checksum. When the EAC
#' issues a new version, the manifest is updated to match it.
#'
#' @format A tibble with one row per file and the columns:
#' \describe{
#'   \item{survey}{`"eavs"`, or `"policy"` for the Policy Survey.}
#'   \item{year}{Survey year.}
#'   \item{format}{File format, `"csv"` or `"xlsx"`.}
#'   \item{version}{The EAC's version label for the file, e.g. `"2.0"`.}
#'   \item{release_date}{Date the version was published.}
#'   \item{file_name}{Name the file is stored under in the cache.}
#'   \item{bytes}{File size in bytes.}
#'   \item{sha256}{SHA-256 checksum of the file.}
#'   \item{source_url}{Direct download URL at eac.gov.}
#'   \item{mirror_url}{Mirror URL, or `NA` when none is set.}
#' }
#' @source U.S. Election Assistance Commission,
#'   <https://www.eac.gov/research-and-data/datasets-codebooks-and-surveys>
"eavs_manifest"

#' Cross-year EAVS variable dictionary
#'
#' Maps each survey year's raw variable codes to stable concept names, so that
#' the same measure can be found in every year despite the EAC's renumbering.
#' This is the crosswalk that [eavs_harmonize()] and [eavs_load()] use, and it
#' is searchable with [eavs_items()].
#'
#' The dictionary is curated: it covers the concepts most used in EAVS
#' analysis (registration, mail and UOCAVA ballots, provisional ballots,
#' participation, polling places, and newer items such as drop boxes), not
#' every one of the survey's ~400 columns. A concept's `code` is `NA` in years
#' when the item was not collected, and `note` records renumbering, wording
#' changes, and breaks worth knowing about—most importantly the cases where the
#' same code letter means different things in different years.
#'
#' @format A tibble with one row per concept per year and the columns:
#' \describe{
#'   \item{concept}{Stable snake_case concept name, e.g. `"mail_rejected"`.}
#'   \item{concept_label}{Plain-language description of the concept.}
#'   \item{section}{Survey section: `"A"`–`"F"`, or `"id"` for identifiers.}
#'   \item{year}{Survey year.}
#'   \item{code}{The raw EAVS variable name that year, or `NA` if not collected.}
#'   \item{codebook_label}{The label the EAC's codebook gives that variable
#'     that year, kept as provenance for the mapping.}
#'   \item{epi_name}{The MIT Elections Performance Index's name for the
#'     concept, where one exists, or `NA`.}
#'   \item{note}{Caveats: renumbering, wording changes, and hard breaks.}
#'   \item{confidence}{How sure the mapping is: `"high"`, `"medium"`, or
#'     `"low"`. Lower confidence usually reflects a wording or definition
#'     change worth reading the `note` about.}
#' }
#' @source Built from EAC codebooks (2016–2024) and the MIT Elections
#'   Performance Index variable maps. See `data-raw/dictionary.R`.
"eavs_dictionary"

#' EAVS jurisdictions, with quirk flags
#'
#' One row per jurisdiction per EAVS year, exactly as the published files list
#' them: identifiers, a normalized FIPS code, the county FIPS where the
#' published code embeds one, a structural type, and flags for the quirks that
#' matter when joining or aggregating. Every published row is kept—including
#' statewide pseudo-rows and duplicated codes—and quirks are flagged in
#' `note`, never corrected.
#'
#' The quirks worth knowing: Wisconsin's ~1,850 codes are non-geographic
#' serials (the county is only in the name, restated in `county_name`, and a
#' few serials are shared by a town/village pair); Maine files a statewide row
#' carrying only its UOCAVA totals; Alaska and the territories file one row
#' each; Kalawao County HI appears but is administered by Maui County; and two
#' 2024 California codes lost a leading zero, which `fips10` restores.
#' Connecticut's embedded county codes are the pre-2022 Census counties, not
#' today's planning regions. Covers the EAVS only, not the Policy Survey.
#'
#' @format A tibble with one row per jurisdiction-year and the columns:
#' \describe{
#'   \item{year}{Survey year.}
#'   \item{fips_code}{The jurisdiction code exactly as published.}
#'   \item{fips10}{`fips_code` normalized to 10 digits (restoring lost leading
#'     zeros), or `NA` for codes that are not FIPS-style: Wisconsin's serials
#'     and Maine's statewide row.}
#'   \item{jurisdiction_name}{Jurisdiction name as published.}
#'   \item{state_abbr}{Two-letter state or territory abbreviation as
#'     published.}
#'   \item{state_name, state_fips}{The standard name and two-digit ANSI FIPS
#'     for `state_abbr`.}
#'   \item{county_fips}{Five-digit county (or county-equivalent) FIPS, where
#'     the published code embeds one; `NA` where it does not (Wisconsin,
#'     Alaska, territories, place-coded Illinois city boards, a few Maine
#'     townships).}
#'   \item{county_name}{For Wisconsin only: the county as published in the
#'     jurisdiction name, restated as its own column for filtering and joins.
#'     `NA` for the 56–58 municipalities per year whose names read "MULTIPLE
#'     COUNTIES"—they straddle county lines, and they include the City of
#'     Milwaukee, which is why Wisconsin stays out of [eavs_aggregate()]'s
#'     county rollups even with this column present.}
#'   \item{type}{Structural type: `"county"` (county or county-equivalent,
#'     including parishes, independent cities, and the District of Columbia),
#'     `"municipality"` (sub-county: New England towns, Wisconsin
#'     municipalities, Illinois city election boards), `"statewide"` (Alaska's
#'     single row and Maine's UOCAVA row), or `"territory"`.}
#'   \item{nongeo_code}{`TRUE` for Wisconsin's non-geographic serial codes.}
#'   \item{code_padded}{`TRUE` where the published code lost a leading zero
#'     and `fips10` restores it.}
#'   \item{shared_code}{`TRUE` where two published rows share one code that
#'     year (three Wisconsin town/village pairs).}
#'   \item{note}{Description of the row's quirk, or `NA`.}
#' }
#' @source Built from the published EAVS files. See
#'   `data-raw/jurisdictions.R`, which records the structural facts and the
#'   years they were verified against.
"eavs_jurisdictions"

#' Internal-consistency checks
#'
#' The checks [eavs_flags()] runs. Every check has one shape: the concepts in
#' `parts` should not sum past `total`, which covers both simple orderings (one
#' part, e.g. mail ballots returned against transmitted) and subparts against a
#' total (several, e.g. counted plus rejected against returned).
#'
#' These encode arithmetic expectations, not judgments. A check firing means two
#' reported numbers do not reconcile; `note` records the ordinary explanations
#' for that particular check, most of which are differences in reporting
#' convention rather than discrepancies in the count.
#'
#' @format A tibble with one row per check:
#' \describe{
#'   \item{check}{Check name, stable snake_case.}
#'   \item{total}{Concept the parts are compared against.}
#'   \item{parts}{Character vector of concepts whose sum is compared.}
#'   \item{section}{Survey section the check sits in (`"A"`–`"F"`).}
#'   \item{note}{What an excess usually means for this check.}
#' }
#' @source Built from `metadata/checks.csv`, the committed definition shared with
#'   the Python implementation. See `data-raw/checks.R`.
"eavs_checks"

#' Known reporting anomalies in the published files
#'
#' Statewide reporting conventions, verified against the published files, that
#' make one state's value for a concept-year not comparable to its other years.
#' Arithmetic checks cannot catch these, because the numbers reconcile
#' internally: in 2018 all 99 Iowa counties report Election Day polling places
#' equal to their Election Day voters, and all 36 Oregon counties answer the
#' mail counted and rejected items for a small subset of ballots. Both are how a
#' state answered the question, not a value this package would change.
#'
#' [eavs_flags()] surfaces each affected observation as
#' `kind = "known_anomaly"`, so an anomaly reaches you through the same output
#' as the other checks instead of living only in documentation. A row here means
#' "read this state-year with the note in hand", nothing more, and every row
#' cites its evidence in `source`.
#'
#' @format A tibble with one row per anomaly:
#' \describe{
#'   \item{year}{Survey year the anomaly appears in.}
#'   \item{state_abbr}{State whose reporting the row describes.}
#'   \item{concept}{The affected concept.}
#'   \item{note}{What the published values show and what that means for use.}
#'   \item{source}{The evidence: file, comparison, and date verified.}
#' }
#' @source Built from `metadata/known_anomalies.csv`, the committed definition
#'   shared with the Python implementation. See `data-raw/known_anomalies.R`.
"eavs_known_anomalies"
