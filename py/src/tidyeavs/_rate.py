"""Rates computed over jurisdictions reporting both sides.

Mirrors ``r/R/rate.R``. Named ``_rate`` so the module does not shadow the
``rate()`` function in the package namespace, the same trap ``_dictionary``
avoids.
"""

from __future__ import annotations

import pandas as pd

from ._aggregate import _entity_type, _group_keys


def rate(
    data: pd.DataFrame,
    numerator: str,
    denominator: str,
    by: str = "state",
    jurisdictions: pd.DataFrame | None = None,
) -> pd.DataFrame:
    """Divide one concept by another over the jurisdictions reporting both.

    This is how the EAC's own published rates are computed, and the restriction
    matters more than it sounds. In 2024 all 67 Alabama counties report
    ``uocava_counted`` and none report ``uocava_returned``, so summing each
    column over every row and dividing gives 112%; on the jurisdictions
    reporting both it is 96.4%, the figure the EAC publishes. States often
    report one side of a pair and not the other, and which pairs are affected
    changes from cycle to cycle.

    It also has to happen here rather than afterwards. Once numerator and
    denominator have been summed separately there is no way to tell which
    jurisdictions were in both, so a defensible rate cannot be recovered from
    :func:`tidyeavs.aggregate` output. Pass the panel.

    **Reading the output.** ``rate`` is ``num_value / den_value``, a ratio of
    sums rather than an average of per-jurisdiction ratios. Check two columns
    before quoting it: ``n_both``, the jurisdictions behind it, and
    ``den_share``, how much of the group's reported denominator they hold. A
    rate resting on 4% of a state's returned ballots prints exactly like one
    resting on 96%. ``n_num_only`` and ``n_den_only`` count the jurisdictions
    that reported only one side, so Alabama above appears as
    ``n_num_only = 67`` rather than as an inflated rate.

    To pool groups, sum ``num_value`` and ``den_value``; averaging ``rate``
    would weight a small county like a large one. The same call gives the EAC's
    voting-mode shares, e.g.
    ``rate(panel, "partic_in_person_ed", "partic_total")``.

    Nothing is corrected here: the restriction selects rows and counts what it
    left out. It cannot see values a state reported under an unusual
    convention, which is what :func:`tidyeavs.flags` is for. ``rate`` is
    missing when the common-subset denominator is zero.
    """
    if by not in ("state", "county"):
        raise ValueError(f"by must be 'state' or 'county'; got {by!r}")
    if "year" not in data.columns:
        raise ValueError("data needs a 'year' column; use tidyeavs.load().")
    for name in (numerator, denominator):
        if (
            not isinstance(name, str)
            or name not in data.columns
            or not pd.api.types.is_numeric_dtype(data[name])
        ):
            raise ValueError(
                f"{name!r} is not a numeric concept column in data. "
                "See items() for the shipped concept names."
            )
    if numerator == denominator:
        raise ValueError("numerator and denominator must differ.")

    keys, keep = _group_keys(data, by, jurisdictions)
    work = keys[keep].copy()
    num = pd.to_numeric(data[numerator][keep], errors="coerce")
    den = pd.to_numeric(data[denominator][keep], errors="coerce")
    both = num.notna() & den.notna()

    work["_num_both"] = num.where(both, 0.0).astype("float64").to_numpy()
    work["_den_both"] = den.where(both, 0.0).astype("float64").to_numpy()
    work["_den_all"] = den.fillna(0.0).astype("float64").to_numpy()
    work["_both"] = both.astype(int).to_numpy()
    work["_num_only"] = (num.notna() & den.isna()).astype(int).to_numpy()
    work["_den_only"] = (num.isna() & den.notna()).astype(int).to_numpy()

    group_cols = list(keys.columns)
    out = (
        work.groupby(group_cols, dropna=False, sort=True)
        .agg(
            num_value=("_num_both", "sum"),
            den_value=("_den_both", "sum"),
            n_both=("_both", "sum"),
            n_num_only=("_num_only", "sum"),
            n_den_only=("_den_only", "sum"),
            _den_all=("_den_all", "sum"),
        )
        .reset_index()
    )

    out["entity_type"] = _entity_type(out["state_abbr"])
    out["numerator"] = numerator
    out["denominator"] = denominator
    out["rate"] = (out["num_value"] / out["den_value"]).where(out["den_value"] > 0)
    out["den_share"] = (out["den_value"] / out["_den_all"]).where(out["_den_all"] > 0)

    lead = ["year"] + [c for c in group_cols if c != "year"]
    out = out[
        lead
        + [
            "entity_type",
            "numerator",
            "denominator",
            "num_value",
            "den_value",
            "rate",
            "n_both",
            "n_num_only",
            "n_den_only",
            "den_share",
        ]
    ]
    return out.sort_values(lead, kind="mergesort").reset_index(drop=True)
