#' Flag internal inconsistencies in an EAVS panel
#'
#' Runs a set of arithmetic checks over a harmonized panel and returns one row
#' per flagged observation. Two kinds: subparts summing past a total (see
#' [eavs_checks]), and a value swinging by more than `swing_factor` against the
#' same jurisdiction's previous cycle.
#'
#' @section These are flags, not errors:
#' A flag says two reported numbers do not reconcile arithmetically. It does not
#' say either is wrong. Thousands of independent jurisdictions keep records in
#' different ways, and most flags have ordinary explanations: ballots transmitted
#' before the reporting window opened, a jurisdiction that treats "returned" as
#' "returned and accepted" so rejections sit outside it, mode categories that
#' overlap, registration forms counted with or without duplicates. Each check's
#' `note` in [eavs_checks] spells out the usual explanations for that check.
#'
#' Nothing is changed. tidyeavs does not alter reported values, and this function
#' only reports; deciding what a flag means for your analysis is yours. The EAC
#' publishes its own validation rules and revises datasets as corrections come
#' in, so a flag here may already be known upstream.
#'
#' @section Reading the output:
#' For a sum check, `observed` is the sum of the check's `parts`, `threshold` is
#' the `total` it was compared against, and `excess` is the difference in
#' ballots (or forms, or whatever the concept counts). For a swing, `observed` is
#' this cycle's value, `threshold` is the previous cycle's, and `excess` is how
#' far the fold-change ran past `swing_factor`. The two are on different scales,
#' so the result is sorted within `kind` rather than across it; filter to one
#' kind before sorting yourself.
#'
#' `n_parts_reported` says how many of the check's parts had a value. A partial
#' sum that already exceeds the total is still a genuine flag, since the absent
#' parts could only add to it.
#'
#' @param data A harmonized panel from [eavs_load()]. Needs `year` and, for
#'   swing checks, more than one year.
#' @param checks The checks to run. Defaults to the bundled [eavs_checks]; pass a
#'   subset or your own to change them. Set to `NULL` to skip sum checks.
#' @param swing_factor Flag a value that is more than this many times, or less
#'   than this fraction of, the same jurisdiction's previous cycle. `NULL` skips
#'   swing checks. Defaults to `10`.
#' @param swing_floor Ignore swings where both cycles are below this value, so
#'   that a count going from 1 to 20 does not dominate the output. Defaults
#'   to `100`.
#'
#' @return A tibble with one row per flag: `year`, `fips_code`, `state_abbr`,
#'   `jurisdiction_name`, `check`, `kind` (`"sum"` or `"swing"`), `concept`,
#'   `observed`, `threshold`, `excess`, `n_parts_reported`, and `note`. Zero rows
#'   if nothing is flagged.
#' @seealso [eavs_checks] for the check definitions, [eavs_aggregate()] for
#'   coverage-aware rollups.
#' @export
#'
#' @examples
#' \dontrun{
#' panel <- eavs_load(c(2022, 2024))
#' flags <- eavs_flags(panel)
#'
#' # Largest discrepancies first:
#' flags[order(-flags$excess), ]
#' }
eavs_flags <- function(data, checks = NULL, swing_factor = 10,
                       swing_floor = 100) {
  if (!"year" %in% names(data)) {
    cli::cli_abort("{.arg data} needs a {.field year} column; use {.fn eavs_load}.")
  }
  if (missing(checks)) {
    checks <- eavs_checks
  }

  out <- list()
  if (!is.null(checks) && nrow(checks) > 0) {
    out <- c(out, flag_sums(data, checks))
  }
  if (!is.null(swing_factor)) {
    out <- c(out, list(flag_swings(data, swing_factor, swing_floor)))
  }

  res <- dplyr::bind_rows(out)
  cols <- c("year", "fips_code", "state_abbr", "jurisdiction_name", "check",
            "kind", "concept", "observed", "threshold", "excess",
            "n_parts_reported", "note")
  if (nrow(res) == 0) {
    empty <- lapply(cols, function(x) switch(
      x,
      year = integer(), observed = numeric(), threshold = numeric(),
      excess = numeric(), n_parts_reported = integer(), character()
    ))
    names(empty) <- cols
    return(tibble::as_tibble(empty))
  }
  # Sort within kind, not across it: `excess` is a count for sum checks and a
  # fold-change for swings, so a global sort would let raw ballot counts bury
  # every swing.
  res <- res[, cols]
  tibble::as_tibble(res[order(res$kind, -res$excess), ])
}

