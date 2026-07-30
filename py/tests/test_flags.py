"""Internal-consistency flags.

Mirrors r/tests/testthat/test-flags.R. Fixture checks, so these don't move when
metadata/checks.csv is edited. Network-free.
"""

from __future__ import annotations

import numpy as np
import pandas as pd
import pytest

import tidyeavs

COLUMNS = [
    "year",
    "fips_code",
    "state_abbr",
    "jurisdiction_name",
    "check",
    "kind",
    "concept",
    "observed",
    "threshold",
    "excess",
    "n_parts_reported",
    "note",
]


def checks_fixture() -> pd.DataFrame:
    return pd.DataFrame(
        {
            "check": ["returned_le_transmitted", "disposition_le_returned"],
            "total": ["mail_transmitted", "mail_returned"],
            "parts": [["mail_returned"], ["mail_counted", "mail_rejected"]],
            "section": ["C", "C"],
            "note": ["note one", "note two"],
        }
    )


def panel_1y(**values) -> pd.DataFrame:
    return pd.DataFrame(
        {
            "year": [2024],
            "fips_code": ["0100100000"],
            "state_abbr": ["AL"],
            "jurisdiction_name": ["AUTAUGA COUNTY"],
            **{k: [v] for k, v in values.items()},
        }
    )


def swing_panel(before, now) -> pd.DataFrame:
    return pd.DataFrame(
        {
            "year": [2022, 2024],
            "fips_code": ["0100100000"] * 2,
            "state_abbr": ["AL"] * 2,
            "jurisdiction_name": ["AUTAUGA COUNTY"] * 2,
            "mail_returned": [float(before), float(now)],
        }
    )


def test_sum_check_fires_when_parts_exceed_total():
    d = panel_1y(mail_transmitted=100.0, mail_returned=80.0,
                 mail_counted=70.0, mail_rejected=20.0)
    f = tidyeavs.flags(d, checks=checks_fixture(), swing_factor=None)
    assert len(f) == 1
    assert f["check"].item() == "disposition_le_returned"
    assert f["observed"].item() == 90
    assert f["threshold"].item() == 80
    assert f["excess"].item() == 10
    assert f["n_parts_reported"].item() == 2
    assert f["note"].item() == "note two"


def test_nothing_flagged_when_arithmetic_reconciles():
    d = panel_1y(mail_transmitted=100.0, mail_returned=80.0,
                 mail_counted=70.0, mail_rejected=10.0)
    assert len(tidyeavs.flags(d, checks=checks_fixture(), swing_factor=None)) == 0


def test_partial_sum_still_flags_and_counts_parts():
    d = panel_1y(mail_transmitted=100.0, mail_returned=50.0,
                 mail_counted=60.0, mail_rejected=None)
    f = tidyeavs.flags(d, checks=checks_fixture(), swing_factor=None)
    assert len(f) == 1
    assert f["observed"].item() == 60
    assert f["n_parts_reported"].item() == 1


def test_missing_total_or_all_parts_produces_no_flag():
    only_disposition = checks_fixture().iloc[[1]]
    no_total = panel_1y(mail_returned=None, mail_counted=70.0, mail_rejected=20.0)
    no_parts = panel_1y(mail_returned=80.0, mail_counted=None, mail_rejected=None)
    assert len(tidyeavs.flags(no_total, checks=only_disposition, swing_factor=None)) == 0
    assert len(tidyeavs.flags(no_parts, checks=only_disposition, swing_factor=None)) == 0


def test_equal_is_not_flagged():
    d = panel_1y(mail_returned=80.0, mail_counted=80.0, mail_rejected=0.0)
    f = tidyeavs.flags(d, checks=checks_fixture().iloc[[1]], swing_factor=None)
    assert len(f) == 0


def test_swings_fire_in_both_directions():
    up = tidyeavs.flags(swing_panel(100, 2000), checks=None, swing_factor=10)
    down = tidyeavs.flags(swing_panel(2000, 100), checks=None, swing_factor=10)
    assert up["check"].item() == "year_over_year_swing"
    assert up["observed"].item() == 2000
    assert up["threshold"].item() == 100
    assert down["check"].item() == "year_over_year_swing"
    assert down["observed"].item() == 100


