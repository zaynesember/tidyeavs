"""Internal-consistency flags.

Mirrors ``r/R/flags.R``. Named ``_flags`` so the module does not shadow the
``flags()`` function in the package namespace.
"""

from __future__ import annotations

from typing import Any, Iterable

import numpy as np
import pandas as pd

from . import _metadata

_ID_COLUMNS = ("year", "fips_code", "state_abbr", "jurisdiction_name")
_COLUMNS = (
    "year",
    "fips_code",
    "state_abbr",
    "jurisdiction_name",
    "check",
    "kind",
    "concept",
    "observed",
    "threshold",
    "excess",
    "n_parts_reported",
    "note",
)

# None means "skip sum checks", so a distinct sentinel is needed for "use the
# shipped ones".
_DEFAULT = object()


def flags(
    data: pd.DataFrame,
    checks: Any = _DEFAULT,
    swing_factor: float | None = 10,
    swing_floor: float = 100,
) -> pd.DataFrame:
    """Flag internal inconsistencies in a harmonized panel.

    Runs arithmetic checks and returns one row per flagged observation. Two
    kinds: subparts summing past a total (see :func:`tidyeavs.checks`), and a
    value swinging by more than ``swing_factor`` against the same jurisdiction's
    previous cycle.

    **These are flags, not errors.** A flag says two reported numbers do not
    reconcile arithmetically. It does not say either is wrong. Thousands of
    independent jurisdictions keep records in different ways, and most flags have
    ordinary explanations: ballots transmitted before the reporting window
    opened, a jurisdiction that treats "returned" as returned-and-accepted so
    rejections sit outside it, mode categories that overlap, registration forms
    counted with or without duplicates. Each check's ``note`` records the usual
    explanations. Nothing is changed here; what a flag means for your analysis is
    yours to decide, and the EAC publishes its own validation rules and revises
    datasets as corrections come in, so a flag may already be known upstream.

    **Reading the output.** For a sum check, ``observed`` is the sum of the
    check's parts, ``threshold`` is the total it was compared against, and
    ``excess`` is the difference in whatever the concept counts. For a swing,
    ``observed`` is this cycle, ``threshold`` the previous one, and ``excess`` how
    far the fold-change ran past ``swing_factor``. Those are different scales, so
    the result is sorted within ``kind``; filter to one kind before sorting
    yourself. ``n_parts_reported`` says how many parts had a value — a partial sum
    already exceeding the total is still a genuine flag, since the absent parts
    could only add to it.

    Pass ``checks=None`` to skip sum checks or ``swing_factor=None`` to skip
    swings. ``swing_floor`` keeps small counts out, so a jump from 1 to 20 does
    not dominate.
    """
    if "year" not in data.columns:
        raise ValueError("data needs a 'year' column; use tidyeavs.load().")

    if checks is _DEFAULT:
        checks = _metadata.checks()

    pieces = []
    if checks is not None and len(checks) > 0:
        pieces.extend(_flag_sums(data, checks))
    if swing_factor is not None:
        pieces.extend(_flag_swings(data, swing_factor, swing_floor))

    if not pieces:
        return pd.DataFrame(
            {
                name: pd.Series(
                    dtype="float64"
                    if name in ("observed", "threshold", "excess")
                    else "Int64"
                    if name in ("year", "n_parts_reported")
                    else "object"
                )
                for name in _COLUMNS
            }
        )

    out = pd.concat(pieces, ignore_index=True)[list(_COLUMNS)]
    return out.sort_values(
        ["kind", "excess"], ascending=[True, False], kind="mergesort"
    ).reset_index(drop=True)


def _ids(data: pd.DataFrame, keep: np.ndarray) -> pd.DataFrame:
    present = [c for c in _ID_COLUMNS if c in data.columns]
    out = data.loc[keep, present].reset_index(drop=True)
    for name in _ID_COLUMNS:
        if name not in out.columns:
            out[name] = pd.NA
    return out


