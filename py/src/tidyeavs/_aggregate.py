"""Quirk-aware rollups to state or county, with honest coverage.

Mirrors ``r/R/aggregate.R``. Named ``_aggregate`` rather than ``aggregate`` so the
module does not shadow the ``aggregate()`` function in the package namespace, the
same trap ``_dictionary`` avoids.
"""

from __future__ import annotations

import warnings
from typing import Iterable

import pandas as pd

from . import _metadata

_ID_COLUMNS = (
    "year",
    "survey",
    "fips_code",
    "jurisdiction_name",
    "state_abbr",
    "state_name",
    "state_fips",
    "county_fips",
)

# EAVS distinguishes why a value is absent, and the distinction decides whether a
# total is untrustworthy or perfectly complete. "Does not apply" and a valid skip
# mean the item did not pertain, so nothing is missing.
_NOT_APPLICABLE = ("does_not_apply", "valid_skip")


def aggregate(
    data: pd.DataFrame,
    status: pd.DataFrame | None = None,
    by: str = "state",
    concepts: Iterable[str] | None = None,
    jurisdictions: pd.DataFrame | None = None,
) -> pd.DataFrame:
    """Sum a harmonized panel to one row per group per concept.

    EAVS totals are only as good as the jurisdictions behind them, so this reports
    how many stood behind each number rather than leaving you to assume all of
    them did. The output is long — one row per ``year``, group, and ``concept`` —
    because a wide frame carrying a value plus three counts for each of ~35
    concepts is unusable. Pivot it yourself if you want concepts as columns.

    **Coverage.** Pass ``status`` (a :func:`tidyeavs.missing_status` frame put
    through :func:`tidyeavs.harmonize`) and the counts distinguish *why* a
    jurisdiction is absent, which matters more than it sounds. In 2024, 1,000
    jurisdictions reported no provisional ballots at all, so counting them as gaps
    drops apparent coverage of ``prov_rejected`` from 94.5% to 79.9% when nothing
    is actually missing. Three buckets:

    - ``n_reported`` — gave a number, and so are in ``value``.
    - ``n_missing`` — genuine gaps: ``not_available``, ``other_missing``,
      ``blank``. These are what make a total untrustworthy.
    - ``n_not_applicable`` — ``does_not_apply`` and ``valid_skip``. Excluded from
      the ``coverage`` denominator, since nothing is missing.

    ``coverage`` is ``n_reported / (n_reported + n_missing)``: the share of
    jurisdictions that *could* have answered and did. Without ``status`` the
    reason is unknowable after recoding, so every absence lands in ``n_missing``
    and ``coverage`` is a lower bound; ``coverage_exact`` says which you have.

    **Nothing is corrected.** Values are summed as reported, with ``NA`` skipped
    and never imputed, so a "does not apply" does not become a zero. Maine's
    statewide UOCAVA row and the territories are included, since both carry real
    reported data — in 2024 no Maine county reports UOCAVA at all, so dropping
    that row would lose the state's only figures. Filter afterwards if your
    analysis wants that; :func:`tidyeavs.jurisdictions` types every row.

    ``by="county"`` drops rows whose published code embeds no county — Wisconsin's
    non-geographic serials, Maine's statewide row, Alaska, the territories — and
    says how many.
    """
    if by not in ("state", "county"):
        raise ValueError(f"by must be 'state' or 'county'; got {by!r}")
    if "year" not in data.columns:
        raise ValueError("data needs a 'year' column; use tidyeavs.load().")
    if status is not None and len(status) != len(data):
        raise ValueError(
            f"status must line up row-for-row with data: data has {len(data)} rows, "
            f"status has {len(status)}. Harmonize both from the same read()."
        )

    items = _item_columns(data, concepts)
    keys, keep = _group_keys(data, by, jurisdictions)

    frames = [
        _aggregate_one(
            concept,
            data[concept],
            status[concept] if (status is not None and concept in status.columns) else None,
            keys,
            keep,
        )
        for concept in items
    ]
    out = pd.concat(frames, ignore_index=True)

    lead = ["year"] + [c for c in keys.columns if c != "year"]
    out = out[
        lead
        + [
            "concept",
            "value",
            "n_reported",
            "n_missing",
            "n_not_applicable",
            "n_total",
            "coverage",
            "coverage_exact",
        ]
    ]
    return out.sort_values(["year", "concept"] + [c for c in lead if c != "year"],
                          kind="mergesort").reset_index(drop=True)


