## Checks eavs_load() against the totals the EAC publishes in its own reports.
##
## The figures come from metadata/reference_totals.csv, quoted from the EAC's
## Comprehensive Report with page provenance, so they are the agency's numbers
## rather than anything derived here. If sentinel decoding leaked a -99 into a
## sum, or a concept were mapped to the wrong year's code, these would move.
##
## Needs both the shared metadata and a populated cache, so it skips during
## R CMD check (which runs from a built copy with no metadata/ alongside) and
## runs under testthat::test_local() in a checkout. The Python suite has the
## same checks in py/tests/test_published_totals.py.

find_metadata <- function() {
  dir <- normalizePath(testthat::test_path("."), mustWork = FALSE)
  for (i in 1:6) {
    candidate <- file.path(dir, "metadata", "reference_totals.csv")
    if (file.exists(candidate)) {
      return(dirname(candidate))
    }
    parent <- dirname(dir)
    if (identical(parent, dir)) break
    dir <- parent
  }
  NULL
}

cached_years <- function(years) {
  cache <- eavs_cache_dir(create = FALSE)
  if (!dir.exists(cache)) {
    return(character())
  }
  vapply(years, function(y) {
    row <- eavs_manifest[eavs_manifest$survey == "eavs" &
                           eavs_manifest$format == "csv" &
                           eavs_manifest$year == y, ]
    nrow(row) == 1 && file.exists(file.path(cache, row$file_name))
  }, logical(1))
}

# A rate over only the jurisdictions that reported both sides. This is not a
# refinement: over all rows, uocava_counted / uocava_returned is 112% for 2024,
# because all 67 Alabama counties report the numerator and none the denominator.
pair_rate <- function(panel, numerator, denominator) {
  both <- !is.na(panel[[numerator]]) & !is.na(panel[[denominator]])
  100 * sum(panel[[numerator]][both]) / sum(panel[[denominator]][both])
}

# A voting-mode share of total participation among jurisdictions reporting that
# mode, which is the convention the EAC's own published shares follow.
mode_share <- function(panel, mode) {
  reported <- !is.na(panel[[mode]])
  100 * sum(panel[[mode]][reported]) / sum(panel$partic_total[reported], na.rm = TRUE)
}

metric_value <- function(panel, metric) {
  switch(
    metric,
    partic_total = sum(panel$partic_total, na.rm = TRUE),
    reg_active = sum(panel$reg_active, na.rm = TRUE),
    reg_forms_received = sum(panel$reg_forms_received, na.rm = TRUE),
    reg_confirmations_sent = sum(panel$reg_confirmations_sent, na.rm = TRUE),
    reg_removed_total = sum(panel$reg_removed_total, na.rm = TRUE),
    poll_workers_total = sum(panel$poll_workers_total, na.rm = TRUE),
    uocava_transmitted = sum(panel$uocava_transmitted, na.rm = TRUE),
    fwab_returned = sum(panel$fwab_returned, na.rm = TRUE),
    fwab_counted = sum(panel$fwab_counted, na.rm = TRUE),
    uocava_returned_rate = pair_rate(panel, "uocava_returned", "uocava_transmitted"),
    uocava_counted_rate = pair_rate(panel, "uocava_counted", "uocava_returned"),
    uocava_rejected_rate = pair_rate(panel, "uocava_rejected", "uocava_returned"),
    reg_new_valid_share = pair_rate(panel, "reg_new_valid", "reg_forms_received"),
    partic_in_person_ed_share = mode_share(panel, "partic_in_person_ed"),
    NULL
  )
}

test_that("published EAC report totals are reproduced", {
  meta <- find_metadata()
  skip_if(is.null(meta), "metadata/ not alongside the package")

  reference <- utils::read.csv(file.path(meta, "reference_totals.csv"),
                              stringsAsFactors = FALSE)
  years <- sort(unique(reference$year))
  have <- cached_years(years)
  skip_if_not(all(have), paste("needs cached EAVS csv for", toString(years[!have])))

  # Every citation needs a way to check it, or it sits in the file doing nothing.
  unimplemented <- unique(reference$metric[
    vapply(reference$metric, function(m) is.null(metric_value(NULL, m)), logical(1))
  ])
  expect_equal(unimplemented, character(0))

  panels <- lapply(years, function(y) eavs_load(y, quiet = TRUE))
  names(panels) <- as.character(years)

  for (i in seq_len(nrow(reference))) {
    row <- reference[i, ]
    got <- metric_value(panels[[as.character(row$year)]], row$metric)
    label <- sprintf("%d %s %s %s (%s)", row$year, row$metric, row$relation,
                     format(row$value, scientific = FALSE), row$source)
    if (row$relation == "gt") {
      expect_gt(got, row$value, label = label)
    } else if (row$relation == "lt") {
      expect_lt(got, row$value, label = label)
    } else {
      stop("unknown relation: ", row$relation)
    }
  }
})

test_that("rate denominators must be restricted to common reporters", {
  meta <- find_metadata()
  skip_if(is.null(meta), "metadata/ not alongside the package")
  skip_if_not(all(cached_years(2024)), "needs the 2024 file cached")

  panel <- eavs_load(2024, quiet = TRUE)
  naive <- 100 * sum(panel$uocava_counted, na.rm = TRUE) /
    sum(panel$uocava_returned, na.rm = TRUE)
  correct <- pair_rate(panel, "uocava_counted", "uocava_returned")

  # If someone "simplifies" pair_rate to a ratio of column sums, this fails.
  expect_gt(naive, 100)
  expect_gt(correct, 96)
  expect_lt(correct, 97)

  alabama <- panel[panel$state_abbr == "AL", ]
  expect_true(all(!is.na(alabama$uocava_counted)))
  expect_true(all(is.na(alabama$uocava_returned)))
})
