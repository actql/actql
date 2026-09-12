# Local Relation sequence measurements

## Release layout comparison

`columnar-experiment.json` fixes the row baseline, workload groups, alternating
candidate order, seven-sample minimum, and conditional adoption rules before
measurement. It is experimental methodology, not a product compatibility pin.
The debug report below does not satisfy those rules.

The release harness is kept in the repository:

```sh
node scripts/measure-layouts.mjs --smoke
node scripts/measure-layouts.mjs --legacy
node scripts/measure-layouts.mjs --additional-smoke
node scripts/measure-layouts.mjs --additional
node scripts/measure-layouts.mjs --prepared-smoke
node scripts/measure-layouts.mjs --prepared
```

Set `MOON_HOME` to the pinned toolchain first. The smoke mode builds native, JS
and Wasm release artifacts and directly executes the exact profiling test,
checking both its measurement and its independent output assertions. It runs
one warmup and one measured invocation of the narrow 100-row case for each of
A, B and C. It is **not** a statistical layout comparison or adoption gate. Logs and smoke output stay
in ignored `_build/layout-measurements/`; they are not committed reports.

The five clocks surround fixture generation/JSON parsing, typed preparation,
input admission/physical import, operations, and output observation. The import
clock includes invocation-specific wiring, budget initialization and complete
input-key validation. Operations use the same private driver called by the
public generated-sequence API, with the same shared counters. No second semantic
executor is used for timing. Authored `values` must remain in operation order;
this initial profiling entry uses explicit inputs and must not be generalized by
hoisting later `values` across earlier failures.

The measured invocation's end-to-end clock encloses all five phases. A separate
process wall clock also includes startup, warmup and test reporting, but not
compilation. Each process is wrapped in macOS time or GNU time to record its
whole-process peak RSS, including warmup. Retained-table slot counters neither
describe allocator bytes nor include all temporary/capture storage; they must
not be presented as process memory or complete physical accounting.

B/C additionally report owned capture/column/selection capacity, separately from
the legacy retained-table counter. Their source capture stays owned throughout
observation. Disposal assertions run after the phase clocks; only the outer
process time currently includes that cleanup. The full comparison must include
equivalent disposal in its enclosing invocation time, add prepared-input repeats,
complete temporary-storage accounting, and run the entire fixed sample matrix.

`--legacy` runs the twelve fixed shapes on native and four fixed representative
shapes on JS/Wasm. Each case has seven paired repeats alternating A/B/C and C/B/A,
with a fresh process and one warmup for every candidate sample. The runner saves
each validated sample under `_build/layout-measurements/legacy-samples.json` and
marks completion only after the full selected schedule succeeds. This subset is
never adoption-eligible: the thirteen additional cases, complete physical
accounting and prepared-input repeats remain necessary. A partial report is not
a successful run. Validate the schedule and parsing with
`node --test scripts/layout-measurement-support.test.mjs`.

The additional entry measures all thirteen fixed additional cases on all
three targets: `--additional-smoke` uses one pair-set per case and `--additional`
uses seven. Neither includes prepared-input repeats or the legacy cases,
so neither constitutes the full adoption matrix. Reports are separate
from the legacy samples and retain every successful prefix if a later sample
fails. Each sample must identify the exact case and assert that disposal is
included. Its enclosing clock ends after the fixture/input/output-owner scope
returns; the five phase clocks exclude cleanup, whose cost remains in that
enclosing time. A does not implement the experimental owned-buffer ledger and
reports those two capacity fields as null, not as zero-byte storage.

For the producer case, phase 1 constructs a real completed row-backed producer
as the identical fixture for A/B/C, including its checking and execution. Phase
2 checks, binds and prepares the receiving branch sequence. Phase 3 performs
the common producer-input admission and physical import; phase 4 runs both
branches; phase 5 observes both retained results. The producer stays owned until
the enclosing measurement scope ends. The B/C ledger includes its row-pointer
and cell slots while destination buffers coexist; it does not pretend to count
all nested objects or schema metadata as allocator bytes.

