#!/usr/bin/env python3
"""Generate compact MoonBit NFC tables from the pinned Unicode 16.0 UCD."""

from __future__ import annotations

import argparse
import json
import hashlib
import pathlib
import re
import sys


ROOT = pathlib.Path(__file__).resolve().parents[1]
UCD = ROOT / "vendor" / "unicode" / "16.0.0"
OUT = ROOT / "src" / "canonical_value" / "unicode_tables.generated.mbt"
TEST_OUT = ROOT / "src" / "canonical_value" / "normalization_conformance.generated_test.mbt"
REQUIRED_INPUTS = {
    "UnicodeData.txt", "CompositionExclusions.txt", "NormalizationTest.txt", "LICENSE.txt",
}


def validate_manifest(manifest: object) -> dict[str, str]:
    if not isinstance(manifest, dict):
        raise ValueError("manifest must be an object")
    if manifest.get("unicode_version") != "16.0.0":
        raise ValueError("unicode_version must be 16.0.0")
    if manifest.get("license") != "LICENSE.txt":
        raise ValueError("license must be LICENSE.txt")
    pins = manifest.get("sha256")
    if not isinstance(pins, dict) or set(pins) != REQUIRED_INPUTS:
        raise ValueError("sha256 must contain exactly the four required input files")
    for name, digest in pins.items():
        if not isinstance(digest, str) or re.fullmatch(r"[0-9a-f]{64}", digest) is None:
            raise ValueError(f"invalid SHA-256 digest: {name}")
    return pins


def read_exclusions(path: pathlib.Path) -> set[int]:
    result: set[int] = set()
    for raw in path.read_text(encoding="utf-8").splitlines():
        body = raw.split("#", 1)[0].strip()
        if body:
            result.add(int(body, 16))
    return result


def wrap(values: list[str], width: int = 96) -> str:
    lines: list[str] = []
    current = "  "
    for value in values:
        item = value + ","
        if len(current) + len(item) + 1 > width:
            lines.append(current.rstrip())
            current = "  " + item + " "
        else:
            current += item + " "
    if current.strip():
        lines.append(current.rstrip())
    return "\n".join(lines)


