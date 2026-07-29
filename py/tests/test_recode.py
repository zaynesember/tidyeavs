"""Sentinel decoding and item-column detection.

These mirror r/tests/testthat/test-recode.R. Network-free.
"""

from __future__ import annotations

import pandas as pd

import tidyeavs
from tidyeavs.recode import is_item_column, strip_code_label


def test_modern_sentinels_become_na():
    df = pd.DataFrame(
        {"FIPSCode": ["01001", "01003", "01005"], "A1a": ["1200", "-99", "-88"]}
    )
    out = tidyeavs.recode_missing(df)
    assert out["A1a"].tolist()[0] == 1200
    assert out["A1a"].isna().tolist() == [False, True, True]


def test_2016_sentinels_become_na():
    df = pd.DataFrame({"A1a": ["1200", "-888888", "-999999", "-999998"]})
    out = tidyeavs.recode_missing(df)
    assert out["A1a"].isna().tolist() == [False, True, True, True]


def test_status_keeps_the_reason():
    df = pd.DataFrame({"A1a": ["1200", "-99", "-88", "-77", "-12345", "", "-999999"]})
    status = tidyeavs.missing_status(df)["A1a"].astype(str).tolist()
    assert status == [
        "reported",
        "not_available",
        "does_not_apply",
        "valid_skip",
        "other_missing",
        "blank",
        "not_available",
    ]


def test_2016_code_label_form_is_decoded():
    """2016 writes sentinels as "CODE: Label" rather than a bare number."""
    df = pd.DataFrame({"A1a": ["1200", "-999999: Data Not Available"]})
    out = tidyeavs.recode_missing(df)
    status = tidyeavs.missing_status(df)["A1a"].astype(str).tolist()
    assert out["A1a"].isna().tolist() == [False, True]
    assert status == ["reported", "not_available"]


def test_strip_code_label_leaves_plain_values_alone():
    values = pd.Series(["1200", "-99", "-999999: Data Not Available", None], dtype="string")
    assert strip_code_label(values).tolist()[:3] == ["1200", "-99", "-999999"]


def test_identifier_columns_are_left_alone():
    df = pd.DataFrame(
        {
            "FIPSCode": ["01001", "01003"],
            "Jurisdiction_Name": ["AUTAUGA COUNTY", "BALDWIN COUNTY"],
            "State_Abbr": ["AL", "AL"],
            "A1a": ["1200", "-99"],
        }
    )
    out = tidyeavs.recode_missing(df)
    # Leading zeros intact, names untouched, only the item column converted.
    assert out["FIPSCode"].tolist() == ["01001", "01003"]
    assert out["Jurisdiction_Name"].tolist() == ["AUTAUGA COUNTY", "BALDWIN COUNTY"]
    assert pd.api.types.is_numeric_dtype(out["A1a"])


def test_numeric_looking_fips_is_still_not_an_item():
    """A FIPS column of all digits must not be treated as a count."""
    assert not is_item_column(pd.Series(["1001", "1003"], dtype="string"), "FIPSCode")
    assert not is_item_column(pd.Series(["1", "2"], dtype="string"), "State_FIPS")


def test_text_column_is_not_an_item():
    assert not is_item_column(
        pd.Series(["some free text", "more text"], dtype="string"), "D6Comments"
    )


def test_mixed_column_is_not_an_item():
    assert not is_item_column(pd.Series(["12", "not a number"], dtype="string"), "A1a")


def test_text_placeholders_count_as_missing():
    df = pd.DataFrame({"A1a": ["1200", "Data Not Available", "N/A", "does not apply"]})
    assert is_item_column(df["A1a"].astype("string"), "A1a")
    status = tidyeavs.missing_status(df)["A1a"].astype(str).tolist()
    assert status == ["reported", "not_available", "not_available", "does_not_apply"]


def test_all_blank_column_is_not_an_item():
    assert not is_item_column(pd.Series(["", ""], dtype="string"), "A1a")


def test_status_categories_are_ordered_consistently():
    df = pd.DataFrame({"A1a": ["1", "-99"]})
    status = tidyeavs.missing_status(df)["A1a"]
    assert list(status.cat.categories) == [
        "reported",
        "does_not_apply",
        "not_available",
        "valid_skip",
        "other_missing",
        "blank",
    ]
