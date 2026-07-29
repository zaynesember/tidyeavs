## Writes ../metadata/schema.json: the column types for every CSV in metadata/.
##
## CSV carries no types, and the defaults are not safe here. readr happens to
## guess `character` for FIPS codes because the leading zero makes them look
## non-numeric, but pandas reads "0100100000" as the integer 100100000 and the
## leading zero is gone. Since the whole point of the shared metadata is that R
## and Python cannot drift apart, the types travel with the data rather than
## living in each reader's assumptions.
##
## Re-run whenever a column is added, removed, or retyped in any of the four
## files. Run from the package root:  Rscript data-raw/schema.R

r_type <- function(x) {
  if (inherits(x, "Date")) "date"          # written as ISO yyyy-mm-dd
  else if (is.character(x)) "string"
  else if (is.logical(x)) "boolean"
  else if (is.integer(x)) "integer"
  else if (is.numeric(x)) "number"
  else stop("unhandled column type: ", paste(class(x), collapse = "/"))
}

# The two hand-edited files: read as all-character, then declare the two
# columns that are genuinely not text.
concepts <- readr::read_csv("../metadata/concepts.csv",
                            col_types = readr::cols(.default = "c"))
crosswalk <- readr::read_csv("../metadata/crosswalk.csv",
                             col_types = readr::cols(.default = "c"))
concepts_types <- c(
  concept = "string", section = "string", concept_label = "string",
  epi_name = "string", shipped = "boolean"
)
crosswalk_types <- c(
  concept = "string", year = "integer", code = "string",
  codebook_label = "string", confidence = "string", note = "string"
)
stopifnot(
  setequal(names(concepts), names(concepts_types)),
  setequal(names(crosswalk), names(crosswalk_types))
)

# The two generated files: take the types from the authoritative R objects.
load("data/eavs_manifest.rda")
load("data/eavs_jurisdictions.rda")
manifest_types <- vapply(eavs_manifest, r_type, character(1))
jurisdictions_types <- vapply(eavs_jurisdictions, r_type, character(1))

as_obj <- function(x) {
  paste0(
    "{\n",
    paste0(sprintf('      "%s": "%s"', names(x), unname(x)), collapse = ",\n"),
    "\n    }"
  )
}

json <- paste0(
  "{\n",
  '  "_comment": "Column types for the CSVs in this directory. Read every ',
  'string column as text: FIPS codes and variable codes carry leading zeros ',
  'that numeric parsing destroys.",\n',
  '  "files": {\n',
  paste0(
    sprintf('    "%s": %s',
            c("concepts.csv", "crosswalk.csv", "manifest.csv", "jurisdictions.csv"),
            c(as_obj(concepts_types), as_obj(crosswalk_types),
              as_obj(manifest_types), as_obj(jurisdictions_types))),
    collapse = ",\n"
  ),
  "\n  }\n}\n"
)

writeLines(json, "../metadata/schema.json")
message("Wrote ../metadata/schema.json (4 files, ",
        length(concepts_types) + length(crosswalk_types) +
          length(manifest_types) + length(jurisdictions_types), " columns)")
