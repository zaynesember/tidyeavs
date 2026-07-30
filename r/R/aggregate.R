#' Roll EAVS jurisdictions up to states, with honest coverage
#'
#' Sums a harmonized panel (see [eavs_load()]) to one row per group per concept.
#' EAVS totals are only as good as the jurisdictions behind them, so this reports
#' how many jurisdictions stood behind each number rather than leaving you to
#' assume all of them did.
#'
#' The output is long — one row per `year`, group, and `concept` — because a wide
#' frame carrying a value plus three counts for each of ~35 concepts is unusable.
#' Pivot it yourself if you want concepts as columns.
#'
#' @section Coverage:
#' Pass `status` (a [eavs_missing_status()] frame put through
#' [eavs_harmonize()]) and the counts distinguish *why* a jurisdiction is absent,
#' which matters more than it sounds. EAVS separates "does not apply" from "data
#' not available", and treating them alike misreports coverage in both
#' directions: in 2024, 1,000 jurisdictions reported no provisional ballots at
#' all, so counting them as a gap drops apparent coverage of
#' `prov_rejected` from 94.5% to 79.9% when nothing is actually missing.
#'
#' Three buckets, then:
#'
#' - `n_reported` — jurisdictions that gave a number, and so are in `value`.
#' - `n_missing` — genuine gaps: `not_available`, `other_missing`, `blank`. These
#'   are what make a total untrustworthy.
#' - `n_not_applicable` — `does_not_apply` and `valid_skip`. The item did not
#'   pertain, so nothing is missing. Excluded from the `coverage` denominator.
#'
#' `coverage` is `n_reported / (n_reported + n_missing)`: the share of
#' jurisdictions that *could* have answered and did. Without `status`, the
#' reason is unknowable after recoding, so every absence lands in `n_missing`
#' and `coverage` is a lower bound; the `coverage_exact` column says which
#' situation you are in.
#'
#' @section What is not corrected:
#' Nothing. Values are summed as reported, with `NA` skipped and never imputed —
#' a "does not apply" is not turned into a zero. Maine's statewide UOCAVA row and
#' the territories are included, since both carry real reported data (in 2024 no
#' Maine county reports UOCAVA at all, so dropping that row would lose the
#' state's only figures). Filter them out afterwards if your analysis wants that;
#' [eavs_jurisdictions] types every row so it is a one-liner.
#'
#' @param data A harmonized panel from [eavs_load()], or one year from
#'   [eavs_harmonize()].
#' @param status Optional. The matching [eavs_missing_status()] output, harmonized
#'   the same way, which makes the coverage counts reason-aware. Must have the
#'   same number of rows as `data`.
#' @param by `"state"` (default) or `"county"`. County rollups drop rows whose
#'   published code embeds no county — Wisconsin's non-geographic serials, Maine's
#'   statewide row, Alaska and the territories — and say how many, loudly.
#' @param concepts Optional character vector limiting which concepts to roll up.
#' @param jurisdictions The jurisdiction table to join for county codes. Defaults
#'   to the bundled [eavs_jurisdictions].
#'
#' @return A tibble with one row per group per concept per year: the grouping
#'   columns, `concept`, `value`, `n_reported`, `n_missing`, `n_not_applicable`,
#'   `n_total`, `coverage`, and `coverage_exact`.
#' @seealso [eavs_missing_status()] for per-jurisdiction reasons.
#' @export
#'
#' @examples
#' \dontrun{
#' panel <- eavs_load(2024)
#' eavs_aggregate(panel)
#'
#' # Reason-aware coverage needs the status frame alongside:
#' raw <- eavs_read(2024)
#' st <- eavs_harmonize(eavs_missing_status(raw), year = 2024)
#' eavs_aggregate(panel, status = st)
#' }
eavs_aggregate <- function(data, status = NULL, by = "state", concepts = NULL,
                           jurisdictions = NULL) {
  by <- match.arg(by, c("state", "county"))

  if (!"year" %in% names(data)) {
    cli::cli_abort("{.arg data} needs a {.field year} column; use {.fn eavs_load}.")
  }
  if (!is.null(status) && nrow(status) != nrow(data)) {
    cli::cli_abort(c(
      "{.arg status} must line up row-for-row with {.arg data}.",
      x = "{.arg data} has {nrow(data)} rows, {.arg status} has {nrow(status)}.",
      i = "Harmonize both from the same {.fn eavs_read} call."
    ))
  }

  item_cols <- aggregate_items(data, concepts)
  keys <- aggregate_keys(data, by, jurisdictions)

  out <- vector("list", length(item_cols))
  for (i in seq_along(item_cols)) {
    out[[i]] <- aggregate_one(
      concept = item_cols[i],
      value = data[[item_cols[i]]],
      reason = if (is.null(status) || !item_cols[i] %in% names(status)) {
        NULL
      } else {
        as.character(status[[item_cols[i]]])
      },
      keys = keys
    )
  }
  res <- dplyr::bind_rows(out)

  key_names <- setdiff(names(keys), ".row")
  res <- res[order(res$year, res$concept), c("year", setdiff(key_names, "year"),
                                             "concept", "value", "n_reported",
                                             "n_missing", "n_not_applicable",
                                             "n_total", "coverage",
                                             "coverage_exact")]
  tibble::as_tibble(res)
}

