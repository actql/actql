import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import check_text_rank_tokenizer as oracle


class TextRankTokenizerTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tables = oracle.UnicodeTables()

    def test_entire_ucd_normalization_corpus_nfc_and_nfkc(self):
        cases = 0
        for raw in (oracle.UCD / "NormalizationTest.txt").read_text().splitlines():
            body = raw.split("#", 1)[0].strip()
            if not body or body.startswith("@"):
                continue
            c1, c2, c3, c4, c5 = ["".join(chr(int(cp, 16)) for cp in field.split())
                                  for field in body.split(";")[:5]]
            for text, expected in [(c1, c2), (c2, c2), (c3, c2), (c4, c4), (c5, c4)]:
                self.assertEqual(self.tables.normalize(text), expected)
            for text in (c1, c2, c3, c4, c5):
                self.assertEqual(self.tables.normalize(text, compatibility=True), c4)
            cases += 1
        self.assertEqual(cases, 19965)

    def test_all_default_fold_records_are_used_and_turkic_only_records_are_not(self):
        count = 0
        for raw in (oracle.UCD / "CaseFolding.txt").read_text().splitlines():
            body = raw.split("#", 1)[0].strip()
            if not body:
                continue
            code, status, mapping, _ = [s.strip() for s in body.split(";")]
            if status in ("C", "F"):
                self.assertEqual(self.tables.folds[int(code, 16)], tuple(int(cp, 16) for cp in mapping.split()))
                count += 1
        self.assertEqual(count, len(self.tables.folds))
        self.assertEqual(self.tables.prepare("Iİı"), "ii\u0307ı")

    def test_range_categories_and_unassigned_delimiters(self):
        self.assertEqual(self.tables.tokenize("漢字", "char_bigram")[1], ["漢字"])
        self.assertEqual(self.tables.tokenize("a\u0378b", "unicode_words")[1], ["a", "b"])
        self.assertEqual(self.tables.tokenize("\U000105c0\U000105c1", "char_bigram")[1], ["\U000105c0\U000105c1"])

    def test_missing_fold_pin_is_rejected_before_tables_are_used(self):
        manifest = json.loads((oracle.UCD / "manifest.json").read_text())
        del manifest["sha256"]["CaseFolding.txt"]
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "manifest.json").write_text(json.dumps(manifest))
            with self.assertRaisesRegex(ValueError, "required input"):
                oracle.UnicodeTables(root)

    def test_wrong_expected_tokens_fail(self):
        corpus = json.loads(oracle.CORPUS.read_text())
        corpus["cases"] = corpus["cases"][:1]
        corpus["cases"][0]["unicode_words"] = ["hello"]
        with patch.object(oracle, "CORPUS", SimpleNamespace(read_text=lambda **kwargs: json.dumps(corpus))):
            with self.assertRaisesRegex(AssertionError, "ascii-repetition"):
                oracle.check()
