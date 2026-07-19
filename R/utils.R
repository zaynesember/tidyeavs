# Sentinel and missing-value handling ------------------------------------

# EAVS marks non-substantive responses with negative integer sentinels. The
# codes changed between survey eras: 2018 onward uses -88 / -99 / -77, while
# 2016 and earlier used six-digit codes. Because every substantive EAVS item
# is a count or a rate (never negative), any negative value in an item column
# is a sentinel, not data. See `eavs_recode_missing()`.
#
# Named vector mapping known sentinel codes to a status label. Codes not
# listed here but still negative are treated as `other_missing`.
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
