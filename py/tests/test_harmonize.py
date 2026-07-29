"""Harmonizing raw codes to concept names, using a fixture crosswalk.

Mirrors r/tests/testthat/test-harmonize.R: the fixture keeps these tests
independent of the shipped metadata, so a crosswalk edit does not silently
change what they assert.
"""

from __future__ import annotations

import pandas as pd
import pytest

import tidyeavs
from tidyeavs.harmonize import harmonize


def fixture_dictionary() -> pd.DataFrame:
    rows = [
        # concept, label, section, year, code
        ("fips_code", "FIPS", "id", 2020, "FIPSCode"),
        ("fips_code", "FIPS", "id", 2024, "FIPSCode"),
        ("mail_rejected", "Mail rejected", "C", 2020, "C4a"),
        ("mail_rejected", "Mail rejected", "C", 2024, "C9a"),
        ("drop_boxes_total", "Drop boxes", "C", 2020, None),
        ("drop_boxes_total", "Drop boxes", "C", 2024, "C10a"),
    ]
    return pd.DataFrame(
        [
            {
                "concept": c,
                "concept_label": lab,
                "section": sec,
                "year": y,
                "code": code,
                "codebook_label": None,
                "epi_name": None,
                "note": None,
                "confidence": "high",
            }
            for c, lab, sec, y, code in rows
        ]
    )


def test_renames_the_year_specific_code():
    d = fixture_dictionary()
    y2020 = pd.DataFrame({"year": [2020], "FIPSCode": ["01001"], "C4a": [5]})
    y2024 = pd.DataFrame({"year": [2024], "FIPSCode": ["01001"], "C9a": [7]})

    out20 = harmonize(y2020, dictionary=d)
    out24 = harmonize(y2024, dictionary=d)

    assert "mail_rejected" in out20.columns
    assert "mail_rejected" in out24.columns
    assert out20["mail_rejected"].item() == 5
    assert out24["mail_rejected"].item() == 7


def test_years_stack_after_harmonizing():
    """The point of the exercise: C4a and C9a line up under one name."""
    d = fixture_dictionary()
    out = pd.concat(
        [
            harmonize(pd.DataFrame({"year": [2020], "FIPSCode": ["01001"], "C4a": [5]}), dictionary=d),
            harmonize(pd.DataFrame({"year": [2024], "FIPSCode": ["01001"], "C9a": [7]}), dictionary=d),
        ],
        ignore_index=True,
    )
    assert out["mail_rejected"].tolist() == [5, 7]
    assert out["year"].tolist() == [2020, 2024]


def test_identifiers_come_before_items():
    d = fixture_dictionary()
    out = harmonize(
        pd.DataFrame({"year": [2024], "C9a": [7], "FIPSCode": ["01001"]}), dictionary=d
    )
    assert list(out.columns) == ["year", "fips_code", "mail_rejected"]


def test_unmatched_columns_are_dropped_by_default():
    d = fixture_dictionary()
    data = pd.DataFrame({"year": [2024], "FIPSCode": ["01001"], "C9a": [7], "ZZ9": [1]})
    assert "ZZ9" not in harmonize(data, dictionary=d).columns
    assert "ZZ9" in harmonize(data, dictionary=d, keep_unmatched=True).columns


def test_a_concept_not_collected_that_year_is_absent():
    d = fixture_dictionary()
    out = harmonize(pd.DataFrame({"year": [2020], "FIPSCode": ["01001"], "C4a": [5]}), dictionary=d)
    assert "drop_boxes_total" not in out.columns


def test_year_can_be_passed_explicitly():
    d = fixture_dictionary()
    out = harmonize(pd.DataFrame({"FIPSCode": ["01001"], "C9a": [7]}), year=2024, dictionary=d)
    assert out["year"].item() == 2024


def test_ambiguous_year_is_an_error():
    d = fixture_dictionary()
    with pytest.raises(ValueError, match="which survey year"):
        harmonize(pd.DataFrame({"FIPSCode": ["01001"], "C9a": [7]}), dictionary=d)


def test_no_matching_columns_is_an_error():
    d = fixture_dictionary()
    with pytest.raises(ValueError, match="None of the columns"):
        harmonize(pd.DataFrame({"year": [2024], "nothing": [1]}), dictionary=d)


def test_harmonize_against_the_shipped_crosswalk():
    """A smoke test against the real metadata rather than the fixture."""
    data = pd.DataFrame({"year": [2024], "FIPSCode": ["01001"], "C9a": [7], "B24a": [3]})
    out = tidyeavs.harmonize(data)
    assert out["mail_rejected"].item() == 7
    assert out["uocava_rejected"].item() == 3
