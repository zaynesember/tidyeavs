## Builds data/eavs_known_anomalies.rda: verified reporting anomalies in the
## published files that arithmetic checks cannot catch.
##
## Reads ../metadata/known_anomalies.csv, the committed shared definition, so
## an anomaly cannot be known to one language and not the other. Admission
## rule: every row must be verified against the published file and cite its
## evidence in `source`. These describe how a state answered an item; nothing
## here alters a value, and the rows surface through eavs_flags() as
## kind = "known_anomaly".
##
## Run from the package root:  Rscript data-raw/known_anomalies.R

anomalies <- readr::read_csv("../metadata/known_anomalies.csv",
                             show_col_types = FALSE)

# Validate against the dictionary: an anomaly naming a concept that does not
# exist would silently never surface.
load("data/eavs_dictionary.rda")
concepts <- unique(eavs_dictionary$concept)

unknown <- setdiff(anomalies$concept, concepts)
if (length(unknown) > 0) {
  stop("known_anomalies.csv names concepts absent from the dictionary: ",
       paste(unknown, collapse = ", "))
}
years <- unique(eavs_dictionary$year)
bad_year <- setdiff(anomalies$year, years)
if (length(bad_year) > 0) {
  stop("known_anomalies.csv has years outside the dictionary: ",
       paste(bad_year, collapse = ", "))
}
load("data/eavs_jurisdictions.rda")
bad_state <- setdiff(anomalies$state_abbr, eavs_jurisdictions$state_abbr)
if (length(bad_state) > 0) {
  stop("known_anomalies.csv has unknown state_abbr value(s): ",
       paste(bad_state, collapse = ", "))
}
key <- paste(anomalies$year, anomalies$state_abbr, anomalies$concept)
if (any(duplicated(key))) {
  stop("known_anomalies.csv has duplicate (year, state_abbr, concept) row(s): ",
       paste(key[duplicated(key)], collapse = "; "))
}
if (any(is.na(anomalies$note)) || any(is.na(anomalies$source))) {
  stop("known_anomalies.csv rows must carry both a note and a source.")
}

eavs_known_anomalies <- anomalies[
  order(anomalies$year, anomalies$state_abbr, anomalies$concept), ]

save(eavs_known_anomalies, file = "data/eavs_known_anomalies.rda",
     compress = "xz")
message("Wrote data/eavs_known_anomalies.rda (", nrow(eavs_known_anomalies),
        " anomalies)")
