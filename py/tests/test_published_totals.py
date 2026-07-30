"""Check tidyeavs against the totals the EAC publishes in its own reports.

This is the strongest external validation available: the figures in
``metadata/reference_totals.csv`` are quoted from the EAC's Comprehensive Report
with page provenance, so they are the agency's own numbers rather than anything
derived here. If the sentinel decoding leaked a -99 into a sum, or a concept were
mapped to the wrong year's code, these would move.

The report states figures as bounds ("over 158 million", "more than 96%"), so the
assertions are bounds too, which is what the source actually supports.

**Rate denominators are restricted to jurisdictions reporting both sides.** This
is not a refinement, it is the difference between right and wrong. Summing
``uocava_counted`` over every row and dividing by ``uocava_returned`` over every
row gives 112% for 2024, because all 67 Alabama counties report the numerator and
none report the denominator. On the common subset it is 96.4%, matching the
report. The same convention reproduces the report's Election Day share exactly.

Needs a populated cache, so skipped otherwise; see test_integration.py.
"""

from __future__ import annotations

import pandas as pd
import pytest

import tidyeavs
from tidyeavs.cache import cache_dir
from tidyeavs.download import manifest_lookup


def _reference() -> pd.DataFrame:
    return pd.read_csv(tidyeavs.metadata_dir() / "reference_totals.csv")


def _years_needed() -> list[int]:
    return sorted(_reference()["year"].unique())


def _cached(year: int) -> bool:
    root = cache_dir(create=False)
    if not root.is_dir():
        return False
    return (root / manifest_lookup(year).iloc[0]["file_name"]).is_file()


@pytest.fixture(scope="module")
def panels():
    years = _years_needed()
    missing = [y for y in years if not _cached(y)]
    if missing:
        pytest.skip(f"needs the {missing} file(s) cached")
    return {y: tidyeavs.load([y], quiet=True) for y in years}


def _pair_rate(panel: pd.DataFrame, numerator: str, denominator: str) -> float:
    """A rate over only the jurisdictions that reported both sides."""
    both = panel[numerator].notna() & panel[denominator].notna()
    return 100 * panel.loc[both, numerator].sum() / panel.loc[both, denominator].sum()


def _mode_share(panel: pd.DataFrame, mode: str) -> float:
    """A voting-mode share of total participation, among jurisdictions reporting
    that mode. This is the convention the EAC's own figures follow."""
    reported = panel[mode].notna()
    return 100 * panel.loc[reported, mode].sum() / panel.loc[reported, "partic_total"].sum()


# metric name -> how to compute it from one year's panel.
METRICS = {
    "partic_total": lambda p: p["partic_total"].sum(),
    "reg_active": lambda p: p["reg_active"].sum(),
    "reg_forms_received": lambda p: p["reg_forms_received"].sum(),
    "reg_confirmations_sent": lambda p: p["reg_confirmations_sent"].sum(),
    "reg_removed_total": lambda p: p["reg_removed_total"].sum(),
    "poll_workers_total": lambda p: p["poll_workers_total"].sum(),
    "uocava_transmitted": lambda p: p["uocava_transmitted"].sum(),
    "fwab_returned": lambda p: p["fwab_returned"].sum(),
    "fwab_counted": lambda p: p["fwab_counted"].sum(),
    "uocava_returned_rate": lambda p: _pair_rate(p, "uocava_returned", "uocava_transmitted"),
    "uocava_counted_rate": lambda p: _pair_rate(p, "uocava_counted", "uocava_returned"),
    "uocava_rejected_rate": lambda p: _pair_rate(p, "uocava_rejected", "uocava_returned"),
    "partic_in_person_ed_share": lambda p: _mode_share(p, "partic_in_person_ed"),
    "reg_new_valid_share": lambda p: _pair_rate(p, "reg_new_valid", "reg_forms_received"),
}


def test_every_reference_figure_has_an_implementation():
    """A citation with no way to check it would sit in the file doing nothing."""
    unimplemented = sorted(set(_reference()["metric"]) - set(METRICS))
    assert not unimplemented, f"reference_totals.csv metrics with no implementation: {unimplemented}"


@pytest.mark.parametrize(
    "row",
    [row for _, row in _reference().iterrows()],
    ids=lambda row: f"{row['year']}-{row['metric']}-{row['relation']}{row['value']:g}",
)
def test_matches_published_figure(panels, row):
    panel = panels[row["year"]]
    got = METRICS[row["metric"]](panel)
    expected = row["value"]

    if row["relation"] == "gt":
        assert got > expected, (
            f"{row['metric']} = {got:,.2f}, expected > {expected:,.2f}. "
            f"Source: {row['source']} — {row['note']}"
        )
    elif row["relation"] == "lt":
        assert got < expected, (
            f"{row['metric']} = {got:,.2f}, expected < {expected:,.2f}. "
            f"Source: {row['source']} — {row['note']}"
        )
    else:
        raise AssertionError(f"unknown relation {row['relation']!r}")


def test_naive_rate_denominators_are_wrong_and_this_is_why():
    """Guards the denominator convention itself, not just the result.

    Alabama 2024 reports uocava_counted for all 67 counties and uocava_returned
    for none, so a rate taken over all rows exceeds 100%. If someone "simplifies"
    _pair_rate to a plain ratio of column sums, this fails loudly.
    """
    if not _cached(2024):
        pytest.skip("needs the 2024 file cached")
    p = tidyeavs.load([2024], quiet=True)

    naive = 100 * p["uocava_counted"].sum() / p["uocava_returned"].sum()
    correct = _pair_rate(p, "uocava_counted", "uocava_returned")
    assert naive > 100, "expected the naive denominator to be visibly wrong"
    assert 96 < correct < 97

    alabama = p[p["state_abbr"] == "AL"]
    assert alabama["uocava_counted"].notna().all()
    assert alabama["uocava_returned"].isna().all()
