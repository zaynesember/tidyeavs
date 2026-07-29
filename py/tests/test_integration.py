"""End-to-end checks against the real published files.

These need the actual EAVS data, so they are skipped unless a populated cache is
available. Point TIDYEAVS_CACHE_DIR at one (the R package's cache works, since
both use the same file names) or let a prior download fill the default location:

    TIDYEAVS_CACHE_DIR=~/Library/Caches/org.R-project.R/R/tidyeavs pytest

The numbers asserted here are properties of the published record, not of this
package, which is what makes them worth pinning: if a refactor breaks the
sentinel decoding or the harmonization, a rate moves and one of these fails.
"""

from __future__ import annotations

import pytest

import tidyeavs
from tidyeavs.cache import cache_dir
from tidyeavs.download import manifest_lookup

PUBLISHED_ROWS = {2016: 6467, 2018: 6460, 2020: 6460, 2022: 6460, 2024: 6461}
YEARS = sorted(PUBLISHED_ROWS)


def _cached_years() -> list[int]:
    root = cache_dir(create=False)
    if not root.is_dir():
        return []
    years = []
    for year in YEARS:
        name = manifest_lookup(year).iloc[0]["file_name"]
        if (root / name).is_file():
            years.append(year)
    return years


@pytest.fixture(scope="module")
def panel():
    years = _cached_years()
    if len(years) < len(YEARS):
        pytest.skip(
            f"needs all {len(YEARS)} survey years cached; found {years or 'none'}"
        )
    return tidyeavs.load(years, quiet=True)


def test_row_counts_match_the_published_files(panel):
    assert panel.groupby("year").size().to_dict() == PUBLISHED_ROWS


def test_fips_codes_keep_their_leading_zeros(panel):
    assert (panel["fips_code"] == "0100100000").any()  # Autauga County, Alabama
    assert (panel["fips_code"] == "0200000000").any()  # Alaska, one statewide row


def test_mail_rejection_rate_is_plausible(panel):
    """Roughly 0.8-1.5% across these cycles. A sentinel leaking in blows this up."""
    for year, group in panel.groupby("year"):
        rate = group["mail_rejected"].sum() / group["mail_returned"].sum()
        assert 0.005 < rate < 0.02, f"{year} mail rejection rate was {rate:.3%}"


def test_no_negative_values_survive_recoding(panel):
    """Every EAVS item is a count or a rate, so a negative means a missed sentinel."""
    numeric = panel.select_dtypes(include=["number", "Float64", "Int64"])
    for column in numeric.columns:
        if column == "year":
            continue
        smallest = numeric[column].min()
        assert smallest is None or not (smallest < 0), f"{column} has {smallest}"


def test_drop_boxes_appear_only_from_2022(panel):
    reported = panel.groupby("year")["drop_boxes_total"].count().to_dict()
    assert reported[2016] == 0
    assert reported[2018] == 0
    assert reported[2020] == 0
    assert reported[2022] > 1000
    assert reported[2024] > 1000


def test_uocava_rejection_rate_is_plausible(panel):
    """The B18a/B24a trap: getting it wrong makes this rate absurd."""
    for year, group in panel.groupby("year"):
        total = group["uocava_returned"].sum()
        if total:
            rate = group["uocava_rejected"].sum() / total
            assert 0.005 < rate < 0.12, f"{year} UOCAVA rejection rate was {rate:.3%}"


def test_2016_is_not_valid_utf8_and_still_reads():
    """The encoding fallback is load-bearing for 2016 specifically.

    Of the five cycles only 2016 is Windows-1252, and what makes it fail a UTF-8
    read is curly quotes in the question-label and comment text rather than any
    accented place name. Reading it must succeed and leave that text intact.
    """
    if 2016 not in _cached_years():
        pytest.skip("needs the 2016 file cached")

    from tidyeavs.read import detect_encoding

    name = manifest_lookup(2016).iloc[0]["file_name"]
    archive = cache_dir(create=False) / name
    extracted = next((archive.parent / f"{name}-extracted").rglob("*.csv"))
    data = extracted.read_bytes()

    with pytest.raises(UnicodeDecodeError):
        data.decode("utf-8")
    assert detect_encoding(data) == "cp1252"
    assert "“vote history”" in data.decode("cp1252")


def test_accented_place_name_survives_in_2018(panel):
    """2018 is the one cycle that spells Doña Ana with its tilde."""
    names = panel.loc[panel["year"] == 2018, "jurisdiction_name"].dropna()
    assert names.str.contains("DOñA ANA", case=False).any()
