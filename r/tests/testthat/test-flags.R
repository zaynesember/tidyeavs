## Fixture checks, so these tests don't move when metadata/checks.csv is edited.

checks_fixture <- function() {
  tibble::tibble(
    check = c("returned_le_transmitted", "disposition_le_returned"),
    total = c("mail_transmitted", "mail_returned"),
    parts = list("mail_returned", c("mail_counted", "mail_rejected")),
    section = c("C", "C"),
    note = c("note one", "note two")
  )
}

panel_1y <- function(...) {
  tibble::tibble(
    year = 2024L, fips_code = "0100100000", state_abbr = "AL",
    jurisdiction_name = "AUTAUGA COUNTY", ...
  )
}

test_that("a sum check fires when parts exceed the total", {
  d <- panel_1y(mail_transmitted = 100, mail_returned = 80,
                mail_counted = 70, mail_rejected = 20)
  f <- eavs_flags(d, checks = checks_fixture(), swing_factor = NULL)
  expect_equal(nrow(f), 1)
  expect_equal(f$check, "disposition_le_returned")
  expect_equal(f$observed, 90)
  expect_equal(f$threshold, 80)
  expect_equal(f$excess, 10)
  expect_equal(f$n_parts_reported, 2L)
  expect_equal(f$note, "note two")
})

test_that("nothing is flagged when the arithmetic reconciles", {
  d <- panel_1y(mail_transmitted = 100, mail_returned = 80,
                mail_counted = 70, mail_rejected = 10)
  f <- eavs_flags(d, checks = checks_fixture(), swing_factor = NULL)
  expect_equal(nrow(f), 0)
})

test_that("a partial sum still flags, and says how many parts it had", {
  d <- panel_1y(mail_transmitted = 100, mail_returned = 50,
                mail_counted = 60, mail_rejected = NA)
  f <- eavs_flags(d, checks = checks_fixture(), swing_factor = NULL)
  expect_equal(nrow(f), 1)
  expect_equal(f$observed, 60)
  expect_equal(f$n_parts_reported, 1L)
})

test_that("a missing total or all-missing parts produce no flag", {
  no_total <- panel_1y(mail_transmitted = 100, mail_returned = NA,
                       mail_counted = 70, mail_rejected = 20)
  no_parts <- panel_1y(mail_transmitted = 100, mail_returned = 80,
                       mail_counted = NA, mail_rejected = NA)
  fixture <- checks_fixture()
  expect_equal(nrow(eavs_flags(no_total, checks = fixture[2, ], swing_factor = NULL)), 0)
  expect_equal(nrow(eavs_flags(no_parts, checks = fixture[2, ], swing_factor = NULL)), 0)
})

test_that("equal is not flagged; only strictly greater", {
  d <- panel_1y(mail_transmitted = 100, mail_returned = 80,
                mail_counted = 80, mail_rejected = 0)
  f <- eavs_flags(d, checks = checks_fixture()[2, ], swing_factor = NULL)
  expect_equal(nrow(f), 0)
})

swing_panel <- function(before, now) {
  tibble::tibble(
    year = c(2022L, 2024L),
    fips_code = c("0100100000", "0100100000"),
    state_abbr = c("AL", "AL"),
    jurisdiction_name = c("AUTAUGA COUNTY", "AUTAUGA COUNTY"),
    mail_returned = c(before, now)
  )
}

test_that("swings fire in both directions past the factor", {
  up <- eavs_flags(swing_panel(100, 2000), checks = NULL, swing_factor = 10)
  down <- eavs_flags(swing_panel(2000, 100), checks = NULL, swing_factor = 10)
  expect_equal(up$check, "year_over_year_swing")
  expect_equal(up$observed, 2000)
  expect_equal(up$threshold, 100)
  expect_equal(down$check, "year_over_year_swing")
  expect_equal(down$observed, 100)
})

test_that("a swing inside the factor is not flagged", {
  f <- eavs_flags(swing_panel(100, 500), checks = NULL, swing_factor = 10)
  expect_equal(nrow(f), 0)
})

test_that("swing_floor keeps small counts out", {
  # 5 -> 100 is a 20-fold change, but both are under the default floor of 100.
  expect_equal(nrow(eavs_flags(swing_panel(5, 99), checks = NULL)), 0)
  expect_equal(nrow(eavs_flags(swing_panel(5, 99), checks = NULL, swing_floor = 10)), 1)
})

test_that("a drop to zero is its own check with a finite excess", {
  f <- eavs_flags(swing_panel(5000, 0), checks = NULL)
  expect_equal(f$check, "dropped_to_zero")
  expect_equal(f$observed, 0)
  expect_equal(f$threshold, 5000)
  expect_equal(f$excess, 5000)
  expect_true(is.finite(f$excess))
})

test_that("a rise from zero is treated as a swing, not a drop", {
  f <- eavs_flags(swing_panel(0, 5000), checks = NULL)
  # b == 0 cannot form a ratio, so nothing is flagged rather than reporting Inf.
  expect_true(all(is.finite(f$excess)))
})

test_that("one year of data produces no swing flags", {
  d <- panel_1y(mail_transmitted = 100, mail_returned = 80,
                mail_counted = 70, mail_rejected = 20)
  f <- eavs_flags(d, checks = checks_fixture())
  expect_true(all(f$kind == "sum"))
})

test_that("either kind can be switched off", {
  d <- swing_panel(100, 2000)
  d$mail_transmitted <- c(100, 100)
  d$mail_counted <- c(0, 0)
  d$mail_rejected <- c(0, 0)
  expect_true(all(eavs_flags(d, checks = checks_fixture(), swing_factor = NULL)$kind == "sum"))
  expect_true(all(eavs_flags(d, checks = NULL)$kind == "swing"))
})

test_that("an empty result still has the full set of columns", {
  d <- panel_1y(mail_transmitted = 100, mail_returned = 80,
                mail_counted = 70, mail_rejected = 10)
  f <- eavs_flags(d, checks = checks_fixture(), swing_factor = NULL)
  expect_equal(nrow(f), 0)
  expect_equal(
    names(f),
    c("year", "fips_code", "state_abbr", "jurisdiction_name", "check", "kind",
      "concept", "observed", "threshold", "excess", "n_parts_reported", "note")
  )
  expect_type(f$excess, "double")
  expect_type(f$check, "character")
})

test_that("a missing year column is an error", {
  d <- panel_1y(mail_returned = 1)
  d$year <- NULL
  expect_error(eavs_flags(d), "needs a .*year.* column")
})

test_that("checks naming absent concepts are skipped, not an error", {
  d <- panel_1y(mail_transmitted = 100, mail_returned = 200)
  absent <- tibble::tibble(
    check = "nope", total = "not_a_concept", parts = list("also_not"),
    section = "C", note = "x"
  )
  expect_equal(nrow(eavs_flags(d, checks = absent, swing_factor = NULL)), 0)
})

test_that("the shipped checks are well formed", {
  expect_true(nrow(eavs_checks) > 0)
  expect_false(any(duplicated(eavs_checks$check)))
  expect_true(is.list(eavs_checks$parts))
  # No check compares a concept against itself.
  for (i in seq_len(nrow(eavs_checks))) {
    expect_false(eavs_checks$total[i] %in% eavs_checks$parts[[i]])
  }
})
