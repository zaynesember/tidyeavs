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
