test_that("manifest_lookup filters to the requested file", {
  rows <- manifest_lookup(2024, survey = "eavs", format = "csv")
  expect_equal(nrow(rows), 1)
  expect_equal(rows$year, 2024L)
  expect_equal(rows$survey, "eavs")
})

test_that("manifest_lookup errors clearly on a missing year", {
  expect_error(
    manifest_lookup(1999, survey = "eavs", format = "csv"),
    "No .*file"
  )
})

test_that("every manifest file has a 64-character checksum and a source URL", {
  expect_true(all(nchar(eavs_manifest$sha256) == 64))
  expect_true(all(!is.na(eavs_manifest$source_url) &
                    nzchar(eavs_manifest$source_url)))
})

test_that("the manifest covers EAVS 2016 through 2024", {
  eavs_years <- sort(unique(eavs_manifest$year[eavs_manifest$survey == "eavs"]))
  expect_equal(eavs_years, c(2016L, 2018L, 2020L, 2022L, 2024L))
})
