"""Sentinel codes and column classification rules.

These mirror ``r/R/utils.R`` exactly. EAVS marks non-substantive responses with
negative integer sentinels, and the codes changed between survey eras: 2018
onward uses -88 / -99 / -77, while 2016 and earlier used six-digit codes.
Because every substantive EAVS item is a count or a rate and never negative,
any negative value in an item column is a sentinel rather than data.

Keeping these in one module, named the same as their R counterparts, is
deliberate: when a new sentinel or token turns up in a future survey year it
has to be added in both languages, and matching names make the pair easy to
find.
"""

from __future__ import annotations

# Known sentinel codes mapped to a status label. Codes not listed here but
# still negative are treated as ``other_missing``.
SENTINELS: dict[str, str] = {
    "-88": "does_not_apply",
    "-99": "not_available",
    "-77": "valid_skip",
    "-888888": "does_not_apply",
    "-999999": "not_available",
    "-999998": "other_missing",
    "-999991": "other_missing",
}

# Text tokens some jurisdictions enter in place of a number, mapped to a
# status. Matched case- and whitespace-insensitively before a column is tested
# for being numeric.
TOKEN_STATUS: dict[str, str] = {
    "data not available": "not_available",
    "not available": "not_available",
    "does not apply": "does_not_apply",
    "n/a": "not_available",
    "na": "not_available",
    "-": "not_available",
}

# Column-name patterns marking identifier or free-text columns. These are never
# treated as numeric items, so FIPS codes keep their leading zeros and comment
# fields are left alone.
ID_PATTERNS: tuple[str, ...] = (
    r"^year$",
    r"^survey$",
    r"fips",
    r"jurisdiction",
    r"^state",
    r"name",
    r"comment",
    r"_other$",
    r"_specify",
    r"preferredorder",
    r"^source$",
)

# The ordered set of status labels a recoded value can take.
STATUS_LEVELS: tuple[str, ...] = (
    "reported",
    "does_not_apply",
    "not_available",
    "valid_skip",
    "other_missing",
    "blank",
)

SURVEYS: tuple[str, ...] = ("eavs", "policy")
FORMATS: tuple[str, ...] = ("csv", "xlsx")
