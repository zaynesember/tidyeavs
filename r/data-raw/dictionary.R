## Builds data/eavs_dictionary.rda from the shared metadata in ../metadata/.
##
## Inputs (committed, language-neutral, shared with any future Python package):
##   - ../metadata/concepts.csv   one row per concept: section, label, EPI name,
##     and `shipped`, which decides whether the concept reaches the dictionary
##   - ../metadata/crosswalk.csv  one row per concept-year: the raw variable code
##     that year (blank where the item was not collected), that year's codebook
##     label, a confidence rating, and any trap warning in `note`
##
## Editing either CSV is how you add a concept or correct a code — there is no
## curated metadata left in this script, which is the point: the crosswalk is
## reviewable in a diff, and R and Python cannot drift apart because they read
## the same file. The guards below run on every build, so a hand-edit that
## breaks the grid fails here rather than downstream.
##
## Run from the package root:  Rscript data-raw/dictionary.R

library(dplyr)

sections <- c("id", "A", "B", "C", "D", "E", "F")
years <- c(2016L, 2018L, 2020L, 2022L, 2024L)

concepts <- readr::read_csv("../metadata/concepts.csv", show_col_types = FALSE)
crosswalk <- readr::read_csv("../metadata/crosswalk.csv", show_col_types = FALSE)

# Validate the hand-edited metadata. ----------------------------------------
orphans <- setdiff(crosswalk$concept, concepts$concept)
if (length(orphans) > 0) {
  stop("crosswalk.csv has concepts missing from concepts.csv: ",
       paste(orphans, collapse = ", "))
}
uncrosswalked <- setdiff(concepts$concept, crosswalk$concept)
if (length(uncrosswalked) > 0) {
  stop("concepts.csv has concepts missing from crosswalk.csv: ",
       paste(uncrosswalked, collapse = ", "))
}
bad_section <- setdiff(concepts$section, sections)
if (length(bad_section) > 0) {
  stop("concepts.csv has unknown section(s): ", paste(bad_section, collapse = ", "))
}
bad_conf <- setdiff(crosswalk$confidence, c("high", "medium", "low"))
if (length(bad_conf) > 0) {
  stop("crosswalk.csv has unknown confidence value(s): ",
       paste(bad_conf, collapse = ", "))
}
# Every concept needs a row for every year, even when the code is blank: a
# missing row would silently drop that year rather than record "not collected".
incomplete <- crosswalk |>
  count(concept) |>
  filter(n != length(years))
if (nrow(incomplete) > 0) {
  stop("crosswalk.csv is not a complete concept-year grid; check: ",
       paste(incomplete$concept, collapse = ", "))
}
if (!setequal(crosswalk$year, years)) {
  stop("crosswalk.csv years do not match the expected set: ",
       paste(sort(unique(crosswalk$year)), collapse = ", "))
}
if (any(duplicated(concepts$concept))) {
  stop("concepts.csv has duplicate concept(s): ",
       paste(unique(concepts$concept[duplicated(concepts$concept)]), collapse = ", "))
}

# Join and ship. ------------------------------------------------------------
eavs_dictionary <- concepts |>
  filter(shipped) |>
  select(concept, concept_label, section, epi_name) |>
  inner_join(
    crosswalk |> select(concept, year, code, codebook_label, note, confidence),
    by = "concept"
  ) |>
  transmute(concept, concept_label, section, year = as.integer(year),
            code, codebook_label, epi_name, note, confidence) |>
  mutate(section = factor(section, levels = sections)) |>
  arrange(year, section, concept) |>
  mutate(section = as.character(section))

save(eavs_dictionary, file = "data/eavs_dictionary.rda", compress = "xz")
message("Wrote data/eavs_dictionary.rda (",
        length(unique(eavs_dictionary$concept)), " concepts, ",
        nrow(eavs_dictionary), " rows; ",
        sum(!concepts$shipped), " concept(s) held back)")
