#' Flag internal inconsistencies in an EAVS panel
#'
#' Runs a set of arithmetic checks over a harmonized panel and returns one row
#' per flagged observation. Three kinds: subparts summing past a total (see
#' [eavs_checks]), a value swinging by more than `swing_factor` against the same
#' jurisdiction's previous cycle, and the reporting anomalies recorded in
#' [eavs_known_anomalies], which arithmetic cannot catch because the numbers
#' reconcile internally.
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
#' `state_share` is roughly how much of its state's total for that concept the
#' flagged jurisdiction holds, and it is the column to sort by when the question
#' is whether a flag could move a number you plan to publish. A discrepancy in a
#' jurisdiction holding 0.2% of the state's mail ballots cannot; one holding 40%
#' can. `excess` will not tell you this, because it is measured on the concept's
#' own scale: a large county's small discrepancy outranks a small county's
#' complete one.
#'
#' The numerator is the larger of `observed` and `threshold`, since the smaller
#' one is often the reason the flag fired. Utah's Washington County reports 943
#' mail ballots returned in 2022 against 65,664 counted, so taking the reported
#' total would call it 0.09% of the state when the county cast 6.5% of Utah's
#' ballots. The share can therefore run above 1. That happens on a sum check
#' where the suspect total is most of what the state reported (the Virgin Islands
#' file as a single jurisdiction), and on a swing where the larger number belongs
#' to the previous cycle while the denominator belongs to this one.
#'
#' `state_share` measures size, not severity. What a flag means for your analysis
#' is still yours to decide.
#'
#' For a known anomaly there is no comparison, only a documented reason to read
#' the value with the `note` in hand, so `observed` is the reported value and
#' `threshold`, `excess`, and `n_parts_reported` are `NA`.
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
#' @param anomalies The known anomalies to surface. Defaults to the bundled
#'   [eavs_known_anomalies]; pass your own or set to `NULL` to skip them.
#' @param jurisdictions The jurisdiction table used to line jurisdictions up
#'   across years for the swing checks. Defaults to the bundled
#'   [eavs_jurisdictions].
#'
#' @return A tibble with one row per flag: `year`, `fips_code`, `state_abbr`,
#'   `jurisdiction_name`, `check`, `kind` (`"sum"`, `"swing"`, or
#'   `"known_anomaly"`), `concept`,
#'   `observed`, `threshold`, `excess`, `n_parts_reported`, `state_share`, and
#'   `note`. Zero rows if nothing is flagged.
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
#'
#' # Or the ones big enough to move a state number:
#' sums <- flags[flags$kind == "sum", ]
#' head(sums[order(-sums$state_share), c("state_abbr", "jurisdiction_name",
#'                                       "check", "state_share")])
#' }
eavs_flags <- function(data, checks = NULL, swing_factor = 10,
                       swing_floor = 100, anomalies = NULL,
                       jurisdictions = NULL) {
  if (!"year" %in% names(data)) {
    cli::cli_abort("{.arg data} needs a {.field year} column; use {.fn eavs_load}.")
  }
  if (missing(checks)) {
    checks <- eavs_checks
  }
  if (missing(anomalies)) {
    anomalies <- eavs_known_anomalies
  }

  out <- list()
  if (!is.null(checks) && nrow(checks) > 0) {
    out <- c(out, flag_sums(data, checks))
  }
  if (!is.null(swing_factor)) {
    out <- c(out, list(flag_swings(data, swing_factor, swing_floor, jurisdictions)))
  }
  if (!is.null(anomalies) && nrow(anomalies) > 0) {
    out <- c(out, flag_known_anomalies(data, anomalies))
  }

  res <- dplyr::bind_rows(out)
  cols <- c("year", "fips_code", "state_abbr", "jurisdiction_name", "check",
            "kind", "concept", "observed", "threshold", "excess",
            "n_parts_reported", "state_share", "note")
  if (nrow(res) == 0) {
    empty <- lapply(cols, function(x) switch(
      x,
      year = integer(), observed = numeric(), threshold = numeric(),
      excess = numeric(), n_parts_reported = integer(),
      state_share = numeric(), character()
    ))
    names(empty) <- cols
    return(tibble::as_tibble(empty))
  }
  res$state_share <- flag_state_share(data, res)
  # Sort within kind, not across it: `excess` is a count for sum checks and a
  # fold-change for swings, so a global sort would let raw ballot counts bury
  # every swing. Known-anomaly rows have no excess; the -Inf fill keeps them
  # grouped under their kind instead of order() shunting NA rows to the end.
  res <- res[, cols]
  ord <- ifelse(is.na(res$excess), -Inf, res$excess)
  tibble::as_tibble(res[order(res$kind, -ord), ])
}

