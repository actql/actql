import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import text_rank_profile as profile


class TextRankProfileTest(unittest.TestCase):
    def test_every_source_and_vector_is_bound(self):
        value = json.loads(profile.generate())
        self.assertEqual(set(value["unicode_source_sha256"]), {
            "UnicodeData.txt", "CaseFolding.txt", "CompositionExclusions.txt",
            "NormalizationTest.txt", "LICENSE.txt",
        })
        for field, (name, _) in profile.VECTORS.items():
            self.assertEqual(value[field], profile.byte_cid((profile.ROOT / "portability/corpus" / name).read_bytes()))
        self.assertEqual(value["tokenizer_law"]["normalization"], ["NFKC", "full_default_case_fold_C_F", "NFC"])
        self.assertEqual(value["numeric_law"]["logarithm"], "correctly_rounded_ln_of_binary64_argument")

    def test_changed_law_changes_identity(self):
        before = profile.generate()
        with patch.dict(profile.NUMERIC_LAW, {"logarithm": "host_log"}):
            self.assertNotEqual(profile.byte_cid(before), profile.byte_cid(profile.generate()))

    def test_reformatted_profile_is_rejected_without_repair(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "profile.json"
            changed = json.dumps(json.loads(profile.generate()), indent=2).encode()
            path.write_bytes(changed)
            with self.assertRaisesRegex(ValueError, "noncanonical"):
                profile.check(path)
            self.assertEqual(path.read_bytes(), changed)

    def test_vector_version_mismatch_rejects_generation(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = Path(temp)
            for _, (name, _) in profile.VECTORS.items():
                value = json.loads((profile.ROOT / "portability/corpus" / name).read_text())
                value["version"] = "unsupported/0.1"
                (folder / name).write_text(json.dumps(value))
            with self.assertRaisesRegex(ValueError, "Invalid vectors"):
                profile.generate(corpus_dir=folder)
