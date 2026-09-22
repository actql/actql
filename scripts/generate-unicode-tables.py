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
    "UnicodeData.txt", "CompositionExclusions.txt", "DerivedNormalizationProps.txt",
    "NormalizationTest.txt", "LICENSE.txt", "CaseFolding.txt",
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
        raise ValueError("sha256 must contain exactly the required input files")
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


def read_nfc_quick_check(path: pathlib.Path) -> tuple[set[int], set[int]]:
    """Read the pinned UCD NFC_QC=No/Maybe properties, defaulting to Yes."""
    no: set[int] = set()
    maybe: set[int] = set()
    for raw in path.read_text(encoding="utf-8").splitlines():
        body = raw.split("#", 1)[0].strip()
        if not body:
            continue
        fields = [field.strip() for field in body.split(";")]
        if len(fields) < 3 or fields[1] != "NFC_QC":
            continue
        if fields[2] not in {"N", "M"}:
            raise ValueError("unexpected NFC_QC value")
        ends = fields[0].split("..")
        if len(ends) > 2:
            raise ValueError("invalid NFC_QC range")
        start = int(ends[0], 16)
        end = int(ends[-1], 16)
        if start > end or end > 0x10FFFF:
            raise ValueError("invalid NFC_QC code point")
        values = set(range(start, end + 1))
        if values & (no | maybe):
            raise ValueError("overlapping NFC_QC entries")
        (no if fields[2] == "N" else maybe).update(values)
    if not no or not maybe:
        raise ValueError("NFC_QC No and Maybe values are required")
    return no, maybe


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


def assigned_scalars(lines: list[str]) -> set[int]:
    """Expand UCD First/Last records, excluding UTF-16 surrogate code points."""
    assigned: set[int] = set()
    pending: tuple[int, str, str] | None = None
    for raw in lines:
        fields = raw.split(";")
        cp, name, category = int(fields[0], 16), fields[1], fields[2]
        if not 0 <= cp <= 0x10FFFF:
            raise ValueError("code point outside Unicode range")
        if name.endswith(", First>"):
            if pending is not None:
                raise ValueError("nested UCD range")
            pending = (cp, name.removesuffix(", First>"), category)
        elif name.endswith(", Last>"):
            if pending is None:
                raise ValueError("UCD range end without start")
            start, prefix, first_category = pending
            if cp < start or name != prefix + ", Last>" or category != first_category:
                raise ValueError("mismatched UCD range")
            assigned.update(range(start, cp + 1))
            pending = None
        else:
            if pending is not None:
                raise ValueError("unterminated UCD range")
            assigned.add(cp)
    if pending is not None:
        raise ValueError("unterminated UCD range")
    assigned.difference_update(range(0xD800, 0xE000))
    return assigned


def normalization_cases(lines: list[str]) -> tuple[list[tuple[str, ...]], set[int]]:
    cases: list[tuple[str, ...]] = []
    part1: set[int] = set()
    section = ""
    saw_part1 = False
    for raw in lines:
        body = raw.split("#", 1)[0].strip()
        if not body:
            continue
        if body.startswith("@"):
            section = body
            saw_part1 |= section == "@Part1"
            continue
        fields = tuple(field.strip() for field in body.split(";")[:5])
        if len(fields) != 5 or any(not field for field in fields):
            raise ValueError("normalization case requires five nonempty columns")
        cases.append(fields)
        if section == "@Part1":
            source = fields[0].split()
            if len(source) != 1:
                raise ValueError("Part1 source must be a single code point")
            part1.add(int(source[0], 16))
    if not saw_part1:
        raise ValueError("NormalizationTest is missing Part1")
    return cases, part1


def contiguous_ranges(values: set[int]) -> list[tuple[int, int]]:
    ranges: list[tuple[int, int]] = []
    for cp in sorted(values):
        if ranges and cp == ranges[-1][1] + 1:
            ranges[-1] = (ranges[-1][0], cp)
        else:
            ranges.append((cp, cp))
    return ranges


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
    unicode_lines = unicode_data.read_text(encoding="utf-8").splitlines()
    for raw in unicode_lines:
        fields = raw.split(";")
        cp = int(fields[0], 16)
        combining = int(fields[3])
        if not 0 <= combining <= 255:
            raise ValueError("canonical combining class must be in 0..255")
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
    # Use Unicode's pinned NFC_QC property, not a reimplementation inferred
    # from decomposition and composition tables. The runtime also checks CCC
    # ordering, as required for a definitive Yes result on a full string.
    nfc_no, nfc_maybe = read_nfc_quick_check(UCD / "DerivedNormalizationProps.txt")
    sources = {
        name: hashlib.sha256((UCD / name).read_bytes()).hexdigest()
        for name in (
            "UnicodeData.txt", "CompositionExclusions.txt",
            "DerivedNormalizationProps.txt", "NormalizationTest.txt",
        )
    }

    text = f'''// Generated by scripts/generate-unicode-tables.py.
// Derived from Unicode data. License: ../../vendor/unicode/16.0.0/LICENSE.txt
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

///|
let nfc_qc_no_scalar_keys : FixedArray[Int] = [
{wrap([hex(value) for value in sorted(nfc_no)])}
]

///|
let nfc_qc_maybe_scalar_keys : FixedArray[Int] = [
{wrap([hex(value) for value in sorted(nfc_maybe)])}
]
'''
    emit(output, text)
    cases, part1 = normalization_cases(
        (UCD / "NormalizationTest.txt").read_text(encoding="utf-8").splitlines()
    )
    unchanged = assigned_scalars(unicode_lines) - part1
    unchanged_ranges = contiguous_ranges(unchanged)
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
            "    assert_eq(normalize_nfc(case.0), Ok(case.1))\n"
            "    assert_eq(normalize_nfc(case.1), Ok(case.1))\n"
            "    assert_eq(normalize_nfc(case.2), Ok(case.1))\n"
            "    assert_eq(normalize_nfc(case.3), Ok(case.3))\n"
            "    assert_eq(normalize_nfc(case.4), Ok(case.3))\n"
            "  }"
        )
    chunks_text = "\n\n".join(rendered_chunks)
    loops_text = "\n".join(rendered_loops)
    emit(
        test_output,
        f'''// Generated by scripts/generate-unicode-tables.py.
// Derived from Unicode data. License: ../../vendor/unicode/16.0.0/LICENSE.txt
// Unicode 16.0.0 NFC: listed cases and assigned scalars outside Part1.

{chunks_text}

///|
test "Unicode 16.0.0 NormalizationTest NFC" {{
{loops_text}
}}

///|
let normalization_unchanged_ranges : FixedArray[(Int, Int)] = [
{wrap([f"({hex(start)}, {hex(end)})" for start, end in unchanged_ranges])}
]

///|
test "Unicode 16.0.0 NFC assigned scalars outside Part1" {{
  for (start, end) in normalization_unchanged_ranges {{
    for scalar = start; scalar <= end; scalar = scalar + 1 {{
      let value = String::from_array([scalar.unsafe_to_char()])
      assert_eq(normalize_nfc(value), Ok(value))
    }}
  }}
}}
''',
    )
    if mismatches:
        print("generated Unicode files differ: " + ", ".join(mismatches), file=sys.stderr)
        return 1
    print(
        f"{'checked' if check else 'generated'} {output}: {len(decomp_keys)} decompositions, "
        f"{len(ccc_keys)} combining classes, {len(compositions)} compositions, "
        f"{len(cases)} normalization cases, {len(unchanged)} unchanged scalars"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
