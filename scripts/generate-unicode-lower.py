#!/usr/bin/env python3
"""Generate shared Unicode 16 default full-lowercase and context-property tables."""

from __future__ import annotations

import argparse
import hashlib
import json
import lzma
import pathlib
import re
import sys


ROOT = pathlib.Path(__file__).resolve().parents[1]
UCD = ROOT / "vendor" / "unicode" / "16.0.0"
OUT = ROOT / "src" / "decode_scalar" / "unicode_lower.generated.mbt"
FILES = {"UnicodeData.txt", "SpecialCasing.txt", "DerivedCoreProperties.txt", "LICENSE.txt"}
UPPER_FILES = {"UnicodeData.txt", "SpecialCasing.txt", "LICENSE.txt"}
ORIGINAL_FILES = {
    "CaseFolding.txt", "UnicodeData.txt", "CompositionExclusions.txt",
    "DerivedNormalizationProps.txt", "NormalizationTest.txt", "LICENSE.txt",
}
PROPERTIES = {"Cased", "Case_Ignorable"}
COMPRESSED_PATH = "DerivedCoreProperties.txt.xz"
MAX_ARCHIVE_BYTES = 128 * 1024
DERIVED_CORE_BYTES = 1115959
DECOMPRESSION_MEMORY_LIMIT = 16 * 1024 * 1024


def code_point(text: str) -> int:
    if not re.fullmatch(r"[0-9A-F]{4,6}", text):
        raise ValueError("invalid lowercase code point")
    value = int(text, 16)
    if value > 0x10FFFF:
        raise ValueError("lowercase code point outside Unicode range")
    return value


def scalar(text: str) -> int:
    value = code_point(text)
    if 0xD800 <= value <= 0xDFFF:
        raise ValueError("lowercase data contains a non-scalar")
    return value


def unique_object(pairs: list[tuple[str, object]]) -> dict:
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate manifest field: {key}")
        result[key] = value
    return result


def compressed_metadata(value: object) -> dict:
    if not isinstance(value, dict) or set(value) != {"path", "sha256", "bytes", "uncompressed_bytes"}:
        raise ValueError("unexpected compressed source fields")
    if value["path"] != COMPRESSED_PATH:
        raise ValueError("unexpected compressed source path")
    if not isinstance(value["sha256"], str) or not re.fullmatch(r"[0-9a-f]{64}", value["sha256"]):
        raise ValueError("invalid compressed source digest")
    if type(value["bytes"]) is not int or not 0 < value["bytes"] <= MAX_ARCHIVE_BYTES:
        raise ValueError("compressed source archive size exceeds bound or is invalid")
    if type(value["uncompressed_bytes"]) is not int or value["uncompressed_bytes"] != DERIVED_CORE_BYTES:
        raise ValueError("unexpected compressed source uncompressed size")
    return value


def read_manifest(path: pathlib.Path, files: set[str], operation: str | None) -> dict:
    manifest = json.loads(path.read_text("utf-8"), object_pairs_hook=unique_object)
    fields = {"unicode_version", "ucd_url", "license"}
    digest_field = "sha256" if operation is None else "source_sha256"
    fields.add(digest_field)
    if operation is not None:
        fields.add("operation")
    if operation == "default_full_lowercase":
        fields.add("compressed_source")
    if not isinstance(manifest, dict) or set(manifest) != fields:
        raise ValueError(f"unexpected manifest fields: {path.name}")
    if (manifest["unicode_version"] != "16.0.0"
            or manifest["ucd_url"] != "https://www.unicode.org/Public/16.0.0/ucd/"
            or manifest["license"] != "LICENSE.txt"
            or (operation is not None and manifest["operation"] != operation)):
        raise ValueError(f"unexpected source contract: {path.name}")
    pins = manifest[digest_field]
    if not isinstance(pins, dict) or set(pins) != files:
        raise ValueError(f"pins must name exactly the required inputs: {path.name}")
    for digest in pins.values():
        if not isinstance(digest, str) or not re.fullmatch(r"[0-9a-f]{64}", digest):
            raise ValueError(f"invalid source digest: {path.name}")
    if operation == "default_full_lowercase":
        compressed_metadata(manifest["compressed_source"])
    return manifest


def manifest_pins(path: pathlib.Path, files: set[str], operation: str | None) -> dict[str, str]:
    manifest = read_manifest(path, files, operation)
    return manifest["sha256" if operation is None else "source_sha256"]


