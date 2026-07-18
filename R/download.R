#' Download published EAVS data files
#'
#' Fetches EAVS data file(s) for the requested survey year(s) into the local
#' cache (see [eavs_cache_dir()]). Files come from the tidyeavs data mirror
#' when one is recorded and otherwise directly from the U.S. Election
#' Assistance Commission. A file already in the cache is reused once its
#' checksum matches, so a given file is downloaded only once.
#'
#' @param years Survey years to download. `NULL` (the default) fetches every
#'   year available for the chosen `survey` and `format`.
#' @param survey Which survey to fetch: `"eavs"` (default) or `"policy"` for
#'   the Policy Survey (available from 2018 on).
#' @param format File format: `"csv"` (default) or `"xlsx"`.
#' @param overwrite Re-download even when a verified copy is already cached.
#' @param quiet Suppress progress messages.
#'
#' @return A tibble with one row per file and columns `year`, `survey`,
#'   `format`, `path` (the cached file), and `status`, one of `"reused"` (a
#'   verified copy was already present) or `"downloaded"`.
#' @export
#'
#' @examples
#' \dontrun{
#' # Fetch the 2022 and 2024 EAVS as CSV:
#' eavs_download(c(2022, 2024))
#' }
eavs_download <- function(years = NULL, survey = "eavs", format = "csv",
                          overwrite = FALSE, quiet = FALSE) {
  rows <- manifest_lookup(years = years, survey = survey, format = format)

  out <- vector("list", nrow(rows))
  for (i in seq_len(nrow(rows))) {
    out[[i]] <- download_file(rows[i, ], overwrite = overwrite, quiet = quiet)
  }
  dplyr::bind_rows(out)
}

# Filter the manifest to the requested files, with informative errors.
manifest_lookup <- function(years = NULL, survey = "eavs", format = "csv") {
  man <- eavs_manifest
  survey <- match.arg(survey, c("eavs", "policy"))
  format <- match.arg(format, c("csv", "xlsx"))

  rows <- man[man$survey == survey & man$format == format, , drop = FALSE]
  if (nrow(rows) == 0) {
    cli::cli_abort(
      "No {.val {format}} files are recorded for the {.val {survey}} survey."
    )
  }
  if (!is.null(years)) {
    missing <- setdiff(years, rows$year)
    if (length(missing) > 0) {
      cli::cli_abort(c(
        "No {.val {survey}} {.val {format}} file for year{?s} {missing}.",
        i = "Available: {.val {sort(unique(rows$year))}}."
      ))
    }
    rows <- rows[rows$year %in% years, , drop = FALSE]
  }
  rows[order(rows$year), , drop = FALSE]
}

# Ensure one manifest row's file is in the cache; return a one-row tibble.
download_file <- function(row, overwrite = FALSE, quiet = FALSE) {
  path <- cache_path(row$file_name)
  result <- function(status) {
    tibble::tibble(
      year = row$year, survey = row$survey, format = row$format,
      path = path, status = status
    )
  }

  if (!overwrite && file.exists(path) && checksum_ok(path, row$sha256)) {
    return(result("reused"))
  }

  urls <- c(row$mirror_url, row$source_url)
  urls <- urls[!is.na(urls) & nzchar(urls)]
  if (length(urls) == 0) {
    cli::cli_abort("No download URL is recorded for {.val {row$file_name}}.")
  }

  if (!quiet) {
    cli::cli_progress_step(
      "Downloading {row$survey} {row$year} ({row$format})",
      msg_done = "Downloaded {row$survey} {row$year} ({row$format})"
    )
  }

  tmp <- tempfile(fileext = paste0(".", tools::file_ext(row$file_name)))
  on.exit(unlink(tmp), add = TRUE)

  errors <- character()
  for (url in urls) {
    ok <- tryCatch({
      curl::curl_download(url, tmp, quiet = TRUE)
      TRUE
    }, error = function(e) {
      errors[[length(errors) + 1]] <<- conditionMessage(e)
      FALSE
    })
    if (!ok) next
    if (!is.na(row$sha256) && !identical(file_sha256(tmp), row$sha256)) {
      errors[[length(errors) + 1]] <- sprintf(
        "checksum mismatch from %s", url
      )
      next
    }
    file.copy(tmp, path, overwrite = TRUE)
    return(result("downloaded"))
  }

  cli::cli_abort(c(
    "Could not download {.val {row$file_name}}.",
    stats::setNames(errors, rep("x", length(errors)))
  ))
}

# TRUE if the file matches the expected checksum, or if none is recorded.
checksum_ok <- function(path, sha256) {
  if (is.na(sha256)) {
    return(TRUE)
  }
  identical(file_sha256(path), sha256)
}
