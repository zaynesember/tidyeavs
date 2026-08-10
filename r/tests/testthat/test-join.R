## Fixtures model the two hazards by hand: a Wisconsin town/village pair sharing
## one serial code (the fan-out) and a Maine statewide row absent from y (the
## drop). Small enough that every row count is checkable.

join_panel <- function() {
  tibble::tibble(
    year = rep(2020L, 4),
    fips_code = c("82575", "82575", "55001000", "23"),
    jurisdiction_name = c("TOWN OF ARBOR", "VILLAGE OF ARBOR",
                          "COUNTY A", "MAINE UOCAVA"),
    state_abbr = c("WI", "WI", "WI", "ME"),
    partic_total = c(100, 50, 200, 7)
  )
}

join_jurisdictions <- function() {
  tibble::tibble(
    year = rep(2020L, 3),
    fips_code = c("82575", "82575", "55001000"),
    jurisdiction_name = c("TOWN OF ARBOR", "VILLAGE OF ARBOR", "COUNTY A"),
    state_abbr = c("WI", "WI", "WI"),
    county_fips = c(NA, NA, "55001"),
    type = c("municipality", "municipality", "county")
  )
}

test_that("a shared code stops the join instead of fanning it out", {
  expect_error(
    eavs_join(join_panel(), join_jurisdictions()),
    "fan out"
  )
})

test_that("the fan-out message points at jurisdiction_name when it can", {
  expect_error(
    eavs_join(join_panel(), join_jurisdictions()),
    "jurisdiction_name"
  )
})

test_that("adding jurisdiction_name to by resolves the pair one-to-one", {
  out <- eavs_join(
    join_panel(), join_jurisdictions(),
    by = c("year", "fips_code", "jurisdiction_name"),
    unmatched = "ignore"
  )
  expect_equal(nrow(out), 4L)             # no fan-out
  town <- out[out$jurisdiction_name == "TOWN OF ARBOR", ]
  expect_true(is.na(town$county_fips))
  county <- out[out$jurisdiction_name == "COUNTY A", ]
  expect_equal(county$county_fips, "55001")
})

test_that("multiple = 'all' keeps the expansion", {
  out <- eavs_join(
    join_panel(), join_jurisdictions(),
    by = c("year", "fips_code"),
    multiple = "all", unmatched = "ignore"
  )
  # 2 panel rows x 2 y rows for 82575 = 4, plus the county (1) and Maine (1).
  expect_equal(nrow(out), 6L)
})

test_that("an unmatched row is reported but kept with NA", {
  by <- c("year", "fips_code", "jurisdiction_name")
  expect_message(
    eavs_join(join_panel(), join_jurisdictions(), by = by),
    "matched nothing"
  )
  expect_error(
    eavs_join(join_panel(), join_jurisdictions(), by = by, unmatched = "error"),
    "matched nothing"
  )
  out <- eavs_join(join_panel(), join_jurisdictions(), by = by, unmatched = "ignore")
  maine <- out[out$jurisdiction_name == "MAINE UOCAVA", ]
  expect_equal(nrow(maine), 1L)
  expect_true(is.na(maine$county_fips))
})

test_that("unmatched = 'ignore' is silent and unmatched = 'inform' names the state", {
  by <- c("year", "fips_code", "jurisdiction_name")
  expect_silent(
    eavs_join(join_panel(), join_jurisdictions(), by = by, unmatched = "ignore")
  )
  expect_message(
    eavs_join(join_panel(), join_jurisdictions(), by = by),
    "ME"
  )
})

test_that("only y's new columns are added, with no .x/.y suffixes", {
  out <- eavs_join(
    join_panel(), join_jurisdictions(),
    by = c("year", "fips_code", "jurisdiction_name"),
    unmatched = "ignore"
  )
  expect_false(any(grepl("\\.x$|\\.y$", names(out))))
  expect_true(all(c("county_fips", "type") %in% names(out)))
  expect_equal(sum(names(out) == "state_abbr"), 1L)   # kept from x, not doubled
})

test_that("by defaults to the shared year and fips_code", {
  x <- tibble::tibble(year = 2020L, fips_code = "55001000", v = 1)
  y <- tibble::tibble(year = 2020L, fips_code = "55001000", w = 2)
  out <- eavs_join(x, y)
  expect_equal(out$w, 2)
})

test_that("no shared key columns is an error", {
  expect_error(
    eavs_join(tibble::tibble(a = 1), tibble::tibble(b = 2)),
    "No columns to join on"
  )
})

test_that("by naming a column missing from a frame is an error", {
  x <- tibble::tibble(year = 2020L, fips_code = "1")
  y <- tibble::tibble(year = 2020L, fips_code = "1")
  expect_error(eavs_join(x, y, by = c("year", "nope")), "not in both frames")
})
