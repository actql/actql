"""Regression tests for pinned Unicode inputs and reproducible generation."""

import json
import importlib.util
import pathlib
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "unicode_generator", ROOT / "scripts" / "generate-unicode-tables.py",
)
GENERATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GENERATOR)


class UnicodeCoverageTests(unittest.TestCase):
    def test_assigned_scalars_expand_ranges_and_exclude_surrogates(self):
        scalars = GENERATOR.assigned_scalars([
            "000D;<control>;Cc",
            "0041;LATIN CAPITAL LETTER A;Lu",
            "3400;<CJK Ideograph Extension A, First>;Lo",
            "3402;<CJK Ideograph Extension A, Last>;Lo",
            "D800;<Surrogate, First>;Cs",
            "DFFF;<Surrogate, Last>;Cs",
            "E000;<Private Use, First>;Co",
            "E002;<Private Use, Last>;Co",
            "10000;LINEAR B SYLLABLE B008 A;Lo",
        ])
        self.assertEqual(
            scalars, {0xD, 0x41, 0x3400, 0x3401, 0x3402, 0xE000, 0xE001, 0xE002, 0x10000},
        )

    def test_ucd_range_errors_are_rejected(self):
        for lines in [
            ["3400;<CJK, First>;Lo"],
            ["3402;<CJK, Last>;Lo"],
            ["3400;<CJK, First>;Lo", "3402;<Other, Last>;Lo"],
            ["3400;<CJK, First>;Lo", "3402;<CJK, Last>;Co"],
            ["3400;<CJK, First>;Lo", "3300;<CJK, Last>;Lo"],
            ["3400;<CJK, First>;Lo", "3401;<Other, First>;Lo"],
            ["3400;<CJK, First>;Lo", "0041;LATIN CAPITAL LETTER A;Lu"],
            ["110000;OUT OF RANGE;Lo"],
        ]:
            with self.subTest(lines=lines), self.assertRaises(ValueError):
                GENERATOR.assigned_scalars(lines)

    def test_only_part1_sources_are_excluded_and_ranges_are_inclusive(self):
        cases, part1 = GENERATOR.normalization_cases([
            "@Part0 # Not excluded",
            "0041;0041;0041;0041;0041;",
            "@Part1",
            "00C0;00C0;0041 0300;00C0;0041 0300;",
            "@Part2",
            "0041 0300;00C0;0041 0300;00C0;0041 0300;",
        ])
        self.assertEqual(len(cases), 3)
        self.assertEqual(part1, {0xC0})
        remaining = {0xD, 0x41, 0x42, 0xC0, 0xE000, 0xE001} - part1
        ranges = GENERATOR.contiguous_ranges(remaining)
        self.assertEqual(ranges, [(0xD, 0xD), (0x41, 0x42), (0xE000, 0xE001)])
        self.assertEqual(
            {cp for start, end in ranges for cp in range(start, end + 1)}, remaining,
        )

    def test_missing_part1_and_multi_scalar_part1_sources_are_rejected(self):
        for lines in [
            ["@Part0", "0041;0041;0041;0041;0041;"],
            ["@Part1", "0041 0300;00C0;0041 0300;00C0;0041 0300;"],
        ]:
            with self.subTest(lines=lines), self.assertRaises(ValueError):
                GENERATOR.normalization_cases(lines)


class UnicodeGenerationTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="actql-unicode-")
        self.addCleanup(temporary.cleanup)
        self.root = pathlib.Path(temporary.name)
        (self.root / "scripts").mkdir()
        self.generator = self.root / "scripts" / "generate-unicode-tables.py"
        shutil.copyfile(ROOT / "scripts" / self.generator.name, self.generator)
        self.inputs = self.root / "vendor" / "unicode" / "16.0.0"
        shutil.copytree(ROOT / "vendor" / "unicode" / "16.0.0", self.inputs)
        self.outputs = self.root / "src" / "canonical_value"

    def generate(self, *args):
        return subprocess.run(
            [sys.executable, str(self.generator), *args],
            capture_output=True, text=True, check=False,
        )

    def assert_success(self, *args):
        result = self.generate(*args)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_input_verification_does_not_generate_code(self):
        self.assert_success("--verify-inputs")
        self.assertFalse(self.outputs.exists())

    def test_reproducible_generation_and_changed_output(self):
        self.assert_success()
        self.assert_success("--check")
        for name in [
            "unicode_tables.generated.mbt", "normalization_conformance.generated_test.mbt",
        ]:
            output = self.outputs / name
            original = output.read_bytes()
            for mutation in ["change", "delete"]:
                with self.subTest(file=name, mutation=mutation):
                    if mutation == "change":
                        output.write_bytes(original + b"// changed\n")
                    else:
                        output.unlink()
                    result = self.generate("--check")
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn(name, result.stderr)
                    output.write_bytes(original)

    def test_generated_corpus_uses_pure_nfc_and_includes_complement(self):
        self.assert_success()
        corpus = (self.outputs / "normalization_conformance.generated_test.mbt").read_text()
        self.assertNotIn("normalize_nfc_lf(", corpus)
        self.assertIn("normalize_nfc(case.4), Ok(case.3)", corpus)
        self.assertIn("normalization_unchanged_ranges", corpus)
        self.assertIn("scalar <= end", corpus)
        self.assertIn("assert_eq(normalize_nfc(value), Ok(value))", corpus)

    def test_changed_input_is_rejected_before_generation(self):
        source = self.inputs / "UnicodeData.txt"
        source.write_bytes(source.read_bytes() + b"\n")
        for args in [("--verify-inputs",), ()]:
            with self.subTest(args=args):
                result = self.generate(*args)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Pinned Unicode input missing or changed", result.stderr)
        self.assertFalse(self.outputs.exists())

    def test_missing_input_is_rejected(self):
        (self.inputs / "NormalizationTest.txt").unlink()
        result = self.generate("--verify-inputs")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("NormalizationTest.txt", result.stderr)

    def test_invalid_manifests_never_create_or_update_outputs(self):
        manifest_path = self.inputs / "manifest.json"
        original = manifest_path.read_text(encoding="utf-8")
        cases = []
        for name in json.loads(original)["sha256"]:
            manifest = json.loads(original)
            del manifest["sha256"][name]
            cases.append((f"missing pin: {name}", manifest))
        for field, value in [
            ("sha256", {}), ("sha256", []),
            ("unicode_version", "15.0.0"), ("license", "OTHER.txt"),
        ]:
            manifest = json.loads(original)
            manifest[field] = value
            cases.append((f"invalid {field}: {value}", manifest))
        for field in ["unicode_version", "license", "sha256"]:
            manifest = json.loads(original)
            del manifest[field]
            cases.append((f"missing {field}", manifest))
        for digest in ["A" * 64, "0" * 63, "g" * 64, 123, None]:
            manifest = json.loads(original)
            manifest["sha256"]["UnicodeData.txt"] = digest
            cases.append((f"invalid digest: {digest}", manifest))
        manifest = json.loads(original)
        manifest["sha256"]["extra.txt"] = "0" * 64
        cases.extend([("extra pin", manifest), ("non-object", [])])
        for label, manifest in cases:
            with self.subTest(label=label):
                manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
                for args in [("--verify-inputs",), (), ("--check",)]:
                    result = self.generate(*args)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn("Invalid Unicode manifest", result.stderr)
                self.assertFalse(self.outputs.exists())

        manifest_path.write_text(original, encoding="utf-8")
        self.assert_success()
        before = {path.name: path.read_bytes() for path in self.outputs.iterdir()}
        for label, manifest in cases:
            with self.subTest(existing_outputs=label):
                manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
                self.assertNotEqual(self.generate().returncode, 0)
                self.assertEqual(
                    {path.name: path.read_bytes() for path in self.outputs.iterdir()}, before,
                )

    def test_missing_license_is_rejected_before_generation(self):
        (self.inputs / "LICENSE.txt").unlink()
        for args in [("--verify-inputs",), ()]:
            result = self.generate(*args)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("LICENSE.txt", result.stderr)
        self.assertFalse(self.outputs.exists())


if __name__ == "__main__":
    unittest.main()
