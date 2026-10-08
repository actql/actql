# Native Operational estimates: finite P2 acceptance

Executed clean source: `c73c7fc900be865d94395e01eb69c4a61195e5e6`. Adopted main:
`556e5c37630284449f390f2fce41438bf2ec90ac`. Final publication adds preserved
local evidence/documentation without retagging those observations. Binary:
`sha256:74371f10e6eed0c6b38363127731f3f52b72ec20d18897d16807422258bcbbc7`. P1 originals remain unchanged; no old-revision
measurements were reused. The [summary](evidence/2026-10-08-native-operational-estimates-c73c7fc90.json) and
[byte-verified original archive](evidence/2026-10-08-native-operational-estimates-c73c7fc90.tar.gz) preserve the six records,
actual metadata capture, Source database and invocations, two receive stdout
records/templates/clock stores, build witness and guard receipts (including
the initial timeout and the successful receive-only continuation).
Archive: 463352 bytes, 136 regular files,
`sha256:b34ba1c09c40d22818b80b5571c6472cdf720a940f80a1e95f8fa00a0d963f8f`. No compiled binary is republished as a product package.

## Exact-source scope

The existing pinned release probe was built with `--deny-warn` after the
fixed-SHA focused JS MoonBit tests passed **5/5**. The original build step is
retained in `run-PJbhVB`; its successful exit and complete streams were checked
before emitting the binary/source witness. Fixed-SHA P2 Node tests passed
**10/10** (`run-nKt0IE`). Pre-commit focused Node tests passed
**29/29** (`run-fn1GlR`); their P1/profile/reference module bytes were unchanged
in the submitted implementation. No full Core, packed or performance matrix
was executed.

Exactly **6/6** successful measurement executions: Native fresh/resident,
metadata-only, three fixed rounds, fresh then resident each round, concurrency
one. No off sample, replacement or retry. Existing independent result, work,
attempt, holding and final cleanup checks passed. Local remained ineligible
under the unchanged Text capacity ceiling; it was not timed as admissible.
OS cache, provider threading and competing load remain uncontrolled/unknown
as recorded; this is not a causal speed comparison or universal profile.

The first guarded run exhausted its 1,200-second budget after all six samples
passed. The final receive script was stopped before its destination directory
existed and before any Native receive process started. Its timeout is retained,
not counted as a performance sample. A subsequent launch was refused by the
shared heavy lock before execution (`run-gs80np`); after that Owner released the
lock, `run-k1i5tS` completed only the two pending receive cases with a 120-second
budget. There was no rebuild or repeated measurement. The release build itself
took **1,011.003 seconds** on this loaded host, separate from runtime timings.

The two **functional** Native receive cases are separate from those samples.
Each used the same release binary/input and actual dispatch Owner. Across them:
**6 normal task-reference receives, 6 reasoned-unknown receives, 60 binding /
issuer / profile / position refusals and 6 post-commit stale-request refusals**.
The fixture compared original candidate bytes, actual choices, acquisition and
attempt correspondence with the admitted sample, checked admission left the
Ledger unchanged, then ran ordinary offline commit/execution and confirmed
final resource cleanup. The API emits no execution or retry authority.
Request expiry and profile freshness boundaries are additionally covered by
the focused decoder/real pending-Owner tests; there is no claim of a timed
Native cancellation/expiry campaign.

```sh
moon test --target js src/physical_strategy/operational_estimates_wbtest.mbt src/query_integration/adaptive_policy_wbtest.mbt
moon build --target native --release src/cmd/native_retained_case_probe --deny-warn
node benchmarks/retained-results/run-local-native-profile.mjs /private/tmp/g-p2-profile-c73c7fc90-20261008 --operational-six
node benchmarks/retained-results/run-native-operational-acceptance.mjs /private/tmp/g-p2-profile-c73c7fc90-20261008 /private/tmp/g-p2-acceptance-c73c7fc90-20261008 /usr/lib/libsqlite3.dylib
```

MoonBit tests use the existing nonzero reporter; the release/six/receive steps
use the cooperative heavy lock and bounded `runLocalCheck` (1,200 seconds,
5-second termination grace), with the separate 120-second receive continuation,
not a bypass of a CI-only entry point.

## Direct recording costs

Milliseconds, median [observed minimum, maximum], three samples per row.
Capture includes its actual persistence/readback. Recording includes the
original observation's persistence/readback. Process cycle excludes subsequent
capture/admission/recording. These scopes overlap with local end-to-end and
must not be summed into customer latency.

| Realization | Samples | Capture | Original recording | Process cycle |
| --- | ---: | --- | --- | --- |
| fresh | 3 | 3.222 [2.485, 12.140] | 1.454 [1.132, 1.666] | 785.288 [743.246, 1603.215] |
| resident | 3 | 7.729 [2.029, 10.681] | 1.687 [1.404, 2.809] | 596.013 [530.810, 662.665] |

Basic aggregation: **1.538 ms**.
Local original readback/aggregation for the producer:
**251.284 ms**.
Checkpoint writes: **90.529 ms**,
separate from per-observation recording. Functional receive timings include
pin/file reads, normal + unknown receives and ten refusal probes; they are
not normal one-sidecar overhead. Their exact scopes and values are retained.

**Additional overhead versus off is unknown**: all six are metadata-only.
The original report's `modeInvariance` field in this six-run schedule checks
repetition invariance within metadata-only, not cross-capture-mode invariance.
No previous-revision off result, 5% threshold, ETA, p90, prediction interval or
scientific expiry calibration is inferred. The 24-hour window is operational.
Task processing, resident preparation/import and task release remain separate;
missing and unselected quantities stay reasoned unknown.

## Remaining scope

Hosted CI is intentionally paused; no local record is an Actions original.
The earlier original authentication/reuse/net-CI-savings work remains deferred
and was not restarted. P3 automatic ranking/search/model learning is excluded.
The repository-wide owned-version scan still reports two negative 0.2 literals
already present in adopted main (`installed-connectors.test.mjs:268`,
`connector-node-bundles.test.mjs:187`); this PR changes neither those fixtures
nor the validator. This document does not claim that full repository check
passed. User review and merge are still required.
