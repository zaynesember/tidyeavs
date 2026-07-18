## Builds data/eavs_dictionary.rda: the cross-year variable crosswalk.
##
## Inputs (in data-raw/sources/, not shipped):
##   - crosswalk_candidate.csv: concept, section, year, code, codebook_label,
##     confidence, note  (per-year codes, verified against EAC codebooks)
##   - codebook_variables.csv: year, VariableName, Label  (for reference)
##
## The concept metadata (labels, EPI names) is curated here. Identifier columns
## are added directly, since they are few and their names are stable within
## eras. Run from the package root:  Rscript data-raw/dictionary.R

library(tibble)
library(dplyr)

# Concept-level metadata: plain-language label and the MIT EPI's name. -------
concept_meta <- tribble(
  ~concept,                ~section, ~concept_label,                                    ~epi_name,
  "reg_eligible_total",    "A", "Registered and eligible voters (total)",           "registeredAndEligible",
  "reg_active",            "A", "Active registered voters",                         "totalActive",
  "reg_inactive",          "A", "Inactive registered voters",                       "totalInactive",
  "reg_forms_received",    "A", "Registration forms received (all sources)",        "totalForm",
  "reg_new_valid",         "A", "New valid registrations",                          "form_ValidReg",
  "reg_rejected",          "A", "Registration forms invalid or rejected",           "form_Rejected",
  "reg_confirmations_sent","A", "Address confirmation notices sent",                "totalConfirmation",
  "reg_removed_total",     "A", "Voters removed from the rolls (total)",            "totalRemoved",
  "uocava_transmitted",    "B", "UOCAVA ballots transmitted",                       "totalAbsTransmit",
  "uocava_returned",       "B", "UOCAVA ballots returned for counting",             "totalAbsSubmit",
  "uocava_counted",        "B", "UOCAVA ballots counted",                           "totalUocavaCount",
  "uocava_rejected",       "B", "UOCAVA ballots rejected",                          "totalUocavaReject",
  "fwab_returned",         "B", "Federal write-in absentee ballots returned",       "totalFwabReturn",
  "fwab_counted",          "B", "Federal write-in absentee ballots counted",        "totalFwabCount",
  "mail_transmitted",      "C", "Mail/absentee ballots transmitted",                "totalByMail",
  "mail_returned",         "C", "Mail/absentee ballots returned",                   "byMail_Return",
  "mail_counted",          "C", "Mail/absentee ballots counted",                    "domAbs_Counted",
  "mail_rejected",         "C", "Mail/absentee ballots rejected",                   "domAbs_Rejected",
  "mail_undeliverable",    "C", "Mail/absentee ballots undeliverable",              "byMail_Undeliv",
  "mail_spoiled",          "C", "Mail/absentee ballots spoiled",                    "byMail_Spoil",
  "prov_submitted",        "E", "Provisional ballots submitted",                    "totalProv",
  "prov_counted_full",     "E", "Provisional ballots counted in full",              "prov_FullCount",
  "prov_counted_partial",  "E", "Provisional ballots counted in part",              "prov_PartCount",
  "prov_rejected",         "E", "Provisional ballots rejected",                     "prov_Rejected",
  "partic_total",          "F", "Total voter participation",                        "totalPartic",
  "partic_in_person_ed",   "F", "Voters: in person on Election Day",                "partic_PollPl",
  "partic_uocava",         "F", "Voters: UOCAVA (absentee) ballot",                 "partic_Abs",
  "partic_by_mail",        "F", "Voters: by mail (vote-by-mail jurisdictions)",     "partic_ByMail",
  "partic_provisional",    "F", "Voters: provisional (credited)",                   "partic_Prov",
  "partic_early_in_person","F", "Voters: early in person",                          "partic_Early",
  "partic_all_mail",       "F", "Voters: all-mail elections",                       "partic_AllMail",
  "polling_places_ed",     "D", "Election Day polling places",                      NA_character_,
  "poll_workers_total",    "D", "Poll workers (total)",                             NA_character_,
  "drop_boxes_total",      "C", "Ballot drop boxes",                                NA_character_,
  "ballots_cured",         "C", "Ballots cured after initial rejection",            NA_character_
)

years <- c(2016L, 2018L, 2020L, 2022L, 2024L)

# Identifier columns, by era. -----------------------------------------------
id_meta <- tribble(
  ~concept,            ~concept_label,               ~code_2016,        ~code_rest,
  "fips_code",         "Jurisdiction FIPS code",     "FIPSCode",        "FIPSCode",
  "jurisdiction_name", "Jurisdiction name",          "JurisdictionName","Jurisdiction_Name",
  "state_abbr",        "State abbreviation",         "State",           "State_Abbr",
  "state_name",        "State name",                 NA_character_,     "State_Full"
)
id_rows <- do.call(rbind, lapply(years, function(y) {
  tibble(
    concept = id_meta$concept,
    concept_label = id_meta$concept_label,
    section = "id",
    year = y,
    code = if (y == 2016L) id_meta$code_2016 else id_meta$code_rest,
    codebook_label = NA_character_,
    epi_name = NA_character_,
    note = NA_character_,
    confidence = "high"
  )
}))

# Item concepts, from the verified crosswalk candidate. ---------------------
cw <- readr::read_csv("data-raw/sources/crosswalk_candidate.csv",
                      show_col_types = FALSE)
cw$code[cw$code %in% c("", "NA")] <- NA
# F1c is UOCAVA participation (F1d is domestic by-mail); name it accordingly.
cw$concept[cw$concept == "partic_absentee"] <- "partic_uocava"
# poll_worker_difficulty is an ordinal stored as text labels in 2016/2018 and
# numeric codes in 2020+; harmonizing it needs care, so hold it for a later
# release. The mapping stays in the source crosswalk.
cw <- cw[cw$concept != "poll_worker_difficulty", ]

extra <- setdiff(cw$concept, concept_meta$concept)
if (length(extra) > 0) {
  stop("Crosswalk concepts missing from concept_meta: ", paste(extra, collapse = ", "))
}

item_rows <- concept_meta |>
  select(concept, concept_label, section, epi_name) |>
  right_join(cw |> select(concept, year, code, codebook_label, note, confidence),
             by = "concept") |>
  transmute(concept, concept_label, section, year = as.integer(year),
            code, codebook_label, epi_name, note, confidence)

eavs_dictionary <- bind_rows(id_rows, item_rows) |>
  mutate(section = factor(section, levels = c("id", "A", "B", "C", "D", "E", "F"))) |>
  arrange(year, section, concept) |>
  mutate(section = as.character(section))

save(eavs_dictionary, file = "data/eavs_dictionary.rda", compress = "xz")
message("Wrote data/eavs_dictionary.rda (",
        length(unique(eavs_dictionary$concept)), " concepts, ",
        nrow(eavs_dictionary), " rows)")
