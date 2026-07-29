"""Cache location, listing, and clearing. Network-free."""

from __future__ import annotations

import pytest

import tidyeavs
from tidyeavs.cache import cache_path
from tidyeavs.download import manifest_lookup
from tidyeavs.read import detect_encoding


@pytest.fixture(autouse=True)
def isolated_cache(tmp_path, monkeypatch):
    monkeypatch.delenv("TIDYEAVS_CACHE_DIR", raising=False)
    tidyeavs.set_cache_dir(tmp_path / "cache")
    yield
    tidyeavs.set_cache_dir(None)


def test_set_cache_dir_wins():
    assert tidyeavs.cache_dir(create=False).name == "cache"


def test_env_var_is_used_when_no_override(tmp_path, monkeypatch):
    tidyeavs.set_cache_dir(None)
    monkeypatch.setenv("TIDYEAVS_CACHE_DIR", str(tmp_path / "from_env"))
    assert tidyeavs.cache_dir(create=False) == tmp_path / "from_env"


def test_cache_dir_creates_on_request():
    assert not tidyeavs.cache_dir(create=False).exists()
    assert tidyeavs.cache_dir(create=True).is_dir()


def test_empty_cache_lists_no_rows():
    listing = tidyeavs.cache_list()
    assert listing.empty
    assert list(listing.columns) == ["file", "bytes", "modified"]


def test_list_and_clear_round_trip():
    path = cache_path("example.csv")
    path.write_text("a,b\n1,2\n", encoding="utf-8")

    listing = tidyeavs.cache_list()
    assert listing["file"].tolist() == ["example.csv"]
    assert listing["bytes"].item() > 0

    assert tidyeavs.cache_clear() == ["example.csv"]
    assert tidyeavs.cache_list().empty


def test_clear_named_file_only():
    cache_path("keep.csv").write_text("x", encoding="utf-8")
    cache_path("drop.csv").write_text("x", encoding="utf-8")
    assert tidyeavs.cache_clear(["drop.csv"]) == ["drop.csv"]
    assert tidyeavs.cache_list()["file"].tolist() == ["keep.csv"]


def test_clear_refuses_to_escape_the_cache_dir():
    cache_path("real.csv").write_text("x", encoding="utf-8")  # so the cache exists
    with pytest.raises(ValueError, match="outside the cache"):
        tidyeavs.cache_clear(["../../etc/passwd"])
    assert tidyeavs.cache_list()["file"].tolist() == ["real.csv"]


def test_clear_on_an_absent_cache_is_a_no_op():
    assert not tidyeavs.cache_dir(create=False).exists()
    assert tidyeavs.cache_clear() == []


def test_manifest_lookup_rejects_an_unavailable_year():
    with pytest.raises(ValueError, match="No eavs csv file for year"):
        manifest_lookup(1999)


def test_manifest_lookup_rejects_a_bad_survey():
    with pytest.raises(ValueError, match="survey must be one of"):
        manifest_lookup(2024, survey="nonsense")


def test_manifest_lookup_returns_years_in_order():
    rows = manifest_lookup([2024, 2016])
    assert rows["year"].tolist() == [2016, 2024]


def test_encoding_detection():
    assert detect_encoding("Autauga County".encode("utf-8")) == "utf-8"
    assert detect_encoding("Doña Ana".encode("utf-8")) == "utf-8"
    # Windows-1252 bytes for the same name are not valid UTF-8.
    assert detect_encoding("Doña Ana".encode("cp1252")) == "cp1252"