def _item_columns(data: pd.DataFrame, concepts: Iterable[str] | None) -> list[str]:
    candidates = [c for c in data.columns if c not in _ID_COLUMNS]
    items = [c for c in candidates if pd.api.types.is_numeric_dtype(data[c])]

    if concepts is not None:
        wanted = list(concepts)
        unknown = [c for c in wanted if c not in items]
        if unknown:
            raise ValueError(
                f"Not numeric concept column(s) in data: {unknown}. Available: {items}."
            )
        items = wanted
    if not items:
        raise ValueError(
            "No numeric concept columns found in data. Did you forget "
            "recode_missing() before harmonizing?"
        )
    return items


def _group_keys(
    data: pd.DataFrame, by: str, jurisdictions: pd.DataFrame | None
) -> tuple[pd.DataFrame, pd.Series]:
    if "state_abbr" not in data.columns:
        raise ValueError("data needs a 'state_abbr' column to group by.")

    keys = pd.DataFrame(
        {"year": data["year"].to_numpy(), "state_abbr": data["state_abbr"].to_numpy()},
        index=data.index,
    )
    if by == "state":
        return keys, pd.Series(True, index=data.index)

    if "fips_code" not in data.columns:
        raise ValueError("A county rollup needs a 'fips_code' column in data.")
    jur = _metadata.jurisdictions() if jurisdictions is None else jurisdictions

    lookup = jur.set_index(
        [jur["year"].astype("Int64"), jur["fips_code"].astype("string")]
    )["county_fips"]
    probe = pd.MultiIndex.from_arrays(
        [data["year"].astype("Int64"), data["fips_code"].astype("string")]
    )
    keys["county_fips"] = lookup.reindex(probe).to_numpy()

    keep = keys["county_fips"].notna()
    dropped = int((~keep).sum())
    if dropped:
        warnings.warn(
            f"Dropping {dropped} row(s) with no county in the published code: "
            "Wisconsin's non-geographic serials, Maine's statewide row, Alaska, "
            "and the territories have none.",
            stacklevel=3,
        )
    return keys, keep


def _aggregate_one(
    concept: str,
    value: pd.Series,
    reason: pd.Series | None,
    keys: pd.DataFrame,
    keep: pd.Series,
) -> pd.DataFrame:
    exact = reason is not None
    work = keys[keep].copy()
    values = pd.to_numeric(value[keep], errors="coerce")

    if exact:
        labels = reason[keep].astype("string")
        reported = labels == "reported"
        not_applicable = labels.isin(_NOT_APPLICABLE)
    else:
        # After recoding the reason is gone, so every absence counts as a gap.
        reported = values.notna()
        not_applicable = pd.Series(False, index=values.index)

    work["_value"] = values.astype("float64")
    work["_reported"] = reported.fillna(False).astype(int).to_numpy()
    work["_na"] = not_applicable.fillna(False).astype(int).to_numpy()
    work["_gap"] = (1 - work["_reported"] - work["_na"]).clip(lower=0)

    group_cols = list(keys.columns)
    grouped = work.groupby(group_cols, dropna=False, sort=True)
    out = grouped.agg(
        value=("_value", "sum"),
        n_reported=("_reported", "sum"),
        n_missing=("_gap", "sum"),
        n_not_applicable=("_na", "sum"),
        n_total=("_value", "size"),
    ).reset_index()

    out["concept"] = concept
    answerable = out["n_reported"] + out["n_missing"]
    out["coverage"] = (out["n_reported"] / answerable).where(answerable > 0)
    out["coverage_exact"] = exact
    return out
