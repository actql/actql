#!/usr/bin/env python3
"""Generate the shared Unicode 16 default full-uppercase mapping table."""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import re
import sys


ROOT = pathlib.Path(__file__).resolve().parents[1]
UCD = ROOT / "vendor" / "unicode" / "16.0.0"
OUT = ROOT / "src" / "decode_scalar" / "unicode_upper.generated.mbt"
FILES = {"UnicodeData.txt", "SpecialCasing.txt", "LICENSE.txt"}


def scalar(text: str) -> int:
    if not re.fullmatch(r"[0-9A-F]{4,6}", text):
        raise ValueError("invalid uppercase mapping scalar")
    value = int(text, 16)
    if value > 0x10FFFF or 0xD800 <= value <= 0xDFFF:
        raise ValueError("uppercase mapping contains a non-scalar")
    return value


def read_sources(directory: pathlib.Path) -> dict[str, str]:
    manifest = json.loads((directory / "casing-manifest.json").read_text("utf-8"))
    if set(manifest) != {"unicode_version", "ucd_url", "license", "operation", "source_sha256"}:
        raise ValueError("unexpected casing manifest fields")
    if (manifest["unicode_version"] != "16.0.0"
            or manifest["ucd_url"] != "https://www.unicode.org/Public/16.0.0/ucd/"
            or manifest["license"] != "LICENSE.txt"
            or manifest["operation"] != "default_full_uppercase"):
        raise ValueError("unexpected casing source contract")
    pins = manifest["source_sha256"]
    if not isinstance(pins, dict) or set(pins) != FILES:
        raise ValueError("casing pins must name exactly the required inputs")
    for name, expected in pins.items():
        if not isinstance(expected, str) or not re.fullmatch(r"[0-9a-f]{64}", expected):
            raise ValueError("invalid casing source digest")
        if hashlib.sha256((directory / name).read_bytes()).hexdigest() != expected:
            raise ValueError(f"pinned casing input changed: {name}")
    # The separate casing manifest must reuse, not replace, the adopted UCD
    # and license originals. The NFC/text-rank manifest remains unchanged.
    original = json.loads((directory / "manifest.json").read_text("utf-8"))
    if original["unicode_version"] != "16.0.0" or any(
            original["sha256"][name] != pins[name] for name in ["UnicodeData.txt", "LICENSE.txt"]):
        raise ValueError("casing inputs differ from the adopted Unicode originals")
    special = (directory / "SpecialCasing.txt").read_text("utf-8")
    if not special.startswith("# SpecialCasing-16.0.0.txt\n"):
        raise ValueError("wrong SpecialCasing version")
    return pins


def upper_mappings(unicode_lines: list[str], special_lines: list[str]) -> dict[int, tuple[int, ...]]:
    mappings: dict[int, tuple[int, ...]] = {}
    seen: set[int] = set()
    for line in unicode_lines:
        fields = line.split(";")
        if len(fields) != 15 or not re.fullmatch(r"[0-9A-F]{4,6}", fields[0]):
            raise ValueError("invalid UnicodeData record")
        code = int(fields[0], 16)
        if code > 0x10FFFF or code in seen:
            raise ValueError("duplicate or invalid UnicodeData code point")
        seen.add(code)
        if fields[12]:
            mappings[scalar(fields[0])] = (scalar(fields[12]),)
    unconditional: set[int] = set()
    conditional: list[tuple[int, tuple[int, ...], str]] = []
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
        mapped = tuple(scalar(part) for part in fields[3].split())
        condition = fields[4] if len(fields) == 5 else ""
        if condition:
            # Default casing has no language tag. Do not adopt locale rules.
            if condition.split()[0] in {"lt", "tr", "az"}:
                continue
            conditional.append((code, mapped, condition))
            continue
        if code in unconditional or not 1 <= len(mapped) <= 3:
            raise ValueError("duplicate or invalid unconditional uppercase mapping")
        unconditional.add(code)
        mappings[code] = mapped
    for code, mapped, condition in conditional:
        # Unicode 16 has only this root condition, and it does not change
        # uppercase. A future contextual uppercase rule needs explicit work.
        if condition != "Final_Sigma" or mapped != mappings.get(code, (code,)):
            raise ValueError("unsupported root-context uppercase change")
    return {code: mapped for code, mapped in mappings.items() if mapped != (code,)}


def table_text(mappings: dict[int, tuple[int, ...]], pins: dict[str, str]) -> str:
    entries = sorted(mappings.items())
    keys = "\n".join("  " + ", ".join(f"0x{code:x}" for code, _ in entries[i:i + 10]) + ","
                     for i in range(0, len(entries), 10))
    values = "\n".join("  " + ", ".join(json.dumps("".join(chr(cp) for cp in mapped), ensure_ascii=False)
                                     for _, mapped in entries[i:i + 8]) + ","
                       for i in range(0, len(entries), 8))
    return f'''// Generated by scripts/generate-unicode-upper.py; do not edit.
// Unicode 16.0.0 default full uppercase. No normalization or locale tailoring.
// Source license: ../../vendor/unicode/16.0.0/LICENSE.txt
// UnicodeData.txt sha256: {pins["UnicodeData.txt"]}
// SpecialCasing.txt sha256: {pins["SpecialCasing.txt"]}

///|
let unicode_upper_keys : FixedArray[Int] = [
{keys}
]

///|
let unicode_upper_values : FixedArray[String] = [
{values}
]
'''


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--output", type=pathlib.Path, default=OUT)
    args = parser.parse_args()
    try:
        pins = read_sources(UCD)
        mappings = upper_mappings((UCD / "UnicodeData.txt").read_text("utf-8").splitlines(),
                                  (UCD / "SpecialCasing.txt").read_text("utf-8").splitlines())
        text = table_text(mappings, pins).encode("utf-8")
        if args.check:
            if not args.output.is_file() or args.output.read_bytes() != text:
                raise ValueError("generated Unicode uppercase table is stale")
        else:
            args.output.write_bytes(text)
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f"Unicode uppercase generation failed: {error}", file=sys.stderr)
        return 1
    print(f"{'checked' if args.check else 'generated'} {args.output}: {len(mappings)} uppercase mappings")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
