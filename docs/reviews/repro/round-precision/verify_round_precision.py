#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Verify fixed ActQL expectations against hash-pinned GoogleSQL source.

Standard library only. No network, package installation, product execution,
expected-value generation, or modification of the supplied source/corpus.
"""
import argparse
import ctypes
import datetime
import hashlib
import json
import math
import pathlib
import platform
import re
import shutil
import struct
import subprocess
import sys
import tempfile

COMMIT = "81c15b796138185c046aefe852321011fdf96615"
SOURCE_HASHES = {
    "round_decimal.cc": "cea59c46644f894fc204d434b7f56f65501b103fdd1f3a81c99304343bdee78d",
    "round_decimal.h": "5a3c7b86e0f86c373c25b6424711bc7a0881faf0e2db266657cd2c8019acd13c",
    "double_double.h": "cfc04e97cad3e04109ad3f91f2f96347ecf63a7aa1750421f4b27c1c0bceb91a",
}
MASK = (1 << 63) - 1
INFINITY = 0x7FF0000000000000
HEX = re.compile(r"[0-9a-f]{16}\Z")
ROOT = pathlib.Path(__file__).resolve().parent


def digest(data):
    return hashlib.sha256(data).hexdigest()


def bits(value):
    return struct.unpack(">Q", struct.pack(">d", value))[0]


def require(condition, message):
    if not condition:
        raise ValueError(message)


def finite_payload(value):
    require(isinstance(value, str) and HEX.fullmatch(value), "invalid bit payload")
    require((int(value, 16) & INFINITY) != INFINITY, "nonfinite fixed payload")
    return int(value, 16)


def source_snapshot(directory):
    candidates = [directory / "googlesql/common", directory]
    selected = next((p for p in candidates if all((p / n).is_file() for n in SOURCE_HASHES)), None)
    require(selected is not None, "reference directory must contain all three files, directly or under googlesql/common")
    snapshot = {name: (selected / name).read_bytes() for name in SOURCE_HASHES}
    for name, data in snapshot.items():
        require(digest(data) == SOURCE_HASHES[name], "pinned source hash mismatch: " + name)
    return snapshot


def load_corpus(path, sources):
    raw = path.read_bytes()
    corpus = json.loads(raw)
    require(corpus.get("format") == "actql-round-trunc-reference-vectors/0.1", "unexpected corpus format")
    require(corpus.get("reference_commit") == COMMIT, "unexpected reference commit")
    require(corpus.get("reference_sha256") == SOURCE_HASHES["round_decimal.cc"], "unexpected corpus source hash")
    rows = corpus.get("rows", [])
    require(len(rows) == corpus.get("vector_count") == 1000, "expected 1000 fixed rows")
    require(corpus.get("operation_count") == 2000, "expected 2000 fixed outputs")
    seen = set()
    overflow = 0
    for row in rows:
        require(isinstance(row, list) and len(row) == 6, "invalid fixed row")
        input_bits, spelling, digits, rounded, truncated, category = row
        encoded = finite_payload(input_bits)
        require(isinstance(spelling, str) and bits(float(spelling)) == encoded, "input label does not round-trip to its payload")
        require(type(digits) is int and -(1 << 63) <= digits < (1 << 63), "digits must fit int64 exactly")
        require(isinstance(category, str), "invalid category")
        require((input_bits, digits) not in seen, "duplicate input/position pair")
        seen.add((input_bits, digits))
        if rounded == "ArithmeticFailure":
            overflow += 1
        else:
            finite_payload(rounded)
        finite_payload(truncated)
    require(overflow == corpus.get("round_overflow_count"), "incorrect overflow count")
    pairs = corpus.get("power_pairs", [])
    require(len(pairs) == 647, "expected 647 fixed power pairs")
    table = re.findall(r"DoubleDouble\{([^,]+), ([^}]+)\}", sources["round_decimal.cc"].decode("utf-8"))
    require(len(table) == 647, "unexpected pinned source table shape")
    for index, (row, captured) in enumerate(zip(pairs, table)):
        require(isinstance(row, list) and len(row) == 3 and row[0] == index - 323, "incorrect power-table exponent")
        hi, lo = finite_payload(row[1]), finite_payload(row[2])
        require((hi, lo) == tuple(bits(float.fromhex(v)) for v in captured), "fixed power pair differs from pinned source at " + str(row[0]))
    return corpus, digest(raw)


def run_command(command, cwd=None):
    completed = subprocess.run(command, cwd=cwd, text=True, capture_output=True, timeout=60, check=False)
    require(completed.returncode == 0, "command failed: " + " ".join(command) + "\n" + (completed.stderr + completed.stdout)[-8000:])
    return completed.stdout.strip()


def admitted_result(raw):
    magnitude = raw & MASK
    if magnitude == 0:
        return "0000000000000000"
    if magnitude == INFINITY:
        return "ArithmeticFailure"
    return f"{raw:016x}"  # NaN remains a mismatch, never an accepted overflow.


def compare_library(path, corpus):
    library = ctypes.CDLL(str(path.resolve()))
    for name in ["actql_reference_round", "actql_reference_trunc"]:
        function = getattr(library, name)
        function.argtypes = [ctypes.c_uint64, ctypes.c_int64]
        function.restype = ctypes.c_uint64
    for name in ["actql_reference_power_hi", "actql_reference_power_lo"]:
        function = getattr(library, name)
        function.argtypes = [ctypes.c_int64]
        function.restype = ctypes.c_uint64
    for name in ["actql_reference_rounding_mode", "actql_reference_nearest_mode"]:
        getattr(library, name).restype = ctypes.c_int
    require(library.actql_reference_rounding_mode() == library.actql_reference_nearest_mode(), "reference requires FE_TONEAREST")
    mismatches = []
    outputs = []
    for index, row in enumerate(corpus["rows"]):
        input_bits, _, digits, rounded, truncated, _ = row
        for operation, expected in [("round", rounded), ("trunc", truncated)]:
            raw = getattr(library, "actql_reference_" + operation)(int(input_bits, 16), digits)
            outputs.append(raw)
            actual = admitted_result(raw)
            if actual != expected:
                mismatches.append({"row": index, "input_bits": input_bits, "digits": digits, "operation": operation, "expected": expected, "actual": actual})
    power_mismatches = []
    for exponent, hi, lo in corpus["power_pairs"]:
        actual_hi = library.actql_reference_power_hi(exponent)
        actual_lo = library.actql_reference_power_lo(exponent)
        if (actual_hi, actual_lo) != (int(hi, 16), int(lo, 16)):
            power_mismatches.append({"exponent": exponent, "expected": [hi, lo], "actual": [f"{actual_hi:016x}", f"{actual_lo:016x}"]})
    return {"scalar_operations": 2000, "scalar_mismatch_count": len(mismatches), "scalar_mismatch_examples": mismatches[:20], "power_pairs": 647, "power_pair_mismatch_count": len(power_mismatches), "power_pair_mismatch_examples": power_mismatches[:20]}, outputs


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reference-root", required=True, type=pathlib.Path)
    parser.add_argument("--corpus", required=True, type=pathlib.Path)
    parser.add_argument("--report", required=True, type=pathlib.Path)
    parser.add_argument("--compiler", default="g++", help="Already-installed GCC-compatible C++17 compiler")
    parser.add_argument("--check-inputs-only", action="store_true", help="Validate source/corpus identities without compiling or executing C++")
    args = parser.parse_args(argv)
    protected = {args.corpus.resolve(), *[p.resolve() for p in ROOT.rglob("*") if p.is_file()]}
    protected.update((args.reference_root / prefix / name).resolve() for prefix in ["", "googlesql/common"] for name in SOURCE_HASHES)
    if args.report.resolve() in protected:
        parser.error("report path must not overwrite supplied sources, corpus, or verifier files")
    report = {"format": "actql-round-trunc-reference-diagnostic/0.1", "started_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(), "reference_commit": COMMIT, "status": "error", "pinned_source_sha256": SOURCE_HASHES, "platform": {"system": platform.system(), "release": platform.release(), "machine": platform.machine(), "python": platform.python_version()}, "adaptations": ["Canonical positive zero", "Finite ROUND infinity mapped to ArithmeticFailure"], "product_code_executed": False, "expectations_regenerated": False, "live_bigquery": False, "variants": {}}
    code = 2
    try:
        require(struct.calcsize("d") == 8 and sys.float_info.mant_dig == 53, "Python must use IEEE binary64")
        sources = source_snapshot(args.reference_root)
        report["source_sha256"] = {name: digest(data) for name, data in sources.items()}
        corpus, corpus_hash = load_corpus(args.corpus, sources)
        report["corpus"] = {"sha256": corpus_hash, "pairs": 1000, "scalar_outputs": 2000, "power_pairs": 647, "source_table_pairs_matched": 647}
        harness_files = [ROOT / "verify_round_precision.py", ROOT / "wrapper.cc", *sorted((ROOT / "include").rglob("*.h"))]
        report["harness_sha256"] = {str(p.relative_to(ROOT)): digest(p.read_bytes()) for p in harness_files}
        if args.check_inputs_only:
            report.update(status="inputs_verified", cpp_execution="not_run")
            code = 0
        else:
            compiler = shutil.which(args.compiler)
            require(compiler is not None, "compiler not found; install nothing automatically")
            compiler = str(pathlib.Path(compiler).resolve())
            report["compiler"] = {"path": compiler, "sha256": digest(pathlib.Path(compiler).read_bytes()), "version": run_command([compiler, "--version"]).splitlines()[0], "target": run_command([compiler, "-dumpmachine"])}
            with tempfile.TemporaryDirectory(prefix="actql-round-reference-") as temporary:
                work = pathlib.Path(temporary)
                common = work / "reference/googlesql/common"
                common.mkdir(parents=True)
                for name, data in sources.items():
                    (common / name).write_bytes(data)
                shutil.copytree(ROOT / "include", work / "harness/include")
                shutil.copyfile(ROOT / "wrapper.cc", work / "harness/wrapper.cc")
                outputs = {}
                for variant, extra in [("dekker", ["-DACTQL_REFERENCE_DEKKER=1"]), ("fma", ["-DFP_FAST_FMA=1"])]:
                    output = "reference_" + variant + ".so"
                    command = [compiler, "-std=c++17", "-O2", "-ffp-contract=off", "-fPIC", "-shared", *extra, "-Ireference", "-Iharness/include", "harness/wrapper.cc", "-o", output]
                    run_command(command, cwd=work)
                    result, outputs[variant] = compare_library(work / output, corpus)
                    report["variants"][variant] = {"compile_command": command, "library_sha256": digest((work / output).read_bytes()), **result}
                report["fma_dekker_raw_output_differences"] = sum(a != b for a, b in zip(outputs["dekker"], outputs["fma"]))
                passed = all(v["scalar_mismatch_count"] == v["power_pair_mismatch_count"] == 0 for v in report["variants"].values()) and report["fma_dekker_raw_output_differences"] == 0
                report.update(status="passed" if passed else "failed", cpp_execution="completed")
                code = 0 if passed else 1
    except (ValueError, OSError, subprocess.SubprocessError, KeyError, TypeError, OverflowError) as error:
        report["error"] = str(error)
    report["ended_at_utc"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"status": report["status"], "report": str(args.report), "cpp_execution": report.get("cpp_execution", "not_completed")}))
    return code


if __name__ == "__main__":
    sys.exit(main())
