"""A safe left join for EAVS frames.

Mirrors ``r/R/join.R``. Named ``_join`` so the module does not shadow the
``join()`` function in the package namespace, the same trap ``_dictionary``
and ``_rate`` avoid.
"""

from __future__ import annotations

import warnings
from typing import Any

import pandas as pd

from . import _metadata

_DEFAULT = object()


def join(
    x: pd.DataFrame,
    y: Any = _DEFAULT,
    by: Any = None,
    multiple: str = "error",
    unmatched: str = "inform",
) -> pd.DataFrame:
    """Attach a table to an EAVS frame without fanning out or dropping rows.

    A left join that keeps every row of ``x`` and adds columns from ``y``,
    guarding the two ways a join on EAVS identifiers goes wrong on its own. A
    code shared by two published rows matches both and multiplies ``x``'s rows,
    inflating any sum taken afterward; a row with no match in ``y`` disappears.
    ``pandas.merge`` does the first silently, so this reports each before it
    reaches a total.

    The fan-out is Wisconsin's: three town/village pairs share one serial code
    (``82575`` and ``84275`` in 2020, ``31550`` in 2022), so joining a panel to
    :func:`tidyeavs.jurisdictions` on ``fips_code`` alone turns four rows into
    eight and overstates the state's 2020 ``partic_total`` by 0.35%. ``join``
    stops and names the shared codes; adding ``jurisdiction_name`` to ``by``
    matches the pairs exactly, since the town and village differ only in name.
    The drop is Maine's: its UOCAVA totals sit in a statewide row carrying no
    county FIPS, so a county-keyed join loses them. ``join`` counts the
    unmatched rows rather than letting them vanish.

    Columns already in ``x`` are kept from ``x``; ``join`` adds only ``y``'s new
    columns, so attaching :func:`tidyeavs.jurisdictions` to a panel brings in
    the county FIPS, structural type, and quirk flags without duplicating the
    identifiers the panel already carries.

    Nothing is corrected here: a shared code and a statewide row are how the
    jurisdictions reported, and the join reports them rather than resolving them.

    Parameters
    ----------
    x
        The frame to keep every row of: a panel from :func:`tidyeavs.load`, one
        harmonized year, or any frame carrying the join columns.
    y
        The frame to attach. Defaults to :func:`tidyeavs.jurisdictions`, the
        common case of adding structural type, county FIPS, and quirk flags to a
        panel.
    by
        Column name or list of columns to join on. Defaults to whichever of
        ``"year"`` and ``"fips_code"`` are in both frames.
    multiple
        What to do when a key matches several rows in ``y`` and so fans out
        ``x``. ``"error"`` (default) stops and names the shared keys; ``"all"``
        performs the expansion.
    unmatched
        What to do with rows of ``x`` that match nothing in ``y``. ``"inform"``
        (default) and ``"warn"`` both raise a warning (Python has no separate
        message channel); ``"error"`` stops; ``"ignore"`` says nothing. The rows
        are kept either way, with NA in ``y``'s columns.

    Returns
    -------
    pandas.DataFrame
        ``x`` with ``y``'s new columns attached, one row per row of ``x`` unless
        ``multiple="all"`` expands a shared code.
    """
    if y is _DEFAULT:
        y = _metadata.jurisdictions()

    if by is None:
        by = [c for c in ("year", "fips_code") if c in x.columns and c in y.columns]
        if not by:
            raise ValueError(
                "No columns to join on: x and y share neither 'year' nor "
                "'fips_code'. Pass by= explicitly."
            )
    by = [by] if isinstance(by, str) else list(by)

    missing_x = [c for c in by if c not in x.columns]
    missing_y = [c for c in by if c not in y.columns]
    if missing_x or missing_y:
        parts = []
        if missing_x:
            parts.append(f"missing from x: {missing_x}")
        if missing_y:
            parts.append(f"missing from y: {missing_y}")
        raise ValueError(
            "by names columns that are not in both frames (" + "; ".join(parts) + ")."
        )

    x_key = _key(x, by)
    y_key = _key(y, by)

    # Fan-out: a key appearing more than once in y multiplies x's matching rows.
    dup_keys = set(y_key[y_key.duplicated(keep=False)])
    offending = sorted(dup_keys & set(x_key))
    if offending and multiple == "error":
        codes = [_display(k, by) for k in offending[:5]]
        more = " (first 5 shown)" if len(offending) > 5 else ""
        msg = (
            f"Joining on {by} would fan out x: {len(offending)} key(s) match "
            f"more than one row in y.\n"
            f"  Shared: {codes}{more}."
        )
        can_disambiguate = (
            "jurisdiction_name" in x.columns
            and "jurisdiction_name" in y.columns
            and "jurisdiction_name" not in by
        )
        if can_disambiguate:
            msg += (
                "\n  These are distinct jurisdictions sharing one published code "
                "(Wisconsin town/village pairs). Add 'jurisdiction_name' to by "
                "to match them exactly."
            )
        msg += "\n  Or pass multiple='all' to keep the fanned-out rows."
        raise ValueError(msg)

    # Silent drop: a row of x matching nothing in y.
    unmatched_mask = ~x_key.isin(set(y_key))
    n_unmatched = int(unmatched_mask.sum())
    if n_unmatched and unmatched != "ignore":
        if "state_abbr" in x.columns:
            states = sorted(x.loc[unmatched_mask, "state_abbr"].dropna().unique())
            shown = states[:6]
            extra = " and more" if len(states) > len(shown) else ""
            where = f" Unmatched rows are in {shown}{extra}."
        else:
            codes = sorted({_display(k, by) for k in x_key[unmatched_mask]})[:6]
            where = f" Unmatched codes: {codes}."
        msg = (
            f"{n_unmatched} row(s) of x matched nothing in y; their y columns "
            f"are NA.{where}"
        )
        if unmatched == "error":
            raise ValueError(msg)
        warnings.warn(msg, stacklevel=2)

    # Add only y's new columns, so identifiers the panel already carries are not
    # duplicated into an _x / _y pair.
    overlap = [c for c in y.columns if c in x.columns and c not in by]
    if overlap:
        y = y.drop(columns=overlap)

    return x.merge(y, on=by, how="left").reset_index(drop=True)


def _key(df: pd.DataFrame, by: list[str]) -> pd.Series:
    """One comparable key per row. \\r cannot occur in a FIPS code or name, so it
    separates columns without colliding with content."""
    return df[by].astype(str).agg("\r".join, axis=1)


def _display(key: str, by: list[str]) -> str:
    """The fips_code alone when it is a join column, else the whole key with +."""
    parts = key.split("\r")
    if "fips_code" in by:
        return parts[by.index("fips_code")]
    return "+".join(parts)
