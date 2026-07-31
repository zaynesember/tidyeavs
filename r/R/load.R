#' Load a tidy, harmonized EAVS panel
#'
#' The one-step entry point. Downloads the requested survey years, decodes
#' their missing-value codes, and harmonizes variable names so the years stack
#' into a single jurisdiction-year panel. It is the same as running
#' [eavs_read()], [eavs_recode_missing()], and [eavs_harmonize()] for each year
#' and binding the results.
#'
#' Loading more than one year prints a one-line reminder to run [eavs_flags()]
#' before publishing, because comparing cycles is where the survey's reporting
#' changes do their damage and a panel gives no sign of them on its own. `quiet`
#' silences it.
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
  out <- dplyr::bind_rows(frames)

  # A cross-year panel looks perfectly ordinary while carrying reporting changes
  # nothing in it can show, and a user who never calls eavs_flags() gets no
  # signal at all. Once per multi-year load, not per year, and not on the
  # single-year case where the swing checks cannot run anyway.
  if (!quiet && length(unique(years)) > 1) {
    cli::cli_inform(c(
      i = paste("Spanning {length(unique(years))} cycles. Run {.fn eavs_flags}",
                "on this panel before publishing from it.")
    ))
  }
  out
}
