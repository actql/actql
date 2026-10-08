import hashlib
import importlib.util
import json
import lzma
import pathlib
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("unicode_lower_generator", ROOT / "scripts/generate-unicode-lower.py")
LOWER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(LOWER)


def record(code, lower=""):
    return ";".join([code, "fixture", "Lu", "0", "L", "", "", "", "", "N", "", "", "", lower, ""])


def contains(ranges, code):
    return any(first <= code <= last for first, last in ranges)


def copy_sources(directory):
    stored = (LOWER.FILES - {"DerivedCoreProperties.txt"}) | {"DerivedCoreProperties.txt.xz"}
    for name in stored | {"manifest.json", "casing-manifest.json", "lower-casing-manifest.json"}:
        shutil.copyfile(LOWER.UCD / name, directory / name)


def compress_fixture(raw):
    return lzma.compress(raw, format=lzma.FORMAT_XZ, check=lzma.CHECK_CRC64, preset=6)


def archive_metadata(archive):
    return {"path": "DerivedCoreProperties.txt.xz", "sha256": hashlib.sha256(archive).hexdigest(),
            "bytes": len(archive), "uncompressed_bytes": 1115959}


class UnicodeLowerGenerationTests(unittest.TestCase):
    def test_fixed_full_mapping_and_unicode_16_vectors(self):
        LOWER.read_sources(LOWER.UCD)
        actual = LOWER.lower_mappings((LOWER.UCD / "UnicodeData.txt").read_text("utf-8").splitlines(),
                                     (LOWER.UCD / "SpecialCasing.txt").read_text("utf-8").splitlines())
        # Expectations are fixed Unicode vectors, never host lowercase/folding.
        for code, expected in {
            0x0041: (0x0061,), 0x0049: (0x0069,), 0x0130: (0x0069, 0x0307),
            0x01F2: (0x01F3,), 0x03A3: (0x03C3,), 0x1E9E: (0x00DF,),
            0x13A0: (0xAB70,), 0x10400: (0x10428,),
            0x10D50: (0x10D70,), 0x1C89: (0x1C8A,),
        }.items():
            with self.subTest(code=code):
                self.assertEqual(actual[code], expected)
        for unchanged in [0xDF, 0xFB03, 0xAB70, 0x345, 0x2B0, 0x1F130, 0x3C2, 0x3C3,
                          0x301, 0x65E5, 0x1F600, 0x000D, 0x000A]:
            with self.subTest(unchanged=unchanged):
                self.assertNotIn(unchanged, actual)

    def test_lowercase_field_and_full_override_preserve_scalar_order(self):
        # Distinct upper/lower/title fields detect an off-by-one column choice.
        line = ";".join(["01F2", "fixture", "Lt", "0", "L", "", "", "", "", "N", "", "",
                         "01F1", "01F3", "01F2"])
        actual = LOWER.lower_mappings([line, record("0130", "0069"), record("012E", "012F")], [
            "0130; 0069 0307; 0130; 0130;",
            # Deliberately non-canonical order: no normalization is permitted.
            "012E; 0069 0307 0323; 012E; 012E;",
        ])
        self.assertEqual(actual, {0x1F2: (0x1F3,), 0x130: (0x69, 0x307), 0x12E: (0x69, 0x307, 0x323)})
        text = LOWER.table_text(actual, {"Cased": [(0x41, 0x5A)], "Case_Ignorable": [(0x300, 0x36F)]},
                                {name: "0" * 64 for name in LOWER.FILES})
        self.assertIn('"\\u{69}\\u{307}\\u{323}"', text)
        self.assertNotIn('"\\u{69}\\u{323}\\u{307}"', text)

    def test_locale_rules_are_omitted_and_final_sigma_stays_contextual(self):
        actual = LOWER.lower_mappings([record("0049", "0069"), record("0130", "0069"),
                                       record("03A3", "03C3"), record("0307")], [
            "0130; 0069 0307; 0130; 0130;",
            "0130; 0069; 0130; 0130; tr;", "0130; 0069; 0130; 0130; az;",
            "0049; 0069 0307; 0049; 0049; lt More_Above;",
            "0049; 0131; 0049; 0049; tr Not_Before_Dot;",
            "0049; 0131; 0049; 0049; az Not_Before_Dot;",
            "0307; ; 0307; 0307; tr After_I;", "0307; ; 0307; 0307; az After_I;",
            "03A3; 03C2; 03A3; 03A3; Final_Sigma;",
        ])
        self.assertEqual(actual, {0x49: (0x69,), 0x130: (0x69, 0x307), 0x3A3: (0x3C3,)})

    def test_new_or_changed_root_contexts_cannot_be_silently_ignored(self):
        for row in [
            "03A3; 03C3; 03A3; 03A3; Final_Sigma;",
            "03A3; 03C2; 03A3; 03A3; New_Context;",
            "03A3; 03C2; 03A3; 03A3; Not_Final_Sigma;",
            "03A3; 03C2; 03A3; 03A3; Final_Sigma More_Above;",
            "0041; 03C2; 0041; 0041; Final_Sigma;",
            "0041; 0061; 0041; 0041; zz;",
            "03A3; ; 03A3; 03A3; Final_Sigma;",
        ]:
            with self.subTest(row=row), self.assertRaises(ValueError):
                LOWER.lower_mappings([record("03A3", "03C3")], [row])
        for unicode in [[], [record("03A3", "03C2")]]:
            with self.subTest(unicode=unicode), self.assertRaisesRegex(ValueError, "default sigma"):
                LOWER.lower_mappings(unicode, ["03A3; 03C2; 03A3; 03A3; Final_Sigma;"])

    def test_malformed_duplicate_and_non_scalar_mappings_fail(self):
        for unicode, special in [
            (["0041;0061"], []), ([record("41", "0061")], []),
            ([record("00a1", "0061")], []), ([record("110000")], []),
            ([record("0041", "0061"), record("0041", "0062")], []),
            ([record("D800", "0061")], []), ([record("0041", "DFFF")], []),
            ([record("0041", "110000")], []), ([record("0041", "0061 0062")], []),
            ([], ["0041;0061"]), ([], ["0041;0061;0041;0041;tr;extra;"]),
            ([], ["D800; 0061; 0041; 0041;"]),
            ([], ["0041; DFFF; 0041; 0041;"]),
            ([], ["0041; 110000; 0041; 0041;"]),
            ([], ["0041; ; 0041; 0041;"]),
            ([], ["0041; 0061 0062 0063 0064; 0041; 0041;"]),
            ([], ["0041; 0061; 0041; 0041;", "0041; 0062; 0041; 0041;"]),
            ([], ["0041; 0061; 0041; 0041; tr;", "0041; 0062; 0041; 0041; tr;"]),
            ([record("03A3", "03C3")], ["03A3; 03C2; 03A3; 03A3; Final_Sigma;"] * 2),
        ]:
            with self.subTest(unicode=unicode, special=special), self.assertRaises(ValueError):
                LOWER.lower_mappings(unicode, special)
        # The official UnicodeData surrogate range markers carry no mapping.
        self.assertEqual(LOWER.lower_mappings([record("D800"), record("DFFF")], []), {})

    def test_fixed_context_properties_include_non_mapping_and_overlap_cases(self):
        properties = LOWER.case_properties(LOWER.read_derived_core_properties(LOWER.UCD).decode("utf-8").splitlines())
        for code in [0x41, 0x7A, 0x3A3, 0x3C2, 0x1F2, 0x13A0, 0xAB70, 0x1C89, 0x1C8A,
                     0x10D50, 0x10D70, 0x1F130]:
            with self.subTest(cased=code):
                self.assertTrue(contains(properties["Cased"], code))
                self.assertFalse(contains(properties["Case_Ignorable"], code))
        for code in [0x345, 0x2B0]:
            with self.subTest(overlap=code):
                self.assertTrue(contains(properties["Cased"], code))
                self.assertTrue(contains(properties["Case_Ignorable"], code))
        for code in [0x27, 0x2019, 0x301, 0x2BC, 0x200D, 0xFE0F, 0xE0100]:
            with self.subTest(ignorable=code):
                self.assertFalse(contains(properties["Cased"], code))
                self.assertTrue(contains(properties["Case_Ignorable"], code))
        for code in [0, 0x20, 0x2D, 0x65E5, 0x1F600, 0x0D, 0x0A, 0x10FFFF]:
            with self.subTest(neither=code):
                self.assertFalse(contains(properties["Cased"], code))
                self.assertFalse(contains(properties["Case_Ignorable"], code))
        for ranges in properties.values():
            self.assertTrue(all(first <= last for first, last in ranges))
            self.assertTrue(all(left[1] + 1 < right[0] for left, right in zip(ranges, ranges[1:])))

    def test_property_ranges_are_sorted_merged_and_independent(self):
        actual = LOWER.case_properties([
            "0044..0045; Cased # fixture", "0041..0043; Cased", "0345; Cased",
            "0345; Case_Ignorable", "0300..0301; Case_Ignorable",
            "0041..0045; Alphabetic", "094D; InCB; Linker",
        ])
        self.assertEqual(actual, {"Cased": [(0x41, 0x45), (0x345, 0x345)],
                                  "Case_Ignorable": [(0x300, 0x301), (0x345, 0x345)]})
        for code in [0x41, 0x45, 0x345]:
            self.assertTrue(contains(actual["Cased"], code))
        for code in [0x40, 0x46, 0x344, 0x346]:
            self.assertFalse(contains(actual["Cased"], code))

    def test_malformed_duplicate_and_overlapping_property_ranges_fail(self):
        baseline = ["0041..005A; Cased", "0300..036F; Case_Ignorable"]
        for row in [
            "0041", "0041; Cased; Y", "0041; Cased;", "0041; Cased; Y; extra",
            "0041; Case-Ignorable", "0041; InCB; Unknown", "0041; ",
            "0060..005B; Cased", "0041...0042; Cased", "0041..0042..0043; Cased",
            "0000410; Cased", "00a0; Cased", "110000; Cased", "D800; Cased",
            "D7FF..E000; Cased", "0041; Cased", "0040..0041; Cased", "005A..005B; Cased",
            "0301; Case_Ignorable", "02FF..0300; Case_Ignorable",
        ]:
            with self.subTest(row=row), self.assertRaises(ValueError):
                LOWER.case_properties(baseline + [row])
        for lines in [[], ["0041; Cased"], ["0300; Case_Ignorable"], ["0041; Alphabetic"]]:
            with self.subTest(lines=lines), self.assertRaisesRegex(ValueError, "missing lowercase context"):
                LOWER.case_properties(lines)

    def test_lower_manifest_reuses_originals_in_a_separate_identity_domain(self):
        pins = LOWER.read_sources(LOWER.UCD)
        self.assertEqual(set(pins), {"UnicodeData.txt", "SpecialCasing.txt", "DerivedCoreProperties.txt", "LICENSE.txt"})
        self.assertEqual(pins["DerivedCoreProperties.txt"],
                         "39d35161f2954497f69e08bdb9e701493f476a3d30222de20028feda36c1dabd")
        manifest = json.loads((LOWER.UCD / "lower-casing-manifest.json").read_text("utf-8"))
        self.assertEqual(manifest["compressed_source"], {
            "path": "DerivedCoreProperties.txt.xz",
            "sha256": "71dc893a4d7526af7aa680ee16744dd186cd799a75eae73417fc4a37a2f74405",
            "bytes": 88776, "uncompressed_bytes": 1115959,
        })
        raw = LOWER.read_derived_core_properties(LOWER.UCD)
        self.assertEqual(len(raw), 1115959)
        self.assertEqual(hashlib.sha256(raw).hexdigest(), pins["DerivedCoreProperties.txt"])
        self.assertFalse((LOWER.UCD / "DerivedCoreProperties.txt").exists())
        original = json.loads((LOWER.UCD / "manifest.json").read_text("utf-8"))
        upper = json.loads((LOWER.UCD / "casing-manifest.json").read_text("utf-8"))
        self.assertEqual(set(original["sha256"]), {
            "CaseFolding.txt", "UnicodeData.txt", "CompositionExclusions.txt",
            "DerivedNormalizationProps.txt", "NormalizationTest.txt", "LICENSE.txt",
        })
        self.assertNotIn("DerivedCoreProperties.txt", upper["source_sha256"])
        for name in ["UnicodeData.txt", "LICENSE.txt"]:
            self.assertEqual(pins[name], original["sha256"][name])
        for name in ["UnicodeData.txt", "SpecialCasing.txt", "LICENSE.txt"]:
            self.assertEqual(pins[name], upper["source_sha256"][name])

    def test_input_mutation_and_missing_sources_are_rejected(self):
        with tempfile.TemporaryDirectory(prefix="actql-lower-input-") as temp:
            directory = pathlib.Path(temp)
            copy_sources(directory)
            for name in LOWER.FILES:
                path = directory / ("DerivedCoreProperties.txt.xz" if name == "DerivedCoreProperties.txt" else name)
                original = path.read_bytes()
                with self.subTest(name=name, mutation="changed"):
                    path.write_bytes(original + b"# tampered\n")
                    error = "compressed source archive size mismatch" if name == "DerivedCoreProperties.txt" else "pinned lowercase input changed"
                    with self.assertRaisesRegex(ValueError, error):
                        LOWER.read_sources(directory)
                with self.subTest(name=name, mutation="missing"):
                    path.unlink()
                    with self.assertRaises(OSError):
                        LOWER.read_sources(directory)
                path.write_bytes(original)

    def test_manifest_shape_pins_and_adopted_originals_are_checked(self):
        with tempfile.TemporaryDirectory(prefix="actql-lower-manifest-") as temp:
            directory = pathlib.Path(temp)
            copy_sources(directory)
            path = directory / "lower-casing-manifest.json"
            original = json.loads(path.read_text("utf-8"))
            mutations = [[], {}, {**original, "extra": True}]
            for field, value in [("unicode_version", "15.0.0"), ("ucd_url", "https://example.invalid/"),
                                 ("license", "OTHER.txt"), ("operation", "default_full_uppercase"),
                                 ("source_sha256", []), ("source_sha256", {})]:
                mutations.append({**original, field: value})
            for field in original:
                changed = dict(original)
                del changed[field]
                mutations.append(changed)
            for name in LOWER.FILES:
                pins = dict(original["source_sha256"])
                del pins[name]
                mutations.append({**original, "source_sha256": pins})
            mutations.append({**original, "source_sha256": {**original["source_sha256"], "extra.txt": "0" * 64}})
            for digest in ["A" * 64, "0" * 63, "g" * 64, 123, None]:
                mutations.append({**original, "source_sha256": {**original["source_sha256"], "UnicodeData.txt": digest}})
            metadata = original["compressed_source"]
            for value in [[], {}, None, {**metadata, "extra": True}]:
                mutations.append({**original, "compressed_source": value})
            for field in metadata:
                changed = dict(metadata)
                del changed[field]
                mutations.append({**original, "compressed_source": changed})
            for field, values in [
                ("path", ["../DerivedCoreProperties.txt.xz", "/tmp/DerivedCoreProperties.txt.xz",
                          "DerivedCoreProperties.txt", "DerivedCoreProperties.txt.xz/..", None]),
                ("sha256", ["A" * 64, "0" * 63, "g" * 64, 123, None]),
                ("bytes", [True, 0, -1, 131073, 88776.0, "88776", None, 88775]),
                ("uncompressed_bytes", [True, 0, 1115958, 1115960, 1115959.0, "1115959", None]),
            ]:
                for value in values:
                    mutations.append({**original, "compressed_source": {**metadata, field: value}})
            mutations.append({**original, "source_sha256": {
                **original["source_sha256"], "DerivedCoreProperties.txt": metadata["sha256"],
            }})
            for manifest in mutations:
                with self.subTest(manifest=manifest), self.assertRaises(ValueError):
                    path.write_text(json.dumps(manifest), encoding="utf-8")
                    LOWER.read_sources(directory)
            path.write_text('{"unicode_version":"16.0.0","unicode_version":"16.0.0"}', encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "duplicate manifest field"):
                LOWER.read_sources(directory)
            path.write_text(json.dumps(original), encoding="utf-8")
            for filename, field, source in [
                ("manifest.json", "sha256", "UnicodeData.txt"),
                ("manifest.json", "sha256", "LICENSE.txt"),
                ("casing-manifest.json", "source_sha256", "SpecialCasing.txt"),
            ]:
                adopted_path = directory / filename
                adopted_bytes = adopted_path.read_bytes()
                adopted = json.loads(adopted_bytes)
                adopted[field][source] = "0" * 64
                adopted_path.write_text(json.dumps(adopted), encoding="utf-8")
                with self.subTest(adopted=filename, source=source), self.assertRaisesRegex(ValueError, "adopted Unicode originals"):
                    LOWER.read_sources(directory)
                adopted_path.write_bytes(adopted_bytes)

    def test_version_headers_are_verified_even_with_matching_pins(self):
        with tempfile.TemporaryDirectory(prefix="actql-lower-version-") as temp:
            directory = pathlib.Path(temp)
            copy_sources(directory)
            for name in ["SpecialCasing", "DerivedCoreProperties"]:
                path = directory / ("DerivedCoreProperties.txt.xz" if name == "DerivedCoreProperties" else f"{name}.txt")
                original_stored = path.read_bytes()
                original_raw = LOWER.read_derived_core_properties(directory) if name == "DerivedCoreProperties" else original_stored
                changed = original_raw.replace(f"# {name}-16.0.0.txt".encode(), f"# {name}-15.0.0.txt".encode(), 1)
                path.write_bytes(compress_fixture(changed) if name == "DerivedCoreProperties" else changed)
                manifests = {}
                for filename in ["lower-casing-manifest.json", "casing-manifest.json"]:
                    manifest_path = directory / filename
                    manifests[filename] = manifest_path.read_bytes()
                    manifest = json.loads(manifests[filename])
                    if f"{name}.txt" in manifest["source_sha256"]:
                        manifest["source_sha256"][f"{name}.txt"] = hashlib.sha256(changed).hexdigest()
                        if name == "DerivedCoreProperties":
                            manifest["compressed_source"] = archive_metadata(path.read_bytes())
                        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
                with self.subTest(name=name), self.assertRaisesRegex(ValueError, f"wrong {name} version"):
                    LOWER.read_sources(directory)
                path.write_bytes(original_stored)
                for filename, raw in manifests.items():
                    (directory / filename).write_bytes(raw)

    def test_compressed_source_accepts_an_independent_fixed_size_fixture(self):
        raw = b"Independent bounded XZ fixture\n".ljust(1115959, b"x")
        archive = compress_fixture(raw)
        with tempfile.TemporaryDirectory(prefix="actql-lower-xz-") as temp:
            directory = pathlib.Path(temp)
            (directory / "DerivedCoreProperties.txt.xz").write_bytes(archive)
            actual = LOWER.read_compressed_source(directory, archive_metadata(archive), hashlib.sha256(raw).hexdigest())
            self.assertEqual(actual, raw)

    def test_compressed_archive_and_official_raw_digests_are_independent(self):
        raw = b"Independent digest fixture\n".ljust(1115959, b"x")
        archive = compress_fixture(raw)
        with tempfile.TemporaryDirectory(prefix="actql-lower-xz-digest-") as temp:
            directory = pathlib.Path(temp)
            path = directory / "DerivedCoreProperties.txt.xz"
            path.write_bytes(archive)
            with self.assertRaisesRegex(ValueError, "archive digest mismatch"):
                LOWER.read_compressed_source(directory, {**archive_metadata(archive), "sha256": "0" * 64},
                                             hashlib.sha256(raw).hexdigest())
            with self.assertRaisesRegex(ValueError, "pinned lowercase input changed"):
                LOWER.read_compressed_source(directory, archive_metadata(archive), hashlib.sha256(archive).hexdigest())
            corrupted = archive[:-1] + bytes([archive[-1] ^ 1])
            path.write_bytes(corrupted)
            with self.assertRaisesRegex(ValueError, "archive digest mismatch"):
                LOWER.read_compressed_source(directory, archive_metadata(archive), hashlib.sha256(raw).hexdigest())

    def test_corrupt_truncated_and_extra_streams_are_rejected_after_archive_verification(self):
        raw = b"Independent stream fixture\n".ljust(1115959, b"x")
        archive = compress_fixture(raw)
        corrupted = archive[:32] + bytes([archive[32] ^ 1]) + archive[33:]
        cases = {
            "corruption": corrupted,
            "truncated header": archive[:8],
            "truncated trailer": archive[:-1],
            "trailing byte": archive + b"x",
            "concatenated stream": archive + compress_fixture(b"second stream"),
            "unprotected stream": lzma.compress(raw, format=lzma.FORMAT_XZ, check=lzma.CHECK_NONE, preset=6),
        }
        with tempfile.TemporaryDirectory(prefix="actql-lower-xz-stream-") as temp:
            directory = pathlib.Path(temp)
            for label, changed in cases.items():
                (directory / "DerivedCoreProperties.txt.xz").write_bytes(changed)
                # Matching archive pins exercise stream checks, not the digest guard.
                with self.subTest(label=label), self.assertRaises(ValueError):
                    LOWER.read_compressed_source(directory, archive_metadata(changed), hashlib.sha256(raw).hexdigest())

    def test_compressed_source_read_and_decode_sizes_are_bounded(self):
        with tempfile.TemporaryDirectory(prefix="actql-lower-xz-bound-") as temp:
            directory = pathlib.Path(temp)
            path = directory / "DerivedCoreProperties.txt.xz"
            oversized = b"x" * 131073
            path.write_bytes(oversized)
            metadata = {**archive_metadata(oversized), "bytes": 131072}
            with self.assertRaisesRegex(ValueError, "archive size exceeds bound"):
                LOWER.read_compressed_source(directory, metadata, "0" * 64)
            for size in [1115958, 1115960, 2 * 1115959]:
                raw = b"x" * size
                archive = compress_fixture(raw)
                path.write_bytes(archive)
                with self.subTest(size=size), self.assertRaisesRegex(ValueError, "uncompressed size mismatch"):
                    LOWER.read_compressed_source(directory, archive_metadata(archive), hashlib.sha256(raw).hexdigest())

    def test_invalid_compressed_input_never_creates_or_repairs_generated_output(self):
        with tempfile.TemporaryDirectory(prefix="actql-lower-xz-cli-") as temp:
            root = pathlib.Path(temp)
            script = root / "scripts/generate-unicode-lower.py"
            script.parent.mkdir()
            shutil.copyfile(ROOT / "scripts/generate-unicode-lower.py", script)
            directory = root / "vendor/unicode/16.0.0"
            directory.mkdir(parents=True)
            copy_sources(directory)
            path = directory / "DerivedCoreProperties.txt.xz"
            truncated = path.read_bytes()[:-1]
            path.write_bytes(truncated)
            manifest_path = directory / "lower-casing-manifest.json"
            manifest = json.loads(manifest_path.read_text("utf-8"))
            manifest["compressed_source"] = archive_metadata(truncated)
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            output = root / "lower.mbt"
            for existing in [False, True]:
                if existing:
                    output.write_bytes(b"unchanged generated fixture\n")
                for mode in [[], ["--check"]]:
                    command = [sys.executable, str(script), "--output", str(output), *mode]
                    with self.subTest(existing=existing, mode=mode):
                        result = subprocess.run(command, cwd=root, capture_output=True)
                        self.assertNotEqual(result.returncode, 0)
                        self.assertIn(b"compressed source", result.stderr)
                        if existing:
                            self.assertEqual(output.read_bytes(), b"unchanged generated fixture\n")
                        else:
                            self.assertFalse(output.exists())
                        self.assertFalse((directory / "DerivedCoreProperties.txt").exists())

    def test_freshness_never_repairs_outputs_or_changes_existing_identity_domains(self):
        protected = [LOWER.UCD / "manifest.json", LOWER.UCD / "casing-manifest.json",
                     LOWER.UCD / "lower-casing-manifest.json", LOWER.UCD / "DerivedCoreProperties.txt.xz",
                     ROOT / "src/decode_scalar/unicode_upper.generated.mbt",
                     ROOT / "src/canonical_value/unicode_tables.generated.mbt",
                     ROOT / "spec/dependencies/actql-text-time-unicode-data.json",
                     ROOT / "portability/profiles/text-rank-unicode16.json"]
        before = {path: hashlib.sha256(path.read_bytes()).hexdigest() for path in protected}
        command = [sys.executable, str(ROOT / "scripts/generate-unicode-lower.py")]
        subprocess.run(command + ["--check"], cwd=ROOT, check=True, capture_output=True)
        with tempfile.TemporaryDirectory(prefix="actql-lower-output-") as temp:
            output = pathlib.Path(temp) / "lower.mbt"
            result = subprocess.run(command + ["--check", "--output", str(output)], cwd=ROOT, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(output.exists())
            subprocess.run(command + ["--output", str(output)], cwd=ROOT, check=True, capture_output=True)
            self.assertEqual(output.read_bytes(), LOWER.OUT.read_bytes())
            output.write_bytes(b"stale fixture\n")
            result = subprocess.run(command + ["--check", "--output", str(output)], cwd=ROOT, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(output.read_bytes(), b"stale fixture\n")
        self.assertEqual(before, {path: hashlib.sha256(path.read_bytes()).hexdigest() for path in protected})
        self.assertFalse((LOWER.UCD / "DerivedCoreProperties.txt").exists())
