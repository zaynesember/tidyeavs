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