def read_compressed_source(directory: pathlib.Path, metadata: dict, expected_sha256: str) -> bytes:
    metadata = compressed_metadata(metadata)
    # Bound the read before decoding, even if the declared archive size is false.
    with (directory / COMPRESSED_PATH).open("rb") as source:
        archive = source.read(MAX_ARCHIVE_BYTES + 1)
    if len(archive) > MAX_ARCHIVE_BYTES:
        raise ValueError("compressed source archive size exceeds bound")
    if len(archive) != metadata["bytes"]:
        raise ValueError("compressed source archive size mismatch")
    if hashlib.sha256(archive).hexdigest() != metadata["sha256"]:
        raise ValueError("compressed source archive digest mismatch")
    try:
        decoder = lzma.LZMADecompressor(format=lzma.FORMAT_XZ, memlimit=DECOMPRESSION_MEMORY_LIMIT)
        raw = decoder.decompress(archive, max_length=metadata["uncompressed_bytes"] + 1)
    except lzma.LZMAError as error:
        raise ValueError(f"invalid compressed source stream: {error}") from error
    if len(raw) != metadata["uncompressed_bytes"]:
        raise ValueError("compressed source uncompressed size mismatch")
    if not decoder.eof:
        raise ValueError("incomplete compressed source stream")
    if decoder.unused_data:
        raise ValueError("trailing data or concatenated compressed source streams")
    if decoder.check != lzma.CHECK_CRC64:
        raise ValueError("unexpected compressed source integrity check")
    if hashlib.sha256(raw).hexdigest() != expected_sha256:
        raise ValueError("pinned lowercase input changed: DerivedCoreProperties.txt")
    return raw


def read_derived_core_properties(directory: pathlib.Path) -> bytes:
    manifest = read_manifest(directory / "lower-casing-manifest.json", FILES, "default_full_lowercase")
    return read_compressed_source(directory, manifest["compressed_source"],
                                  manifest["source_sha256"]["DerivedCoreProperties.txt"])


def read_sources(directory: pathlib.Path) -> dict[str, str]:
    manifest = read_manifest(directory / "lower-casing-manifest.json", FILES, "default_full_lowercase")
    pins = manifest["source_sha256"]
    derived_core = read_compressed_source(directory, manifest["compressed_source"], pins["DerivedCoreProperties.txt"])
    for name, expected in pins.items():
        if name == "DerivedCoreProperties.txt":
            continue
        if hashlib.sha256((directory / name).read_bytes()).hexdigest() != expected:
            raise ValueError(f"pinned lowercase input changed: {name}")
    # LOWER adds a separate identity domain. It must reuse the adopted originals
    # without expanding either the UPPER manifest or the NFC/text-rank manifest.
    upper = manifest_pins(directory / "casing-manifest.json", UPPER_FILES, "default_full_uppercase")
    original = manifest_pins(directory / "manifest.json", ORIGINAL_FILES, None)
    if (any(pins[name] != upper[name] for name in UPPER_FILES)
            or any(pins[name] != original[name] for name in {"UnicodeData.txt", "LICENSE.txt"})):
        raise ValueError("lowercase inputs differ from the adopted Unicode originals")
    for name, text in [("SpecialCasing", (directory / "SpecialCasing.txt").read_text("utf-8")),
                       ("DerivedCoreProperties", derived_core.decode("utf-8"))]:
        if not text.startswith(f"# {name}-16.0.0.txt\n"):
            raise ValueError(f"wrong {name} version")
    return pins


def lower_mappings(unicode_lines: list[str], special_lines: list[str]) -> dict[int, tuple[int, ...]]:
    mappings: dict[int, tuple[int, ...]] = {}
    seen: set[int] = set()
    for line in unicode_lines:
        fields = line.split(";")
        if len(fields) != 15:
            raise ValueError("invalid UnicodeData record")
        code = code_point(fields[0])
        if code in seen:
            raise ValueError("duplicate UnicodeData code point")
        seen.add(code)
        # UnicodeData contains surrogate range markers, but these cannot own a
        # lowercase mapping. Field 13 is Simple_Lowercase_Mapping (zero based).
        if fields[13]:
            mappings[scalar(fields[0])] = (scalar(fields[13]),)
    seen_special: set[tuple[int, str]] = set()
    has_final_sigma = False
    for raw in special_lines:
        body = raw.split("#", 1)[0].strip()
        if not body:
            continue
        fields = [part.strip() for part in body.split(";")]
        if fields[-1] == "":
            fields.pop()
        if len(fields) not in (4, 5):
            raise ValueError("invalid SpecialCasing record")
        code = scalar(fields[0])
        columns = [tuple(scalar(part) for part in field.split()) for field in fields[1:4]]
        if any(len(column) > 3 for column in columns):
            raise ValueError("invalid SpecialCasing expansion")
        mapped = columns[0]
        condition = " ".join(fields[4].split()) if len(fields) == 5 else ""
        key = (code, condition)
        if key in seen_special:
            raise ValueError("duplicate SpecialCasing record")
        seen_special.add(key)
        if condition:
            # Locale tailoring is deliberately outside default casing. Locale
            # rows may contain deletions; unconditional lowercase may not.
            if condition.split()[0] in {"lt", "tr", "az"}:
                continue
            if code != 0x03A3 or condition != "Final_Sigma" or mapped != (0x03C2,):
                raise ValueError("unsupported root-context lowercase change")
            has_final_sigma = True
            continue
        if not mapped:
            raise ValueError("empty unconditional lowercase mapping")
        # SpecialCasing full lowercase replaces the simple UnicodeData field.
        # Preserve scalar order exactly; do not normalize the expansion.
        mappings[code] = mapped
    if has_final_sigma and mappings.get(0x03A3) != (0x03C3,):
        raise ValueError("Final_Sigma requires the default sigma mapping")
    # The runtime evaluates the approved Final_Sigma condition on original
    # input scalars using the pinned properties, before choosing this table.
    return {code: mapped for code, mapped in mappings.items() if mapped != (code,)}


