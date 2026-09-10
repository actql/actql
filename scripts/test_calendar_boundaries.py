import json
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import check_calendar_boundaries as oracle


class CalendarBoundaryTest(unittest.TestCase):
    def setUp(self):
        self.profile = {
            "coverage_start_ms": oracle.parse("0001-01-01T00:00:00.000Z"),
            "coverage_end_ms": 253402300800000,
            "zones": {"Synthetic": {
                "initial_offset_seconds": 0,
                "transitions": [
                    {"at_ms": oracle.parse("2024-03-31T00:00:00.000Z"), "offset_seconds": 3600},
                    {"at_ms": oracle.parse("2024-10-27T00:00:00.000Z"), "offset_seconds": 0},
                ],
            }},
        }
        self.zone = oracle.Zone(self.profile, "Synthetic")

    def test_transition_instant_uses_new_offset(self):
        at = oracle.parse("2024-03-31T00:00:00.000Z")
        self.assertEqual(self.zone.offset(at - 1), 0)
        self.assertEqual(self.zone.offset(at), 3600000)

    def test_gap_is_half_open_and_advances_to_first_valid_instant(self):
        at = oracle.parse("2024-03-31T00:00:00.000Z")
        for delta in (0, 1, 1800000, 3599999, 3600000):
            self.assertEqual(self.zone.resolve(at + delta), at)
        self.assertEqual(self.zone.resolve(at + 3600001), at + 1)

    def test_fold_selects_earliest_including_ambiguous_midnight(self):
        at = oracle.parse("2024-10-27T00:00:00.000Z")
        self.assertEqual(self.zone.resolve(at), at - 3600000)
        self.assertEqual(self.zone.resolve(at + 1800000), at - 1800000)
        self.assertEqual(self.zone.resolve(at + 3600000), at + 3600000)
        self.assertEqual(oracle.bucket(self.zone, at, "day"), [
            "2024-10-26T23:00:00.000Z", "2024-10-28T00:00:00.000Z"])

    def test_bucket_end_is_exclusive(self):
        at = oracle.parse("2024-03-31T23:00:00.000Z")
        self.assertEqual(oracle.bucket(self.zone, at - 1, "day"), [
            "2024-03-31T00:00:00.000Z", "2024-03-31T23:00:00.000Z"])
        self.assertEqual(oracle.bucket(self.zone, at, "day"), [
            "2024-03-31T23:00:00.000Z", "2024-04-01T23:00:00.000Z"])

    def test_domain_is_not_extrapolated(self):
        with self.assertRaisesRegex(ValueError, "BoundaryOutOfRange"):
            self.zone.offset(self.profile["coverage_end_ms"])
        with self.assertRaisesRegex(ValueError, "BoundaryOutOfRange"):
            oracle.bucket(self.zone, oracle.parse("9999-12-31T12:00:00.000Z"), "day")

    def test_noncanonical_timestamp_is_not_repaired(self):
        for text in ("2024-01-01T00:00:00Z", "2024-01-01T00:00:00.000+00:00",
                     "1900-02-29T00:00:00.000Z", "0000-01-01T00:00:00.000Z"):
            with self.assertRaisesRegex(ValueError, "InvalidTimestamp"):
                oracle.parse(text)

    def test_changed_artifact_fails_before_evaluation(self):
        with patch.object(oracle, "TABLE", SimpleNamespace(read_bytes=lambda: b"{}")):
            with self.assertRaisesRegex(ValueError, "transition pin mismatch"):
                oracle.check()

    def test_wrong_fixed_expectation_fails(self):
        corpus = json.loads(oracle.CORPUS.read_text())
        corpus["cases"] = corpus["cases"][:1]
        corpus["cases"][0]["expected"][1] = "2024-03-02T00:00:00.000Z"
        with patch.object(oracle, "CORPUS", SimpleNamespace(read_text=lambda: json.dumps(corpus))):
            with self.assertRaisesRegex(AssertionError, "leap-day"):
                oracle.check()

    def test_empty_corpus_and_unknown_case_fields_fail(self):
        original = json.loads(oracle.CORPUS.read_text())
        empty = {**original, "cases": []}
        typo = {**original, "cases": [{**original["cases"][0], "unt": "month"}]}
        for corpus in (empty, typo):
            with patch.object(oracle, "CORPUS", SimpleNamespace(read_text=lambda: json.dumps(corpus))):
                with self.assertRaisesRegex(ValueError, "Invalid"):
                    oracle.check()
