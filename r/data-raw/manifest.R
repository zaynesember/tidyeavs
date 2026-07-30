## Builds data/eavs_manifest.rda: the catalog of published EAVS files that
## tidyeavs can download and verify.
##
## Source URLs were verified against eac.gov on 2026-07-18. Each row's byte
## size and SHA-256 are computed from the file as downloaded, so the manifest
## pins a specific published version; when the EAC releases a revised version,
## update the version, release_date, source_url, and re-run this script.
##
## Note on formats: EAVS CSVs for 2016/2020/2022/2024 are zipped, but the 2018
## EAVS CSV and the 2018/2020 Policy Survey CSVs are plain .csv. The file
## extension is taken from the source URL, so both are handled.
##
## The mirror: every file is also published as an asset on a GitHub release, so
## eavs_download() has a source that does not move when the EAC re-releases a
## cycle. mirror_url is derived from MIRROR_TAG and file_name rather than typed
## out per row, so a new survey year picks one up automatically. Upload the files
## to the release *before* running this script, since it checks each mirror URL
## and leaves mirror_url empty for any asset that is not there yet:
##
##   gh release create <tag> <files...> --target dev --title "..." --notes "..."
##   gh release upload <tag> <files...>          # to add to an existing release
##
## Run from the package root:  Rscript data-raw/manifest.R

library(tibble)

MIRROR_TAG <- "data-mirror-v1"
MIRROR_BASE <- "https://github.com/zaynesember/tidyeavs/releases/download"

files <- tribble(
  ~survey,  ~year, ~format, ~version, ~release_date, ~source_url,
  # ---- EAVS ----
  "eavs",   2016L, "csv",  "1.1", "2023-12-18",
    "https://www.eac.gov/sites/default/files/2023-12/EAVS_2016_for_Public_Release_nolabel_V1.1_CSV.zip",
  "eavs",   2016L, "xlsx", "1.1", "2023-12-18",
    "https://www.eac.gov/sites/default/files/2023-12/EAVS_2016_for_Public_Release_V1.1_0.xlsx",
  "eavs",   2018L, "csv",  "1.3", "2020-07-15",
    "https://www.eac.gov/sites/default/files/Research/EAVS_2018_for_Public_Release_Updates3.csv",
  "eavs",   2018L, "xlsx", "1.3", "2020-07-15",
    "https://www.eac.gov/sites/default/files/Research/EAVS_2018_for_Public_Release_Updates3.xlsx",
  "eavs",   2020L, "csv",  "1.2", "2023-12-18",
    "https://www.eac.gov/sites/default/files/2023-12/2020_EAVS_for_Public_Release_nolabel_V1.2_CSV.zip",
  "eavs",   2020L, "xlsx", "1.2", "2023-12-18",
    "https://www.eac.gov/sites/default/files/2023-12/2020_EAVS_for_Public_Release_V1.2.xlsx",
  "eavs",   2022L, "csv",  "1.1", "2023-12-18",
    "https://www.eac.gov/sites/default/files/2023-12/2022_EAVS_for_Public_Release_nolabel_V1.1_CSV.zip",
  "eavs",   2022L, "xlsx", "1.1", "2023-12-18",
    "https://www.eac.gov/sites/default/files/2023-12/2022_EAVS_for_Public_Release_V1.1.xlsx",
  "eavs",   2024L, "csv",  "2.0", "2026-02-12",
    "https://www.eac.gov/sites/default/files/2026-02/2024_EAVS_for_Public_Release_nolabel_V2_csv.zip",
  "eavs",   2024L, "xlsx", "2.0", "2026-02-12",
    "https://www.eac.gov/sites/default/files/2026-02/2024_EAVS_for_Public_Release_V2.xlsx",
  # ---- Policy Survey ----
  "policy", 2018L, "csv",  "1.0", "2019-06-27",
    "https://www.eac.gov/sites/default/files/eac_assets/1/6/EAVS_PolicySurvey_2018_nolabel.csv",
  "policy", 2018L, "xlsx", "1.0", "2019-06-27",
    "https://www.eac.gov/sites/default/files/eac_assets/1/6/EAVS_PolicySurvey_2018_for_Public_Release.xlsx",
  "policy", 2020L, "csv",  "1.0", "2021-08-16",
    "https://www.eac.gov/sites/default/files/2021-08/2020_Policy_Survey_for_Public_Release_nolabel%5B1%5D.csv",
  "policy", 2020L, "xlsx", "1.0", "2021-08-16",
    "https://www.eac.gov/sites/default/files/2021-08/2020_Policy_Survey_for_Public_Release%5B1%5D.xlsx",
  "policy", 2022L, "csv",  "1.1", "2023-12-18",
    "https://www.eac.gov/sites/default/files/2023-12/2022_Policy_Survey_for_Public_Release_nolabel_V2_CSV.zip",
  "policy", 2022L, "xlsx", "1.1", "2023-12-18",
    "https://www.eac.gov/sites/default/files/2023-12/2022_Policy_Survey_for_Public_Release_V2_v1.1.xlsx",
  "policy", 2024L, "csv",  "2.0", "2026-02-12",
    "https://www.eac.gov/sites/default/files/2026-02/2024_Policy_Survey_for_Public_Release_nolabel_V2_csv.zip",
  "policy", 2024L, "xlsx", "2.0", "2026-02-12",
    "https://www.eac.gov/sites/default/files/2026-02/2024_Policy_Survey_for_Public_Release_V2.xlsx"
)