def case_properties(lines: list[str]) -> dict[str, list[tuple[int, int]]]:
    properties: dict[str, list[tuple[int, int]]] = {name: [] for name in PROPERTIES}
    for raw in lines:
        body = raw.split("#", 1)[0].strip()
        if not body:
            continue
        fields = [part.strip() for part in body.split(";")]
        if len(fields) not in (2, 3) or not re.fullmatch(r"[A-Za-z_]+", fields[1]):
            raise ValueError("invalid DerivedCoreProperties record")
        if len(fields) == 3 and (fields[1] != "InCB" or fields[2] not in {"Linker", "Consonant", "Extend"}):
            raise ValueError("unexpected DerivedCoreProperties value")
        ends = fields[0].split("..")
        if len(ends) not in (1, 2):
            raise ValueError("invalid DerivedCoreProperties range")
        first, last = scalar(ends[0]), scalar(ends[-1])
        if first > last or first <= 0xDFFF and last >= 0xD800:
            raise ValueError("invalid DerivedCoreProperties scalar range")
        if fields[1] in PROPERTIES:
            properties[fields[1]].append((first, last))
    for name, ranges in properties.items():
        if not ranges:
            raise ValueError(f"missing lowercase context property: {name}")
        merged: list[tuple[int, int]] = []
        for first, last in sorted(ranges):
            if merged and first <= merged[-1][1]:
                raise ValueError(f"overlapping lowercase context ranges: {name}")
            if merged and first == merged[-1][1] + 1:
                merged[-1] = (merged[-1][0], last)
            else:
                merged.append((first, last))
        properties[name] = merged
    # Cased and Case_Ignorable intentionally overlap. Do not subtract either
    # property from the other: Final_Sigma gives Case_Ignorable precedence.
    return properties


def table_text(mappings: dict[int, tuple[int, ...]],
               properties: dict[str, list[tuple[int, int]]], pins: dict[str, str]) -> str:
    entries = sorted(mappings.items())
    keys = "\n".join("  " + ", ".join(f"0x{code:x}" for code, _ in entries[i:i + 10]) + ","
                     for i in range(0, len(entries), 10))
    strings = ['"' + "".join(f"\\u{{{cp:x}}}" for cp in mapped) + '"' for _, mapped in entries]
    values = "\n".join("  " + ", ".join(strings[i:i + 8]) + "," for i in range(0, len(strings), 8))
    text = f'''// Generated by scripts/generate-unicode-lower.py; do not edit.
// Unicode 16.0.0 default full lowercase and Final_Sigma context properties.
// No normalization or locale tailoring. Runtime owns Final_Sigma selection.
// Source license: ../../vendor/unicode/16.0.0/LICENSE.txt
// UnicodeData.txt sha256: {pins["UnicodeData.txt"]}
// SpecialCasing.txt sha256: {pins["SpecialCasing.txt"]}
// DerivedCoreProperties.txt sha256: {pins["DerivedCoreProperties.txt"]}
// LICENSE.txt sha256: {pins["LICENSE.txt"]}

///|
let unicode_lower_keys : FixedArray[Int] = [
{keys}
]

///|
let unicode_lower_values : FixedArray[String] = [
{values}
]
'''
    for property_name, table_name in [
        ("Cased", "unicode_cased_ranges"), ("Case_Ignorable", "unicode_case_ignorable_ranges"),
    ]:
        ranges = properties[property_name]
        items = [f"(0x{first:x}, 0x{last:x})" for first, last in ranges]
        body = "\n".join("  " + ", ".join(items[i:i + 4]) + "," for i in range(0, len(items), 4))
        text += f'''
///|
let {table_name} : FixedArray[(Int, Int)] = [
{body}
]
'''
    return text


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--output", type=pathlib.Path, default=OUT)
    args = parser.parse_args()
    try:
        pins = read_sources(UCD)
        mappings = lower_mappings((UCD / "UnicodeData.txt").read_text("utf-8").splitlines(),
                                  (UCD / "SpecialCasing.txt").read_text("utf-8").splitlines())
        properties = case_properties(read_derived_core_properties(UCD).decode("utf-8").splitlines())
        text = table_text(mappings, properties, pins).encode("utf-8")
        if args.check:
            if not args.output.is_file() or args.output.read_bytes() != text:
                raise ValueError("generated Unicode lowercase table is stale")
        else:
            args.output.write_bytes(text)
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f"Unicode lowercase generation failed: {error}", file=sys.stderr)
        return 1
    counts = ", ".join(f"{len(properties[name])} {name} ranges" for name in sorted(PROPERTIES))
    print(f"{'checked' if args.check else 'generated'} {args.output}: {len(mappings)} lowercase mappings, {counts}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
