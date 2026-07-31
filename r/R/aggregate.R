#' Roll EAVS jurisdictions up to states, with honest coverage
#'
#' Sums a harmonized panel (see [eavs_load()]) to one row per group per concept,
#' and reports how many jurisdictions stood behind each number rather than
#' leaving you to assume all of them did.
#'
#' The output is long, one row per `year`, group, and `concept`, because a wide
#' frame carrying a value plus five counts for each of ~40 concepts is unusable.
#' Pivot it yourself if you want concepts as columns.
#'
#' @section Coverage:
#' Pass `status` (a [eavs_missing_status()] frame put through
#' [eavs_harmonize()]) and the counts distinguish *why* a jurisdiction is
#' absent. That distinction matters: EAVS separates "does not apply" from "data
#' not available", and treating them alike misreports coverage in both
#' directions. In 2024 a thousand jurisdictions had no provisional ballots at
#' all, so counting them as gaps drops apparent coverage of `prov_rejected`
#' from 94.5% to 79.9% when nothing is missing.
#'
#' Five buckets, which sum to `n_total`:
#'
#' - `n_reported` gave a number, and are in `value`.
#' - `n_missing` are the genuine gaps (`not_available`, `other_missing`): the
#'   ones that make a total untrustworthy.
#' - `n_blank` left the cell empty, which the file does not explain. A blank
#'   could be a gap or a skip, so it is counted separately and the call is
#'   yours. Most blanks are 2016 Maine, whose municipalities leave the UOCAVA
#'   items to the statewide row.
#' - `n_not_applicable` said the item did not pertain (`does_not_apply`,
#'   `valid_skip`), so nothing is missing.
#' - `n_not_collected` were never asked, because the concept was not on that
#'   year's questionnaire.
#'
#' `coverage` is `n_reported / (n_reported + n_missing + n_blank)`: the share of
#' jurisdictions that could have answered and did. The last two buckets stay out
#' of the denominator, since nothing is missing there. Without `status` the
#' reason is unknowable after recoding, so every absence lands in `n_missing`
#' and `coverage` is a lower bound; `coverage_exact` says which case you have.
#'
#' `coverage_reg` weights the same ratio by `reg_eligible_total`, answering how
#' much of the electorate the reporters hold rather than how many of them there
#' were. Since `value` is a sum, that is usually the better guide to how much of
#' it you have: in 2024 `ballots_cured` comes from 28.5% of jurisdictions but
#' 65.9% of the registered electorate. Jurisdictions with no usable weight leave
#' both sides of the ratio, and the column is `NA` if the panel carries no
#' `reg_eligible_total`.
#'
#' @section Anomalous state-years:
#' `known_anomaly` is `TRUE` where this year, state, and concept are recorded in
#' [eavs_known_anomalies] and at least one jurisdiction in the group reported a
#' value, so the total rests on the anomalous convention. Coverage cannot tell
#' you this: Iowa's 2018 polling places are reported by all 99 counties, so every
#' coverage column reads as complete, and the state total is still not comparable
#' to its other cycles. The value is summed as reported either way, and what to
#' do about it is yours; [eavs_flags()] gives the reason and the evidence.
#'
#' @section What is not corrected:
#' Nothing. Values are summed as reported, and `NA` is skipped rather than
#' imputed, so a "does not apply" never becomes a zero. Maine's statewide UOCAVA
#' row and the territories are included, because both carry real reported data.
#' Filter them afterwards if your analysis wants that; `entity_type` and
#' [eavs_jurisdictions] make it a one-liner.
#'
#' @param data A harmonized panel from [eavs_load()], or one year from
#'   [eavs_harmonize()].
#' @param status Optional. The matching [eavs_missing_status()] output, harmonized
#'   the same way, which makes the coverage counts reason-aware. It must line up
#'   with `data` row for row; `year` and `fips_code` are checked, so a frame
#'   bound in a different year order is an error rather than wrong coverage.
#' @param by `"state"` (default) or `"county"`. County rollups drop rows whose
#'   published code embeds no county, and say how many: Wisconsin's serials,
#'   Maine's statewide row, Alaska, the territories. Wisconsin stays out even
#'   though [eavs_jurisdictions] parses its county names, because the ~57
#'   municipalities that straddle county lines include the City of Milwaukee.
#' @param concepts Optional character vector limiting which concepts to roll up.
#' @param jurisdictions The jurisdiction table to join for county codes. Defaults
#'   to the bundled [eavs_jurisdictions].
#' @param anomalies The verified reporting anomalies to mark. Defaults to the
#'   bundled [eavs_known_anomalies]; pass your own or set to `NULL` to skip them.
#'
#' @return A tibble with one row per group per concept per year: the grouping
#'   columns, `entity_type` (`"state"`, `"territory"`, or `"district"`, so a
#'   50-state analysis is one filter), `concept`, `value`, the five bucket
#'   counts, `n_total`, `coverage`, `coverage_reg`, `coverage_exact`, and
#'   `known_anomaly`.
#' @seealso [eavs_rate()] for a rate rather than a total, [eavs_flags()] for
#'   consistency checks, [eavs_missing_status()] for per-jurisdiction reasons.
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
                           jurisdictions = NULL, anomalies = NULL) {
  by <- match.arg(by, c("state", "county"))
  if (missing(anomalies)) {
    anomalies <- eavs_known_anomalies
  }

  if (!"year" %in% names(data)) {
    cli::cli_abort("{.arg data} needs a {.field year} column; use {.fn eavs_load}.")
  }
  if (!is.null(status)) {
    if (nrow(status) != nrow(data)) {
      cli::cli_abort(c(
        "{.arg status} must line up row-for-row with {.arg data}.",
        x = "{.arg data} has {nrow(data)} rows, {.arg status} has {nrow(status)}.",
        i = "Harmonize both from the same {.fn eavs_read} call."
      ))
    }
    # Matching row counts are not alignment: binding per-year status frames in a
    # different year order than the panel passes the count check and then
    # reports another year's coverage. Both frames carry the keys to prove it.
    for (key in intersect(c("year", "fips_code"), intersect(names(data), names(status)))) {
      if (!identical(as.character(data[[key]]), as.character(status[[key]]))) {
        cli::cli_abort(c(
          "{.arg status} is not aligned with {.arg data}.",
          x = "Their {.field {key}} columns differ row-for-row.",
          i = "Bind the per-year status frames in the same year order as {.fn eavs_load}."
        ))
      }
    }
  }

  item_cols <- aggregate_items(data, concepts)
  keys <- aggregate_keys(data, by, jurisdictions)
  # The coverage_reg weight, taken from the panel itself whether or not
  # reg_eligible_total is among the concepts being rolled up.
  weight <- if ("reg_eligible_total" %in% names(data)) {
    data$reg_eligible_total
  } else {
    NULL
  }

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
      keys = keys,
      weight = weight
    )
  }
  res <- dplyr::bind_rows(out)

  res$entity_type <- entity_type_of(res$state_abbr)
  # A total can rest on an anomalous reporting convention while every coverage
  # column reads as complete, so say so here rather than leaving it to a
  # separate eavs_flags() call the user has to know to make.
  res$known_anomaly <- anomaly_match(res$year, res$state_abbr, res$concept,
                                     anomalies) & res$n_reported > 0

  key_names <- setdiff(names(keys), ".row")
  res <- res[order(res$year, res$concept), c("year", setdiff(key_names, "year"),
                                             "entity_type", "concept", "value",
                                             "n_reported", "n_missing",
                                             "n_blank", "n_not_applicable",
                                             "n_not_collected",
                                             "n_total", "coverage",
                                             "coverage_reg",
                                             "coverage_exact",
                                             "known_anomaly")]
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
aggregate_one <- function(concept, value, reason, keys, weight = NULL) {
  keep <- if ("county_fips" %in% names(keys)) !is.na(keys$county_fips) else TRUE
  keys <- keys[keep, , drop = FALSE]
  value <- value[keep]
  if (!is.null(reason)) {
    reason <- reason[keep]
  }
  if (!is.null(weight)) {
    weight <- weight[keep]
  }

  group <- interaction(keys, drop = TRUE, lex.order = TRUE)
  exact <- !is.null(reason)
  none <- rep(FALSE, length(value))

  # Without a status frame the reason is gone, so every absence is a gap.
  # With one, an NA reason means the concept was not on that year's
  # questionnaire (a multi-year status bind fills those rows with NA), which
  # gets its own bucket so the five sum to n_total.
  is_not_collected <- if (exact) is.na(reason) else none
  is_reported <- if (exact) !is_not_collected & reason == "reported" else !is.na(value)
  is_na_ok <- if (exact) reason %in% c("does_not_apply", "valid_skip") else none
  # A blank is ambiguous—gap or skip, the file does not say—so it is counted
  # apart rather than folded into either. See the Coverage section.
  is_blank <- if (exact) !is_not_collected & reason == "blank" else none
  is_gap <- !is_reported & !is_na_ok & !is_blank & !is_not_collected

  agg <- function(x) as.integer(tapply(x, group, sum, na.rm = TRUE))
  totals <- as.numeric(tapply(value, group, sum, na.rm = TRUE))

  first_rows <- match(levels(group), as.character(group))
  res <- keys[first_rows, , drop = FALSE]
  res$concept <- concept
  res$value <- totals
  res$n_reported <- agg(is_reported)
  res$n_missing <- agg(is_gap)
  res$n_blank <- agg(is_blank)
  res$n_not_applicable <- agg(is_na_ok)
  res$n_not_collected <- agg(is_not_collected)
  res$n_total <- as.integer(table(group))
  answerable <- res$n_reported + res$n_missing + res$n_blank
  res$coverage <- ifelse(answerable > 0, res$n_reported / answerable, NA_real_)

  # Registration-weighted coverage: how much of the electorate the reporting
  # jurisdictions hold. Rows with no usable weight contribute to neither side.
  if (is.null(weight)) {
    res$coverage_reg <- NA_real_
  } else {
    w <- ifelse(is.na(weight), 0, as.numeric(weight))
    wagg <- function(flag) as.numeric(tapply(ifelse(flag, w, 0), group, sum, na.rm = TRUE))
    w_reported <- wagg(is_reported)
    w_answerable <- w_reported + wagg(is_gap) + wagg(is_blank)
    res$coverage_reg <- ifelse(w_answerable > 0, w_reported / w_answerable, NA_real_)
  }
  res$coverage_exact <- exact
  res
}
