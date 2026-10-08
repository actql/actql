# Native empirical first-task selection

## Frozen experiment and acceptance contract

The objective is the first task processing interval only, excluding resident
preparation/import and final release. Positions 0/7 select complete assignments,
including subsequent tasks. Later tasks use current common offline selection.
No whole-assignment optimum, whole-Run fastest, ETA, p90 or calibration is claimed.

The initial dependency was P2 #978. It is now merged; main
`2a77b066ad2ab56278fe657ad07487e7b84688f7` was subsequently merged normally
onto this branch without conflict. The initial adoption was
`861715d844b1835615bccf57f80affcc856e4696`.
The P3 branch will remain Draft; CI is paused and no Actions original is required
for this local acceptance unit. The deferred CI-reuse work remains independent.

Before measurement, fix the source SHA, successful release build/binary digest,
input DB bytes, toolchain, capture/instrumentation/scope revisions, controls and
candidate bytes. Old profile originals are retained and never relabelled.

## Finite protocol

- Native Host, existing 1,000-row Text/1024 three-task fixture, metadata-only,
  concurrency one, existing capacities/work/result gate. OS cache and competing
  load are uncontrolled. No adaptive expansion, warmup discard or replacement.
- Both candidate arms offer the same resident-enabled configuration. Declared
  fresh task rates are 1/1/1; declared resident task/shared/import rates are 1000.
  These deliberately fixed diagnostic estimates make the offline baseline prefer
  position 0. They are not observed rates or a claim about normal defaults.
- Comparison slots: 0,7 / 7,0 / 0,7. Every forced position goes through the existing
  closed policy admission/commit, then all three tasks, independent Result and
  confirmed formal cleanup. Require identical initial projected candidate bytes.
- Freeze the comparison originals; derive references only from three attributed
  successes for each position. Never update them with evaluation observations.
- Evaluation slots: empirical,offline-fallback / offline-fallback,empirical /
  empirical,offline-fallback. Offline-fallback conditions are respectively
  all-unknown input mismatch, partial missing processing quantity, and stale
  observations. The actual pending request remains valid and the caller explicitly
  configures offline fallback before execution. Include its diagnostic/consultation
  cost; this is not an uninstrumented normal-default baseline.
- Keep whole process cold/warm/cycle, acquisition/preparation, resident import,
  identity/holding, task release/cleanup, record/capture/aggregate/consultation
  expenses separately. Raw stream persistence/digests and template derivation/
  persistence are directly timed, as is profile readback/aggregation. These
  intervals overlap the enclosing cycle/end-to-end observations; they are not
  summed to claim whole-Run ETA.
- Two separate functional negatives (not performance slots): actual durable-clock
  expiry with zero Compute, and selected resident dispatch stop after task 1.
  Verify retained responsibility until confirmed close, duplicate close and no
  later physical dispatch. This is not a public Run Cancelled claim.

Unknown evidence produces no empirical order and never removes a presented
candidate. Single-position selection is not an ordering improvement. Invalid
request bindings, expired requests and old proposals after state changes are
refused; errors never silently create a request, retry or select offline.

Record failures/censoring as such and retain diagnostics. Stop further execution
when physical cleanup is unresolved. Do not replenish failed/slow observations.
If selection does not change or held-out processing does not improve, report that
outcome without altering the fixed plan or gates.

## Preserved failed implementation campaign

The first campaign at `18c469a01abe95beb32aadfc7d2a8c5bf789499c`
executed one position-0 slot and then stopped: the fixture incorrectly used its
positive-count CLI parser for a zero-based candidate position. Source acquisition
completed, Compute never started, and the process exited with SIGABRT. Formal
Owner cleanup was not observed. The original retains its then-emitted
`interrupted` label plus the actual SIGABRT; that crash is a failure, not cancellation.
The recorder classification is corrected without rewriting that original.

The failed slot, raw bytes, Source DB and `run-Zc3BQW` remain preserved. No
successful replacement is appended to that six-slot campaign. Following the
fixture fix, a separately identified source/binary campaign keeps the same fixed
six/six protocol and uses no measurement from the failed source. Candidate
position parsing now admits zero and rejects malformed/negative forced input
before Source/resource initialization. Positive fixture counts stay positive.

## Preserved completed positive campaign and failed boundary

At `bbba06a9818e00f192b7f96e023ce761ac1f44ce`, the fixed six comparison and
six evaluation executions all succeeded through the independent Result and
formal cleanup. Their originals are retained unchanged. The separate stop
boundary then exposed a fixture expectation error: the Native Owner drains a
stopped dispatch as `Ok(None)`, closes admission, then returns `Closed` on a
subsequent call. The fixture incorrectly required its first call to be an error
and aborted before cleanup. This does not establish a product cancellation bug.
The expiry boundary/readback were not reached in that guarded invocation.

The fixture now requires the exact drain/Closed contract, unchanged full Ledger,
held material until close, and the same confirmed/double-close checks. Product
stop/admission behavior is unchanged. Because this fix changes Native binary
bytes, a newly pinned source/binary campaign repeats the same predeclared finite
six/six protocol. It does not relabel, pool or substitute the completed old
observations; no slow result or unsuccessful slot is selectively replenished.

