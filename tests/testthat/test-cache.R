test_that("cache dir falls back to the R user cache", {
  withr::local_options(tidyeavs.cache_dir = NULL)
  withr::local_envvar(TIDYEAVS_CACHE_DIR = NA)
  expect_match(eavs_cache_dir(create = FALSE), "tidyeavs")
})

test_that("cache dir honors the option and env var", {
  tmp <- withr::local_tempdir()
  withr::local_options(tidyeavs.cache_dir = tmp)
  expect_equal(eavs_cache_dir(create = FALSE), tmp)

  withr::local_options(tidyeavs.cache_dir = NULL)
  tmp2 <- withr::local_tempdir()
  withr::local_envvar(TIDYEAVS_CACHE_DIR = tmp2)
  expect_equal(eavs_cache_dir(create = FALSE), tmp2)
})

test_that("listing an empty cache returns zero rows", {
  withr::local_options(tidyeavs.cache_dir = withr::local_tempdir())
  expect_equal(nrow(eavs_cache_list()), 0)
})
