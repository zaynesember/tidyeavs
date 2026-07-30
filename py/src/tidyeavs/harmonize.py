"""Renaming a survey year's raw codes to stable concept names."""

from __future__ import annotations

import pandas as pd

from ._dictionary import dict_for_year, resolve_year


def harmonize(
    data: pd.DataFrame,
    year: int | None = None,
    keep_unmatched: bool = False,
    dictionary: pd.DataFrame | None = None,
) -> pd.DataFrame:
    """Rename one year's raw variables to the concept names shared across years.

    Mail ballots rejected is ``C4a`` in 2020 and ``C9a`` in 2024; both become
    ``mail_rejected``. This is the step that makes years comparable, and it is
    what turns EAVS's renumbering between cycles from a trap into a non-issue.

    Only the curated concepts in the crosswalk are renamed. Other columns are
    dropped unless ``keep_unmatched=True``, which keeps them under their
    original names.

    ``data`` is typically the output of :func:`tidyeavs.recode_missing`, so item
    columns are already numeric. The year is taken from a ``year`` column when
    there is one, as :func:`tidyeavs.read` adds.
    """
    year = resolve_year(data, year)
    dict_year = dict_for_year(year, dictionary)

    matched = dict_year[dict_year["code"].isin(data.columns)]
    if matched.empty:
        raise ValueError(
            f"None of the columns match the {year} dictionary. "
            f"Is this really the {year} EAVS?"
        )

    renames = dict(zip(matched["code"], matched["concept"]))
    out = data.rename(columns=renames)

    lead = [name for name in ("year", "survey") if name in out.columns]
    ids = [c for c in matched.loc[matched["section"] == "id", "concept"]]
    concepts = [c for c in matched.loc[matched["section"] != "id", "concept"]]

    keep = lead + ids + concepts
    if keep_unmatched:
        keep += [name for name in out.columns if name not in keep]

    out = out[keep]
    if "year" not in out.columns:
        out = out.copy()
        out.insert(0, "year", year)
    return out.reset_index(drop=True)
