#' Rates over the jurisdictions that reported both sides
#'
#' Divides one concept by another using only the jurisdictions that reported
#' both, which is how the EAC's own published rates are computed.
#'
#' The restriction matters more than it sounds. In 2024 all 67 Alabama counties
#' report `uocava_counted` and none report `uocava_returned`, so Alabama alone
#' adds 131,961 to the national numerator and nothing to the denominator.
#' Summing both columns over every jurisdiction in the country and dividing
#' gives a national rate of 112%; over the jurisdictions reporting both it is
#' 96.4%, the figure the EAC publishes. (Alabama's own ratio is not 112% but
#' undefined, which is what `rate = NA` in its row means.) States often report
#' one side of a pair and not the other, and which pairs are affected changes
#' from cycle to cycle, so this is not a rare edge case.
#'
#' It also has to happen here rather than afterwards. Once numerator and
#' denominator have been summed separately there is no way to tell which
#' jurisdictions were in both, so a defensible rate cannot be recovered from
#' [eavs_aggregate()] output. Pass the panel.
#'
#' @section Reading the output:
#' `rate` is `num_value / den_value`, a ratio of sums rather than an average of
#' per-jurisdiction ratios. Check two columns before quoting it: `n_both`, the
#' jurisdictions behind it, and `den_share`, how much of the group's reported
#' denominator they hold. A rate resting on 4% of a state's returned ballots
#' prints exactly like one resting on 96%. `n_num_only` and `n_den_only` count
#' the jurisdictions that reported only one side, so Alabama above appears as
#' `n_num_only = 67` rather than as an inflated rate.
#'
#' To pool groups, sum `num_value` and `den_value`; averaging `rate` would
#' weight a small county like a large one. The same call gives the EAC's
#' voting-mode shares, e.g.
#' `eavs_rate(panel, "partic_in_person_ed", "partic_total")`.
#'
#' Nothing is corrected here: the restriction selects rows and counts what it
#' left out.
#'
#' @section Rates that rest on an anomalous state-year:
#' The columns above measure how many jurisdictions answered, not whether what
#' they reported is comparable, so a rate can be fully supported and still
#' unusable. Oregon's 2018 mail rejection rate comes back at 0.009% with
#' `n_both = 36` and `den_share = 1`, meaning every county reported, because all
#' 36 answered the disposition items for a small subset of ballots that year.
#'
#' `known_anomaly` says so: `NA` when neither side is affected, otherwise
#' `"numerator"`, `"denominator"`, or `"both"`, naming which side of the ratio
#' the anomaly touches. It fires when the year, state, and concept appear in
#' [eavs_known_anomalies] and `n_both` is above zero, so the rate actually rests
#' on them. Nothing is withheld or adjusted: the rate is still computed and
#' returned. [eavs_flags()] carries the reason and the evidence for each one, and
#' the table is short, so absence of a flag is not proof a state-year is
#' comparable.
#'
#' @param data A harmonized panel from [eavs_load()], or one year from
#'   [eavs_harmonize()].
#' @param numerator,denominator Names of two numeric concept columns in `data`.
#' @param by `"state"` (default) or `"county"`. County rollups drop rows whose
#'   published code embeds no county, as in [eavs_aggregate()].
#' @param jurisdictions The jurisdiction table to join for county codes.
#'   Defaults to the bundled [eavs_jurisdictions].
#' @param anomalies The verified reporting anomalies to mark. Defaults to the
#'   bundled [eavs_known_anomalies]; pass your own or set to `NULL` to skip them.
#'
#' @return A tibble with one row per group per year: the grouping columns,
#'   `entity_type` (`"state"`, `"territory"`, or `"district"`—DC is the one
#'   district, so a 50-state ranking wants
#'   `entity_type %in% c("state", "district")` or neither, deliberately),
#'   `numerator`, `denominator`, `num_value` and `den_value`
#'   (sums over the common subset), `rate`, `n_both`, `n_num_only`,
#'   `n_den_only`, `den_share`, and `known_anomaly`. `rate` is `NA` when the
#'   common-subset denominator is zero.
#' @seealso [eavs_aggregate()] for totals with coverage, [eavs_flags()] for the
#'   anomalies a subset restriction cannot see.
#' @export
#'
#' @examples
#' \dontrun{
#' panel <- eavs_load(2024)
#' eavs_rate(panel, "mail_rejected", "mail_returned")
#'
#' # Alabama reports the numerator and not the denominator, so its rate is NA.
#' r <- eavs_rate(panel, "uocava_counted", "uocava_returned")
#' r[r$state_abbr == "AL", ]
#'
#' # Fully supported and still not comparable: Oregon 2018 has every county
#' # reporting, and known_anomaly says the numerator is affected.
#' r <- eavs_rate(eavs_load(c(2016, 2018, 2020)), "mail_rejected", "mail_returned")
#' r[r$state_abbr == "OR", c("year", "rate", "n_both", "den_share", "known_anomaly")]
#' }
eavs_rate <- function(data, numerator, denominator, by = "state",
                      jurisdictions = NULL, anomalies = NULL) {
  by <- match.arg(by, c("state", "county"))
  if (missing(anomalies)) {
    anomalies <- eavs_known_anomalies
  }
  if (!"year" %in% names(data)) {
    cli::cli_abort("{.arg data} needs a {.field year} column; use {.fn eavs_load}.")
  }
  for (nm in c(numerator, denominator)) {
    if (!is.character(nm) || length(nm) != 1 || !nm %in% names(data) ||
        !is.numeric(data[[nm]])) {
      cli::cli_abort(c(
        "{.val {nm}} is not a numeric concept column in {.arg data}.",
        i = "See {.fn eavs_items} for the shipped concept names."
      ))
    }
  }
  if (identical(numerator, denominator)) {
    cli::cli_abort("{.arg numerator} and {.arg denominator} must differ.")
  }

  keys <- aggregate_keys(data, by, jurisdictions)
  keep <- if ("county_fips" %in% names(keys)) !is.na(keys$county_fips) else rep(TRUE, nrow(keys))
  keys <- keys[keep, , drop = FALSE]
  num <- data[[numerator]][keep]
  den <- data[[denominator]][keep]

  group <- interaction(keys, drop = TRUE, lex.order = TRUE)
  both <- !is.na(num) & !is.na(den)

  gsum <- function(x, flag) {
    as.numeric(tapply(ifelse(flag, x, 0), group, sum, na.rm = TRUE))
  }
  gcount <- function(flag) as.integer(tapply(flag, group, sum))

  first_rows <- match(levels(group), as.character(group))
  res <- keys[first_rows, , drop = FALSE]
  res$entity_type <- entity_type_of(res$state_abbr)
  res$numerator <- numerator
  res$denominator <- denominator
  res$num_value <- gsum(num, both)
  res$den_value <- gsum(den, both)
  res$rate <- ifelse(res$den_value > 0, res$num_value / res$den_value, NA_real_)
  res$n_both <- gcount(both)
  res$n_num_only <- gcount(!is.na(num) & is.na(den))
  res$n_den_only <- gcount(is.na(num) & !is.na(den))
  den_all <- gsum(den, !is.na(den))
  res$den_share <- ifelse(den_all > 0, res$den_value / den_all, NA_real_)

  # A rate can rest on every jurisdiction in the state and still be built on an
  # anomalous convention, which none of the columns above can show. Name the
  # side rather than a bare TRUE: only one half of a ratio is usually affected.
  # Conditioned on n_both, since with no common subset there is no rate to
  # distrust.
  num_anom <- anomaly_match(res$year, res$state_abbr, numerator, anomalies) &
    res$n_both > 0
  den_anom <- anomaly_match(res$year, res$state_abbr, denominator, anomalies) &
    res$n_both > 0
  res$known_anomaly <- ifelse(
    num_anom & den_anom, "both",
    ifelse(num_anom, "numerator", ifelse(den_anom, "denominator", NA_character_))
  )

  key_names <- names(keys)
  res <- res[order(res$year), c("year", setdiff(key_names, "year"),
                                "entity_type", "numerator", "denominator",
                                "num_value", "den_value", "rate", "n_both",
                                "n_num_only", "n_den_only", "den_share",
                                "known_anomaly")]
  tibble::as_tibble(res)
}
