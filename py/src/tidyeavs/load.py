"""The one-step entry point: download, decode, harmonize, stack."""

from __future__ import annotations

from typing import Iterable

import pandas as pd

from .harmonize import harmonize
from .read import read
from .recode import recode_missing


def load(
    years: int | Iterable[int],
    survey: str = "eavs",
    format: str = "csv",
    quiet: bool = False,
) -> pd.DataFrame:
    """Load a tidy, harmonized EAVS panel.

    Downloads the requested survey years, decodes their missing-value codes, and
    harmonizes variable names so the years stack into one jurisdiction-year
    panel. Equivalent to running :func:`tidyeavs.read`,
    :func:`tidyeavs.recode_missing`, and :func:`tidyeavs.harmonize` for each year
    and concatenating.

    The first call for a year downloads a few megabytes and caches it; later
    calls read from the cache.

    A word of caution on aggregating the result: a jurisdiction that did not
    report an item is ``NA``, so a ``sum()`` with ``skipna=True`` silently covers
    only the jurisdictions that reported. When a large jurisdiction is missing —
    Cook County, Illinois is the recurring example — a state total can be badly
    off. :func:`tidyeavs.missing_status` is how you check coverage first.
    """
    wanted = [years] if isinstance(years, int) else list(years)
    frames = [
        harmonize(
            recode_missing(read(year, survey=survey, format=format, quiet=quiet)),
            year=year,
        )
        for year in wanted
    ]
    return pd.concat(frames, ignore_index=True)
