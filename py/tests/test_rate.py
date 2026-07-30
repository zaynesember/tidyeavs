"""Rates over jurisdictions reporting both sides.

Mirrors r/tests/testthat/test-rate.R. The AL rows model the Alabama pattern: a
jurisdiction reporting the numerator without the denominator must leave the
rate untouched. Network-free.
"""

from __future__ import annotations

import pandas as pd
import pytest

import tidyeavs


def rate_panel() -> pd.DataFrame:
    return pd.DataFrame(
        {
            "year": [2024] * 4,
            "fips_code": ["0100100000", "0100300000", "2300100000", "2300300000"],
            "state_abbr": ["AL", "AL", "ME", "ME"],
            "mail_rejected": [10.0, 20.0, 5.0, None],
            "mail_returned": [100.0, None, 50.0, 50.0],
        }
    )


def row(out, state):
    return out[out["state_abbr"] == state].iloc[0]


def test_rate_is_computed_over_the_common_subset():
    out = tidyeavs.rate(rate_panel(), "mail_rejected", "mail_returned")
    al = row(out, "AL")
    assert al["rate"] == 0.1  # 10/100; the 20 with no denominator is out
    assert al["num_value"] == 10
    assert al["den_value"] == 100
    assert al["n_both"] == 1
    assert al["n_num_only"] == 1
    assert al["n_den_only"] == 0


def test_den_share_says_how_much_the_restriction_kept():
    out = tidyeavs.rate(rate_panel(), "mail_rejected", "mail_returned")
    assert row(out, "AL")["den_share"] == 1.0
    me = row(out, "ME")
    assert me["n_den_only"] == 1
    assert me["den_share"] == 0.5  # 50 of 100 reported returns
    assert me["rate"] == 0.1


def test_zero_or_empty_denominator_gives_na_not_inf():
    p = rate_panel()
    p["mail_returned"] = [0.0, None, None, None]
    out = tidyeavs.rate(p, "mail_rejected", "mail_returned")
    assert out["rate"].isna().all()
    assert row(out, "AL")["n_both"] == 1
    me = row(out, "ME")
    assert me["n_both"] == 0
    assert pd.isna(me["den_share"])


def test_entity_type_carried_and_years_separate():
    p = pd.concat([rate_panel(), rate_panel().assign(year=2022)], ignore_index=True)
    p.loc[p["state_abbr"] == "ME", "state_abbr"] = "PR"
    out = tidyeavs.rate(p, "mail_rejected", "mail_returned")
    assert len(out) == 4  # 2 years x 2 groups
    assert set(out.loc[out["state_abbr"] == "PR", "entity_type"]) == {"territory"}


def test_bad_columns_are_an_error():
    with pytest.raises(ValueError, match="not a numeric concept"):
        tidyeavs.rate(rate_panel(), "nope", "mail_returned")
    with pytest.raises(ValueError, match="not a numeric concept"):
        tidyeavs.rate(rate_panel(), "fips_code", "mail_returned")
    with pytest.raises(ValueError, match="must differ"):
        tidyeavs.rate(rate_panel(), "mail_rejected", "mail_rejected")
    with pytest.raises(ValueError, match="needs a 'year' column"):
        tidyeavs.rate(
            rate_panel().drop(columns="year"), "mail_rejected", "mail_returned"
        )


def test_county_rollup_drops_codes_with_no_county():
    jur = pd.DataFrame(
        {
            "year": pd.array([2024] * 4, dtype="Int64"),
            "fips_code": pd.array(
                ["0100100000", "0100300000", "2300100000", "2300300000"],
                dtype="string",
            ),
            "county_fips": pd.array(["01001", "01003", "23001", None], dtype="string"),
        }
    )
    with pytest.warns(UserWarning, match="Dropping 1 row"):
        out = tidyeavs.rate(
            rate_panel(), "mail_rejected", "mail_returned", by="county",
            jurisdictions=jur,
        )
    assert "county_fips" in out.columns
    assert len(out) == 3
