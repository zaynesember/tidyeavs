"""Loading the shared metadata in ``metadata/`` at the repo root.

This is the module that makes the Python package a parallel implementation
rather than a second source of truth. The file catalog, the cross-year variable
crosswalk, and the jurisdiction table are read from the same committed CSVs the
R package builds its datasets from, so a corrected variable code cannot land in
one language and be missed in the other.

Every read goes through ``schema.json``. That is not ceremony: pandas reads
Alaska's ``0200000000`` as the integer ``200000000`` and turns ``county_fips``
into a float, so letting pandas guess would silently destroy the leading zeros
this package exists to preserve.
"""

from __future__ import annotations

import functools
import json
import os
from pathlib import Path

import pandas as pd

_SECTIONS = ("id", "A", "B", "C", "D", "E", "F")

# schema.json type name -> pandas dtype. Dates are read as strings and parsed
# afterwards, so a malformed date is visible rather than silently coerced.
_DTYPES = {
    "string": "string",
    "integer": "Int64",
    "number": "Float64",
    "boolean": "boolean",
    "date": "string",
}

_override: Path | None = None


def set_metadata_dir(path: str | os.PathLike[str] | None) -> None:
    """Point the package at a different ``metadata/`` directory.

    Mainly for tests and for working against an extended crosswalk. Pass
    ``None`` to restore the default lookup.
    """
    global _override
    _override = None if path is None else Path(path)
    _clear_caches()


def metadata_dir() -> Path:
    """Locate the shared metadata directory.

    Resolved in this order: an explicit :func:`set_metadata_dir`, the
    ``TIDYEAVS_METADATA_DIR`` environment variable, a copy packaged inside the
    installed distribution, then a ``metadata/`` directory in an enclosing
    source tree (the case when running from a checkout).
    """
    if _override is not None:
        return _override

    env = os.environ.get("TIDYEAVS_METADATA_DIR", "")
    if env:
        return Path(env)

    packaged = Path(__file__).parent / "metadata"
    if (packaged / "schema.json").is_file():
        return packaged

    for parent in Path(__file__).resolve().parents:
        candidate = parent / "metadata"
        if (candidate / "schema.json").is_file():
            return candidate

    raise FileNotFoundError(
        "Could not find the tidyeavs metadata directory. Set "
        "TIDYEAVS_METADATA_DIR, or call tidyeavs.set_metadata_dir()."
    )


@functools.lru_cache(maxsize=1)
def schema() -> dict[str, dict[str, str]]:
    """The declared column types for every metadata CSV."""
    with (metadata_dir() / "schema.json").open(encoding="utf-8") as fh:
        return json.load(fh)["files"]


def read_metadata_csv(name: str) -> pd.DataFrame:
    """Read one metadata CSV with its declared types.

    Use this rather than :func:`pandas.read_csv` for anything in
    ``metadata/``; see the module docstring for what type guessing costs here.
    """
    types = schema().get(name)
    if types is None:
        raise KeyError(f"{name} is not described in schema.json")

    frame = pd.read_csv(
        metadata_dir() / name,
        dtype={col: _DTYPES[kind] for col, kind in types.items()},
        keep_default_na=True,
        na_values=[""],
    )
    for col, kind in types.items():
        if kind == "date":
            frame[col] = pd.to_datetime(frame[col], format="%Y-%m-%d").dt.date
    return frame


@functools.lru_cache(maxsize=1)
def manifest() -> pd.DataFrame:
    """The catalog of downloadable EAVS files, one row per file."""
    return read_metadata_csv("manifest.csv")


@functools.lru_cache(maxsize=1)
def jurisdictions() -> pd.DataFrame:
    """Every published jurisdiction row per year, with quirk flags."""
    return read_metadata_csv("jurisdictions.csv")


@functools.lru_cache(maxsize=1)
def dictionary() -> pd.DataFrame:
    """The cross-year variable crosswalk, one row per concept per year.

    Built by joining ``concepts.csv`` to ``crosswalk.csv`` and keeping the
    concepts flagged ``shipped``, which is the same join
    ``r/data-raw/dictionary.R`` performs to write ``eavs_dictionary.rda``. The
    result is column-for-column and row-for-row identical to the R dataset.
    """
    concepts = read_metadata_csv("concepts.csv")
    crosswalk = read_metadata_csv("crosswalk.csv")

    shipped = concepts[concepts["shipped"].fillna(False).astype(bool)]
    merged = shipped[["concept", "concept_label", "section", "epi_name"]].merge(
        crosswalk[["concept", "year", "code", "codebook_label", "confidence", "note"]],
        on="concept",
        how="inner",
    )
    merged = merged[
        [
            "concept",
            "concept_label",
            "section",
            "year",
            "code",
            "codebook_label",
            "epi_name",
            "note",
            "confidence",
        ]
    ]

    # Sort to match the R dataset: year, then section in survey order, then
    # concept alphabetically.
    order = pd.Categorical(merged["section"], categories=_SECTIONS, ordered=True)
    merged = (
        merged.assign(_section_order=order)
        .sort_values(["year", "_section_order", "concept"], kind="mergesort")
        .drop(columns="_section_order")
        .reset_index(drop=True)
    )
    return merged


def _clear_caches() -> None:
    for fn in (schema, manifest, jurisdictions, dictionary):
        fn.cache_clear()
