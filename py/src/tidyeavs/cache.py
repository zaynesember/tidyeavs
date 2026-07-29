"""Where tidyeavs stores downloaded data."""

from __future__ import annotations

import os
import shutil
import sys
from pathlib import Path

import pandas as pd

_override: Path | None = None


def set_cache_dir(path: str | os.PathLike[str] | None) -> None:
    """Set the cache directory for this session.

    The Python analogue of R's ``options(tidyeavs.cache_dir = ...)``. Pass
    ``None`` to restore the default lookup.
    """
    global _override
    _override = None if path is None else Path(path)


def cache_dir(create: bool = True) -> Path:
    """Return the directory downloaded EAVS files are kept in.

    Resolved in this order: an explicit :func:`set_cache_dir`, the
    ``TIDYEAVS_CACHE_DIR`` environment variable, then the per-user cache
    directory for the platform.

    The R package honours ``TIDYEAVS_CACHE_DIR`` too, so setting it in both
    gives one shared cache and a file downloaded from either language is reused
    by the other. The platform defaults deliberately differ, since R resolves
    its own via ``tools::R_user_dir()``.
    """
    if _override is not None:
        path = _override
    else:
        env = os.environ.get("TIDYEAVS_CACHE_DIR", "")
        path = Path(env) if env else _platform_cache_dir()

    if create:
        path.mkdir(parents=True, exist_ok=True)
    return path


def _platform_cache_dir() -> Path:
    if sys.platform == "darwin":
        return Path.home() / "Library" / "Caches" / "tidyeavs"
    if os.name == "nt":
        base = os.environ.get("LOCALAPPDATA") or (Path.home() / "AppData" / "Local")
        return Path(base) / "tidyeavs" / "Cache"
    xdg = os.environ.get("XDG_CACHE_HOME", "")
    return (Path(xdg) if xdg else Path.home() / ".cache") / "tidyeavs"


def cache_list() -> pd.DataFrame:
    """List cached files, with one row per file.

    Columns are ``file`` (the name, relative to the cache directory), ``bytes``,
    and ``modified``. Zero rows if the cache is empty or absent.
    """
    root = cache_dir(create=False)
    rows = []
    if root.is_dir():
        for path in sorted(root.rglob("*")):
            if path.is_file():
                stat = path.stat()
                rows.append(
                    {
                        "file": str(path.relative_to(root)),
                        "bytes": stat.st_size,
                        "modified": pd.Timestamp(stat.st_mtime, unit="s"),
                    }
                )
    return pd.DataFrame(rows, columns=["file", "bytes", "modified"])


def cache_clear(files: list[str] | None = None) -> list[str]:
    """Delete files from the cache and return the names removed.

    ``files`` names entries as :func:`cache_list` reports them; ``None`` (the
    default) removes everything. Unlike the R function there is no interactive
    confirmation, since Python callers are usually scripts. Nothing outside the
    cache directory is touched.
    """
    root = cache_dir(create=False)
    if not root.is_dir():
        return []

    names = list(cache_list()["file"]) if files is None else list(files)
    removed = []
    for name in names:
        target = (root / name).resolve()
        # Refuse a name that escapes the cache directory.
        if root.resolve() not in target.parents:
            raise ValueError(f"{name!r} is outside the cache directory")
        if target.is_dir():
            shutil.rmtree(target)
            removed.append(name)
        elif target.exists():
            target.unlink()
            removed.append(name)
    return removed


def cache_path(file_name: str) -> Path:
    """Full path to a named file in the cache. Does not check existence."""
    return cache_dir(create=True) / file_name