def moonbit_string(codepoints: str) -> str:
    escaped = "".join(f"\\u{{{part}}}" for part in codepoints.split())
    return f'"{escaped}"'


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--verify-inputs", action="store_true")
    parser.add_argument("--output-dir", type=pathlib.Path, default=OUT.parent)
    args = parser.parse_args()
    check = args.check
    try:
        manifest = json.loads((UCD / "manifest.json").read_text(encoding="utf-8"))
        pins = validate_manifest(manifest)
    except (OSError, ValueError) as error:
        print(f"Invalid Unicode manifest: {error}", file=sys.stderr)
        return 1
    for name, expected in pins.items():
        path = UCD / name
        if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            print(f"Pinned Unicode input missing or changed: {name}", file=sys.stderr)
            return 1
    if args.verify_inputs:
        print("Unicode 16.0.0 inputs verified")
        return 0
    output = args.output_dir / OUT.name
    test_output = args.output_dir / TEST_OUT.name
    mismatches: list[str] = []

    def emit(path: pathlib.Path, text: str) -> None:
        if check:
            if not path.is_file() or path.read_bytes() != text.encode("utf-8"):
                mismatches.append(str(path))
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding="utf-8")

    unicode_data = UCD / "UnicodeData.txt"
    exclusions_file = UCD / "CompositionExclusions.txt"
    if not unicode_data.is_file() or not exclusions_file.is_file():
        print("Pinned Unicode 16.0 UCD files are missing", file=sys.stderr)
        return 1

    exclusions = read_exclusions(exclusions_file)
    ccc: dict[int, int] = {}
    decompositions: dict[int, list[int]] = {}
    compositions: list[tuple[int, int, int]] = []
    for raw in unicode_data.read_text(encoding="utf-8").splitlines():
        fields = raw.split(";")
        cp = int(fields[0], 16)
        combining = int(fields[3])
        if combining:
            ccc[cp] = combining
        decomposition = fields[5]
        if decomposition and not decomposition.startswith("<"):
            seq = [int(part, 16) for part in decomposition.split()]
            decompositions[cp] = seq
    for cp, seq in decompositions.items():
        # Full_Composition_Exclusion also excludes canonical decompositions
        # whose first element is not a starter (for example U+0344).
        if len(seq) == 2 and cp not in exclusions and ccc.get(seq[0], 0) == 0:
            compositions.append((seq[0], seq[1], cp))

    decomp_keys = sorted(decompositions)
    decomp_offsets = [0]
    decomp_data: list[int] = []
    for cp in decomp_keys:
        decomp_data.extend(decompositions[cp])
        decomp_offsets.append(len(decomp_data))

    ccc_keys = sorted(ccc)
    compositions.sort()
    composition_keys = [(a << 21) | b for a, b, _ in compositions]
    composition_values = [result for _, _, result in compositions]
    sources = {
        name: hashlib.sha256((UCD / name).read_bytes()).hexdigest()
        for name in ("UnicodeData.txt", "CompositionExclusions.txt", "NormalizationTest.txt")
    }

    text = f'''// Generated by scripts/generate-unicode-tables.py.
// Unicode version: 16.0.0
// UnicodeData.txt sha256: {sources["UnicodeData.txt"]}
// CompositionExclusions.txt sha256: {sources["CompositionExclusions.txt"]}
// NormalizationTest.txt sha256: {sources["NormalizationTest.txt"]}

///|
let canonical_decomposition_keys : FixedArray[Int] = [
{wrap([hex(value) for value in decomp_keys])}
]

///|
let canonical_decomposition_offsets : FixedArray[Int] = [
{wrap([str(value) for value in decomp_offsets])}
]

///|
let canonical_decomposition_data : FixedArray[Int] = [
{wrap([hex(value) for value in decomp_data])}
]

///|
let canonical_combining_class_keys : FixedArray[Int] = [
{wrap([hex(value) for value in ccc_keys])}
]

///|
let canonical_combining_class_values : FixedArray[Int] = [
{wrap([str(ccc[value]) for value in ccc_keys])}
]

///|
let canonical_composition_keys : FixedArray[Int64] = [
{wrap([str(value) + "L" for value in composition_keys])}
]

///|
let canonical_composition_values : FixedArray[Int] = [
{wrap([hex(value) for value in composition_values])}
]
'''
    emit(output, text)
    cases: list[tuple[str, str, str, str, str]] = []
    for raw in (UCD / "NormalizationTest.txt").read_text(encoding="utf-8").splitlines():
        body = raw.split("#", 1)[0].strip()
        if not body or body.startswith("@"):
            continue
        fields = [field.strip() for field in body.split(";")]
        cases.append(tuple(fields[:5]))
    # MoonBit splits top-level declarations into text segments. Keeping the
    # complete Unicode corpus in one 20k-line literal eventually crosses that
    # limit, so generated fixtures are intentionally sharded. This is a source
    # layout concern only; the normative order and test coverage are unchanged.
    case_chunks = [cases[index : index + 4000] for index in range(0, len(cases), 4000)]
    rendered_chunks = []
    rendered_loops = []
    for index, chunk in enumerate(case_chunks):
        rendered_cases = "\n".join(
            "  (" + ", ".join(moonbit_string(field) for field in case) + "),"
            for case in chunk
        )
        rendered_chunks.append(
            "///|\n"
            f"let normalization_conformance_cases_{index} : "
            "FixedArray[(String, String, String, String, String)] = [\n"
            f"{rendered_cases}\n"
            "]"
        )
        rendered_loops.append(
            f"  for case in normalization_conformance_cases_{index} {{\n"
            "    assert_eq(normalize_nfc_lf(case.0), Ok(case.1))\n"
            "    assert_eq(normalize_nfc_lf(case.1), Ok(case.1))\n"
            "    assert_eq(normalize_nfc_lf(case.2), Ok(case.1))\n"
            "    assert_eq(normalize_nfc_lf(case.3), Ok(case.3))\n"
            "    assert_eq(normalize_nfc_lf(case.4), Ok(case.3))\n"
            "  }"
        )
    chunks_text = "\n\n".join(rendered_chunks)
    loops_text = "\n".join(rendered_loops)
    emit(
        test_output,
        f'''// Generated by scripts/generate-unicode-tables.py.
// Full Unicode 16.0.0 NormalizationTest NFC conformance corpus.

{chunks_text}

///|
test "Unicode 16.0.0 NormalizationTest NFC" {{
{loops_text}
}}
''',
    )
    if mismatches:
        print("generated Unicode files differ: " + ", ".join(mismatches), file=sys.stderr)
        return 1
    print(
        f"{'checked' if check else 'generated'} {output}: {len(decomp_keys)} decompositions, "
        f"{len(ccc_keys)} combining classes, {len(compositions)} compositions, "
        f"{len(cases)} normalization cases"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
