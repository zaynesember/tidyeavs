## Fixtures small enough to check every number by hand. The AL rows model the
## Alabama pattern: a jurisdiction reporting the numerator without the
## denominator must leave the rate untouched.

rate_panel <- function() {
  tibble::tibble(
    year = rep(2024L, 4),
    fips_code = c("0100100000", "0100300000", "2300100000", "2300300000"),
    state_abbr = c("AL", "AL", "ME", "ME"),
    mail_rejected = c(10, 20, 5, NA),
    mail_returned = c(100, NA, 50, 50)
  )
}

test_that("the rate is computed over jurisdictions reporting both sides", {
  out <- eavs_rate(rate_panel(), "mail_rejected", "mail_returned")
  al <- out[out$state_abbr == "AL", ]
  expect_equal(al$rate, 0.1)          # 10/100; the 20 with no denominator is out
  expect_equal(al$num_value, 10)
  expect_equal(al$den_value, 100)
  expect_equal(al$n_both, 1L)
  expect_equal(al$n_num_only, 1L)
  expect_equal(al$n_den_only, 0L)
})

test_that("den_share says how much of the denominator the restriction kept", {
  out <- eavs_rate(rate_panel(), "mail_rejected", "mail_returned")
  al <- out[out$state_abbr == "AL", ]
  expect_equal(al$den_share, 1)       # the only reported denominator is in
  me <- out[out$state_abbr == "ME", ]
  expect_equal(me$n_den_only, 1L)
  expect_equal(me$den_share, 0.5)     # 50 of 100 reported returns
  expect_equal(me$rate, 0.1)
})

test_that("a zero or empty common-subset denominator gives NA, not Inf", {
  p <- rate_panel()
  p$mail_returned <- c(0, NA, NA, NA) # AL: both reported but zero; ME: none
  out <- eavs_rate(p, "mail_rejected", "mail_returned")
  expect_true(all(is.na(out$rate)))
  al <- out[out$state_abbr == "AL", ]
  expect_equal(al$n_both, 1L)
  me <- out[out$state_abbr == "ME", ]
  expect_equal(me$n_both, 0L)
  expect_true(is.na(me$den_share))
})

test_that("entity_type is carried and years stay separate", {
  p <- rbind(rate_panel(), transform(rate_panel(), year = 2022L))
  p$state_abbr[3:4] <- "PR"
  p$state_abbr[7:8] <- "PR"
  out <- eavs_rate(p, "mail_rejected", "mail_returned")
  expect_equal(nrow(out), 4)          # 2 years x 2 groups
  expect_setequal(out$entity_type[out$state_abbr == "PR"], "territory")
})

test_that("bad columns are an error", {
  expect_error(eavs_rate(rate_panel(), "nope", "mail_returned"), "not a numeric concept")
  expect_error(eavs_rate(rate_panel(), "fips_code", "mail_returned"), "not a numeric concept")
  expect_error(eavs_rate(rate_panel(), "mail_rejected", "mail_rejected"), "must differ")
  p <- rate_panel()
  p$year <- NULL
  expect_error(eavs_rate(p, "mail_rejected", "mail_returned"), "needs a .*year.* column")
})

test_that("county rollups drop codes with no county, as in eavs_aggregate", {
  jur <- tibble::tibble(
    year = rep(2024L, 4),
    fips_code = c("0100100000", "0100300000", "2300100000", "2300300000"),
    county_fips = c("01001", "01003", "23001", NA)
  )
  expect_message(
    out <- eavs_rate(rate_panel(), "mail_rejected", "mail_returned",
                     by = "county", jurisdictions = jur),
    "Dropping 1 row"
  )
  expect_true("county_fips" %in% names(out))
  expect_equal(nrow(out), 3)
})

## The known_anomaly column. Oregon 2018 is the case it exists for: every county
## reports, so n_both and den_share both read as perfect support, and the rate is
## still built on a convention that makes it unusable.

rate_anomalies <- function() {
  tibble::tibble(
    year = 2024,
    state_abbr = "AL",
    concept = "mail_rejected",
    note = "Test fixture.",
    source = "Test fixture."
  )
}

test_that("known_anomaly names which side of the ratio is affected", {
  out <- eavs_rate(rate_panel(), "mail_rejected", "mail_returned",
                   anomalies = rate_anomalies())
  expect_equal(out$known_anomaly[out$state_abbr == "AL"], "numerator")
  expect_true(is.na(out$known_anomaly[out$state_abbr == "ME"]))

  # The same concept as denominator is reported as the denominator side.
  flip <- eavs_rate(rate_panel(), "mail_returned", "mail_rejected",
                    anomalies = rate_anomalies())
  expect_equal(flip$known_anomaly[flip$state_abbr == "AL"], "denominator")
})

test_that("known_anomaly is 'both' when the anomaly covers each side", {
  an <- rate_anomalies()
  an <- rbind(an, transform(an, concept = "mail_returned"))
  out <- eavs_rate(rate_panel(), "mail_rejected", "mail_returned", anomalies = an)
  expect_equal(out$known_anomaly[out$state_abbr == "AL"], "both")
})

test_that("known_anomaly stays NA when no common subset carries the anomaly", {
  # With no jurisdiction reporting both sides there is no rate to distrust.
  p <- rate_panel()
  p$mail_returned <- c(NA, NA, 50, 50)
  out <- eavs_rate(p, "mail_rejected", "mail_returned", anomalies = rate_anomalies())
  expect_equal(out$n_both[out$state_abbr == "AL"], 0L)
  expect_true(is.na(out$known_anomaly[out$state_abbr == "AL"]))
})

test_that("anomalies = NULL skips the lookup", {
  out <- eavs_rate(rate_panel(), "mail_rejected", "mail_returned", anomalies = NULL)
  expect_true(all(is.na(out$known_anomaly)))
})