ext_of <- function(url) {
  base <- utils::URLdecode(sub("\\?.*$", "", basename(url)))
  tolower(tools::file_ext(base))
}
files$file_name <- sprintf(
  "%s_%d_%s.%s",
  files$survey, files$year, files$format,
  vapply(files$source_url, ext_of, character(1))
)

stage <- file.path(tempdir(), "eavs-manifest-stage")
dir.create(stage, showWarnings = FALSE, recursive = TRUE)

sha256 <- character(nrow(files))
bytes <- numeric(nrow(files))
for (i in seq_len(nrow(files))) {
  dest <- file.path(stage, files$file_name[i])
  if (!file.exists(dest)) {
    message("Downloading ", files$file_name[i])
    curl::curl_download(files$source_url[i], dest, quiet = TRUE)
  }
  sha256[i] <- digest::digest(dest, algo = "sha256", file = TRUE)
  bytes[i] <- file.info(dest)$size
}

# Mirror URLs, kept honest: a manifest that claims a mirror which is not there
# would send every user through a pointless 404 before the eac.gov fallback, so
# check each asset exists and record only the ones that do.
mirror_url <- sprintf("%s/%s/%s", MIRROR_BASE, MIRROR_TAG, files$file_name)
reachable <- vapply(mirror_url, function(url) {
  h <- curl::new_handle(nobody = TRUE, followlocation = TRUE)
  status <- tryCatch(curl::curl_fetch_memory(url, handle = h)$status_code,
                     error = function(e) NA_integer_)
  isTRUE(status == 200L)
}, logical(1))
if (!all(reachable)) {
  message("No mirror asset yet for: ",
          paste(files$file_name[!reachable], collapse = ", "),
          "\n  Upload them to the '", MIRROR_TAG,
          "' release and re-run; mirror_url is left empty for now.")
  mirror_url[!reachable] <- NA_character_
}

eavs_manifest <- tibble::tibble(
  survey = files$survey,
  year = files$year,
  format = files$format,
  version = files$version,
  release_date = as.Date(files$release_date),
  file_name = files$file_name,
  bytes = bytes,
  sha256 = sha256,
  source_url = files$source_url,
  mirror_url = mirror_url
)
eavs_manifest <- eavs_manifest[order(eavs_manifest$survey,
                                     eavs_manifest$year,
                                     eavs_manifest$format), ]

save(eavs_manifest, file = "data/eavs_manifest.rda", compress = "xz")
message("Wrote data/eavs_manifest.rda (", nrow(eavs_manifest), " files)")

# Also write the shared copy any future Python package reads, so the pinned
# catalog exists once rather than once per language. Generated, not hand-edited.
readr::write_csv(eavs_manifest, "../metadata/manifest.csv", na = "")
message("Wrote ../metadata/manifest.csv")
