#' Decode EAVS missing-value codes
#'
#' EAVS marks non-substantive responses with negative sentinel codes. From
#' 2018 on these are `-88` ("does not apply"), `-99` ("data not available"),
#' and `-77` ("valid skip"); in 2016 and earlier they are `-888888` and
#' `-999999`. This finds the numeric item columns in a raw EAVS table (see
#' [eavs_read()]), converts them to numbers, and sets sentinel values to `NA`.
#'
#' Identifier and text columns—FIPS codes, jurisdiction and state names,
#' comment and write-in fields—are left untouched. A column is treated as a
#' numeric item when, ignoring blanks and text placeholders, all of its values
#' are numbers. Because every EAVS item is a count or a rate, any negative
#' value in an item column is read as missing; recognized sentinels keep their
#' specific meaning, which [eavs_missing_status()] reports.
#'
#' @param data A data frame from [eavs_read()], or any table of EAVS columns.
#'
#' @return `data` with item columns converted to numeric and sentinel values
#'   set to `NA`. Other columns are unchanged.
#' @seealso [eavs_missing_status()] to see *why* each value is missing.
#' @export
#'
#' @examples
#' df <- data.frame(
#'   FIPSCode = c("01001", "01003"),
#'   A1a = c("1200", "-99"),
#'   A3a = c("15", "-88")
#' )
#' eavs_recode_missing(df)
eavs_recode_missing <- function(data) {
  recode_core(data)$values
}

#' Report why EAVS values are missing
#'
#' Companion to [eavs_recode_missing()]. Returns a table the same shape as
#' `data` in which each item value is replaced by the reason it is, or is not,
#' missing: `"reported"`, `"does_not_apply"`, `"not_available"`,
#' `"valid_skip"`, `"other_missing"`, or `"blank"`. This keeps the distinction
#' between "does not apply" and "data not available" that recoding to `NA`
#' alone would lose.
#'
#' @inheritParams eavs_recode_missing
#'
#' @return `data` with item columns replaced by an ordered factor of status
#'   labels. Identifier and text columns are unchanged.
#' @seealso [eavs_recode_missing()] for the recoded values themselves.
#' @export
#'
#' @examples
#' df <- data.frame(
#'   FIPSCode = c("01001", "01003"),
#'   A1a = c("1200", "-99"),
#'   A3a = c("15", "-88")
#' )
#' eavs_missing_status(df)
eavs_missing_status <- function(data) {
  recode_core(data)$status
}

# Shared engine: classify each item column once, return both the numeric
# values and the status labels.
recode_core <- function(data) {
  is_item <- vapply(
    seq_along(data),
    function(i) item_column(data[[i]], names(data)[i]),
    logical(1)
  )
  values <- data
  status <- data
  for (i in which(is_item)) {
    cl <- classify_values(as.character(data[[i]]))
    values[[i]] <- cl$value
    status[[i]] <- factor(cl$status, levels = .eavs_status_levels)
  }
  list(
    values = tibble::as_tibble(values),
    status = tibble::as_tibble(status)
  )
}

# Is a column a numeric EAVS item, as opposed to an identifier or text field?
item_column <- function(x, name) {
  if (any(grepl(paste(.eavs_id_patterns, collapse = "|"), name, perl = TRUE))) {
    return(FALSE)
  }
  if (is.numeric(x)) {
    return(TRUE)
  }
  if (!is.character(x)) {
    return(FALSE)
  }
  trimmed <- trimws(strip_code_label(x))
  keep <- !is.na(x) & trimmed != "" &
    !(tolower(trimmed) %in% names(.eavs_token_status))
  if (!any(keep)) {
    return(FALSE)
  }
  all(!is.na(suppressWarnings(as.numeric(trimmed[keep]))))
}

# Turn a character item column into numeric values and matching status labels.
classify_values <- function(x) {
  x <- strip_code_label(x)
  n <- length(x)
  status <- rep("reported", n)
  value <- rep(NA_real_, n)

  trimmed <- trimws(x)
  blank <- is.na(x) | trimmed == ""
  status[blank] <- "blank"

  norm <- tolower(trimmed)
  tok <- !blank & norm %in% names(.eavs_token_status)
  status[tok] <- unname(.eavs_token_status[norm[tok]])

  rest <- !blank & !tok
  num <- suppressWarnings(as.numeric(trimmed[rest]))
  rstatus <- rep("reported", length(num))
  rvalue <- num

  sent <- match(as.character(num), names(.eavs_sentinels))
  is_sent <- !is.na(sent)
  rstatus[is_sent] <- unname(.eavs_sentinels[sent[is_sent]])
  rvalue[is_sent] <- NA_real_

  neg <- !is.na(num) & num < 0 & !is_sent
  rstatus[neg] <- "other_missing"
  rvalue[neg] <- NA_real_

  bad <- is.na(num)
  rstatus[bad] <- "other_missing"
  rvalue[bad] <- NA_real_

  status[rest] <- rstatus
  value[rest] <- rvalue
  list(value = value, status = status)
}
