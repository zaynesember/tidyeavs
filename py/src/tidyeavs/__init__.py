"""tidyeavs: a tidy interface to the EAC's Election Administration and Voting Survey.

Downloads published EAVS files, decodes their missing-value codes, and
harmonizes variable names across survey years so jurisdictions line up over
time. It does not change the values jurisdictions reported.

This is a parallel implementation of the R package in the same repository, not a
binding to it. Both read the same crosswalk and file catalog from ``metadata/``,
so a corrected variable code cannot land in one language and be missed in the
other.

One-shot::

    import tidyeavs

    panel = tidyeavs.load([2022, 2024])

Or the steps, if you want the intermediate stages::

    raw = tidyeavs.read(2024)              # as published, all text
    decoded = tidyeavs.recode_missing(raw)  # sentinels -> NA
    tidy = tidyeavs.harmonize(decoded)      # raw codes -> concept names
"""

from __future__ import annotations

from ._aggregate import aggregate
from ._dictionary import items
from ._flags import flags
from ._metadata import (
    checks,
    dictionary,
    jurisdictions,
    manifest,
    metadata_dir,
    set_metadata_dir,
)
from .cache import cache_clear, cache_dir, cache_list, set_cache_dir
from .download import download
from .harmonize import harmonize
from .load import load
from .read import read
from .recode import missing_status, recode_missing

__version__ = "0.0.1.dev0"

__all__ = [
    "__version__",
    # one-shot
    "load",
    # steps
    "download",
    "read",
    "recode_missing",
    "missing_status",
    "harmonize",
    "aggregate",
    "flags",
    "items",
    # shared metadata
    "dictionary",
    "checks",
    "manifest",
    "jurisdictions",
    "metadata_dir",
    "set_metadata_dir",
    # cache
    "cache_dir",
    "cache_list",
    "cache_clear",
    "set_cache_dir",
]