## Execution evidence

Native execution/measurement source:
`b51af198e7d15b977998c38a3815f657ba7a7b57`. Actual release binary:
`sha256:73dc6c1ce415305f7dfe84bc936c053e6fd03822a44da663001eaf6db2c34b1d`.
The real preceding release build succeeded under `run-Bkf3Kb` using the pinned
MoonBit toolchain:

```sh
moon build --target native --release src/cmd/native_retained_case_probe --deny-warn
node benchmarks/retained-results/run-local-native-profile.mjs <comparison> --empirical-comparison
node benchmarks/retained-results/run-local-native-profile.mjs <evaluation> --empirical-evaluation <comparison>
node benchmarks/retained-results/run-native-empirical-boundaries.mjs <comparison> <boundaries>
```

`run-pmjFLt` recorded all six comparison, six evaluation and two separate
functional boundaries as successful. Every positive execution completed all
three tasks, independent Result/schema, actual policy/physical-attempt
correspondence, work/capacity/retention assertions and formal/duplicate cleanup.
The stop boundary preserves the exact full Ledger until confirmed close; the
expiry boundary observes the real trusted deadline and dispatches zero Compute.

The last step of that guard failed because its independent consumer compared the
Native present-option diagnostic `[7]` to the scalar `7`. The guard remains
`failed`; its receipt is not rewritten. The corrected independent consumer at
`4cf4a3eae6fe3caa336dbfecbc086345c68929f7` passed under `run-V0VKQX` against
those immutable originals. Only `empirical-comparison.mjs` changed between these
SHAs: Native sources, binary, recording/instrumentation and measurement inputs
are unchanged. No execution was replenished or repeated for this reader fix.
The source/measurement SHA remains the executed SHA, not the consumer or later
evidence-publication revision.

Comparison reference medians (three samples each) were 201.740 ms at position 0
and 131.567 ms at position 7. The real policy therefore proposed position 7.
The independent evaluation used position 7 in all empirical slots and position 0
in all explicit offline-fallback slots. All-unknown, partial-unknown and stale
profiles produced the expected reasons, without dropping a presented candidate.
Invalid binding, already committed request and old responses after state updates
were rejected through the actual Native/common admission path.

| Evaluation interval/cost, median ms | Empirical (n=3) | Explicit offline fallback (n=3) |
| --- | ---: | ---: |
| First-task processing | 110.291 | 223.638 |
| Process cycle | 1112.997 | 1434.865 |
| Existing cold interval | 1098.631 | 1432.943 |
| Same-Run task intervals | 430.536 | 713.475 |
| Formal cleanup | 8.542 | 1.820 |
| Observation recording | 3.570 | 9.740 |
| Raw stream recording/digest | 7.788 | 7.959 |
| Metadata capture | 2.741 | 6.162 |
| Template preparation | 3.736 | 5.349 |
| Native consultation | 7.438 | 16.584 |
| Observed end-to-end interval | 1181.977 | 1493.732 |

The held-out first-task median difference is 113.347 ms. Observed ranges are
96.479–184.394 ms (empirical) and 214.164–261.691 ms (fallback), not prediction
intervals. Original profile readback/aggregation before evaluation cost
413.219 ms; final independent two-profile validation/readback/aggregation cost
1168.556 ms. These are exposed analysis costs, not hidden operator work.
Intervals overlap and must not be added. Three samples and uncontrolled OS
cache/load do not establish causal confidence, population performance or a
normal-default improvement. Off-mode incremental overhead, ETA and p90 remain
unknown. The declared controls intentionally prefer position 0 offline.

[Structured evidence](evidence/2026-10-08-native-empirical-selection-b51af198e.json)
and [original archive](evidence/2026-10-08-native-empirical-selection-b51af198e.tar.gz)
retain commands, actual build witnesses, all original records/raw/capture bytes,
Source DB, templates, successful and failed guard receipts and prior source
campaigns. Archive SHA-256:
`2432d5b46c0e10a34e9ed53fe134d9f06f22275dc652a032058a725722e2ac40`;
2,298,564 bytes, 550 regular members including the manifest, with byte-for-byte
readback validation. Archival helper scripts describe their collected state;
they are not substituted for historical execution receipts.

Earlier scoped diagnostics: JS 7/7 at `dd4a804fd0f979d8949bccb823d414a40b9a10fa`;
Node 49/49 plus Native compiler check with source files subsequently committed
at `bbba06a9818e00f192b7f96e023ce761ac1f44ce`; the stop-fixture compiler check
with source files subsequently committed at
`743dbf53107033064e396954f8aef80d24bf3892`. These are not retagged as final-SHA
full-suite checks. The final actual Native 12 + 2 campaign is the acceptance above.

Hosted CI is deliberately paused. Full Core, Wasm, packed acceptance and the full
performance matrix were not executed. Public Run cancellation, Host auto-selection,
calibrated prediction, whole-Run optimization and Actions-original CI reuse remain
outside this P3 handoff. Review/integration and merge belong to the user.
