from decimal import Decimal, localcontext
from fractions import Fraction
import json
import random
import struct
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import check_text_rank_numeric as oracle


class TextRankNumericTest(unittest.TestCase):
    def test_rational_log_agrees_with_separate_high_precision_decimal(self):
        rng = random.Random(104729)
        patterns = [1, 0x3ff0000000000001, 0x3fefffffffffffff, 0x7fefffffffffffff]
        patterns += [rng.randrange(1, 0x7ff0000000000000) for _ in range(100)]
        with localcontext() as context:
            context.prec = 160
            for pattern in patterns:
                value = struct.unpack(">d", struct.pack(">Q", pattern))[0]
                expected = float(Decimal.from_float(value).ln())
                self.assertEqual(oracle.bits(oracle.rounded_log(value)), oracle.bits(expected))

    def test_log_intervals_nest_and_are_nonzero_width(self):
        low, high = oracle.log_interval(Fraction(3, 2), 4)
        tighter_low, tighter_high = oracle.log_interval(Fraction(3, 2), 8)
        self.assertLess(low, tighter_low)
        self.assertLess(tighter_low, tighter_high)
        self.assertLess(tighter_high, high)
        self.assertEqual(oracle.log_interval(Fraction(1), 8), (0, 0))

    def test_log_domain_and_finiteness(self):
        for value in (0.0, -0.0, -1.0):
            with self.assertRaisesRegex(ValueError, "LogDomain"):
                oracle.rounded_log(value)
        for value in (float("inf"), float("nan")):
            with self.assertRaisesRegex(ValueError, "NonFinite"):
                oracle.rounded_log(value)

    def test_zero_output_does_not_bypass_parameter_or_identity_admission(self):
        case = {"corpus": [], "queries": [], "k1": 1.2, "b": 0.75, "k": 1}
        for changes, error in [({"k": 0}, "InvalidK"), ({"k": True}, "InvalidK"),
                               ({"k1": 0}, "InvalidScoring"), ({"k1": True}, "InvalidScoring"),
                               ({"b": True}, "InvalidScoring"), ({"b": 2}, "InvalidScoring"),
                               ({"queries": [{"id": "a", "tokens": []}] * 2}, "DuplicateIdentity")]:
            with self.assertRaisesRegex(ValueError, error):
                oracle.rank({**case, **changes})

    def test_wrong_score_bits_fail_the_fixed_corpus_check(self):
        corpus = json.loads(oracle.CORPUS.read_text())
        corpus["cases"] = corpus["cases"][:1]
        corpus["cases"][0]["expected"][0]["score_bits"] = "0000000000000000"
        with patch.object(oracle, "CORPUS", SimpleNamespace(read_text=lambda: json.dumps(corpus))):
            with self.assertRaisesRegex(AssertionError, "one-document"):
                oracle.check()

    def test_empty_corpus_is_not_a_successful_validation_suite(self):
        corpus = json.loads(oracle.CORPUS.read_text())
        corpus["cases"] = []
        with patch.object(oracle, "CORPUS", SimpleNamespace(read_text=lambda: json.dumps(corpus))):
            with self.assertRaisesRegex(ValueError, "InvalidCorpus"):
                oracle.check()
