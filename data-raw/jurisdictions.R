## Builds data/eavs_jurisdictions.rda: one row per jurisdiction per EAVS year,
## with the published identifiers, a normalized FIPS code, the county FIPS
## where the published code embeds one, a structural type, and quirk flags.
## Nothing is corrected: every published row is kept, including duplicate
## codes and statewide pseudo-rows, and the quirks are flagged, not fixed.
##
## Reads the raw EAVS files from the cache (downloading if absent), so it
## needs the package loadable and network on first run. Run from the package
## root:  Rscript data-raw/jurisdictions.R
##
## Structural facts encoded below, verified against the published files:
##   - Wisconsin codes are 5-digit non-geographic serials (~1,850/year), so no
##     county is derivable; the county lives in the jurisdiction name. In 2020
##     the town/village pairs Vernon (82575) and Waukesha (84275), and in 2022
##     Greenville (31550), each share one serial across two rows.
##   - Maine files a statewide UOCAVA row: FIPS "23." in 2016, "23" after.
##   - Sub-county codes in CT/MA/ME/NH/RI/VT are state+county+town, so the
##     county is derivable—except five Maine towns coded to county "099",
##     and with the caveat that CT's are the pre-2022 Census counties.
##   - Illinois city election boards (Aurora 2016 only; Bloomington, Danville,
##     East St. Louis, Galesburg every year) are state+place+000: the middle
##     digits are a place code, NOT a county, so no county is derivable.
##   - Alaska and the territories (AS/GU/MP/PR/VI) file one statewide row
##     coded SS00000000. AS and MP first appear in 2020; PR is absent in the
##     midterm years 2018 and 2022.
##   - In 2024, Alameda and Calaveras CA lost their leading zero (9 digits).
##   - NY 2016 codes Yates County "3612295082"; 2018 on use "3612300000".
##   - SD's Oglala Lakota County is "4611300000" in 2016 (the pre-rename
##     Shannon County code) and "4610200000" from 2018 on.
##   - Kalawao HI ("1500500000") appears every year; Maui County administers
##     its elections.

pkgload::load_all(".", quiet = TRUE)
library(tibble)

years <- c(2016L, 2018L, 2020L, 2022L, 2024L)

# State/territory abbreviation -> ANSI FIPS and standard name.
state_ref <- c(
  AL = "01", AK = "02", AZ = "04", AR = "05", CA = "06", CO = "08", CT = "09",
  DE = "10", DC = "11", FL = "12", GA = "13", HI = "15", ID = "16", IL = "17",
  IN = "18", IA = "19", KS = "20", KY = "21", LA = "22", ME = "23", MD = "24",
  MA = "25", MI = "26", MN = "27", MS = "28", MO = "29", MT = "30", NE = "31",
  NV = "32", NH = "33", NJ = "34", NM = "35", NY = "36", NC = "37", ND = "38",
  OH = "39", OK = "40", OR = "41", PA = "42", RI = "44", SC = "45", SD = "46",
  TN = "47", TX = "48", UT = "49", VT = "50", VA = "51", WA = "53", WV = "54",
  WI = "55", WY = "56", AS = "60", GU = "66", MP = "69", PR = "72", VI = "78"
)
state_names <- c(
  stats::setNames(state.name, state.abb),
  DC = "District of Columbia", AS = "American Samoa", GU = "Guam",
  MP = "Northern Mariana Islands", PR = "Puerto Rico",
  VI = "U.S. Virgin Islands"
)

territories <- c("AS", "GU", "MP", "PR", "VI")
# States whose sub-county codes embed the county FIPS (state+county+town).
town_states <- c("CT", "MA", "ME", "NH", "RI", "VT")

