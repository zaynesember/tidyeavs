"""Quirk-aware rollups to state or county, with honest coverage.

Mirrors ``r/R/aggregate.R``. Named ``_aggregate`` rather than ``aggregate`` so the
module does not shadow the ``aggregate()`` function in the package namespace, the
same trap ``_dictionary`` avoids.
"""

from __future__ import annotations

import warnings
from typing import Any, Iterable

import numpy as np
import pandas as pd

from . import _metadata
from ._constants import TERRITORIES

# None means "skip the anomaly column", so a distinct sentinel is needed for
# "use the shipped table". Same pattern as _flags.py.
_DEFAULT = object()

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
    anomalies: Any = _DEFAULT,
) -> pd.DataFrame:
    """Sum a harmonized panel to one row per group per concept.

    Reports how many jurisdictions stood behind each number rather than leaving
    you to assume all of them did. The output is long, one row per ``year``,
    group, and ``concept``, because a wide frame carrying a value plus five
    counts for each of ~40 concepts is unusable.

    **Coverage.** Pass ``status`` (a :func:`tidyeavs.missing_status` frame put
    through :func:`tidyeavs.harmonize`) and the counts distinguish *why* a
    jurisdiction is absent. That distinction matters: in 2024 a thousand
    jurisdictions had no provisional ballots at all, so counting them as gaps
    drops apparent coverage of ``prov_rejected`` from 94.5% to 79.9% when
    nothing is missing. Five buckets, which sum to ``n_total``:

    - ``n_reported`` gave a number, and are in ``value``.
    - ``n_missing`` are the genuine gaps (``not_available``,
      ``other_missing``): the ones that make a total untrustworthy.
    - ``n_blank`` left the cell empty, which the file does not explain. A blank
      could be a gap or a skip, so it is counted separately and the call is
      yours. Most blanks are 2016 Maine, whose municipalities leave the UOCAVA
      items to the statewide row.
    - ``n_not_applicable`` said the item did not pertain (``does_not_apply``,
      ``valid_skip``), so nothing is missing.
    - ``n_not_collected`` were never asked, because the concept was not on that
      year's questionnaire.

    ``coverage`` is ``n_reported / (n_reported + n_missing + n_blank)``: the
    share of jurisdictions that could have answered and did. The last two
    buckets stay out of the denominator, since nothing is missing there.
    Without ``status`` the reason is unknowable after recoding, so every
    absence lands in ``n_missing`` and ``coverage`` is a lower bound;
    ``coverage_exact`` says which case you have.

    ``coverage_reg`` weights the same ratio by ``reg_eligible_total``,
    answering how much of the electorate the reporters hold rather than how
    many of them there were. Since ``value`` is a sum, that is usually the
    better guide to how much of it you have: in 2024 ``ballots_cured`` comes
    from 28.5% of jurisdictions but 65.9% of the registered electorate.
    Jurisdictions with no usable weight leave both sides of the ratio, and the
    column is missing if the panel carries no ``reg_eligible_total``.

    Every row also carries ``entity_type`` (``"state"``, ``"territory"``, or
    ``"district"``), so a 50-state analysis is one filter.

    **Anomalous state-years.** ``known_anomaly`` is ``True`` where this year,
    state, and concept are recorded in :func:`tidyeavs.known_anomalies` and at
    least one jurisdiction in the group reported a value, so the total rests on
    the anomalous convention. Coverage cannot tell you this: Iowa's 2018 polling
    places are reported by all 99 counties, so every coverage column reads as
    complete, and the state total is still not comparable to its other cycles.
    The value is summed as reported either way; :func:`tidyeavs.flags` gives the
    reason and the evidence. Pass ``anomalies=None`` to skip the column's
    lookup.

    **Nothing is corrected.** Values are summed as reported, and ``NA`` is
    skipped rather than imputed, so a "does not apply" never becomes a zero.
    Maine's statewide UOCAVA row and the territories are included, because both
    carry real reported data; filter them afterwards if your analysis wants
    that.

    ``by="county"`` drops rows whose published code embeds no county, and says
    how many: Wisconsin's serials, Maine's statewide row, Alaska, the
    territories. Wisconsin stays out even though
    :func:`tidyeavs.jurisdictions` parses its county names, because the ~57
    municipalities that straddle county lines include the City of Milwaukee.
    """
    if by not in ("state", "county"):
        raise ValueError(f"by must be 'state' or 'county'; got {by!r}")
    if "year" not in data.columns:
        raise ValueError("data needs a 'year' column; use tidyeavs.load().")
    if anomalies is _DEFAULT:
        anomalies = _metadata.known_anomalies()
    if status is not None:
        if len(status) != len(data):
            raise ValueError(
                f"status must line up row-for-row with data: data has {len(data)} rows, "
                f"status has {len(status)}. Harmonize both from the same read()."
            )
        # Matching row counts are not alignment: binding per-year status frames
        # in a different year order than the panel passes the count check and
        # then reports another year's coverage. Both frames carry the keys.
        for key in ("year", "fips_code"):
            if key in data.columns and key in status.columns:
                left = data[key].astype("string").to_numpy()
                right = status[key].astype("string").to_numpy()
                if not (left == right).all():
                    raise ValueError(
                        f"status is not aligned with data: their {key!r} columns "
                        "differ row-for-row. Bind the per-year status frames in "
                        "the same year order as load()."
                    )

    items = _item_columns(data, concepts)
    keys, keep = _group_keys(data, by, jurisdictions)
    # The coverage_reg weight, taken from the panel itself whether or not
    # reg_eligible_total is among the concepts being rolled up.
    weight = data["reg_eligible_total"] if "reg_eligible_total" in data.columns else None

    frames = [
        _aggregate_one(
            concept,
            data[concept],
            status[concept] if (status is not None and concept in status.columns) else None,
            keys,
            keep,
            weight,
        )
        for concept in items
    ]
    out = pd.concat(frames, ignore_index=True)
    out["entity_type"] = _entity_type(out["state_abbr"])
    # A total can rest on an anomalous reporting convention while every coverage
    # column reads as complete, so say so here rather than leaving it to a
    # separate flags() call the user has to know to make.
    out["known_anomaly"] = _anomaly_match(
        out["year"], out["state_abbr"], out["concept"], anomalies
    ) & (out["n_reported"] > 0).to_numpy()

    lead = ["year"] + [c for c in keys.columns if c != "year"]
    out = out[
        lead
        + [
            "entity_type",
            "concept",
            "value",
            "n_reported",
            "n_missing",
            "n_blank",
            "n_not_applicable",
            "n_not_collected",
            "n_total",
            "coverage",
            "coverage_reg",
            "coverage_exact",
            "known_anomaly",
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


def _entity_type(state_abbr: pd.Series) -> pd.Series:
    """Classify a state_abbr column as state, territory, or district (DC)."""
    out = pd.Series("state", index=state_abbr.index, dtype="object")
    out[state_abbr.isin(TERRITORIES)] = "territory"
    out[state_abbr == "DC"] = "district"
    return out


def _anomaly_match(year, state_abbr, concept, anomalies) -> np.ndarray:
    """Is this year/state/concept one of the verified reporting anomalies?

    Keyed the same three ways ``_flag_known_anomalies`` matches, since every
    anomaly recorded so far is a statewide convention for one concept in one
    cycle. ``concept`` may be a single name, recycled. Mirrors
    ``anomaly_match()`` in ``utils.R``.

    This is what lets :func:`rate` and :func:`aggregate` say that a number rests
    on an anomalous state-year, which no arithmetic check can tell you: Oregon's
    2018 mail rejection rate comes back with every county reporting and is still
    unusable. Reporting it is as far as this goes—the value is returned as
    summed, and what to do about it is the user's call.
    """
    years = list(pd.to_numeric(pd.Series(list(year)), errors="coerce").astype("Int64"))
    states = list(state_abbr)
    n = len(years)
    concepts = [concept] * n if isinstance(concept, str) else list(concept)

    if anomalies is None or len(anomalies) == 0:
        return np.zeros(n, dtype=bool)

    known = {
        f"{a_year} {a_state} {a_concept}"
        for a_year, a_state, a_concept in zip(
            pd.to_numeric(anomalies["year"], errors="coerce").astype("Int64"),
            anomalies["state_abbr"],
            anomalies["concept"],
        )
    }
    return np.array(
        [f"{y} {s} {c}" in known for y, s, c in zip(years, states, concepts)],
        dtype=bool,
    )


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
    # A few Wisconsin serials are shared by two published rows in one year, so
    # this index is not unique and reindex would refuse it. Both rows of a pair
    # carry the same county, so taking the first matches what R's match() does.
    lookup = lookup[~lookup.index.duplicated()]
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
    weight: pd.Series | None = None,
) -> pd.DataFrame:
    exact = reason is not None
    work = keys[keep].copy()
    values = pd.to_numeric(value[keep], errors="coerce")

    if exact:
        labels = reason[keep].astype("string")
        reported = labels == "reported"
        not_applicable = labels.isin(_NOT_APPLICABLE)
        # A blank is ambiguous—gap or skip, the file does not say—so it is
        # counted apart rather than folded into either. See the docstring.
        blank = labels == "blank"
        # No reason at all means the concept was not on that year's
        # questionnaire (a multi-year status bind fills those rows with NA),
        # which gets its own bucket so the five sum to n_total.
        not_collected = labels.isna()
    else:
        # After recoding the reason is gone, so every absence counts as a gap.
        reported = values.notna()
        not_applicable = pd.Series(False, index=values.index)
        blank = pd.Series(False, index=values.index)
        not_collected = pd.Series(False, index=values.index)

    work["_value"] = values.astype("float64")
    work["_reported"] = reported.fillna(False).astype(int).to_numpy()
    work["_na"] = not_applicable.fillna(False).astype(int).to_numpy()
    work["_blank"] = blank.fillna(False).astype(int).to_numpy()
    work["_nc"] = not_collected.astype(int).to_numpy()
    work["_gap"] = (
        1 - work["_reported"] - work["_na"] - work["_blank"] - work["_nc"]
    ).clip(lower=0)

    # Registration-weighted coverage: how much of the electorate the reporting
    # jurisdictions hold. Rows with no usable weight contribute to neither side.
    if weight is not None:
        w = pd.to_numeric(weight[keep], errors="coerce").fillna(0).astype("float64")
        work["_w_reported"] = w.to_numpy() * work["_reported"]
        work["_w_answerable"] = w.to_numpy() * (
            work["_reported"] + work["_gap"] + work["_blank"]
        )
    else:
        work["_w_reported"] = 0.0
        work["_w_answerable"] = 0.0

    group_cols = list(keys.columns)
    grouped = work.groupby(group_cols, dropna=False, sort=True)
    out = grouped.agg(
        value=("_value", "sum"),
        n_reported=("_reported", "sum"),
        n_missing=("_gap", "sum"),
        n_blank=("_blank", "sum"),
        n_not_applicable=("_na", "sum"),
        n_not_collected=("_nc", "sum"),
        n_total=("_value", "size"),
        _w_reported=("_w_reported", "sum"),
        _w_answerable=("_w_answerable", "sum"),
    ).reset_index()

    out["concept"] = concept
    answerable = out["n_reported"] + out["n_missing"] + out["n_blank"]
    out["coverage"] = (out["n_reported"] / answerable).where(answerable > 0)
    if weight is not None:
        out["coverage_reg"] = (out["_w_reported"] / out["_w_answerable"]).where(
            out["_w_answerable"] > 0
        )
    else:
        out["coverage_reg"] = float("nan")
    out = out.drop(columns=["_w_reported", "_w_answerable"])
    out["coverage_exact"] = exact
    return out
