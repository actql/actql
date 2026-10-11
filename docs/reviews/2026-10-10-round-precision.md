# ROUND and TRUNC precision implementation provenance

## Decision and verified scope

The finite Number two-argument ROUND/TRUNC implementation preserves the
operation sequence of Google's pinned double-double reference. Two simpler
exact-rational algorithms were rejected after fixed counterexamples established
observable differences. The implementation uses a bounded numerical cursor
inside the existing binary-expression owner.

Focused working-tree execution passed **13/13 tests on each of JS, Wasm, and
Native**. Each target executes the 1,000-pair reference corpus (2,000 ROUND/TRUNC
expectations), all 647 power pairs, and the selected accounting regressions.
These are selected working-tree results. A later clean logical integration
passed 1,062 selected JS tests; final generated-closure and public Host acceptance
are reported on the submitted Draft revision. There is no live BigQuery or
exhaustive binary64-conformance claim.

## Reference and license

Reference: [google/googlesql at 81c15b796138185c046aefe852321011fdf96615](https://github.com/google/googlesql/tree/81c15b796138185c046aefe852321011fdf96615).
The adapted sources are `googlesql/common/round_decimal.cc` and
`googlesql/common/double_double.h`, with `round_decimal.h` retained for the
standalone build. Copyright 2019 Google LLC; Apache License 2.0. Preserve the
source attribution and applicable license notices when redistributing the
adaptation.

The implementation, consistent with the public [ROUND documentation](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/mathematical_functions#round),
uses half-away-from-zero decimal integer selection. The reference header's
contradictory ties-to-even sentence is not the selected contract. Binary64
representation rounding remains nearest-even.

| Captured source | SHA-256 |
|---|---|
| round_decimal.cc | `cea59c46644f894fc204d434b7f56f65501b103fdd1f3a81c99304343bdee78d` |
| round_decimal.h | `5a3c7b86e0f86c373c25b6424711bc7a0881faf0e2db266657cd2c8019acd13c` |
| double_double.h | `cfc04e97cad3e04109ad3f91f2f96347ecf63a7aa1750421f4b27c1c0bceb91a` |

## Why the rational proxies were rejected

A single exact final conversion loses the reference's two-stage subnormal
rounding. Preserving that final binary scaling is still insufficient: exact
integer selection omits the reference's relative-error tolerance, and exact
intermediate conversion omits rounded double-double multiplication.

| Operation | Rejected proxy bits | Pinned reference bits |
|---|---|---|
| ROUND(2.2250738585072014e-308,311), single final conversion | `000fffdd31a00c6d` | `000fffdd31a00c6e` |
| ROUND(2.328158521232893e41,-26), exact-intermediate proxy | `4885617970e7e3bd` | `4885617970e7e3be` |
| TRUNC(1.0608098227205722e-8,24), exact-intermediate proxy | `3e46c7dd19c90499` | `3e46c7dd19c9049a` |
| TRUNC(9.293272072201609e-11,26), exact-intermediate proxy | `3dd98b8f10cee22e` | `3dd98b8f10cee22f` |

The exact-intermediate proxy initially passed 997,750 selected/random/adjacent
operation checks. A targeted modular search subsequently found 18 output
differences over 12,363,612 active operations. These overlapping diagnostic
counts are **non-additive**, and the initial success does not establish proxy
compatibility. The fixed corpus includes the discovered counterexamples and
adjacent inputs. Its 2,000 reference outputs agree between the FMA and portable
Dekker reference variants; this does not prove universal variant equivalence.

## Final bounded sequence

1. Demand both children once, left to right, using the existing expression owner.
   Apply strict NULL propagation, finite-number and integral-position validation,
   unary-position-zero behavior, and reference range guards before integer growth.
2. Construct the required powers of five with bounded exponentiation. Synthesize
   each pair as hi=RN(exact power), lo=RN(exact power-hi). All 647 independent
   source-table pairs are retained as expected bit payloads.
3. Binary-scale the magnitude, form the two Dekker products, and select the
   decimal integer with the reference's grouped corrections. Preserve the
   2^-105 threshold (`3960000000000000`), low-46-bit mask, sticky adjustments,
   and negative-correction rounding direction.
4. Multiply by the inverse power pair in the original operation order; take its
   high part and perform final nearest-even binary scaling. Canonicalize zero
   to positive zero and convert finite-input ROUND overflow to ArithmeticFailure.

The cursor reserves 32 structural scratch entries; these are not heap-byte
measurements. Integer temporaries remain below 2200 bits and exponentiation
requires at most nine stages for the admitted interior position range. The
cursor introduces no unbounded decimal domain or new generic arithmetic system.
Its range guards justify omitting general-purpose DD overflow/underflow branches.
FMA substitution and reassociation are excluded from the owned operation sequence.

## Reference harness and reproduction

Reference compiler: `g++ (Debian 14.2.0-19) 14.2.0`, target
`x86_64-linux-gnu`. Compiler executable SHA-256:
`6b3696e4dcb85e1c949c732a02befa50e3983ecf94ce7e8e58d9d503b954b79d`.
Host: Linux 6.18.44, x86_64, glibc 2.41, Python 3.12.14;
FLT_EVAL_METHOD=0, FE_TONEAREST, eight-byte double and long long.

The self-contained offline verifier is in `docs/reviews/repro/round-precision`.
Supply the pinned GoogleSQL checkout, or a directory containing its three
unchanged source files. It verifies their captured hashes, then compiles and
checks the existing repository fixture; it never downloads dependencies or
regenerates expected results.

```sh
python3 docs/reviews/repro/round-precision/verify_round_precision.py \
  --reference-root /path/to/pinned/googlesql \
  --corpus portability/corpus/round-precision-reference.json \
  --compiler g++ \
  --report /tmp/actql-round-precision-reference.json
```

An optional `--check-inputs-only` validates inputs without compiling. Normal
execution builds two temporary libraries using the checked-in wrapper and
minimal Abseil shims. The wrapper includes the numerical source unchanged,
selects Dekker or upstream FMA explicitly, and exposes the original power table.
Neither variant enables contraction or fast-math. Both compare all 2,000 scalar
expectations and all 647 compiled power pairs. Temporary libraries are removed;
only the machine-readable report is retained.

A bounded verifier self-test passed both variants with zero differences. Its
compiler identity matches the one above. Reproduction reports record fresh
compiler, source, corpus, harness, and library hashes. These hashes identify the
self-contained verifier build; the earlier exploratory wrappers had different
library identities and are not required for reproduction.

| Self-contained reference library | Verified SHA-256 |
|---|---|
| Portable Dekker | `3eb2ba14df6912d373ca2a9fb4a80aa0c442078f41c849e3e0a1678ff078b63c` |
| FMA | `15afee0036126e5f781efa720605ce4ee83ed6d4be1595b1db205b585c813bdb` |

The verifier sources, shims, license, and attribution are sufficient for the PR;
compiled binaries and exploratory logs are excluded. Corpus expectations still
come only from the pinned reference, with ActQL zero/overflow admission applied.

## Isolated optimized Native arithmetic

The byte-identical numerical helper and generated reference files also passed
6/6 tests in a minimal Native release package, covering the same 2,000 outputs
and 647 power pairs. The position-zero finite helper and ROUND/TRUNC arm were
extracted verbatim from the existing scalar source. Only operator/value type
plumbing and direct delegation were stubbed. Source and copy hashes remained
identical before and after execution.

The bounded diagnostic used Moon's default GCC 14.2.0 release configuration on
Linux x86_64, including `-O2 -fwrapv -fno-strict-aliasing`, with no floating-point
flag overrides. It completed in approximately 12 seconds with a 180-second cap
and three-CPU affinity. Its receipts are `run-axr7Go` and `focused-test-v0spxG`.
Compiler flags come from the unchanged successful configuration's read-only
Moon build plan. Other architectures and compiler contraction settings remain
unverified.

See the [reproduction instructions](repro/round-precision-native/README.md) and
[hash-bound evidence](evidence/round-precision-native-release.json). This is
isolated arithmetic evidence, not expression-owner/accounting or full-product
Native acceptance. It does not turn the full-package release compilation timeout
into a pass, and its corpus counts are not additional independent coverage.

## Working tree receipts and remaining limits

The verified receipts identify dirty source based on
`8b51ac1f0da3656695e6b699e208f5fc331e2cb6`:

| Target | Local attempt | Focused receipt | Result |
|---|---|---|---|
| JS | run-7774VG | focused-test-xDzxEc | 13/13 |
| Wasm | run-ha2min | focused-test-JtQ6dC | 13/13 |
| Native debug (-O0, x86_64 Linux) | run-L2bqrf | focused-test-o8naKw | 13/13 |

A separate selected Native release attempt, `run-UQqvxS`, reached the unchanged
180-second cap during C compilation before any tests executed. It generated
about 150 MB of whole-package white-box C despite selecting only three files.
This is an incomplete compilation diagnostic, not a numerical mismatch or an
optimized product acceptance pass. The cap was not extended.

To repeat the selected product checks, use the repository's pinned toolchain
and bounded wrapper with TARGET set to js, wasm, then native:

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target "$TARGET" \
  src/execution_relation/round_precision_execution_wbtest.mbt \
  src/execution_relation/round_precision_reference.generated_wbtest.mbt \
  src/execution_relation/round_precision_powers.generated_wbtest.mbt
```

The exact commands, receipt hashes, reference identities, and fixture hashes are
in [`evidence/round-trunc-provenance.manifest.json`](evidence/round-trunc-provenance.manifest.json). It also records the clean logical integration
`2781ca39d0b010142de009e7ce550e201d9b6fc1`, tree
`5d8015032eff01046d7a13cae1730530fe551984`, with 1,062 selected JS tests
(`run-Ev6loE`, `focused-test-rTaT7c`) and an unchanged source tree. Additional frontend/caller and
generator/law working-tree receipts are recorded separately in that manifest;
their overlapping counts are not combined with the numerical corpus.

The final closure freezes the actual SAFE predecessor at published revision
`0a561739e64ed93d647c24219225ea6e41e4d1f6`, tree
`aae5ce55104dec14f5accc5da482cca24a241fbb`. Its ten normative bodies, seventeen
source preimages, twenty-one complete identity envelopes, and Values Program/Run
preimages remain separate from the new contract. All earlier historical files
retain their exact inherited bytes. The SAFE transition's adopted side selects
this frozen predecessor rather than the later installed ROUND/TRUNC bodies.

Final clean-candidate closure, validator, and fresh public Host receipts belong
to the submitted revision's PR verification record. They are distinct from the
logical-only and earlier working-tree results above. Wasm and Native results
above cover the earlier numerical implementation; no full-product optimized
Native pass is claimed.

The selected tests do not stand
in for full Core, packed distribution, public Host acceptance, or hosted CI.
Numerical agreement is established for the recorded cases and targets; future
compiler changes, contraction, reassociation, or range-guard changes require
renewed evidence.

## Public cancellation fixture correction

The first final-candidate public selection passed 61/63 tests. Only the two
new cancellation fixtures failed, before execution, because their 512 Values
rows exceeded the existing 100-row default compilation ceiling. Temporary local
diagnostics established the exact nested `ValuesFailure(0, ValuesLimit)` cause;
the public ingress correctly retained its existing unknown-submission wrapper.
No product limit or error boundary was changed.

The corrected fixtures keep 100 rows and split the numeric consumer into its
own task. Their barrier requires positive work and progress from that consumer,
then checks cancellation acknowledgement, confirmed physical stop, unavailable
results, retained cancelled reread, and no redispatch. Both focused cases passed
against the already freshly built runtime. Exact in-cursor phase cancellation
remains covered by the core owner tests. Diagnostic instrumentation was restored
byte-for-byte. See the [failure and correction record](evidence/round-precision-public-cancellation.json).