build_year <- function(y) {
  raw <- eavs_read(y, quiet = TRUE)
  if (y == 2016L) {
    d <- tibble(
      fips_code = raw$FIPSCode,
      jurisdiction_name = raw$JurisdictionName,
      state_abbr = raw$State
    )
  } else {
    d <- tibble(
      fips_code = raw$FIPSCode,
      jurisdiction_name = raw$Jurisdiction_Name,
      state_abbr = raw$State_Abbr
    )
  }
  stopifnot(!anyNA(d$fips_code), !anyNA(d$state_abbr),
            all(d$state_abbr %in% names(state_ref)))

  d$year <- y
  d$state_name <- unname(state_names[d$state_abbr])
  d$state_fips <- unname(state_ref[d$state_abbr])

  n <- nchar(d$fips_code)
  me_state_row <- d$state_abbr == "ME" & d$fips_code %in% c("23", "23.")
  stopifnot(sum(me_state_row) == 1, all(n >= 9 | n == 5 | me_state_row))

  # Normalized 10-digit code, for codes that are FIPS-style. Wisconsin's
  # serials and Maine's statewide row carry no geography, so NA there.
  d$fips10 <- ifelse(n == 10, d$fips_code,
              ifelse(n == 9, paste0("0", d$fips_code), NA_character_))

  county_part <- substr(d$fips10, 3, 5)
  place_coded <- !is.na(d$fips10) & substr(d$fips10, 6, 10) != "00000" &
    !(d$state_abbr %in% town_states)

  d$type <- dplyr::case_when(
    d$state_abbr %in% territories ~ "territory",
    d$state_abbr == "AK" | me_state_row ~ "statewide",
    n == 5 ~ "municipality",
    place_coded & d$fips_code != "3612295082" ~ "municipality",
    !is.na(d$fips10) & substr(d$fips10, 6, 10) != "00000" ~ "municipality",
    TRUE ~ "county"
  )

  # County FIPS, only where the published code embeds one: county rows and
  # town-state rows, excluding the no-geography codes and the malformed 2016
  # Yates County code. County part "099" is a real county in many states
  # (Macomb MI, Stanislaus CA, ...) but in Maine it is a catch-all bucket for
  # a few townships, not a county—Maine's counties stop at 031.
  me_bucket <- county_part == "099" & d$state_abbr == "ME"
  embeds_county <- !is.na(d$fips10) & !place_coded &
    county_part != "000" & !me_bucket & d$fips_code != "3612295082" &
    d$type %in% c("county", "municipality")
  d$county_fips <- ifelse(embeds_county, substr(d$fips10, 1, 5), NA_character_)
  stopifnot(all(is.na(d$county_fips) |
                  substr(d$county_fips, 1, 2) == d$state_fips))

  d$nongeo_code <- n == 5
  d$code_padded <- n == 9
  d$shared_code <- d$fips_code %in% d$fips_code[duplicated(d$fips_code)]

  d$note <- NA_character_
  d$note[me_state_row] <-
    "Statewide row: Maine reports UOCAVA ballots at the state level; town rows carry everything else."
  d$note[d$state_abbr == "AK"] <-
    "Alaska administers elections statewide and files as a single jurisdiction."
  d$note[d$fips10 %in% "1500500000"] <-
    "Kalawao County's elections are administered by Maui County."
  d$note[d$shared_code] <-
    "Published code is shared by two rows this year."
  d$note[d$code_padded] <-
    "Published code has nine digits; fips10 restores the leading zero."
  d$note[me_bucket] <-
    "Published code uses Maine's '099' township bucket in the county position, not a county code."
  d$note[d$fips_code == "3612295082"] <-
    "Published code does not follow the state+county+00000 pattern used for other New York counties; later years publish 3612300000."
  d$note[d$fips_code == "4611300000" & d$state_abbr == "SD"] <-
    "Pre-rename Shannon County code; Oglala Lakota County is 4610200000 from 2018 on."

  d[, c("year", "fips_code", "fips10", "jurisdiction_name", "state_abbr",
        "state_name", "state_fips", "county_fips", "type",
        "nongeo_code", "code_padded", "shared_code", "note")]
}

frames <- lapply(years, build_year)
eavs_jurisdictions <- dplyr::bind_rows(frames)
eavs_jurisdictions <- eavs_jurisdictions[
  order(eavs_jurisdictions$year, eavs_jurisdictions$state_abbr,
        eavs_jurisdictions$fips_code), ]

# The table must carry every published row, exactly.
counts <- table(eavs_jurisdictions$year)
stopifnot(identical(
  as.integer(counts[as.character(years)]),
  c(6467L, 6460L, 6460L, 6460L, 6461L)
))

save(eavs_jurisdictions, file = "data/eavs_jurisdictions.rda", compress = "xz")
message("Wrote data/eavs_jurisdictions.rda (", nrow(eavs_jurisdictions),
        " rows, ", length(unique(eavs_jurisdictions$year)), " years)")
