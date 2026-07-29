"""Looking up EAVS variables and concepts."""

from __future__ import annotations

from typing import Iterable

import pandas as pd

from . import _metadata


def get_dictionary(dictionary: pd.DataFrame | None = None) -> pd.DataFrame:
    """The dictionary to use: the one supplied, or the shared crosswalk."""
    return _metadata.dictionary() if dictionary is None else dictionary


def items(
    query: str | None = None,
    year: int | Iterable[int] | None = None,
    section: str | Iterable[str] | None = None,
    dictionary: pd.DataFrame | None = None,
) -> pd.DataFrame:
    """Search the crosswalk that maps raw variable codes to concept names.

    Use it to answer "what is ``C9a``?", to find the code for a concept in a
    given year, or to see which years collected an item. ``query`` is matched
    case-insensitively against concept names, labels, raw codes, and EPI names.

    Because the mapping is explicit, the renumbering traps become visible rather
    than silent: ``items("uocava_rejected")`` shows the code is ``B24a`` in 2024
    but ``B18a`` in 2018 through 2022, and ``items("B18a")`` shows that ``B18a``
    in 2024 is a different item entirely.
    """
    frame = get_dictionary(dictionary)

    if year is not None:
        wanted = [year] if isinstance(year, int) else list(year)
        frame = frame[frame["year"].isin(wanted)]

    if section is not None:
        wanted_sections = [section] if isinstance(section, str) else list(section)
        lowered = [s.lower() for s in wanted_sections]
        frame = frame[frame["section"].str.lower().isin(lowered)]

    if query is not None:
        haystack = (
            frame[["concept", "concept_label", "codebook_label", "code", "epi_name"]]
            .fillna("")
            .agg(" ".join, axis=1)
            .str.lower()
        )
        frame = frame[haystack.str.contains(query.lower(), regex=False)]

    return frame.reset_index(drop=True)


def dict_for_year(
    year: int, dictionary: pd.DataFrame | None = None
) -> pd.DataFrame:
    """Dictionary rows for one year that have a code, i.e. were collected."""
    frame = get_dictionary(dictionary)
    rows = frame[(frame["year"] == year) & frame["code"].notna()]
    if rows.empty:
        raise ValueError(f"The dictionary has no entries for {year}.")
    return rows


def resolve_year(data: pd.DataFrame, year: int | None) -> int:
    """Work out which single survey year ``data`` is."""
    if year is not None:
        return int(year)
    if "year" in data.columns:
        unique = pd.unique(data["year"].dropna())
        if len(unique) == 1:
            return int(unique[0])
    raise ValueError(
        "Could not tell which survey year this data is. Pass year=, or include "
        "a single-valued 'year' column."
    )
