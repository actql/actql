#!/usr/bin/env python3
"""Independent, fixed direct-math test vectors, never product/library outputs.

Requires libmpfr.so.6 (MPFR 4.2.x). Exact binary64 inputs are set with mpfr_set_d.
Each operation is evaluated at 4096 bits using both RNDD and RNDU; conversion
to binary64 uses the matching direction. The two extra adjacent binary64 values
on each side are an a-priori *test* allowance for target last-bit differences,
not a normative universal error bound. Never widen a fixture after a failure.
Exact identities, tiny odd-function controls, domains and overflow are tested
separately without this allowance. Regeneration reads no ActQL implementation.
"""

import argparse
import ctypes
import hashlib
import json
import math
from pathlib import Path
import re
import struct

ROOT = Path(__file__).resolve().parents[1]
JSON_PATH = ROOT / "scripts/fixtures/direct-trig-oracles.json"
MOON_PATH = ROOT / "src/execution_relation/direct_trig_oracles_wbtest.mbt"
PRECISION = 4096
ALLOWANCE = 2


class Mpfr(ctypes.Structure):
    _fields_ = [("precision", ctypes.c_long), ("sign", ctypes.c_int),
                ("exponent", ctypes.c_long), ("limbs", ctypes.c_void_p)]


LIB = ctypes.CDLL("libmpfr.so.6")
PTR = ctypes.POINTER(Mpfr)
LIB.mpfr_init2.argtypes = [PTR, ctypes.c_long]
LIB.mpfr_clear.argtypes = [PTR]
LIB.mpfr_set_d.argtypes = [PTR, ctypes.c_double, ctypes.c_int]
LIB.mpfr_get_d.argtypes = [PTR, ctypes.c_int]
LIB.mpfr_get_d.restype = ctypes.c_double
LIB.mpfr_get_version.restype = ctypes.c_char_p
for NAME in ("sin cos tan asin acos atan sinh cosh tanh asinh acosh atanh atan2").split():
    getattr(LIB, "mpfr_" + NAME).argtypes = [PTR] * (3 if NAME == "atan2" else 2) + [ctypes.c_int]


def bits(value):
    return struct.pack(">d", value).hex()


def moon_number(value):
    mantissa, separator, exponent = repr(value).partition("e")
    if "." not in mantissa:
        mantissa += ".0"
    return mantissa + ("e" + str(int(exponent)) if separator else "")


def bounds(operation, values):
    args = [Mpfr() for _ in values]
    result = Mpfr()
    for arg, value in zip(args, values):
        LIB.mpfr_init2(ctypes.byref(arg), PRECISION)
        assert LIB.mpfr_set_d(ctypes.byref(arg), value, 0) == 0
    LIB.mpfr_init2(ctypes.byref(result), PRECISION)
    try:
        answers = []
        # MPFR_RNDD = 3; MPFR_RNDU = 2. Each conversion remains outward.
        for rounding in (3, 2):
            getattr(LIB, "mpfr_" + operation)(ctypes.byref(result),
                                             *[ctypes.byref(arg) for arg in args], rounding)
            answers.append(LIB.mpfr_get_d(ctypes.byref(result), rounding))
        return answers
    finally:
        for arg in args + [result]:
            LIB.mpfr_clear(ctypes.byref(arg))


def inputs():
    half_pi = float.fromhex("0x1.921fb54442d18p+0")
    tiny = float.fromhex("0x0.0000000000001p-1022")
    maximum = float.fromhex("0x1.fffffffffffffp+1023")
    below_one = math.nextafter(1.0, 0.0)
    above_one = math.nextafter(1.0, math.inf)
    boundary = 710.4758600739439
    for op in ("sin", "cos", "tan"):
        for x in (0.5, -0.5, 1.0, -1.0, math.nextafter(half_pi, 0.0), half_pi,
                  math.nextafter(half_pi, math.inf), 1.0e20, -1.0e20,
                  1.0e100, -1.0e100, 1.0e300, -1.0e300, maximum, -maximum):
            yield op, [x]
    for op in ("asin", "acos"):
        for x in (0.5, -0.5, below_one, -below_one, 1.0, -1.0):
            yield op, [x]
    for x in (0.5, -0.5, 1.0, -1.0, 1.0e20, -1.0e20, maximum, -maximum):
        yield "atan", [x]
    for op in ("sinh", "cosh"):
        for x in (0.5, -0.5, 1.0, -1.0, 20.0, -20.0, 710.0, -710.0,
                  boundary, -boundary):
            yield op, [x]
    for x in (0.5, -0.5, 1.0, -1.0, 10.0, -10.0, 20.0, -20.0):
        yield "tanh", [x]
    for x in (0.5, -0.5, 1.0, -1.0, 1.0e20, -1.0e20, maximum, -maximum):
        yield "asinh", [x]
    for x in (above_one, 1.5, 2.0, 1.0e20, maximum):
        yield "acosh", [x]
    for x in (0.5, -0.5, below_one, -below_one):
        yield "atanh", [x]
    for first, second in ((1.0, 1.0), (1.0, -1.0), (-1.0, -1.0), (-1.0, 1.0),
                          (1.0, 2.0), (2.0, 1.0), (1.0, 0.0), (-1.0, 0.0),
                          (0.0, -1.0), (tiny, maximum), (-tiny, maximum),
                          (maximum, tiny), (maximum, -tiny), (-maximum, tiny),
                          (-maximum, -tiny), (maximum, maximum), (-maximum, maximum),
                          (tiny, tiny), (tiny, -tiny), (-tiny, -tiny), (-tiny, tiny)):
        yield "atan2", [first, second]


