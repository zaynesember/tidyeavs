#' Read an EAVS data file
#'
#' Reads a single survey year of EAVS data from the cache, downloading it first
#' if necessary. The data are returned as published, with every column as
#' character. Reading everything as text preserves FIPS codes with leading
#' zeros and the survey's missing-value codes without guessing types.
#'
#' Use [eavs_recode_missing()] to turn item columns into numbers, or
#' [eavs_load()] for a cleaned, harmonized panel across years.
#'
#' @param year A single survey year.
#' @param survey `"eavs"` (default) or `"policy"` for the Policy Survey.
#' @param format `"csv"` (default) or `"xlsx"`.
#' @param download Whether to download the file if it is not already cached.
#' @param quiet Suppress progress messages.
#'
#' @return A tibble of the data as published, with `year` and `survey` columns
#'   added at the front. Every other column is character.
#' @export
#'
#' @examples
#' \dontrun{
#' raw_2024 <- eavs_read(2024)
#' }
eavs_read <- function(year, survey = "eavs", format = "csv",
                      download = TRUE, quiet = FALSE) {
  if (length(year) != 1) {
    cli::cli_abort("{.arg year} must be a single year; you gave {length(year)}.")
  }
  survey <- match.arg(survey, c("eavs", "policy"))
  format <- match.arg(format, c("csv", "xlsx"))

  if (download) {
    path <- eavs_download(year, survey = survey, format = format,
                          quiet = quiet)$path
  } else {
    row <- manifest_lookup(year, survey = survey, format = format)
    path <- cache_path(row$file_name)
    if (!file.exists(path)) {
      cli::cli_abort(c(
        "{.val {survey}} {year} ({format}) is not in the cache.",
        i = "Call again with {.code download = TRUE} to fetch it."
      ))
    }
  }

  raw <- switch(format,
    csv  = read_raw_csv(path),
    xlsx = read_raw_xlsx(path)
  )
  tibble::add_column(raw, year = year, survey = survey, .before = 1)
}

read_raw_csv <- function(path) {
  if (identical(tolower(tools::file_ext(path)), "zip")) {
    path <- unzip_member(path, "\\.csv$")
  }
  readr::read_csv(
    path,
    col_types = readr::cols(.default = readr::col_character()),
    locale = readr::locale(encoding = file_encoding(path)),
    show_col_types = FALSE,
    name_repair = "minimal",
    progress = FALSE
  )
}

# EAVS CSVs are usually Windows-1252 (Excel/SPSS exports), which breaks a
# UTF-8 read on place names like "Doña Ana". Detect the encoding: use
# UTF-8 if the bytes are valid UTF-8, otherwise fall back to Windows-1252.
file_encoding <- function(path) {
  s <- tryCatch(
    {
      x <- rawToChar(readBin(path, "raw", n = file.info(path)$size))
      Encoding(x) <- "UTF-8"
      x
    },
    error = function(e) NULL
  )
  if (is.null(s) || !validUTF8(s)) "Windows-1252" else "UTF-8"
}

read_raw_xlsx <- function(path, sheet = 1) {
  require_pkg("readxl", "to read xlsx files")
  if (identical(tolower(tools::file_ext(path)), "zip")) {
    path <- unzip_member(path, "\\.xlsx$")
  }
  readxl::read_excel(
    path,
    sheet = sheet,
    col_types = "text",
    .name_repair = "minimal"
  )
}

# Extract the largest zip member matching `pattern` into a sibling folder in
# the cache and return its path, reusing a previous extraction if present.
unzip_member <- function(zip_path, pattern) {
  contents <- utils::unzip(zip_path, list = TRUE)
  hits <- contents[grepl(pattern, contents$Name, ignore.case = TRUE), , drop = FALSE]
  if (nrow(hits) == 0) {
    cli::cli_abort(
      "No file matching {.val {pattern}} inside {.file {basename(zip_path)}}."
    )
  }
  member <- hits$Name[which.max(hits$Length)]
  exdir <- paste0(zip_path, "-extracted")
  out <- file.path(exdir, member)
  if (!file.exists(out)) {
    utils::unzip(zip_path, files = member, exdir = exdir)
  }
  out
}
