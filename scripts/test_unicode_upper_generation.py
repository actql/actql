import hashlib
import importlib.util
import json
import pathlib
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("unicode_upper_generator", ROOT / "scripts/generate-unicode-upper.py")
UPPER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(UPPER)


def record(code, upper=""):
    return ";".join([code, "fixture", "Ll", "0", "L", "", "", "", "", "N", "", "", upper, "", ""])


class UnicodeUpperGenerationTests(unittest.TestCase):
    def test_fixed_full_mapping_and_unicode_16_vectors(self):
        UPPER.read_sources(UPPER.UCD)
        actual = UPPER.upper_mappings((UPPER.UCD / "UnicodeData.txt").read_text().splitlines(),
                                     (UPPER.UCD / "SpecialCasing.txt").read_text().splitlines())
        for code, expected in {
            0xDF: (0x53, 0x53), 0xFB03: (0x46, 0x46, 0x49), 0x1F3: (0x1F1,),
            0x1F80: (0x1F08, 0x399), 0x390: (0x399, 0x308, 0x301),
            0x345: (0x399,), 0x1F0: (0x4A, 0x30C), 0x10428: (0x10400,),
            0x10D70: (0x10D50,), 0x1C8A: (0x1C89,), 0x69: (0x49,), 0x131: (0x49,),
        }.items():
            with self.subTest(code=code):
                self.assertEqual(actual[code], expected)
        for unchanged in [0x1E9E, 0x130, 0x3A3, 0x301, 0x65E5, 0x1F600]:
            self.assertNotIn(unchanged, actual)

    def test_special_casing_overrides_simple_uppercase(self):
        self.assertEqual(UPPER.upper_mappings([record("1F80", "1F88")],
            ["1F80; 1F80; 1F88; 1F08 0399;"]), {0x1F80: (0x1F08, 0x399)})

    def test_locale_rules_do_not_enter_default_uppercase(self):
        actual = UPPER.upper_mappings([record("0069", "0049"), record("0307")], [
            "0069; 0069; 0130; 0130; tr;", "0069; 0069; 0130; 0130; az;",
            "0307; 0307; ; ; lt After_Soft_Dotted;", "03A3; 03C2; 03A3; 03A3; Final_Sigma;",
        ])
        self.assertEqual(actual, {0x69: (0x49,)})

    def test_new_root_contexts_cannot_be_silently_ignored(self):
        for row in ["0061; 0061; 0041; 0042; Final_Sigma;",
                    "0061; 0061; 0041; 0041; New_Context;"]:
            with self.subTest(row=row), self.assertRaises(ValueError):
                UPPER.upper_mappings([record("0061", "0041")], [row])

    def test_duplicate_non_scalar_and_invalid_expansions_fail(self):
        for unicode, special in [
            ([record("0061", "0041"), record("0061", "0042")], []),
            ([record("D800", "0041")], []),
            ([record("0061", "DFFF")], []),
            ([], ["0061; 0061; 0041; 0041;", "0061; 0061; 0041; 0042;"]),
            ([], ["0061; 0061; 0041; ;"]),
            ([], ["0061; 0061; 0041; 0041 0042 0043 0044;"]),
            ([], ["0061; 0061; 0041; 110000;"]),
        ]:
            with self.subTest(unicode=unicode, special=special), self.assertRaises(ValueError):
                UPPER.upper_mappings(unicode, special)

    def test_casing_manifest_is_separate_and_detects_input_mutation(self):
        with tempfile.TemporaryDirectory(prefix="actql-upper-input-") as temp:
            directory = pathlib.Path(temp)
            for name in UPPER.FILES | {"manifest.json", "casing-manifest.json"}:
                shutil.copyfile(UPPER.UCD / name, directory / name)
            pins = UPPER.read_sources(directory)
            original = json.loads((directory / "manifest.json").read_text())
            self.assertNotIn("SpecialCasing.txt", original["sha256"])
            self.assertEqual(pins["UnicodeData.txt"], original["sha256"]["UnicodeData.txt"])
            with (directory / "SpecialCasing.txt").open("ab") as out:
                out.write(b"# tampered\n")
            with self.assertRaisesRegex(ValueError, "pinned casing input changed"):
                UPPER.read_sources(directory)

    def test_freshness_checks_do_not_repair_generated_output_or_existing_profiles(self):
        protected = [UPPER.UCD / "manifest.json",
                     ROOT / "src/canonical_value/unicode_tables.generated.mbt",
                     ROOT / "spec/dependencies/actql-text-time-unicode-data.json",
                     ROOT / "portability/profiles/text-rank-unicode16.json"]
        before = {path: hashlib.sha256(path.read_bytes()).hexdigest() for path in protected}
        command = [sys.executable, str(ROOT / "scripts/generate-unicode-upper.py")]
        subprocess.run(command + ["--check"], cwd=ROOT, check=True, capture_output=True)
        with tempfile.TemporaryDirectory(prefix="actql-upper-output-") as temp:
            output = pathlib.Path(temp) / "upper.mbt"
            subprocess.run(command + ["--output", str(output)], cwd=ROOT, check=True, capture_output=True)
            self.assertEqual(output.read_bytes(), UPPER.OUT.read_bytes())
            output.write_bytes(b"stale fixture\n")
            result = subprocess.run(command + ["--check", "--output", str(output)], cwd=ROOT, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(output.read_bytes(), b"stale fixture\n")
        self.assertEqual(before, {path: hashlib.sha256(path.read_bytes()).hexdigest() for path in protected})