def test_swing_inside_the_factor_is_not_flagged():
    assert len(tidyeavs.flags(swing_panel(100, 500), checks=None, swing_factor=10)) == 0


def test_swing_floor_keeps_small_counts_out():
    assert len(tidyeavs.flags(swing_panel(5, 99), checks=None)) == 0
    assert len(tidyeavs.flags(swing_panel(5, 99), checks=None, swing_floor=10)) == 1


def test_drop_to_zero_is_its_own_check_with_finite_excess():
    f = tidyeavs.flags(swing_panel(5000, 0), checks=None)
    assert f["check"].item() == "dropped_to_zero"
    assert f["observed"].item() == 0
    assert f["threshold"].item() == 5000
    assert f["excess"].item() == 5000
    assert np.isfinite(f["excess"]).all()


def test_rise_from_zero_never_yields_infinity():
    f = tidyeavs.flags(swing_panel(0, 5000), checks=None)
    assert np.isfinite(f["excess"]).all()


def test_zero_drop_note_has_no_padding():
    f = tidyeavs.flags(swing_panel(963, 0), checks=None)
    assert "Reported 963 in 2022" in f["note"].item()


def test_one_year_produces_no_swings():
    d = panel_1y(mail_transmitted=100.0, mail_returned=80.0,
                 mail_counted=70.0, mail_rejected=20.0)
    f = tidyeavs.flags(d, checks=checks_fixture())
    assert (f["kind"] == "sum").all()


def test_either_kind_can_be_switched_off():
    d = swing_panel(100, 2000).assign(
        mail_transmitted=100.0, mail_counted=0.0, mail_rejected=0.0
    )
    assert (tidyeavs.flags(d, checks=checks_fixture(), swing_factor=None)["kind"] == "sum").all()
    assert (tidyeavs.flags(d, checks=None)["kind"] == "swing").all()


def test_empty_result_still_has_all_columns():
    d = panel_1y(mail_transmitted=100.0, mail_returned=80.0,
                 mail_counted=70.0, mail_rejected=10.0)
    f = tidyeavs.flags(d, checks=checks_fixture(), swing_factor=None)
    assert len(f) == 0
    assert list(f.columns) == COLUMNS


def test_missing_year_is_an_error():
    with pytest.raises(ValueError, match="needs a 'year' column"):
        tidyeavs.flags(panel_1y(mail_returned=1.0).drop(columns="year"))


def test_checks_naming_absent_concepts_are_skipped():
    absent = pd.DataFrame(
        {
            "check": ["nope"],
            "total": ["not_a_concept"],
            "parts": [["also_not"]],
            "section": ["C"],
            "note": ["x"],
        }
    )
    d = panel_1y(mail_transmitted=100.0, mail_returned=200.0)
    assert len(tidyeavs.flags(d, checks=absent, swing_factor=None)) == 0


def test_shipped_checks_are_well_formed():
    c = tidyeavs.checks()
    assert len(c) > 0
    assert not c["check"].duplicated().any()
    assert isinstance(c["parts"].iloc[0], list)
    # No check compares a concept against itself.
    for _, row in c.iterrows():
        assert row["total"] not in row["parts"]


def test_shipped_checks_only_name_real_concepts():
    concepts = set(tidyeavs.dictionary()["concept"])
    for _, row in tidyeavs.checks().iterrows():
        assert row["total"] in concepts
        for part in row["parts"]:
            assert part in concepts


def anomalies_fixture() -> pd.DataFrame:
    return pd.DataFrame(
        {
            "year": [2024],
            "state_abbr": ["AL"],
            "concept": ["mail_returned"],
            "note": ["fixture note"],
            "source": ["fixture source"],
        }
    )


