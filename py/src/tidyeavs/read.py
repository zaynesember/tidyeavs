"""Reading one survey year as published, every column as text."""

from __future__ import annotations

import zipfile
from pathlib import Path

import pandas as pd

from ._constants import FORMATS, SURVEYS
from .cache import cache_path
from .download import download, manifest_lookup


def read(
    year: int,
    survey: str = "eavs",
    format: str = "csv",
    download_if_missing: bool = True,
    quiet: bool = False,
) -> pd.DataFrame:
    """Read a single survey year of EAVS data from the cache.

    Downloads the file first if it is not already cached. The data come back as
    published, with every column read as text. Reading everything as text is
    what keeps FIPS codes' leading zeros and the survey's missing-value codes
    intact instead of guessing types on the way in.

    Use :func:`tidyeavs.recode_missing` to turn item columns into numbers, or
    :func:`tidyeavs.load` for a harmonized panel across years.

    Returns a DataFrame with ``year`` and ``survey`` inserted as the first two
    columns; every other column is a pandas ``string``.
    """
    if survey not in SURVEYS:
        raise ValueError(f"survey must be one of {SURVEYS}; got {survey!r}")
    if format not in FORMATS:
        raise ValueError(f"format must be one of {FORMATS}; got {format!r}")

    if download_if_missing:
        path = Path(download(year, survey=survey, format=format, quiet=quiet)["path"][0])
    else:
        row = manifest_lookup(year, survey=survey, format=format).iloc[0]
        path = cache_path(row["file_name"])
        if not path.is_file():
            raise FileNotFoundError(
                f"{survey} {year} ({format}) is not in the cache. "
                "Call again with download_if_missing=True to fetch it."
            )

    frame = _read_csv(path) if format == "csv" else _read_xlsx(path)
    frame.insert(0, "survey", survey)
    frame.insert(0, "year", year)
    return frame


def _read_csv(path: Path) -> pd.DataFrame:
    if path.suffix.lower() == ".zip":
        path = _extract_member(path, ".csv")
    data = path.read_bytes()
    return pd.read_csv(
        path,
        dtype="string",
        encoding=detect_encoding(data),
        keep_default_na=True,
        na_values=[""],
        low_memory=False,
    )


def _read_xlsx(path: Path, sheet: int = 0) -> pd.DataFrame:
    if path.suffix.lower() == ".zip":
        path = _extract_member(path, ".xlsx")
    return pd.read_excel(path, sheet_name=sheet, dtype="string")


def detect_encoding(data: bytes) -> str:
    """Guess a published EAVS file's encoding from its bytes.

    Some EAVS CSVs are Windows-1252, being Excel and SPSS exports, so a naive
    UTF-8 read fails outright on them. Of the 2016-2024 cycles only 2016 is,
    where the offending bytes are curly quotes in the question-label and comment
    text. Use UTF-8 when the bytes are valid UTF-8 and fall back to Windows-1252
    otherwise, matching ``r/R/read.R``.
    """
    try:
        data.decode("utf-8")
    except UnicodeDecodeError:
        return "cp1252"
    return "utf-8"


def _extract_member(zip_path: Path, suffix: str) -> Path:
    """Extract the largest member with ``suffix`` beside the archive.

    A previous extraction is reused. EAVS zips occasionally carry a small
    readme or codebook alongside the data, so the largest match is the one
    wanted rather than the first.
    """
    with zipfile.ZipFile(zip_path) as archive:
        hits = [
            info
            for info in archive.infolist()
            if info.filename.lower().endswith(suffix) and not info.is_dir()
        ]
        if not hits:
            raise FileNotFoundError(f"No {suffix} file inside {zip_path.name}.")
        member = max(hits, key=lambda info: info.file_size)

        out_dir = zip_path.with_name(zip_path.name + "-extracted")
        out = out_dir / member.filename
        if not out.is_file():
            archive.extract(member, path=out_dir)
    return out
