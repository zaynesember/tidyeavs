"""The one-step entry point: download, decode, harmonize, stack."""

from __future__ import annotations

import numbers
import warnings
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

    Loading more than one year emits a one-line reminder to run
    :func:`tidyeavs.flags` before publishing, because comparing cycles is where
    the survey's reporting changes do their damage and a panel gives no sign of
    them on its own. ``quiet=True`` silences it.

    A word of caution on aggregating the result: a jurisdiction that did not
    report an item is ``NA``, so a ``sum()`` with ``skipna=True`` silently covers
    only the jurisdictions that reported. When a large jurisdiction is
    missing—Cook County, Illinois is the recurring example—a state total can be
    badly off. :func:`tidyeavs.missing_status` is how you check coverage first.
    """
    # numbers.Integral covers numpy.int64, which pandas hands back and which
    # is not an int.
    wanted = [years] if isinstance(years, numbers.Integral) else list(years)
    frames = [
        harmonize(
            recode_missing(read(year, survey=survey, format=format, quiet=quiet)),
            year=year,
        )
        for year in wanted
    ]
    out = pd.concat(frames, ignore_index=True)

    # A cross-year panel looks perfectly ordinary while carrying reporting
    # changes nothing in it can show, and a user who never calls flags() gets no
    # signal at all. Once per multi-year load, not per year, and not on the
    # single-year case where the swing checks cannot run anyway.
    n_cycles = len(set(wanted))
    if not quiet and n_cycles > 1:
        warnings.warn(
            f"Spanning {n_cycles} cycles. Run tidyeavs.flags() on this panel "
            "before publishing from it.",
            stacklevel=2,
        )
    return out
