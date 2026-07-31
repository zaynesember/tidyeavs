"""State and county rollups, and reason-aware coverage.

Mirrors r/tests/testthat/test-aggregate.R. Fixtures small enough to check every
count by hand. Network-free.
"""

from __future__ import annotations

import pandas as pd
import pytest

import tidyeavs

FIPS = ["0100100000", "0100300000", "2300100000", "23"]


def panel() -> pd.DataFrame:
    return pd.DataFrame(
        {
            "year": [2024] * 4,
            "fips_code": FIPS,
            "state_abbr": ["AL", "AL", "ME", "ME"],
            "mail_rejected": [10.0, 20.0, 5.0, None],
            "prov_rejected": [1.0, None, None, None],
        }
    )


def status() -> pd.DataFrame:
    return pd.DataFrame(
        {
            "year": [2024] * 4,
            "fips_code": FIPS,
            "state_abbr": ["AL", "AL", "ME", "ME"],
            "mail_rejected": ["reported", "reported", "reported", "not_available"],
            # AL: one reported, one genuine gap. ME: both inapplicable.
            "prov_rejected": ["reported", "not_available", "does_not_apply", "valid_skip"],
        }
    )


def cell(out, concept, state, column):
    row = out[(out["concept"] == concept) & (out["state_abbr"] == state)]
    return row[column].item()


def test_values_summed_per_state_and_output_is_long():
    out = tidyeavs.aggregate(panel())
    assert set(out["concept"]) == {"mail_rejected", "prov_rejected"}
    assert len(out) == 2 * 2
    assert cell(out, "mail_rejected", "AL", "value") == 30
    assert cell(out, "mail_rejected", "ME", "value") == 5


def test_state_total_equals_a_plain_sum():
    p = panel()
    out = tidyeavs.aggregate(p)
    assert out.loc[out["concept"] == "mail_rejected", "value"].sum() == p[
        "mail_rejected"
    ].sum()


def test_every_input_row_is_accounted_for():
    p = panel()
    out = tidyeavs.aggregate(p)
    assert out.loc[out["concept"] == "mail_rejected", "n_total"].sum() == len(p)


def test_without_status_every_absence_is_a_gap():
    out = tidyeavs.aggregate(panel())
    assert cell(out, "mail_rejected", "ME", "coverage_exact") is False or not cell(
        out, "mail_rejected", "ME", "coverage_exact"
    )
    assert cell(out, "mail_rejected", "ME", "n_reported") == 1
    assert cell(out, "mail_rejected", "ME", "n_missing") == 1
    assert cell(out, "mail_rejected", "ME", "n_not_applicable") == 0
    assert cell(out, "mail_rejected", "ME", "coverage") == 0.5


def test_does_not_apply_is_not_a_gap():
    out = tidyeavs.aggregate(panel(), status=status())
    assert bool(cell(out, "prov_rejected", "ME", "coverage_exact"))
    assert cell(out, "prov_rejected", "ME", "n_reported") == 0
    assert cell(out, "prov_rejected", "ME", "n_missing") == 0
    assert cell(out, "prov_rejected", "ME", "n_not_applicable") == 2
    assert pd.isna(cell(out, "prov_rejected", "ME", "coverage"))


def test_blanks_counted_apart_and_kept_in_coverage_denominator():
    st = status()
    st["mail_rejected"] = ["reported", "blank", "reported", "not_available"]
    out = tidyeavs.aggregate(panel(), status=st)
    assert cell(out, "mail_rejected", "AL", "n_reported") == 1
    assert cell(out, "mail_rejected", "AL", "n_missing") == 0
    assert cell(out, "mail_rejected", "AL", "n_blank") == 1
    # A blank counts as a gap in coverage, so the number reads as a lower bound.
    assert cell(out, "mail_rejected", "AL", "coverage") == 0.5


def test_entity_type_separates_states_territories_and_dc():
    p = panel()
    p["state_abbr"] = ["AL", "PR", "DC", "ME"]
    out = tidyeavs.aggregate(p)
    types = dict(zip(out["state_abbr"], out["entity_type"]))
    assert types["AL"] == "state"
    assert types["PR"] == "territory"
    assert types["DC"] == "district"


def test_not_applicable_excluded_from_coverage_denominator():
    out = tidyeavs.aggregate(panel(), status=status())
    assert cell(out, "prov_rejected", "AL", "n_reported") == 1
    assert cell(out, "prov_rejected", "AL", "n_missing") == 1
    assert cell(out, "prov_rejected", "AL", "coverage") == 0.5


def test_status_changes_coverage_but_never_the_value():
    without = tidyeavs.aggregate(panel())
    with_status = tidyeavs.aggregate(panel(), status=status())
    key = ["year", "state_abbr", "concept"]
    a = without.sort_values(key).reset_index(drop=True)
    b = with_status.sort_values(key).reset_index(drop=True)
    assert a["value"].equals(b["value"])
    assert not a["n_missing"].equals(b["n_missing"])


def test_mismatched_status_is_an_error():
    with pytest.raises(ValueError, match="line up row-for-row"):
        tidyeavs.aggregate(panel(), status=status().iloc[:2])


def test_concepts_filter_and_unknown_name():
    out = tidyeavs.aggregate(panel(), concepts=["mail_rejected"])
    assert set(out["concept"]) == {"mail_rejected"}
    with pytest.raises(ValueError, match="Not numeric concept"):
        tidyeavs.aggregate(panel(), concepts=["nope"])


