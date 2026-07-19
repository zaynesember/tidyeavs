# Invariants of the shipped eavs_jurisdictions dataset. Offline: these test
# the bundled data, not the build script.

test_that("every published row is present, per year", {
  counts <- table(eavs_jurisdictions$year)
  expect_equal(
    as.integer(counts[c("2016", "2018", "2020", "2022", "2024")]),
    c(6467L, 6460L, 6460L, 6460L, 6461L)
  )
})

test_that("identifiers are complete and consistent", {
  j <- eavs_jurisdictions
  expect_false(anyNA(j$fips_code))
  expect_false(anyNA(j$state_abbr))
  expect_false(anyNA(j$state_fips))
  expect_true(all(nchar(j$state_fips) == 2))
  expect_true(all(is.na(j$fips10) | nchar(j$fips10) == 10))
  # A derived county always sits inside the row's state.
  ok <- is.na(j$county_fips) |
    (nchar(j$county_fips) == 5 & substr(j$county_fips, 1, 2) == j$state_fips)
  expect_true(all(ok))
})

test_that("types cover the known structure", {
  j <- eavs_jurisdictions
  expect_setequal(unique(j$type),
                  c("county", "municipality", "statewide", "territory"))
  # Alaska and Maine's UOCAVA row, every year.
  expect_equal(sum(j$type == "statewide"), 10)
  expect_true(all(c("23.", "23") %in% j$fips_code[j$type == "statewide"]))
  # Territories file one row per year present.
  terr <- j[j$type == "territory", ]
  expect_true(all(terr$state_abbr %in% c("AS", "GU", "MP", "PR", "VI")))
  expect_false(any(duplicated(terr[, c("year", "state_abbr")])))
})

test_that("Wisconsin serials are flagged non-geographic with no county", {
  wi <- eavs_jurisdictions[eavs_jurisdictions$state_abbr == "WI", ]
  expect_true(all(wi$nongeo_code))
  expect_true(all(is.na(wi$county_fips)))
  expect_true(all(is.na(wi$fips10)))
  expect_true(all(table(wi$year) >= 1850))
})

test_that("shared Wisconsin codes keep both rows and are flagged", {
  j <- eavs_jurisdictions
  shared <- j[j$shared_code, ]
  expect_equal(nrow(shared), 6)
  expect_equal(sort(unique(shared$fips_code)), c("31550", "82575", "84275"))
  expect_true(all(shared$state_abbr == "WI"))
})

test_that("the 2024 California codes are padded, not altered", {
  ca <- eavs_jurisdictions[eavs_jurisdictions$code_padded, ]
  expect_equal(ca$year, c(2024L, 2024L))
  expect_equal(sort(ca$fips_code), c("600100000", "600900000"))
  expect_equal(sort(ca$fips10), c("0600100000", "0600900000"))
})

test_that("known one-off quirks carry notes", {
  j <- eavs_jurisdictions
  kalawao <- j[!is.na(j$fips10) & j$fips10 == "1500500000", ]
  expect_equal(nrow(kalawao), 5)
  expect_true(all(grepl("Maui", kalawao$note)))
  yates <- j[j$fips_code == "3612295082", ]
  expect_equal(yates$year, 2016L)
  expect_false(is.na(yates$note))
  expect_true(is.na(yates$county_fips))
})

test_that("county derivation matches known state counts in 2024", {
  j24 <- eavs_jurisdictions[eavs_jurisdictions$year == 2024, ]
  n_counties <- function(st) {
    length(unique(stats::na.omit(j24$county_fips[j24$state_abbr == st])))
  }
  expect_equal(n_counties("TX"), 254)
  expect_equal(n_counties("MI"), 83)
  expect_equal(n_counties("ME"), 16) # the '099' township bucket is excluded
  expect_equal(n_counties("HI"), 5)
  expect_equal(n_counties("WI"), 0)
})
