#' Where tidyeavs stores downloaded data
#'
#' EAVS data files are downloaded once and kept in a local cache, so that
#' later calls reuse the file instead of fetching it again. This returns the
#' cache directory.
#'
#' The location is resolved in this order:
#'
#' 1. the `tidyeavs.cache_dir` option, if set;
#' 2. the `TIDYEAVS_CACHE_DIR` environment variable, if set;
#' 3. `tools::R_user_dir("tidyeavs", "cache")`, the standard per-user cache
#'    directory for R packages.
#'
#' To use a project-local cache for one session, set the option before
#' downloading, e.g. `options(tidyeavs.cache_dir = "data/eavs")`.
#'
#' @param create Whether to create the directory if it does not yet exist.
#'   Defaults to `TRUE`.
#'
#' @return The cache directory path, as a string.
#' @export
#'
#' @examples
#' # Where files will be stored (without creating the directory):
#' eavs_cache_dir(create = FALSE)
eavs_cache_dir <- function(create = TRUE) {
  dir <- getOption("tidyeavs.cache_dir", default = NULL)
  if (is.null(dir)) {
    dir <- Sys.getenv("TIDYEAVS_CACHE_DIR", unset = "")
    if (!nzchar(dir)) {
      dir <- tools::R_user_dir("tidyeavs", "cache")
    }
  }
  if (create && !dir.exists(dir)) {
    dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  }
  dir
}

#' List files in the tidyeavs cache
#'
#' @return A tibble with one row per cached file: its `file` name, size in
#'   bytes (`bytes`), and last-modified time (`modified`). Zero rows if the
#'   cache is empty.
#' @export
eavs_cache_list <- function() {
  dir <- eavs_cache_dir(create = FALSE)
  if (!dir.exists(dir)) {
    return(tibble::tibble(
      file = character(), bytes = numeric(),
      modified = as.POSIXct(character())
    ))
  }
  files <- list.files(dir, full.names = TRUE, recursive = TRUE)
  info <- file.info(files)
  tibble::tibble(
    file = sub(paste0("^", dir, .Platform$file.sep), "", files),
    bytes = info$size,
    modified = info$mtime
  )
}

#' Delete files from the tidyeavs cache
#'
#' @param files Names of files to delete, as returned by `eavs_cache_list()`.
#'   If `NULL` (the default), every file in the cache is removed.
#' @param confirm Whether to ask before deleting when running interactively.
#'   Defaults to `TRUE`.
#'
#' @return The names of the deleted files, invisibly.
#' @export
eavs_cache_clear <- function(files = NULL, confirm = TRUE) {
  dir <- eavs_cache_dir(create = FALSE)
  if (!dir.exists(dir)) {
    return(invisible(character()))
  }
  if (is.null(files)) {
    files <- eavs_cache_list()$file
  }
  if (length(files) == 0) {
    return(invisible(character()))
  }
  if (confirm && interactive()) {
    msg <- sprintf(
      "Delete %d file%s from the tidyeavs cache?",
      length(files), if (length(files) == 1) "" else "s"
    )
    if (!isTRUE(utils::askYesNo(msg))) {
      return(invisible(character()))
    }
  }
  unlink(file.path(dir, files), recursive = TRUE)
  invisible(files)
}

# Full path to a named file in the cache (does not check existence).
cache_path <- function(file_name) {
  file.path(eavs_cache_dir(create = TRUE), file_name)
}