# Identifier columns carried onto every flag row, when present.
flag_ids <- function(data, keep) {
  ids <- c("year", "fips_code", "state_abbr", "jurisdiction_name")
  present <- intersect(ids, names(data))
  res <- data[keep, present, drop = FALSE]
  for (nm in setdiff(ids, present)) {
    res[[nm]] <- NA_character_
  }
  res
}

# Parts summing past their total.
flag_sums <- function(data, checks) {
  out <- vector("list", nrow(checks))
  for (i in seq_len(nrow(checks))) {
    total_col <- checks$total[i]
    parts <- checks$parts[[i]]
    if (is.character(parts) && length(parts) == 1) {
      parts <- strsplit(parts, ";", fixed = TRUE)[[1]]
    }
    parts <- intersect(parts, names(data))
    if (!total_col %in% names(data) || length(parts) == 0) {
      next
    }

    part_mat <- as.matrix(data[, parts, drop = FALSE])
    n_reported <- rowSums(!is.na(part_mat))
    observed <- rowSums(part_mat, na.rm = TRUE)
    observed[n_reported == 0] <- NA_real_
    threshold <- data[[total_col]]

    keep <- which(!is.na(observed) & !is.na(threshold) & observed > threshold)
    if (length(keep) == 0) {
      next
    }
    res <- flag_ids(data, keep)
    res$check <- checks$check[i]
    res$kind <- "sum"
    res$concept <- total_col
    res$observed <- observed[keep]
    res$threshold <- threshold[keep]
    res$excess <- observed[keep] - threshold[keep]
    res$n_parts_reported <- as.integer(n_reported[keep])
    res$note <- checks$note[i]
    out[[i]] <- res
  }
  out
}

# A value swinging hard against the same jurisdiction's previous cycle.
flag_swings <- function(data, swing_factor, swing_floor) {
  if (!"fips_code" %in% names(data) || length(unique(data$year)) < 2) {
    return(NULL)
  }
  concepts <- setdiff(
    names(data)[vapply(data, is.numeric, logical(1))],
    c("year", "survey")
  )
  years <- sort(unique(data$year))

  out <- list()
  for (k in seq_along(years)[-1]) {
    now <- data[data$year == years[k], , drop = FALSE]
    before <- data[data$year == years[k - 1], , drop = FALSE]
    idx <- match(now$fips_code, before$fips_code)

    for (concept in concepts) {
      a <- now[[concept]]
      b <- before[[concept]][idx]
      both <- !is.na(a) & !is.na(b) & pmax(a, b) >= swing_floor

      # A value falling to zero is its own case, not an infinite fold-change:
      # the ratio math would report Inf and bury every finite swing under it.
      zeroed <- which(both & b > 0 & a == 0)
      if (length(zeroed) > 0) {
        res <- flag_ids(now, zeroed)
        res$check <- "dropped_to_zero"
        res$kind <- "swing"
        res$concept <- concept
        res$observed <- 0
        res$threshold <- b[zeroed]
        res$excess <- b[zeroed]
        res$n_parts_reported <- 1L
        res$note <- sprintf(
          paste("Reported %s in %d and zero here. A genuine zero and a year the",
                "item went unreported both look like this, so check the same",
                "row in eavs_missing_status() before treating it as a change."),
          # trim = TRUE, or format() pads every value to the widest one.
          format(b[zeroed], big.mark = ",", trim = TRUE), years[k - 1]
        )
        out[[length(out) + 1]] <- res
      }

      comparable <- both & b > 0 & a > 0
      ratio <- ifelse(comparable, a / b, NA_real_)
      keep <- which(comparable & (ratio > swing_factor | ratio < 1 / swing_factor))
      if (length(keep) == 0) {
        next
      }
      res <- flag_ids(now, keep)
      res$check <- "year_over_year_swing"
      res$kind <- "swing"
      res$concept <- concept
      res$observed <- a[keep]
      res$threshold <- b[keep]
      # Fold-change past the allowed band, so swings rank against each other
      # rather than against raw ballot counts.
      res$excess <- pmax(ratio[keep], 1 / ratio[keep]) - swing_factor
      res$n_parts_reported <- 1L
      res$note <- sprintf(
        paste("Changed %.1f-fold against %d. Real shifts happen (a state moving",
              "to all-mail, a question changing scope), so check the concept's",
              "note in eavs_items() before reading this as a discrepancy."),
        ratio[keep], years[k - 1]
      )
      out[[length(out) + 1]] <- res
    }
  }
  dplyr::bind_rows(out)
}
