## Builds data/eavs_checks.rda: the internal-consistency checks eavs_flags runs.
##
## Reads ../metadata/checks.csv, the committed shared definition, so that R and
## Python apply the same checks. Every check has the same shape — the concepts in
## `parts` should not sum past `total` — which covers both orderings (one part)
## and subpart-versus-total (several).
##
## Run from the package root:  Rscript data-raw/checks.R

library(dplyr)

checks <- readr::read_csv("../metadata/checks.csv", show_col_types = FALSE)

# Validate against the dictionary: a check naming a concept that does not exist
# would silently never fire.
load("data/eavs_dictionary.rda")
concepts <- unique(eavs_dictionary$concept)

named <- unique(c(checks$total, unlist(strsplit(checks$parts, ";", fixed = TRUE))))
unknown <- setdiff(named, concepts)
if (length(unknown) > 0) {
  stop("checks.csv names concepts absent from the dictionary: ",
       paste(unknown, collapse = ", "))
}
if (any(duplicated(checks$check))) {
  stop("checks.csv has duplicate check name(s): ",
       paste(unique(checks$check[duplicated(checks$check)]), collapse = ", "))
}
bad_section <- setdiff(checks$section, c("A", "B", "C", "D", "E", "F"))
if (length(bad_section) > 0) {
  stop("checks.csv has unknown section(s): ", paste(bad_section, collapse = ", "))
}
# A check whose total is also one of its parts would compare a number to itself.
overlap <- vapply(seq_len(nrow(checks)), function(i) {
  checks$total[i] %in% strsplit(checks$parts[i], ";", fixed = TRUE)[[1]]
}, logical(1))
if (any(overlap)) {
  stop("checks.csv has a check whose total appears in its own parts: ",
       paste(checks$check[overlap], collapse = ", "))
}

eavs_checks <- checks |>
  mutate(parts = strsplit(parts, ";", fixed = TRUE)) |>
  arrange(section, check)

save(eavs_checks, file = "data/eavs_checks.rda", compress = "xz")
message("Wrote data/eavs_checks.rda (", nrow(eavs_checks), " checks)")
