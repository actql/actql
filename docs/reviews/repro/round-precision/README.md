# ROUND and TRUNC reference reproduction

This offline verifier checks the existing ActQL fixture against the pinned
GoogleSQL implementation. It does not execute ActQL, generate expectations,
fetch sources, install packages, or modify the supplied source or corpus.

## Requirements

- Python 3 with IEEE binary64 floats; standard library only
- An already-installed GCC-compatible C++17 compiler and shared-library loader
- GoogleSQL commit `81c15b796138185c046aefe852321011fdf96615`, or a directory
  containing its unchanged `round_decimal.cc`, `round_decimal.h`, and
  `double_double.h`
- The repository's `portability/corpus/round-precision-reference.json`

The verifier accepts either a GoogleSQL checkout root or the flat directory
containing those three files. It verifies all three captured SHA-256 identities
before compiling. The supplied source files are not bundled here.

## Run from the ActQL repository root

Use the repository's bounded local-check wrapper for this optional diagnostic:

```sh
python3 docs/reviews/repro/round-precision/verify_round_precision.py \
  --reference-root /path/to/pinned/googlesql \
  --corpus portability/corpus/round-precision-reference.json \
  --compiler g++ \
  --report /tmp/actql-round-precision-reference.json
```

Add `--check-inputs-only` to validate source identities, corpus shape, and all
647 source-table pairs without compiling or executing C++. That mode reports
`inputs_verified`, not a completed numerical comparison.

Normal execution compiles two small libraries in a temporary directory, using
C++17, `-O2`, and `-ffp-contract=off`. One selects the portable Dekker branch;
the other selects the upstream FMA branch. Both compare all 2,000 fixed scalar
expectations and all 647 compiled power-table pairs. The temporary source copies
and libraries are removed afterward. A compiler invocation times out after
60 seconds.

The JSON report records source, corpus, harness, compiler, and library identities;
commands; per-variant comparison counts; mismatch examples; and variant agreement.
Exit status is 0 for successful comparison (or successful input-only validation),
1 for a numerical mismatch, and 2 for an input/build/runtime error. The report's
status and `cpp_execution` fields distinguish these modes. No report is written
over a supplied source, corpus, or verifier file.

## Numerical adaptations and branch selection

Only admitted-result comparison changes: both zero signs compare as positive
zero, and a reference infinity from finite ROUND input compares as
`ArithmeticFailure`. NaN is never silently accepted as overflow. TRUNC has no
accepted overflow expectations.

`wrapper.cc` includes the hash-verified numerical source without modifying it,
exposes the two functions and original table, and checks the rounding mode.
For the Dekker variant, standard headers are loaded first and FMA-selection
macros are temporarily suppressed around the upstream include. This prevents an
architecture macro from silently selecting FMA. The macros are restored afterward.
The FMA variant enables the upstream `std::fma` branch. Minimal Abseil shims
provide only bit_cast, assertions, prediction identity, and the unused C++17
comparison include. They do not replace numerical operations.

Passing this fixture is not exhaustive binary64 equivalence or live BigQuery
validation. Both variants execute the same fixed cases, so their counts are
not independent coverage and must not be added together.

## License and attribution

The harness and shims are provided under Apache License 2.0; see `LICENSE`.
The separately supplied GoogleSQL numerical files retain their upstream notices:
Copyright 2019 Google LLC, Apache License 2.0. The verifier never strips or rewrites
those files. See `NOTICE.md` for the pinned upstream source locations.
