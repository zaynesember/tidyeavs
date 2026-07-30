## Fixtures: two states, four jurisdictions, so every count is checkable by hand.

panel_fixture <- function() {
  tibble::tibble(
    year = rep(2024L, 4),
    fips_code = c("0100100000", "0100300000", "2300100000", "23"),
    state_abbr = c("AL", "AL", "ME", "ME"),
    mail_rejected = c(10, 20, 5, NA),
    prov_rejected = c(1, NA, NA, NA)
  )
}

status_fixture <- function() {
  tibble::tibble(
    year = rep(2024L, 4),
    fips_code = c("0100100000", "0100300000", "2300100000", "23"),
    state_abbr = c("AL", "AL", "ME", "ME"),
    mail_rejected = c("reported", "reported", "reported", "not_available"),
    # AL: one reported, one genuinely missing. ME: both inapplicable.
    prov_rejected = c("reported", "not_available", "does_not_apply", "valid_skip")
  )
}

test_that("values are summed per state and the shape is long", {
  out <- eavs_aggregate(panel_fixture())
  expect_setequal(unique(out$concept), c("mail_rejected", "prov_rejected"))
  expect_equal(nrow(out), 2 * 2) # 2 states x 2 concepts
  expect_equal(out$value[out$concept == "mail_rejected" & out$state_abbr == "AL"], 30)
  expect_equal(out$value[out$concept == "mail_rejected" & out$state_abbr == "ME"], 5)
})

test_that("a state total equals a plain sum of its jurisdictions", {
  panel <- panel_fixture()
  out <- eavs_aggregate(panel)
  expect_equal(
    sum(out$value[out$concept == "mail_rejected"]),
    sum(panel$mail_rejected, na.rm = TRUE)
  )
})

test_that("every input row is accounted for in n_total", {
  panel <- panel_fixture()
  out <- eavs_aggregate(panel)
  expect_equal(sum(out$n_total[out$concept == "mail_rejected"]), nrow(panel))
})

test_that("without status every absence counts as a gap", {
  out <- eavs_aggregate(panel_fixture())
  me <- out[out$concept == "mail_rejected" & out$state_abbr == "ME", ]
  expect_false(me$coverage_exact)
  expect_equal(me$n_reported, 1L)
  expect_equal(me$n_missing, 1L)
  expect_equal(me$n_not_applicable, 0L)
  expect_equal(me$coverage, 0.5)
})

test_that("with status, does_not_apply is not counted as a gap", {
  out <- eavs_aggregate(panel_fixture(), status = status_fixture())
  me <- out[out$concept == "prov_rejected" & out$state_abbr == "ME", ]
  expect_true(me$coverage_exact)
  expect_equal(me$n_reported, 0L)
  expect_equal(me$n_missing, 0L)       # does_not_apply + valid_skip are not gaps
  expect_equal(me$n_not_applicable, 2L)
  expect_true(is.na(me$coverage))      # nothing could have been answered
})

test_that("blanks are counted apart and stay in the coverage denominator", {
  status <- status_fixture()
  status$mail_rejected <- c("reported", "blank", "reported", "not_available")
  out <- eavs_aggregate(panel_fixture(), status = status)
  al <- out[out$concept == "mail_rejected" & out$state_abbr == "AL", ]
  expect_equal(al$n_reported, 1L)
  expect_equal(al$n_missing, 0L)
  expect_equal(al$n_blank, 1L)
  # A blank counts as a gap in coverage, so the number reads as a lower bound.
  expect_equal(al$coverage, 0.5)
})

test_that("entity_type separates states, territories, and DC", {
  panel <- panel_fixture()
  panel$state_abbr <- c("AL", "PR", "DC", "ME")
  out <- eavs_aggregate(panel)
  types <- unique(out[, c("state_abbr", "entity_type")])
  expect_equal(types$entity_type[types$state_abbr == "AL"], "state")
  expect_equal(types$entity_type[types$state_abbr == "PR"], "territory")
  expect_equal(types$entity_type[types$state_abbr == "DC"], "district")
})

test_that("not_applicable is excluded from the coverage denominator", {
  out <- eavs_aggregate(panel_fixture(), status = status_fixture())
  al <- out[out$concept == "prov_rejected" & out$state_abbr == "AL", ]
  # One reported, one not_available: 1/2, not 1/2-of-something-larger.
  expect_equal(al$n_reported, 1L)
  expect_equal(al$n_missing, 1L)
  expect_equal(al$coverage, 0.5)
})

test_that("status changes coverage but never the summed value", {
  panel <- panel_fixture()
  without <- eavs_aggregate(panel)
  with <- eavs_aggregate(panel, status = status_fixture())
  expect_equal(without$value, with$value)
  expect_false(isTRUE(all.equal(without$n_missing, with$n_missing)))
})