# Which columns are concepts to sum, as opposed to identifiers?
aggregate_items <- function(data, concepts = NULL) {
  ids <- c("year", "survey", "fips_code", "jurisdiction_name", "state_abbr",
           "state_name", "state_fips", "county_fips")
  candidates <- setdiff(names(data), ids)
  numeric_ok <- vapply(candidates, function(nm) is.numeric(data[[nm]]), logical(1))
  items <- candidates[numeric_ok]

  if (!is.null(concepts)) {
    unknown <- setdiff(concepts, items)
    if (length(unknown) > 0) {
      cli::cli_abort(c(
        "Not numeric concept column{?s} in {.arg data}: {.val {unknown}}.",
        i = "Available: {.val {items}}."
      ))
    }
    items <- concepts
  }
  if (length(items) == 0) {
    cli::cli_abort(c(
      "No numeric concept columns found in {.arg data}.",
      i = "Did you forget {.fn eavs_recode_missing} before harmonizing?"
    ))
  }
  items
}

# The grouping columns, joining the jurisdiction table when rolling up to county.
aggregate_keys <- function(data, by, jurisdictions = NULL) {
  if (!"state_abbr" %in% names(data)) {
    cli::cli_abort("{.arg data} needs a {.field state_abbr} column to group by.")
  }
  keys <- tibble::tibble(year = data$year, state_abbr = data$state_abbr)
  if (by == "state") {
    return(keys)
  }

  jur <- if (is.null(jurisdictions)) eavs_jurisdictions else jurisdictions
  if (!"fips_code" %in% names(data)) {
    cli::cli_abort("A county rollup needs a {.field fips_code} column in {.arg data}.")
  }
  idx <- match(
    paste(data$year, data$fips_code),
    paste(jur$year, jur$fips_code)
  )
  keys$county_fips <- jur$county_fips[idx]

  unmatched <- sum(is.na(idx))
  if (unmatched > 0) {
    cli::cli_warn(
      "{unmatched} row{?s} did not match {.arg jurisdictions} on year + fips_code."
    )
  }
  dropped <- sum(is.na(keys$county_fips))
  if (dropped > 0) {
    cli::cli_inform(c(
      "!" = "Dropping {dropped} row{?s} with no county in the published code.",
      i = paste("Wisconsin's non-geographic serials, Maine's statewide row,",
                "Alaska, and the territories have none.")
    ))
  }
  keys
}

# Sum one concept within groups, counting why jurisdictions are absent.
aggregate_one <- function(concept, value, reason, keys) {
  keep <- if ("county_fips" %in% names(keys)) !is.na(keys$county_fips) else TRUE
  keys <- keys[keep, , drop = FALSE]
  value <- value[keep]
  if (!is.null(reason)) {
    reason <- reason[keep]
  }

  group <- interaction(keys, drop = TRUE, lex.order = TRUE)
  exact <- !is.null(reason)

  # Without a status frame the reason is gone, so every absence is a gap.
  is_reported <- if (exact) reason == "reported" else !is.na(value)
  is_na_ok <- if (exact) reason %in% c("does_not_apply", "valid_skip") else rep(FALSE, length(value))
  is_gap <- !is_reported & !is_na_ok

  agg <- function(x) as.integer(tapply(x, group, sum, na.rm = TRUE))
  totals <- as.numeric(tapply(value, group, sum, na.rm = TRUE))

  first_rows <- match(levels(group), as.character(group))
  res <- keys[first_rows, , drop = FALSE]
  res$concept <- concept
  res$value <- totals
  res$n_reported <- agg(is_reported)
  res$n_missing <- agg(is_gap)
  res$n_not_applicable <- agg(is_na_ok)
  res$n_total <- as.integer(table(group))
  answerable <- res$n_reported + res$n_missing
  res$coverage <- ifelse(answerable > 0, res$n_reported / answerable, NA_real_)
  res$coverage_exact <- exact
  res
}
