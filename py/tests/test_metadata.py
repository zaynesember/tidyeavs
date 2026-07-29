"""The shared metadata: types, the crosswalk, and the renumbering traps.

Network-free; reads the committed CSVs in metadata/.
"""

from __future__ import annotations

import pandas as pd
import pytest

import tidyeavs


def test_metadata_dir_is_found():
    assert (tidyeavs.metadata_dir() / "schema.json").is_file()


def test_dictionary_shape():
    d = tidyeavs.dictionary()
    assert len(d) == 195
    assert d["concept"].nunique() == 39
    assert list(d.columns) == [
        "concept",
        "concept_label",
        "section",
        "year",
        "code",
        "codebook_label",
        "epi_name",
        "note",
        "confidence",
    ]


def test_held_back_concept_is_not_shipped():
    """poll_worker_difficulty is curated but deliberately not exported."""
    assert "poll_worker_difficulty" not in set(tidyeavs.dictionary()["concept"])
    crosswalk = pd.read_csv(tidyeavs.metadata_dir() / "crosswalk.csv", dtype="string")
    assert "poll_worker_difficulty" in set(crosswalk["concept"])


def test_fips_leading_zeros_survive_the_typed_read():
    """The whole reason schema.json exists: a naive read destroys these."""
    j = tidyeavs.jurisdictions()
    assert j["fips_code"].dtype == "string"
    # Alaska files one statewide row, coded 0200000000.
    assert (j["fips_code"] == "0200000000").any()
    # County FIPS keep their leading zero rather than becoming floats.
    assert (j["county_fips"] == "01001").any()


def test_manifest_pins_every_file_by_checksum():
    m = tidyeavs.manifest()
    assert len(m) == 18
    assert m["sha256"].notna().all()
    assert m["sha256"].str.len().eq(64).all()
    assert m["source_url"].notna().all()


def test_jurisdiction_row_counts_match_the_published_files():
    counts = tidyeavs.jurisdictions().groupby("year").size().to_dict()
    assert counts == {2016: 6467, 2018: 6460, 2020: 6460, 2022: 6460, 2024: 6461}


def test_uocava_rejected_renumbering_trap():
    """B18a is uocava_rejected 2018-2022 but uocava_counted in 2024."""
    codes = dict(
        zip(
            tidyeavs.items("uocava_rejected")["year"],
            tidyeavs.items("uocava_rejected")["code"],
        )
    )
    assert codes == {2016: "B13a", 2018: "B18a", 2020: "B18a", 2022: "B18a", 2024: "B24a"}

    d = tidyeavs.dictionary()
    b18a = d[d["code"] == "B18a"]
    assert b18a.loc[b18a["year"] == 2024, "concept"].item() == "uocava_counted"


def test_mail_rejected_breaks_at_2020_to_2022():
    codes = dict(
        zip(tidyeavs.items("mail_rejected")["year"], tidyeavs.items("mail_rejected")["code"])
    )
    assert codes[2020] == "C4a"
    assert codes[2022] == "C9a"


def test_drop_boxes_only_from_2022():
    codes = tidyeavs.items("drop_boxes_total").set_index("year")["code"]
    assert codes[2016] is pd.NA or pd.isna(codes[2016])
    assert codes[2020] is pd.NA or pd.isna(codes[2020])
    assert pd.notna(codes[2022])


def test_items_search_matches_codes_and_labels():
    assert not tidyeavs.items("C9a").empty
    assert not tidyeavs.items("mail_rejected").empty
    assert set(tidyeavs.items(section="C")["section"]) == {"C"}
    assert set(tidyeavs.items(year=2024)["year"]) == {2024}


def test_items_query_is_case_insensitive():
    assert len(tidyeavs.items("MAIL_REJECTED")) == len(tidyeavs.items("mail_rejected"))


def test_2016_identifier_columns_differ_from_later_years():
    ids = tidyeavs.items(section="id")
    by_year = ids.set_index(["concept", "year"])["code"]
    assert by_year[("jurisdiction_name", 2016)] == "JurisdictionName"
    assert by_year[("jurisdiction_name", 2024)] == "Jurisdiction_Name"
    assert pd.isna(by_year[("state_name", 2016)])


def test_set_metadata_dir_rejects_a_bad_path(tmp_path):
    tidyeavs.set_metadata_dir(tmp_path)
    try:
        with pytest.raises(Exception):
            tidyeavs.dictionary()
    finally:
        tidyeavs.set_metadata_dir(None)
    # Restored, so the real crosswalk loads again.
    assert len(tidyeavs.dictionary()) == 195