The zero-column fixture supplies 1,000 already-empty rows and applies identity
drop and empty sort, preserving their multiplicity. The earlier proposed
all-column drop followed by take is not a legal Program under the selected
Language: dropping every field of a nonempty schema must fail during check.
That rejection remains a separate regression; no comparison case bypasses it.
Take continues to be exercised with valid ordering evidence in the other cases.

### Reused-input operation measurements

`--prepared[-smoke]` runs the same thirteen additional cases in separate
processes from E2E measurement. Each process constructs and admits its fixture
once, imports its physical input once, and retains that immutable input through
one warmup and one measured invocation. Both invocations receive fresh budgets,
run the common input ownership/key/value admission, and fully observe their
outputs before releasing them. Logical consumption must agree between repeats.
The clock covers only the operation sequence; repeated admission, attachment of
existing input buffers, output observation and final disposal are outside it.

A reuses its admitted row Table. B/C pin the sealed column buffers and attach
fresh invocation handles without re-transposing or copying cells. The new
invocation ledger reserves the full input capacity as an existing floor, while
the pin keeps the physical buffer alive. Do not sum these ledgers to claim two
physical copies. Source captures and real producer completions remain alive and
are also represented in each run's capacity floor. A's row storage is not thereby
converted to the B/C owned-column accounting model.

The fixed producer workload has no receiver projection. This entry rejects one
rather than caching away its required output-budget charges; that restriction is
on the benchmark entry, not the supported execution API. Prepared reports contain
`operation_us` and separate `warmup_operation_us`, never `end_to_end_us` or five
phase timings. Their whole-process RSS includes the retained prepared fixture
and cannot replace the E2E RSS observations. This additional-case report alone
does not cover prepared legacy cases or authorize adoption.

### Paired statistical method

`scripts/layout-statistics.mjs` summarizes each candidate against A within the
same case, target and metric. It uses the median of paired candidate/A ratios,
not a ratio of averages pooled across workloads. Its percentile bootstrap uses
10,000 resamples, xorshift32 seed `0x5eeda017`, and nearest-rank 2.5%/97.5%
endpoints. The same sampled index selects both members of a pair. At least seven
pairs are required; reproducibility additionally requires at least `ceil(6*n/7)`
pairs in the stated direction and a confidence interval strictly excluding 1.
Missing, nonpositive or nonfinite observations are rejected, never filled in.
Test this calculation with `node --test scripts/layout-statistics.test.mjs`.

This calculation alone does not authorize adoption. The full mandatory matrix,
valid timing scope, semantic gates and source provenance must be established
separately. Apply the 20% threshold to every member of a preselected major group;
do not pool away a reproducible regression in any other required case or target.

## Historical debug measurements

Build and measure with the repository's pinned MoonBit toolchain:

```sh
moon test --target native src/execution_relation/sequence_scale_wbtest.mbt
node scripts/measure-local-relation.mjs
```

The default executable is the native **debug** whitebox test binary. An explicit
binary path may be supplied as the first argument. Each of twelve shapes runs
three times in a fresh process. The runner checks the exact test-result event,
not merely the executable exit code. macOS `/usr/bin/time -l` reports bytes;
GNU time on Linux reports KiB, converted to bytes in the report.

The measured scope includes startup, fixture construction, checking/lowering,
input decoding/admission, execution and assertions; it excludes compilation.
Peak RSS includes test fixtures and the runtime, not just live Relation tables.
Logical budgets do not claim to cap this RSS. These figures do not establish
browser/Worker capacity, production latency or performance on other machines.

Cases cover 100/1,000/10,000 rows, 2/64 columns and equal/different grouping
keys. Unique input IDs make the grouping winner independently predictable.
The same generated sequence performs rename, identity drop, stable sorting,
projection/distinct/take and an alias branch with dedupe/sort/take. Closed-form
expected values check both outputs and retained payload. Nonselected intermediate
outputs must be released. Scalar-domain and logical-budget boundary tests remain
separate from this size matrix.

Reports record source commit, worktree state, executable and test-source hashes,
host identity and all samples. Rebuild before measuring after source edits; a
report is evidence for its recorded build, not for a later revision.
