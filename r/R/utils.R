# Sentinel and missing-value handling ------------------------------------

# EAVS marks non-substantive responses with negative integer sentinels. The
# codes changed between survey eras: 2018 onward uses -88 / -99 / -77, while
# 2016 and earlier used six-digit codes. Because every substantive EAVS item
# is a count or a rate (never negative), any negative value in an item column
# is a sentinel, not data. See `eavs_recode_missing()`.
#
# Named vector mapping known sentinel codes to a status label. Codes not
# listed here but still negative are treated as `other_missing`. That includes
# -88888 (five 8s; 480 occurrences, all 2016 Maine, mostly F7d booth/counter
# items): plausibly a truncated -888888, but unattested in the codebook, so it
# stays unrecognized rather than guessed at (decided 2026-07-30).
.eavs_sentinels <- c(
  "-88"      = "does_not_apply",
  "-99"      = "not_available",
  "-77"      = "valid_skip",
  "-888888"  = "does_not_apply",
  "-999999"  = "not_available",
  "-999998"  = "other_missing",
  "-999991"  = "other_missing"
)

# Text tokens some jurisdictions enter in place of a number, mapped to a
# status. Matched case- and whitespace-insensitively before a column is tested
# for being numeric.
.eavs_token_status <- c(
  "data not available" = "not_available",
  "not available"      = "not_available",
  "does not apply"     = "does_not_apply",
  "n/a"                = "not_available",
  "na"                 = "not_available",
  "-"                  = "not_available"
)

# Column-name patterns (Perl regex) that mark identifier or free-text columns.
# These are never treated as numeric items, so FIPS codes keep leading zeros
# and comment fields are left alone.
.eavs_id_patterns <- c(
  "(?i)^year$",
  "(?i)^survey$",
  "(?i)fips",
  "(?i)jurisdiction",
  "(?i)^state",
  "(?i)name",
  "(?i)comment",
  "(?i)_other$",
  "(?i)_specify",
  "(?i)preferredorder",
  "(?i)^source$"
)

# The ordered set of status labels a recoded value can take.
.eavs_status_levels <- c(
  "reported", "does_not_apply", "not_available",
  "valid_skip", "other_missing", "blank"
)

# Territories that file EAVS rows. State-level output is not all states: these
# five and DC file too, and a 50-state analysis needs to see which is which
# without memorizing the codes. Mirrored as TERRITORIES in _constants.py.
.eavs_territories <- c("AS", "GU", "MP", "PR", "VI")

# Classify a state_abbr for the entity_type column in eavs_aggregate() output.
entity_type_of <- function(state_abbr) {
  ifelse(state_abbr %in% .eavs_territories, "territory",
         ifelse(state_abbr == "DC", "district", "state"))
}

# Is this year/state/concept one of the verified reporting anomalies? Keyed the
# same three ways `flag_known_anomalies()` matches, since every anomaly recorded
# so far is a statewide convention for one concept in one cycle. Vectorized over
# all three arguments; `concept` is usually a single name recycled.
#
# This is what lets eavs_rate() and eavs_aggregate() say that a number rests on
# an anomalous state-year, which no arithmetic check can tell you: Oregon's 2018
# mail rejection rate comes back with n_both = 36 and den_share = 1, i.e. every
# county reporting, and is still unusable. Reporting it is as far as this goes.
# The value is returned as summed, and what to do about it is the user's call.
anomaly_match <- function(year, state_abbr, concept, anomalies) {
  n <- max(length(year), length(state_abbr), length(concept))
  if (is.null(anomalies) || nrow(anomalies) == 0) {
    return(rep(FALSE, n))
  }
  paste(year, state_abbr, concept) %in%
    paste(anomalies$year, anomalies$state_abbr, anomalies$concept)
}

# The 2016 EAVS writes sentinels as "CODE: Label" (e.g.
# "-999999: Data Not Available"). Reduce such a value to its numeric code so
# the shared sentinel logic can handle it. Plain values pass through unchanged.
strip_code_label <- function(x) {
  m <- !is.na(x) & grepl("^\\s*-?[0-9]+\\s*:", x)
  x[m] <- sub("^\\s*(-?[0-9]+)\\s*:.*$", "\\1", x[m])
  x
}

# Compute the SHA-256 of a file on disk.
file_sha256 <- function(path) {
  digest::digest(path, algo = "sha256", file = TRUE)
}

# Is a Suggests-level package available? Errors with an install hint if not.
require_pkg <- function(pkg, reason) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    cli::cli_abort(c(
      "The {.pkg {pkg}} package is required {reason}.",
      i = "Install it with {.run install.packages(\"{pkg}\")}."
    ))
  }
  invisible(TRUE)
}
