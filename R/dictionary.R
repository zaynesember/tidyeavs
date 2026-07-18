#' Look up EAVS variables and concepts
#'
#' Searches the tidyeavs dictionary, which maps each survey year's raw variable
#' codes to stable concept names. Use it to answer "what is `C9a`?", to find
#' the code for a concept in a given year, or to see which years collected an
#' item.
#'
#' @param query A string matched (case-insensitively) against concept names,
#'   labels, raw codes, and EPI names. `NULL` (default) returns everything,
#'   subject to `year` and `section`.
#' @param year Restrict to one or more survey years.
#' @param section Restrict to one or more survey sections (`"A"` through `"F"`,
#'   or `"id"` for identifier columns).
#' @param dictionary The dictionary to search. Defaults to the bundled
#'   [eavs_dictionary]; pass your own to search an extended crosswalk.
#'
#' @return A tibble of matching dictionary rows (see [eavs_dictionary]).
#' @export
#'
#' @examples
#' # What does C9a measure, and is it C9a in every year?
#' eavs_items("C9a")
#'
#' # All mail-ballot concepts:
#' eavs_items(section = "C")
#'
#' # The code for mail ballots rejected, by year:
#' eavs_items("mail_rejected")
eavs_items <- function(query = NULL, year = NULL, section = NULL,
                       dictionary = NULL) {
  dict <- resolve_dictionary(dictionary)
  if (!is.null(year)) {
    dict <- dict[dict$year %in% year, , drop = FALSE]
  }
  if (!is.null(section)) {
    dict <- dict[tolower(dict$section) %in% tolower(section), , drop = FALSE]
  }
  if (!is.null(query)) {
    hay <- tolower(paste(
      dict$concept, dict$concept_label, dict$codebook_label,
      dict$code, dict$epi_name
    ))
    dict <- dict[grepl(tolower(query), hay, fixed = TRUE), , drop = FALSE]
  }
  tibble::as_tibble(dict)
}

# The dictionary to use: the supplied one, or the bundled dataset.
resolve_dictionary <- function(dictionary = NULL) {
  if (!is.null(dictionary)) {
    return(dictionary)
  }
  tryCatch(
    eavs_dictionary,
    error = function(e) {
      cli::cli_abort(c(
        "The bundled EAVS dictionary isn't available.",
        i = "Reinstall tidyeavs, or pass {.arg dictionary}."
      ))
    }
  )
}

# Dictionary rows for one year that have a raw code (i.e., were collected).
dict_for_year <- function(year, dictionary = NULL) {
  dict <- resolve_dictionary(dictionary)
  rows <- dict[dict$year == year & !is.na(dict$code), , drop = FALSE]
  if (nrow(rows) == 0) {
    cli::cli_abort("The dictionary has no entries for {year}.")
  }
  rows
}

# Resolve a single year from an explicit argument or a `year` column.
resolve_year <- function(data, year) {
  if (!is.null(year)) {
    if (length(year) != 1) {
      cli::cli_abort("{.arg year} must be a single year.")
    }
    return(year)
  }
  if ("year" %in% names(data)) {
    yy <- unique(data$year)
    if (length(yy) == 1) {
      return(yy)
    }
  }
  cli::cli_abort(c(
    "Could not tell which survey year {.arg data} is.",
    i = "Pass {.arg year}, or include a single-valued {.field year} column."
  ))
}