def test_no_numeric_concepts_is_an_error():
    bad = pd.DataFrame({"year": [2024], "state_abbr": ["AL"], "fips_code": ["0100100000"]})
    with pytest.raises(ValueError, match="No numeric concept columns"):
        tidyeavs.aggregate(bad)


def test_missing_year_is_an_error():
    with pytest.raises(ValueError, match="needs a 'year' column"):
        tidyeavs.aggregate(panel().drop(columns="year"))


def test_bad_by_is_an_error():
    with pytest.raises(ValueError, match="by must be"):
        tidyeavs.aggregate(panel(), by="precinct")


def test_county_rollup_drops_codes_with_no_county():
    jur = pd.DataFrame(
        {
            "year": pd.array([2024] * 4, dtype="Int64"),
            "fips_code": pd.array(FIPS, dtype="string"),
            # Maine's statewide row embeds no county.
            "county_fips": pd.array(["01001", "01003", "23001", None], dtype="string"),
        }
    )
    with pytest.warns(UserWarning, match="Dropping 1 row"):
        out = tidyeavs.aggregate(panel(), by="county", jurisdictions=jur)
    assert "county_fips" in out.columns
    assert out.loc[out["concept"] == "mail_rejected", "n_total"].sum() == 3


def test_multiple_years_stay_separate():
    p = pd.concat([panel(), panel().assign(year=2022)], ignore_index=True)
    out = tidyeavs.aggregate(p)
    assert set(out["year"]) == {2022, 2024}
    assert len(out) == 2 * 2 * 2


def test_coverage_reg_weights_coverage_by_registration():
    p = panel()
    p["reg_eligible_total"] = [1000.0, 3000.0, 500.0, 1500.0]
    out = tidyeavs.aggregate(p)
    assert cell(out, "mail_rejected", "ME", "coverage") == 0.5
    assert cell(out, "mail_rejected", "ME", "coverage_reg") == 0.25
    assert cell(out, "mail_rejected", "AL", "coverage_reg") == 1.0


def test_coverage_reg_na_without_weight_and_na_weights_drop():
    out = tidyeavs.aggregate(panel())
    assert out["coverage_reg"].isna().all()
    p = panel()
    p["reg_eligible_total"] = [1000.0, 3000.0, 500.0, None]
    out = tidyeavs.aggregate(p)
    # The unreported Maine row has no usable weight, so it leaves the weighted
    # ratio entirely while the unweighted coverage still counts it as a gap.
    assert cell(out, "mail_rejected", "ME", "coverage") == 0.5
    assert cell(out, "mail_rejected", "ME", "coverage_reg") == 1.0


def test_na_reason_counts_as_not_collected_and_buckets_sum():
    st = status()
    st["mail_rejected"] = ["reported", "not_available", None, None]
    out = tidyeavs.aggregate(panel(), status=st)
    assert cell(out, "mail_rejected", "ME", "n_not_collected") == 2
    assert cell(out, "mail_rejected", "ME", "n_reported") == 0
    assert cell(out, "mail_rejected", "ME", "n_missing") == 0
    assert pd.isna(cell(out, "mail_rejected", "ME", "coverage"))
    assert cell(out, "mail_rejected", "AL", "n_not_collected") == 0
    assert cell(out, "mail_rejected", "AL", "coverage") == 0.5
    sums = (
        out["n_reported"]
        + out["n_missing"]
        + out["n_blank"]
        + out["n_not_applicable"]
        + out["n_not_collected"]
    )
    assert (sums == out["n_total"]).all()


def test_status_in_the_wrong_year_order_is_an_error():
    p = pd.concat([panel(), panel().assign(year=2022)], ignore_index=True)
    st = pd.concat([status(), status().assign(year=2022)], ignore_index=True)
    tidyeavs.aggregate(p, status=st)  # aligned: fine
    reversed_status = pd.concat([st.iloc[4:], st.iloc[:4]], ignore_index=True)
    assert len(reversed_status) == len(p)  # the row count check cannot see it
    with pytest.raises(ValueError, match="not aligned"):
        tidyeavs.aggregate(p, status=reversed_status)


# known_anomaly: a total can rest on an anomalous convention while every
# coverage column reads as complete, which is exactly Iowa's 2018 polling places
# (all 99 counties reporting).


def agg_anomalies() -> pd.DataFrame:
    return pd.DataFrame(
        {
            "year": [2024],
            "state_abbr": ["AL"],
            "concept": ["mail_rejected"],
            "note": ["Test fixture."],
            "source": ["Test fixture."],
        }
    )


def test_known_anomaly_marks_totals_resting_on_an_anomalous_state_year():
    out = tidyeavs.aggregate(panel(), anomalies=agg_anomalies())
    hit = (out["state_abbr"] == "AL") & (out["concept"] == "mail_rejected")
    assert out.loc[hit, "known_anomaly"].all()
    assert not out.loc[~hit, "known_anomaly"].any()
    # Coverage is unaffected: the column reports, it does not adjust.
    assert out.loc[hit, "coverage"].notna().all()


def test_known_anomaly_is_false_where_the_group_reported_nothing():
    frame = panel()
    frame.loc[frame["state_abbr"] == "AL", "mail_rejected"] = None
    out = tidyeavs.aggregate(frame, anomalies=agg_anomalies())
    hit = (out["state_abbr"] == "AL") & (out["concept"] == "mail_rejected")
    assert (out.loc[hit, "n_reported"] == 0).all()
    assert not out.loc[hit, "known_anomaly"].any()


def test_anomalies_none_skips_the_lookup():
    out = tidyeavs.aggregate(panel(), anomalies=None)
    assert not out["known_anomaly"].any()
