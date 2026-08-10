"""A safe left join for EAVS frames.

Mirrors r/tests/testthat/test-join.R. Fixtures model the two hazards by hand: a
Wisconsin town/village pair sharing one serial code (the fan-out) and a Maine
statewide row absent from y (the drop). Network-free.
"""

from __future__ import annotations

import warnings

import pandas as pd
import pytest

import tidyeavs


def join_panel() -> pd.DataFrame:
    return pd.DataFrame(
        {
            "year": [2020] * 4,
            "fips_code": ["82575", "82575", "55001000", "23"],
            "jurisdiction_name": [
                "TOWN OF ARBOR",
                "VILLAGE OF ARBOR",
                "COUNTY A",
                "MAINE UOCAVA",
            ],
            "state_abbr": ["WI", "WI", "WI", "ME"],
            "partic_total": [100.0, 50.0, 200.0, 7.0],
        }
    )


def join_jurisdictions() -> pd.DataFrame:
    return pd.DataFrame(
        {
            "year": [2020] * 3,
            "fips_code": ["82575", "82575", "55001000"],
            "jurisdiction_name": ["TOWN OF ARBOR", "VILLAGE OF ARBOR", "COUNTY A"],
            "state_abbr": ["WI", "WI", "WI"],
            "county_fips": [None, None, "55001"],
            "type": ["municipality", "municipality", "county"],
        }
    )


def test_shared_code_stops_the_join():
    with pytest.raises(ValueError, match="fan out"):
        tidyeavs.join(join_panel(), join_jurisdictions())


def test_fanout_message_points_at_jurisdiction_name():
    with pytest.raises(ValueError, match="jurisdiction_name"):
        tidyeavs.join(join_panel(), join_jurisdictions())


def test_disambiguating_resolves_the_pair_one_to_one():
    out = tidyeavs.join(
        join_panel(),
        join_jurisdictions(),
        by=["year", "fips_code", "jurisdiction_name"],
        unmatched="ignore",
    )
    assert len(out) == 4  # no fan-out
    town = out[out["jurisdiction_name"] == "TOWN OF ARBOR"].iloc[0]
    assert pd.isna(town["county_fips"])
    county = out[out["jurisdiction_name"] == "COUNTY A"].iloc[0]
    assert county["county_fips"] == "55001"


def test_multiple_all_keeps_the_expansion():
    out = tidyeavs.join(
        join_panel(),
        join_jurisdictions(),
        by=["year", "fips_code"],
        multiple="all",
        unmatched="ignore",
    )
    # 2 panel rows x 2 y rows for 82575 = 4, plus the county (1) and Maine (1).
    assert len(out) == 6


def test_unmatched_row_is_reported_but_kept():
    by = ["year", "fips_code", "jurisdiction_name"]
    with pytest.warns(UserWarning, match="matched nothing"):
        tidyeavs.join(join_panel(), join_jurisdictions(), by=by)
    with pytest.raises(ValueError, match="matched nothing"):
        tidyeavs.join(join_panel(), join_jurisdictions(), by=by, unmatched="error")
    out = tidyeavs.join(join_panel(), join_jurisdictions(), by=by, unmatched="ignore")
    maine = out[out["jurisdiction_name"] == "MAINE UOCAVA"]
    assert len(maine) == 1
    assert pd.isna(maine.iloc[0]["county_fips"])


def test_ignore_is_silent_and_inform_names_the_state():
    by = ["year", "fips_code", "jurisdiction_name"]
    with warnings.catch_warnings():
        warnings.simplefilter("error")  # any warning becomes an error
        tidyeavs.join(join_panel(), join_jurisdictions(), by=by, unmatched="ignore")
    with pytest.warns(UserWarning, match="ME"):
        tidyeavs.join(join_panel(), join_jurisdictions(), by=by)


def test_only_new_columns_are_added():
    out = tidyeavs.join(
        join_panel(),
        join_jurisdictions(),
        by=["year", "fips_code", "jurisdiction_name"],
        unmatched="ignore",
    )
    assert not any(c.endswith("_x") or c.endswith("_y") for c in out.columns)
    assert {"county_fips", "type"}.issubset(out.columns)
    assert list(out.columns).count("state_abbr") == 1  # kept from x, not doubled


def test_by_defaults_to_shared_year_and_fips_code():
    x = pd.DataFrame({"year": [2020], "fips_code": ["55001000"], "v": [1]})
    y = pd.DataFrame({"year": [2020], "fips_code": ["55001000"], "w": [2]})
    out = tidyeavs.join(x, y)
    assert out.iloc[0]["w"] == 2


def test_no_shared_key_columns_is_an_error():
    with pytest.raises(ValueError, match="No columns to join on"):
        tidyeavs.join(pd.DataFrame({"a": [1]}), pd.DataFrame({"b": [2]}))


def test_by_naming_a_missing_column_is_an_error():
    x = pd.DataFrame({"year": [2020], "fips_code": ["1"]})
    y = pd.DataFrame({"year": [2020], "fips_code": ["1"]})
    with pytest.raises(ValueError, match="not in both frames"):
        tidyeavs.join(x, y, by=["year", "nope"])
