test_that("modern sentinels map to NA with the right status", {
  df <- tibble::tibble(
    FIPSCode = c("01001", "02000"),
    x = c("100", "-99"),
    y = c("-88", "-77")
  )
  v <- eavs_recode_missing(df)
  expect_type(v$x, "double")
  expect_equal(v$x, c(100, NA_real_))
  expect_equal(v$y, c(NA_real_, NA_real_))

  s <- eavs_missing_status(df)
  expect_equal(as.character(s$x), c("reported", "not_available"))
  expect_equal(as.character(s$y), c("does_not_apply", "valid_skip"))
})

test_that("six-digit-era sentinels are handled", {
  df <- tibble::tibble(a = c("5", "-888888", "-999999"))
  expect_equal(eavs_recode_missing(df)$a, c(5, NA, NA))
  expect_equal(
    as.character(eavs_missing_status(df)$a),
    c("reported", "does_not_apply", "not_available")
  )
})

test_that("identifier and text columns are left alone", {
  df <- tibble::tibble(
    FIPSCode = c("01001", "01003"),
    Jurisdiction_Name = c("A", "B"),
    A2 = c("Both", "Active")
  )
  v <- eavs_recode_missing(df)
  expect_identical(v$FIPSCode, df$FIPSCode)
  expect_identical(v$A2, df$A2)
})

test_that("blanks and text tokens are distinguished", {
  df <- tibble::tibble(a = c("", "NA", "Data not available", "10"))
  expect_equal(eavs_recode_missing(df)$a, c(NA, NA, NA, 10))
  expect_equal(
    as.character(eavs_missing_status(df)$a),
    c("blank", "not_available", "not_available", "reported")
  )
})

test_that("unknown negatives are flagged other_missing", {
  df <- tibble::tibble(a = c("5", "-1234"))
  expect_equal(eavs_recode_missing(df)$a, c(5, NA))
  expect_equal(as.character(eavs_missing_status(df)$a),
               c("reported", "other_missing"))
})

test_that("recode and status return the same shape as the input", {
  df <- tibble::tibble(id = c("a", "b"), x = c("1", "-99"))
  expect_equal(dim(eavs_recode_missing(df)), dim(df))
  expect_equal(dim(eavs_missing_status(df)), dim(df))
})
