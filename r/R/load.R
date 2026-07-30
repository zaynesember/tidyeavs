#' Load a tidy, harmonized EAVS panel
#'
#' The one-step entry point. Downloads the requested survey years, decodes
#' their missing-value codes, and harmonizes variable names so the years stack
#' into a single jurisdiction-year panel. It is the same as running
#' [eavs_read()], [eavs_recode_missing()], and [eavs_harmonize()] for each year
#' and binding the results.
#'
#' @param years Survey years to load.
#' @param survey `"eavs"` (default) or `"policy"`.
#' @param format `"csv"` (default) or `"xlsx"`.
#' @param quiet Suppress progress messages.
#'
#' @return A tibble with one row per jurisdiction per year; identifier and
#'   concept columns named consistently across years (see [eavs_dictionary]),
#'   plus a `year` column.
#' @export
#'
#' @examples
#' \dontrun{
#' panel <- eavs_load(c(2020, 2022, 2024))
#' }
eavs_load <- function(years, survey = "eavs", format = "csv", quiet = FALSE) {
  frames <- lapply(years, function(y) {
    raw <- eavs_read(y, survey = survey, format = format, quiet = quiet)
    eavs_harmonize(eavs_recode_missing(raw), year = y)
  })
  dplyr::bind_rows(frames)
}
