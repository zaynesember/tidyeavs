"""Decoding EAVS missing-value codes.

Mirrors ``r/R/recode.R``. The classification rules are subtle enough that the
two implementations are kept deliberately parallel: identifier and text columns
are left alone, a column counts as a numeric item only when every substantive
value in it parses as a number, and because every EAVS item is a count or a rate
any negative value is read as missing.
"""

from __future__ import annotations

import re

import pandas as pd

from ._constants import ID_PATTERNS, SENTINELS, STATUS_LEVELS, TOKEN_STATUS

# Sentinels matched on the parsed number rather than its text, which makes
# "-88", "-088" and "-88.0" all resolve to the same code, as they do in R.
_SENTINEL_VALUES = {float(code): status for code, status in SENTINELS.items()}

_CODE_LABEL = re.compile(r"^\s*(-?[0-9]+)\s*:.*$")
_ID_RE = tuple(re.compile(pattern, re.IGNORECASE) for pattern in ID_PATTERNS)


def strip_code_label(values: pd.Series) -> pd.Series:
    """Reduce a 2016-style ``"CODE: Label"`` value to its numeric code.

    The 2016 EAVS writes sentinels as ``"-999999: Data Not Available"`` rather
    than a bare number. Plain values pass through unchanged.
    """
    return values.str.replace(_CODE_LABEL, lambda m: m.group(1), regex=True)


def is_item_column(values: pd.Series, name: str) -> bool:
    """Is this a numeric EAVS item, as opposed to an identifier or text field?"""
    if any(pattern.search(name) for pattern in _ID_RE):
        return False
    if pd.api.types.is_numeric_dtype(values):
        return True
    if not (
        pd.api.types.is_string_dtype(values) or pd.api.types.is_object_dtype(values)
    ):
        return False

    text = values.astype("string")
    trimmed = strip_code_label(text).str.strip()
    keep = text.notna() & (trimmed != "") & ~trimmed.str.lower().isin(TOKEN_STATUS)
    if not keep.any():
        return False
    return bool(pd.to_numeric(trimmed[keep], errors="coerce").notna().all())


def _classify(values: pd.Series) -> tuple[pd.Series, pd.Series]:
    """Return (numeric values, status labels) for one item column."""
    text = strip_code_label(values.astype("string"))
    trimmed = text.str.strip()
    lowered = trimmed.str.lower()

    blank = text.isna() | (trimmed == "")
    token = ~blank & lowered.isin(TOKEN_STATUS)
    rest = ~blank & ~token

    number = pd.to_numeric(trimmed.where(rest), errors="coerce")

    status = pd.Series("reported", index=values.index, dtype=object)
    status[blank] = "blank"
    status[token] = lowered[token].map(TOKEN_STATUS)

    sentinel = rest & number.isin(_SENTINEL_VALUES)
    status[sentinel] = number[sentinel].map(_SENTINEL_VALUES)
    # A negative that is not a recognized sentinel is still missing, since no
    # EAVS item is legitimately negative. So is a value that will not parse.
    status[rest & number.notna() & (number < 0) & ~sentinel] = "other_missing"
    status[rest & number.isna()] = "other_missing"

    reported = rest & number.notna() & ~sentinel & (number >= 0)
    value = pd.Series(pd.NA, index=values.index, dtype="Float64")
    value[reported] = number[reported].astype("Float64")

    labels = pd.Categorical(status, categories=STATUS_LEVELS, ordered=True)
    return value, pd.Series(labels, index=values.index)


def _recode_core(data: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame]:
    values = data.copy()
    status = data.copy()
    for name in data.columns:
        if is_item_column(data[name], str(name)):
            values[name], status[name] = _classify(data[name])
    return values, status


def recode_missing(data: pd.DataFrame) -> pd.DataFrame:
    """Convert item columns to numbers, with sentinel values set to ``NA``.

    Identifier and text columns—FIPS codes, jurisdiction and state names,
    comment and write-in fields—are left untouched, so this is safe to call on
    a whole raw year from :func:`tidyeavs.read`.

    Recognized sentinels keep their specific meaning, which
    :func:`missing_status` reports; collapsing everything to ``NA`` would lose
    the distinction between "does not apply" and "data not available".
    """
    return _recode_core(data)[0]


def missing_status(data: pd.DataFrame) -> pd.DataFrame:
    """Report *why* each item value is, or is not, missing.

    Returns a frame the same shape as ``data`` with each item value replaced by
    an ordered categorical: ``reported``, ``does_not_apply``, ``not_available``,
    ``valid_skip``, ``other_missing``, or ``blank``. Identifier and text columns
    are unchanged.

    This is the companion to :func:`recode_missing`, and the reason to reach for
    it is coverage: a state total computed with ``skipna=True`` silently covers
    only the jurisdictions that reported, so it is worth knowing how many did.
    """
    return _recode_core(data)[1]