test_that("a mismatched status frame is an error", {
  expect_error(
    eavs_aggregate(panel_fixture(), status = status_fixture()[1:2, ]),
    "line up row-for-row"
  )
})

test_that("concepts= restricts the rollup and rejects unknown names", {
  out <- eavs_aggregate(panel_fixture(), concepts = "mail_rejected")
  expect_equal(unique(out$concept), "mail_rejected")
  expect_error(eavs_aggregate(panel_fixture(), concepts = "nope"), "Not numeric concept")
})

test_that("a panel with no numeric concepts is an error", {
  bad <- tibble::tibble(year = 2024L, state_abbr = "AL", fips_code = "0100100000")
  expect_error(eavs_aggregate(bad), "No numeric concept columns")
})

test_that("a missing year column is an error", {
  bad <- panel_fixture()
  bad$year <- NULL
  expect_error(eavs_aggregate(bad), "needs a .*year.* column")
})

test_that("county rollups drop codes that embed no county, and say so", {
  jur <- tibble::tibble(
    year = rep(2024L, 4),
    fips_code = c("0100100000", "0100300000", "2300100000", "23"),
    county_fips = c("01001", "01003", "23001", NA) # Maine's statewide row has none
  )
  expect_message(
    out <- eavs_aggregate(panel_fixture(), by = "county", jurisdictions = jur),
    "Dropping 1 row"
  )
  expect_true("county_fips" %in% names(out))
  expect_equal(sum(out$n_total[out$concept == "mail_rejected"]), 3)
})

test_that("multiple years stay separate", {
  panel <- rbind(panel_fixture(), transform(panel_fixture(), year = 2022L))
  out <- eavs_aggregate(panel)
  expect_setequal(unique(out$year), c(2022L, 2024L))
  expect_equal(nrow(out), 2 * 2 * 2) # 2 years x 2 states x 2 concepts
})

test_that("coverage_reg weights coverage by reg_eligible_total", {
  panel <- panel_fixture()
  panel$reg_eligible_total <- c(1000, 3000, 500, 1500)
  out <- eavs_aggregate(panel)
  me <- out[out$concept == "mail_rejected" & out$state_abbr == "ME", ]
  expect_equal(me$coverage, 0.5)
  expect_equal(me$coverage_reg, 0.25) # 500 reported of 2000 answerable
  al <- out[out$concept == "mail_rejected" & out$state_abbr == "AL", ]
  expect_equal(al$coverage_reg, 1)
})

test_that("coverage_reg is NA without the weight, and NA weights drop from both sides", {
  out <- eavs_aggregate(panel_fixture())
  expect_true(all(is.na(out$coverage_reg)))
  panel <- panel_fixture()
  panel$reg_eligible_total <- c(1000, 3000, 500, NA)
  out <- eavs_aggregate(panel)
  me <- out[out$concept == "mail_rejected" & out$state_abbr == "ME", ]
  # The unreported Maine row has no usable weight, so it leaves the weighted
  # ratio entirely while the unweighted coverage still counts it as a gap.
  expect_equal(me$coverage, 0.5)
  expect_equal(me$coverage_reg, 1)
})

test_that("an NA reason counts as not collected, and the buckets sum to n_total", {
  status <- status_fixture()
  status$mail_rejected <- c("reported", "not_available", NA, NA)
  out <- eavs_aggregate(panel_fixture(), status = status)
  me <- out[out$concept == "mail_rejected" & out$state_abbr == "ME", ]
  expect_equal(me$n_not_collected, 2L)
  expect_equal(me$n_reported + me$n_missing + me$n_blank + me$n_not_applicable, 0L)
  expect_true(is.na(me$coverage))      # nothing was asked, so nothing to cover
  al <- out[out$concept == "mail_rejected" & out$state_abbr == "AL", ]
  expect_equal(al$n_not_collected, 0L)
  expect_equal(al$coverage, 0.5)
  sums <- out$n_reported + out$n_missing + out$n_blank +
    out$n_not_applicable + out$n_not_collected
  expect_equal(sums, out$n_total)
})

test_that("a status frame in the wrong year order is an error, not wrong coverage", {
  panel <- rbind(panel_fixture(), transform(panel_fixture(), year = 2022L))
  status <- rbind(status_fixture(), transform(status_fixture(), year = 2022L))
  expect_silent(out <- eavs_aggregate(panel, status = status))
  reversed <- status[c(5:8, 1:4), ]
  expect_equal(nrow(reversed), nrow(panel))   # the row count check cannot see it
  expect_error(eavs_aggregate(panel, status = reversed), "not aligned")
})
