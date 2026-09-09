"""Regression tests for pinned Unicode inputs and reproducible generation."""

import json
import pathlib
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


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
        output = self.outputs / "unicode_tables.generated.mbt"
        output.write_bytes(output.read_bytes() + b"// changed\n")
        result = self.generate("--check")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("generated Unicode files differ", result.stderr)

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
