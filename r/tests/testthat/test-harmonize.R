# A tiny dictionary with the mail-rejected renumbering trap: C4a in 2020,
# C9a in 2024. Lets us test harmonization without the bundled dataset.
fixture_dict <- function() {
  tibble::tribble(
    ~concept,        ~concept_label,  ~section, ~year,  ~code,       ~codebook_label, ~epi_name, ~note,
    "fips_code",     "FIPS",          "id",     2020L,  "FIPSCode",  NA,              NA,        NA,
    "fips_code",     "FIPS",          "id",     2024L,  "FIPSCode",  NA,              NA,        NA,
    "mail_returned", "Mail returned", "C",      2020L,  "C1b",       NA,              NA,        NA,
    "mail_returned", "Mail returned", "C",      2024L,  "C1b",       NA,              NA,        NA,
    "mail_rejected", "Mail rejected", "C",      2020L,  "C4a",       NA,              NA,        NA,
    "mail_rejected", "Mail rejected", "C",      2024L,  "C9a",       NA,              NA,        NA
  )
}

test_that("harmonize renames each year's code to the shared concept", {
  y2020 <- tibble::tibble(
    year = 2020, FIPSCode = c("01", "02"),
    C1b = c(100, 200), C4a = c(10, 20), C9a = c(999, 999)
  )
  h <- eavs_harmonize(y2020, dictionary = fixture_dict())
  expect_true(all(c("fips_code", "mail_returned", "mail_rejected") %in% names(h)))
  expect_false(any(c("C1b", "C4a", "C9a") %in% names(h)))
  expect_equal(h$mail_rejected, c(10, 20)) # from C4a, not C9a
})

test_that("harmonize pulls the right code per year (the renumbering trap)", {
  y2024 <- tibble::tibble(year = 2024, FIPSCode = "01", C4a = 999, C9a = 7)
  h <- eavs_harmonize(y2024, dictionary = fixture_dict())
  expect_equal(h$mail_rejected, 7) # from C9a in 2024
})

test_that("harmonized years stack into one panel", {
  d <- fixture_dict()
  a <- eavs_harmonize(tibble::tibble(year = 2020, FIPSCode = "01", C4a = 5), dictionary = d)
  b <- eavs_harmonize(tibble::tibble(year = 2024, FIPSCode = "01", C9a = 8), dictionary = d)
  panel <- dplyr::bind_rows(a, b)
  expect_equal(nrow(panel), 2)
  expect_equal(panel$mail_rejected, c(5, 8))
})

test_that("harmonize keeps unmatched columns only when asked", {
  d <- fixture_dict()
  x <- tibble::tibble(year = 2020, FIPSCode = "01", C4a = 5, ZZ9 = 1)
  expect_false("ZZ9" %in% names(eavs_harmonize(x, dictionary = d)))
  expect_true("ZZ9" %in% names(eavs_harmonize(x, dictionary = d, keep_unmatched = TRUE)))
})

test_that("harmonize errors when nothing matches the year", {
  expect_error(
    eavs_harmonize(tibble::tibble(year = 2020, foo = 1), dictionary = fixture_dict()),
    "match"
  )
})

test_that("eavs_items finds a concept by its raw code", {
  hits <- eavs_items("C9a", dictionary = fixture_dict())
  expect_true("mail_rejected" %in% hits$concept)
})