def _flag_sums(data: pd.DataFrame, checks: pd.DataFrame) -> list[pd.DataFrame]:
    out = []
    for _, check in checks.iterrows():
        total = check["total"]
        parts = check["parts"]
        if isinstance(parts, str):
            parts = parts.split(";")
        parts = [p for p in parts if p in data.columns]
        if total not in data.columns or not parts:
            continue

        block = data[parts].apply(pd.to_numeric, errors="coerce")
        n_reported = block.notna().sum(axis=1)
        observed = block.sum(axis=1, min_count=1)
        threshold = pd.to_numeric(data[total], errors="coerce")

        keep = (observed.notna() & threshold.notna() & (observed > threshold)).to_numpy()
        if not keep.any():
            continue

        res = _ids(data, keep)
        res["check"] = check["check"]
        res["kind"] = "sum"
        res["concept"] = total
        res["observed"] = observed[keep].to_numpy(dtype="float64")
        res["threshold"] = threshold[keep].to_numpy(dtype="float64")
        res["excess"] = res["observed"] - res["threshold"]
        res["n_parts_reported"] = n_reported[keep].to_numpy(dtype="int64")
        res["note"] = check["note"]
        out.append(res)
    return out


def _flag_swings(
    data: pd.DataFrame, swing_factor: float, swing_floor: float
) -> list[pd.DataFrame]:
    if "fips_code" not in data.columns or data["year"].nunique() < 2:
        return []

    concepts = [
        c
        for c in data.columns
        if c not in ("year", "survey") and pd.api.types.is_numeric_dtype(data[c])
    ]
    years = sorted(data["year"].dropna().unique())
    out = []

    for previous, current in zip(years, years[1:]):
        now = data[data["year"] == current].reset_index(drop=True)
        before = data[data["year"] == previous]
        lookup = before.drop_duplicates("fips_code").set_index("fips_code")

        for concept in concepts:
            a = pd.to_numeric(now[concept], errors="coerce").astype("float64")
            b = pd.to_numeric(
                now["fips_code"].map(lookup[concept]), errors="coerce"
            ).astype("float64")
            both = a.notna() & b.notna() & (np.maximum(a, b) >= swing_floor)

            # A fall to zero is its own case, not an infinite fold-change: the
            # ratio would be Inf and would bury every finite swing under it.
            zeroed = (both & (b > 0) & (a == 0)).to_numpy()
            if zeroed.any():
                res = _ids(now, zeroed)
                res["check"] = "dropped_to_zero"
                res["kind"] = "swing"
                res["concept"] = concept
                res["observed"] = 0.0
                res["threshold"] = b[zeroed].to_numpy(dtype="float64")
                res["excess"] = res["threshold"]
                res["n_parts_reported"] = 1
                res["note"] = [
                    f"Reported {v:,.0f} in {previous} and zero here. A genuine zero "
                    "and a year the item went unreported both look like this, so "
                    "check the same row in missing_status() before treating it as "
                    "a change."
                    for v in res["threshold"]
                ]
                out.append(res)

            comparable = both & (b > 0) & (a > 0)
            ratio = (a / b).where(comparable)
            keep = (
                comparable & ((ratio > swing_factor) | (ratio < 1 / swing_factor))
            ).to_numpy()
            if not keep.any():
                continue

            res = _ids(now, keep)
            res["check"] = "year_over_year_swing"
            res["kind"] = "swing"
            res["concept"] = concept
            res["observed"] = a[keep].to_numpy(dtype="float64")
            res["threshold"] = b[keep].to_numpy(dtype="float64")
            folds = ratio[keep].to_numpy(dtype="float64")
            res["excess"] = np.maximum(folds, 1 / folds) - swing_factor
            res["n_parts_reported"] = 1
            res["note"] = [
                f"Changed {f:.1f}-fold against {previous}. Real shifts happen (a "
                "state moving to all-mail, a question changing scope), so check "
                "the concept's note in items() before reading this as a "
                "discrepancy."
                for f in folds
            ]
            out.append(res)
    return out
