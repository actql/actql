# Isolated Native release arithmetic evidence

## Result and scope

The copied-source optimized Native diagnostic passed **6/6 tests** under the
pinned MoonBit toolchain and Moon's default release C flags. It executes the
unchanged fixed 1,000 input/position pairs (2,000 ROUND/TRUNC expectations) and
all 647 power pairs. These repeat the existing corpus; counts are non-additive
across backends or diagnostics.

This is isolated arithmetic evidence. The existing binary-expression owner,
root custody, cancellation, resource accounting, public Host, and full product
Native integration are not present in this package. The full-package Native
`--release` attempt `run-UQqvxS` timed out at 180 seconds before tests; that
attempt is not converted into a pass by this smaller diagnostic.

## Unchanged numerical inputs

The preparer byte-copies these production files:

- `src/execution_relation/decimal_rounding.mbt`
- `src/execution_relation/round_precision_reference.generated_wbtest.mbt`
- `src/execution_relation/round_precision_powers.generated_wbtest.mbt`

For position zero, it extracts the complete `finite()` helper and exact
`Round | Trunc` unary arm from `src/execution_relation/scalar.mbt`. The extraction
ranges are lines 44–50 and 86–107 in scalar source SHA-256
`de001ca4b3054ada591c6b951e19225d0e0b007d003519396393b379fafcdba7`.
Byte offsets, extracted-body hashes, whole-source hashes, and the ScalarIssue
type extraction are recorded in [`round-precision-native-release.json`](../../evidence/round-precision-native-release.json).

Only Value/operator type plumbing, a minimal package configuration, and direct
binary delegation are stubbed. The unused Captured payload is an Int placeholder;
no numerical algorithm or expected value is substituted. Production files,
scalar source, and destination copies matched their captured hashes both before
and after execution, and were rechecked when collecting the report.

## Bounded execution and compiler

- Local receipt: `run-axr7Go`
- Focused receipt: `focused-test-v0spxG`
- Actual command: `moon test --target native --release --frozen --verbose` on the
  two unchanged generated reference files
- Bound: 180 seconds plus the existing five-second termination grace; affinity
  restricted to CPUs 0, 1, and 2
- Duration: approximately 12 seconds; no cap extension
- Compiler: GCC 14.2.0 through `/usr/bin/cc`
- Default generated-code flags: `-O2 -fwrapv -fno-strict-aliasing`, normal
  MIMALLOC definition and runtime links; no FMA, contraction, or fast-math override
- Compiler flags were captured with Moon's read-only `--dry-run` for the unchanged
  successful configuration. This capture executed no compilation or tests.

The executed white-box program hash is
`7b37e8ae981e9fb02d80a719400c41f42595b7f34845192edb5525f74c954c6e`.
Its generated C was 3,044,415 bytes. Binary, C, compiler, toolchain, wrapper and
receipt hashes are recorded in [`round-precision-native-release.json`](../../evidence/round-precision-native-release.json); binaries and raw logs are not
part of this review package.

One expected isolated-package warning reports unused `DECIMAL_ROUNDING_SLOTS`,
because the expression owner is absent. An earlier launcher attempt
`run-X1DipB` failed before invoking Moon because Node needed an argument
delimiter. It executed no compilation or tests; the corrected launcher is the
preparation script supplied here.

## Reproduction

Use the repository's already-installed pinned toolchain. No fetching or
installation is performed. Choose a new destination outside the repository:

```sh
python3 prepare_native_release.py \
  --repo /path/to/actql \
  --destination /tmp/actql-round-native-release \
  --moon-home /path/to/pinned/moonbit \
  --node /path/to/pinned/node \
  --run
```

The script uses the repository's existing `runLocalCheck` and `runFocusedTests`
wrappers, retains the 180-second limit, sets three-CPU affinity, and verifies
source/copy hashes before and after the run. Omit `--run` to prepare only.
`--home` can select an existing writable wrapper-cache home; otherwise a private
home is created inside the new destination. Existing destinations are refused.

Afterward, in the isolated package with the same MOON_HOME and PATH, capture
Moon's plan without executing it:

```sh
moon test --target native --release --frozen --dry-run \
  src/kernel/round_precision_reference.generated_wbtest.mbt \
  src/kernel/round_precision_powers.generated_wbtest.mbt > /tmp/native-release-plan.txt
python3 collect_native_release.py \
  --work /tmp/actql-round-native-release \
  --repo /path/to/actql \
  --plan /tmp/native-release-plan.txt \
  --output /tmp/native-release-evidence.json
```

The collector checks completed, nonzero receipts and re-verifies input hashes;
it runs no compiler or test. This evidence is specific to the captured compiler,
architecture, inputs, and fixed corpus. It is not a clean-commit receipt or a
claim about every binary64 input, another architecture/compiler, packed releases,
public Host behavior, or live BigQuery.