def test_known_anomaly_flags_every_reported_observation():
    d = pd.concat(
        [panel_1y(mail_returned=100.0), panel_1y(mail_returned=200.0)],
        ignore_index=True,
    )
    f = tidyeavs.flags(
        d, checks=None, swing_factor=None, anomalies=anomalies_fixture()
    )
    assert len(f) == 2
    assert set(f["check"]) == {"known_anomaly"}
    assert set(f["kind"]) == {"known_anomaly"}
    assert sorted(f["observed"]) == [100.0, 200.0]
    assert f["threshold"].isna().all()
    assert f["excess"].isna().all()
    assert set(f["note"]) == {"fixture note"}


def test_known_anomaly_skips_other_states_years_and_na():
    other_state = panel_1y(mail_returned=100.0).assign(state_abbr="GA")
    other_year = panel_1y(mail_returned=100.0).assign(year=2022)
    no_value = panel_1y(mail_returned=np.nan)
    for d in (other_state, other_year, no_value):
        f = tidyeavs.flags(
            d, checks=None, swing_factor=None, anomalies=anomalies_fixture()
        )
        assert len(f) == 0


def test_anomalies_none_skips_them():
    d = panel_1y(mail_returned=100.0)
    f = tidyeavs.flags(d, checks=None, swing_factor=None, anomalies=None)
    assert len(f) == 0


def test_shipped_anomalies_are_well_formed():
    a = tidyeavs.known_anomalies()
    assert len(a) > 0
    concepts = set(tidyeavs.dictionary()["concept"])
    assert set(a["concept"]) <= concepts
    assert a["note"].notna().all()
    assert a["source"].notna().all()
    assert not a[["year", "state_abbr", "concept"]].duplicated().any()


def alameda_panel() -> pd.DataFrame:
    # Alameda CA: 10 digits in 2022, 9 in 2024. The jurisdiction table's fips10
    # is what makes these the same jurisdiction.
    return pd.DataFrame(
        {
            "year": [2022, 2024],
            "fips_code": ["0600100000", "600100000"],
            "state_abbr": ["CA", "CA"],
            "jurisdiction_name": ["ALAMEDA COUNTY", "ALAMEDA COUNTY"],
            "mail_returned": [100.0, 5000.0],
        }
    )


def test_swings_line_up_a_code_that_lost_a_leading_zero():
    jur = pd.DataFrame(
        {
            "year": pd.array([2022, 2024], dtype="Int64"),
            "fips_code": pd.array(["0600100000", "600100000"], dtype="string"),
            "fips10": pd.array(["0600100000", "0600100000"], dtype="string"),
        }
    )
    f = tidyeavs.flags(
        alameda_panel(), checks=None, anomalies=None, jurisdictions=jur
    )
    assert len(f) == 1
    assert f["check"].iloc[0] == "year_over_year_swing"

    # Without the normalization the two rows look like different jurisdictions.
    raw = jur.assign(fips10=pd.array([None, None], dtype="string"))
    with pytest.warns(UserWarning, match="not swing-checked"):
        f0 = tidyeavs.flags(
            alameda_panel(), checks=None, anomalies=None, jurisdictions=raw
        )
    assert len(f0) == 0


def test_shared_code_is_not_compared_against_the_wrong_row():
    # Wisconsin publishes one serial for a town/village pair in some years.
    d = pd.DataFrame(
        {
            "year": [2020, 2020, 2022],
            "fips_code": ["82575"] * 3,
            "state_abbr": ["WI"] * 3,
            "jurisdiction_name": [
                "TOWN OF VERNON",
                "VILLAGE OF VERNON",
                "TOWN OF VERNON",
            ],
            "mail_returned": [100.0, 5000.0, 5000.0],
        }
    )
    jur = pd.DataFrame(
        {
            "year": pd.array([2020, 2020, 2022], dtype="Int64"),
            "fips_code": pd.array(["82575"] * 3, dtype="string"),
            "fips10": pd.array([None] * 3, dtype="string"),
        }
    )
    f = tidyeavs.flags(d, checks=None, anomalies=None, jurisdictions=jur)
    # TOWN OF VERNON 100 -> 5000 is a real 50-fold swing; the village must not
    # be the one credited with it.
    assert len(f) == 1
    assert f["jurisdiction_name"].iloc[0] == "TOWN OF VERNON"
    assert f["threshold"].iloc[0] == 100
