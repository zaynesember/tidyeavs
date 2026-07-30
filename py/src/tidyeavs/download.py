"""Downloading published EAVS files, verified against a pinned checksum."""

from __future__ import annotations

import functools
import hashlib
import os
import shutil
import ssl
import tempfile
import urllib.request
from pathlib import Path
from typing import Iterable

import pandas as pd

from . import _metadata
from ._constants import FORMATS, SURVEYS
from .cache import cache_path

_CHUNK = 1 << 20

# eac.gov answers urllib's default "Python-urllib/3.x" User-Agent with a 403, so
# identify the client honestly instead. R's curl is unaffected, which is why this
# only ever bit the Python side.
_USER_AGENT = "tidyeavs (+https://github.com/zaynesember/tidyeavs)"


@functools.lru_cache(maxsize=1)
def _ssl_context() -> ssl.SSLContext:
    """A TLS context with a trust store that actually exists.

    urllib verifies against OpenSSL's compiled-in CA paths, which on the
    python.org macOS builds point at a ``cert.pem`` that is only created once the
    bundled "Install Certificates.command" has been run. A library cannot assume
    a user has run it — the symptom is every download failing with
    CERTIFICATE_VERIFY_FAILED — so fall back to certifi's bundle when the default
    store is missing. A working system store is left alone, since on Linux it may
    carry CAs certifi does not.
    """
    paths = ssl.get_default_verify_paths()
    usable = (paths.cafile and os.path.exists(paths.cafile)) or (
        paths.capath and os.path.isdir(paths.capath)
    )
    if not usable:
        try:
            import certifi
        except ImportError:
            pass
        else:
            return ssl.create_default_context(cafile=certifi.where())
    return ssl.create_default_context()


def manifest_lookup(
    years: int | Iterable[int] | None = None,
    survey: str = "eavs",
    format: str = "csv",
) -> pd.DataFrame:
    """Filter the manifest to the requested files, sorted by year."""
    if survey not in SURVEYS:
        raise ValueError(f"survey must be one of {SURVEYS}; got {survey!r}")
    if format not in FORMATS:
        raise ValueError(f"format must be one of {FORMATS}; got {format!r}")

    man = _metadata.manifest()
    rows = man[(man["survey"] == survey) & (man["format"] == format)]
    if rows.empty:
        raise ValueError(f"No {format!r} files are recorded for the {survey!r} survey.")

    if years is not None:
        wanted = [years] if isinstance(years, int) else list(years)
        missing = sorted(set(wanted) - set(rows["year"].dropna().astype(int)))
        if missing:
            available = sorted(rows["year"].dropna().astype(int).unique())
            raise ValueError(
                f"No {survey} {format} file for year(s) {missing}. "
                f"Available: {available}."
            )
        rows = rows[rows["year"].isin(wanted)]

    return rows.sort_values("year").reset_index(drop=True)


def file_sha256(path: str | Path) -> str:
    """SHA-256 of a file on disk, read in chunks."""
    digest = hashlib.sha256()
    with open(path, "rb") as fh:
        for block in iter(lambda: fh.read(_CHUNK), b""):
            digest.update(block)
    return digest.hexdigest()


def download(
    years: int | Iterable[int] | None = None,
    survey: str = "eavs",
    format: str = "csv",
    overwrite: bool = False,
    quiet: bool = False,
) -> pd.DataFrame:
    """Fetch EAVS data files into the local cache.

    Files come from the tidyeavs data mirror when the manifest records one, and
    otherwise straight from the EAC. Every download is verified against the
    manifest's SHA-256, and a cached copy whose checksum already matches is
    reused, so a given file is fetched once.

    A checksum mismatch is an error rather than a warning. It means the file at
    that URL is not the version this release pins, which in practice means the
    EAC has published a revision and the manifest needs updating.

    Returns one row per file with ``year``, ``survey``, ``format``, ``path``,
    and ``status`` (``"reused"`` or ``"downloaded"``).
    """
    rows = manifest_lookup(years, survey=survey, format=format)
    return pd.DataFrame(
        [_download_one(row, overwrite=overwrite, quiet=quiet) for _, row in rows.iterrows()],
        columns=["year", "survey", "format", "path", "status"],
    )


def _download_one(row: pd.Series, overwrite: bool, quiet: bool) -> dict:
    path = cache_path(row["file_name"])
    expected = row["sha256"] if pd.notna(row["sha256"]) else None

    def result(status: str) -> dict:
        return {
            "year": int(row["year"]),
            "survey": row["survey"],
            "format": row["format"],
            "path": str(path),
            "status": status,
        }

    if not overwrite and path.is_file() and _checksum_ok(path, expected):
        return result("reused")

    urls = [
        url
        for url in (row.get("mirror_url"), row.get("source_url"))
        if isinstance(url, str) and url
    ]
    if not urls:
        raise ValueError(f"No download URL is recorded for {row['file_name']!r}.")

    if not quiet:
        print(f"Downloading {row['survey']} {int(row['year'])} ({row['format']})")

    errors = []
    for url in urls:
        with tempfile.NamedTemporaryFile(delete=False, suffix=Path(row["file_name"]).suffix) as tmp:
            tmp_path = Path(tmp.name)
        try:
            request = urllib.request.Request(url, headers={"User-Agent": _USER_AGENT})
            with urllib.request.urlopen(
                request, context=_ssl_context()
            ) as response, tmp_path.open("wb") as out:
                shutil.copyfileobj(response, out, _CHUNK)
        except Exception as exc:  # noqa: BLE001 - report and try the next URL
            errors.append(f"{url}: {exc}")
            tmp_path.unlink(missing_ok=True)
            continue

        if expected is not None and file_sha256(tmp_path) != expected:
            errors.append(f"checksum mismatch from {url}")
            tmp_path.unlink(missing_ok=True)
            continue

        path.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(tmp_path), path)
        return result("downloaded")

    raise RuntimeError(
        f"Could not download {row['file_name']!r}:\n  " + "\n  ".join(errors)
    )


def _checksum_ok(path: Path, expected: str | None) -> bool:
    return True if expected is None else file_sha256(path) == expected
