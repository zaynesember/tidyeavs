## Checks that the files published at the URLs in eavs_manifest still match
## their pinned SHA-256 checksums. The EAC re-releases revised versions of a
## cycle for years after the first release, and eac.gov URLs churn; when either
## happens this script fails, which is the signal to update data-raw/manifest.R
## (version, release_date, source_url) and rebuild the manifest.
##
## Run from the package root:  Rscript data-raw/check_manifest.R
## CI runs it weekly (.github/workflows/manifest-drift.yaml).
##
## Needs only the curl and digest packages, not the package itself.

load("data/eavs_manifest.rda")

label <- sprintf("%s %d %s", eavs_manifest$survey, eavs_manifest$year,
                 eavs_manifest$format)

check_url <- function(url, sha256) {
  dest <- tempfile()
  on.exit(unlink(dest), add = TRUE)
  ok <- tryCatch(
    {
      curl::curl_download(url, dest, quiet = TRUE)
      TRUE
    },
    error = function(e) FALSE
  )
  if (!ok) {
    return("unreachable")
  }
  got <- digest::digest(dest, algo = "sha256", file = TRUE)
  if (identical(got, sha256)) "ok" else "drift"
}

status <- character(nrow(eavs_manifest))
for (i in seq_len(nrow(eavs_manifest))) {
  urls <- c(eavs_manifest$mirror_url[i], eavs_manifest$source_url[i])
  urls <- urls[!is.na(urls) & nzchar(urls)]
  status[i] <- "unreachable"
  for (url in urls) {
    status[i] <- check_url(url, eavs_manifest$sha256[i])
    if (status[i] == "ok") break
  }
  cat(sprintf("%-18s %s\n", label[i], status[i]))
}

bad <- status != "ok"
if (any(bad)) {
  cat("\nThe published files no longer match the manifest:\n")
  cat(sprintf("  %s: %s\n", label[bad], status[bad]), sep = "")
  cat("\nLikely an EAC re-release or a moved URL. Update data-raw/manifest.R",
      "(version, release_date, source_url) and rebuild.\n")
  quit(status = 1)
}
cat("\nAll", length(status), "files match the manifest.\n")