def generate():
    vectors = []
    for index, (op, args) in enumerate(inputs()):
        exact_bounds = bounds(op, args)
        assert all(math.isfinite(x) for x in exact_bounds)
        lo, hi = exact_bounds
        # Zero from an unrepresentably tiny angle is independently exact at the
        # public Number boundary, so its fixture must not admit a subnormal.
        underflow_zero = op == "atan2" and abs(args[0]) == 5e-324 and args[1] > 1e308
        if underflow_zero:
            lo = hi = 0.0
        else:
            for _ in range(ALLOWANCE):
                lo = math.nextafter(lo, -math.inf)
                hi = math.nextafter(hi, math.inf)
        vectors.append({"id": f"{op}_{index}", "operation": op, "inputs": args,
                        "inputBits": [bits(x) for x in args],
                        "directedBounds": exact_bounds,
                        "directedBoundBits": [bits(x) for x in exact_bounds],
                        "acceptanceBounds": [lo, hi],
                        "acceptanceBoundBits": [bits(lo), bits(hi)],
                        "exactCanonicalZero": underflow_zero})
    fixture = {"version": "actql-direct-trig-oracles/0.1", "generator": {
        "library": "MPFR", "version": LIB.mpfr_get_version().decode(),
        "precisionBits": PRECISION, "input": "exact IEEE-754 binary64 via mpfr_set_d",
        "rounding": ["MPFR_RNDD", "MPFR_RNDU"],
        "adjacentBinary64Allowance": ALLOWANCE,
        "scope": "Frozen test controls, not a universal accuracy guarantee; never widened to accommodate product output."},
        "vectors": vectors}
    payload = json.dumps(fixture, indent=2, allow_nan=False) + "\n"
    moon = ["// Generated only from independent directed MPFR oracles.",
            "// See scripts/generate-direct-trig-oracles.py; never derive expectations from product output.",
            "// Two adjacent values per side are fixed test tolerance, not a universal accuracy law.", ""]
    for op in dict.fromkeys(v["operation"] for v in vectors):
        moon += ["///|", f'test "direct trig MPFR frozen {op} controls" {{']
        if op == "atan2":
            moon += ["  for (first, second, lower, upper) in ["]
        else:
            moon += ["  for (input, lower, upper) in ["]
        for vector in vectors:
            if vector["operation"] == op:
                values = vector["inputs"] + vector["acceptanceBounds"]
                moon += ["    (" + ", ".join(moon_number(x) for x in values) + "),"]
        moon += ["  ] {"]
        call = "binary(@lower.Atan2, Number(first), Number(second))" if op == "atan2" else f"unary(@lower.{op.capitalize()}, Number(input))"
        moon += [f"    guard {call} is Ok(Number(actual)) else {{",
                 f'      fail("{op} unexpectedly refused a finite-domain result")', "    }",
                 "    assert_true(actual >= lower && actual <= upper)", "  }", "}", ""]
    return {JSON_PATH: payload, MOON_PATH: "\n".join(moon)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()
    for path, content in generate().items():
        if args.write:
            path.write_text(content)
        else:
            actual = path.read_text()
            # Moon formatting is centrally maintained. Ignore whitespace and
            # optional trailing commas only; numeric spellings and every
            # operator/control still have to match.
            def moon_tokens(source):
                return re.sub(r",([)\]])", r"\1", "".join(source.split()))
            same = (moon_tokens(actual) == moon_tokens(content)
                    if path == MOON_PATH else actual == content)
            if not same:
                raise SystemExit(f"independent direct-trig oracle differs: {path.relative_to(ROOT)}")
            content = actual
        print(f"{path.relative_to(ROOT)} sha256={hashlib.sha256(content.encode()).hexdigest()}")


if __name__ == "__main__":
    main()