# How big is this jurisdiction, in this concept, within its state-year? A flag on
# a jurisdiction holding 0.1% of the state's mail ballots cannot move a state
# number; one holding 40% can, and nothing else in the output distinguishes them:
# `excess` is on the concept's own scale, so it ranks a large county's small
# discrepancy above a small county's total one.
#
# The numerator is the larger of the two numbers already on the row, because the
# smaller one is often the reason the flag fired and would hide a large
# jurisdiction. Utah's Washington County reports 943 mail ballots returned in
# 2022 against 65,664 counted: taking the reported total would call it 0.09% of
# the state when the county cast 6.5% of Utah's ballots. A dropped_to_zero flag
# is the same problem in the other direction, its current value being zero by
# construction. Grouping on year + state_abbr rather than fips_code keeps the
# Wisconsin serials shared by a town/village pair out of it.
flag_state_share <- function(data, res) {
  share <- rep(NA_real_, nrow(res))
  if (!"state_abbr" %in% names(data)) {
    return(share)
  }
  own <- pmax(res$observed, res$threshold, na.rm = TRUE)
  group <- paste(data$year, data$state_abbr)
  for (concept in unique(res$concept)) {
    if (!concept %in% names(data)) {
      next
    }
    totals <- tapply(as.numeric(data[[concept]]), group, sum, na.rm = TRUE)
    hit <- which(res$concept == concept)
    denom <- as.numeric(totals[paste(res$year[hit], res$state_abbr[hit])])
    share[hit] <- ifelse(!is.na(denom) & denom > 0, own[hit] / denom, NA_real_)
  }
  share
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

# Verified reporting anomalies: one flag per affected observation, carrying
# the anomaly's note. Reported values only—a jurisdiction with NA is not
# carrying the anomalous convention.
flag_known_anomalies <- function(data, anomalies) {
  if (!"state_abbr" %in% names(data)) {
    return(NULL)
  }
  out <- list()
  for (i in seq_len(nrow(anomalies))) {
    concept <- anomalies$concept[i]
    if (!concept %in% names(data)) {
      next
    }
    keep <- which(data$year == anomalies$year[i] &
                    data$state_abbr == anomalies$state_abbr[i] &
                    !is.na(data[[concept]]))
    if (length(keep) == 0) {
      next
    }
    res <- flag_ids(data, keep)
    res$check <- "known_anomaly"
    res$kind <- "known_anomaly"
    res$concept <- concept
    res$observed <- as.numeric(data[[concept]][keep])
    res$threshold <- NA_real_
    res$excess <- NA_real_
    res$n_parts_reported <- NA_integer_
    res$note <- anomalies$note[i]
    out[[length(out) + 1]] <- res
  }
  out
}

# Lining a jurisdiction up with itself in the previous cycle. The published
# code will not do it alone: two 2024 California counties lost a leading zero,
# Maine's statewide row is "23." then "23", New York and South Dakota each
# recode a county, and a few Wisconsin serials are shared by two rows in one
# year. So normalize to fips10 where the jurisdiction table has one, and where
# a code really is shared, add the name so a village is never silently
# compared against the town next door.
swing_keys <- function(data, jurisdictions = NULL) {
  jur <- if (is.null(jurisdictions)) eavs_jurisdictions else jurisdictions
  key <- as.character(data$fips_code)

  if (all(c("year", "fips_code", "fips10") %in% names(jur))) {
    idx <- match(paste(data$year, data$fips_code), paste(jur$year, jur$fips_code))
    norm <- jur$fips10[idx]
    key <- ifelse(is.na(norm), key, norm)
  }
  if ("jurisdiction_name" %in% names(data)) {
    # Add the name in *every* year a shared code appears, not only the year it
    # collides in: the pair is published under one serial in 2020 and
    # separately in 2022, and a key that changes shape between them would stop
    # the same town matching itself.
    collides <- unlist(lapply(split(key, data$year), function(k) k[duplicated(k)]))
    shared <- key %in% unique(collides)
    key[shared] <- paste(key[shared], data$jurisdiction_name[shared])
  }
  key
}

# A value swinging hard against the same jurisdiction's previous cycle.
flag_swings <- function(data, swing_factor, swing_floor, jurisdictions = NULL) {
  if (!"fips_code" %in% names(data) || length(unique(data$year)) < 2) {
    return(NULL)
  }
  keys <- swing_keys(data, jurisdictions)
  concepts <- setdiff(
    names(data)[vapply(data, is.numeric, logical(1))],
    c("year", "survey")
  )
  years <- sort(unique(data$year))

  out <- list()
  for (k in seq_along(years)[-1]) {
    is_now <- data$year == years[k]
    is_before <- data$year == years[k - 1]
    now <- data[is_now, , drop = FALSE]
    before <- data[is_before, , drop = FALSE]
    idx <- match(keys[is_now], keys[is_before])

    unmatched <- sum(is.na(idx))
    if (unmatched > 0) {
      cli::cli_inform(c(
        "!" = paste("{unmatched} {years[k]} jurisdiction{?s} had no counterpart in",
                    "{years[k - 1]}, so {?it/they} {?is/are} not swing-checked."),
        i = "New jurisdictions, and codes shared by two rows in one year, look like this."
      ))
    }

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
