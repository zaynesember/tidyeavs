#' Harmonize an EAVS year to stable concept names
#'
#' Renames a single survey year's raw variables to the concept names shared
#' across years, so that different years line up. For example, mail ballots
#' rejected is `C4a` in 2020 but `C9a` in 2024; both become `mail_rejected`.
#' This is the step that makes years comparable, and it is what turns EAVS's
#' silent renumbering from a trap into a non-issue.
#'
#' Only the curated concepts in [eavs_dictionary] are renamed. By default other
#' columns are dropped; set `keep_unmatched = TRUE` to keep them under their
#' original names.
#'
#' @param data A single survey year of EAVS data, typically from
#'   [eavs_recode_missing()] (so item columns are numeric). A `year` column, as
#'   added by [eavs_read()], is used to pick the year.
#' @param year The survey year, if `data` has no `year` column.
#' @param keep_unmatched Keep columns that are not in the dictionary, under
#'   their original names. Defaults to `FALSE`.
#' @param dictionary The dictionary to harmonize against. Defaults to the
#'   bundled [eavs_dictionary]; pass your own to use an extended crosswalk.
#'
#' @return A tibble with identifier and concept columns named consistently
#'   across years, plus `year`.
#' @seealso [eavs_load()] to download, recode, and harmonize in one step.
#' @export
eavs_harmonize <- function(data, year = NULL, keep_unmatched = FALSE,
                           dictionary = NULL) {
  year <- resolve_year(data, year)
  dict_y <- dict_for_year(year, dictionary)

  matched <- dict_y[dict_y$code %in% names(data), c("concept", "code", "section")]
  if (nrow(matched) == 0) {
    cli::cli_abort(c(
      "None of {.arg data}'s columns match the {year} dictionary.",
      i = "Is {.arg data} really the {year} EAVS?"
    ))
  }

  out <- data
  idx <- match(matched$code, names(out))
  names(out)[idx] <- matched$concept

  lead <- intersect(c("year", "survey"), names(out))
  ids <- matched$concept[matched$section == "id"]
  items <- matched$concept[matched$section != "id"]
  keep <- c(lead, ids, items)
  if (keep_unmatched) {
    keep <- c(keep, setdiff(names(out), keep))
  }
  out <- out[, keep, drop = FALSE]

  if (!"year" %in% names(out)) {
    out <- tibble::add_column(out, year = year, .before = 1)
  }
  tibble::as_tibble(out)
}
