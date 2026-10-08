# Native whole-Run empirical selection: finite acceptance

This unit connects whole-Run references to the existing Native policy, admission,
execution and cleanup owners. The two fixed workloads completed independent
comparison and held-out evaluation. It **does not establish that empirical
selection is economically better than ordinary offline selection**. First use is
slower in both workloads; reuse is slower for JOIN, and the Text difference is not
a causal or repeatable ranking benefit.

## Fixed source and originals

- Adopted main: `5e297d6a8c4687dee8f4b6af00cf1d371e4d0e6d`.
- Accepted implementation and measured clean checkout:
  `ef9079b83d119e54b03618056bfd7fb94b7dc4f9`.
- Release binary:
  `sha256:da0e0b5105c9ab29dd9339ddc6f598add5c7345c1c43e56a3723b626ae08f3b4`.
- Its guarded release producer used
  `06baf2324007b7b98105cc20aefef430efe29386`. The build witness checks equality
  of compiled source/module/toolchain inputs with the measured revision. An
  actual release build at the measured revision also passed incrementally.
  The later change is the consumer's explicit failed-release/retry validation.
- [Handoff record](evidence/2026-10-09-native-whole-run-ef9079b83.json) and
  [original archive](evidence/2026-10-09-native-whole-run-ef9079b83.tar.gz).
  Archive: 4,154,923 bytes,
  `sha256:c4e5573ace884940c1980b0c111b49b37110a78ab659120ccd73fd578f7e8fef`.

The archive contains accepted comparison/evaluation originals, raw stdout and
stderr, independent analyses, synthetic input databases, functional boundary
receipts, the build witness, local guard summaries and reproduction scripts.
Prior campaigns remain separate originals. Private retained stores and transient
clock databases are excluded. Documentation-only publication commits do not
rewrite the measured source, binary or receipt identity.

Publication readback checked archive digest, safe regular-file members, all nine
boundary stdout/stderr digests and the final guard's completion/lock release.
Independent reconstruction from the extracted archive admitted all 72 originals,
reproduced both candidate rankings and arm statistics, and recalculated the
separate full creation-cost application and recovery values. This was read-only;
it did not rerun a benchmark or replace a sample.

## What the implementation admits

`run-caller-elapsed` is a separate reference quantity. Host is an explicit Native
experimental condition. Every presented initial assignment needs three compatible
successful observations before empirical ranking is available. Missing, failed,
stale or incompatible evidence makes ranking unknown; it does not drop an
inconvenient candidate. The configured offline fallback is a separate functional
case, outside the positive performance samples.

An initial position denotes an assignment, including later tasks. Subsequent
steps inspect their actual current pending request and candidate snapshot and
match remaining task, registration and resident realizations. Positions have no
persistent meaning. Current identity, generation, revision, authority, deadline,
feasibility and resources are still checked by the existing Native owner and
closed policy response/commit path. Neither sidecars nor cached profiles issue
execution authority. Opaque physical attempt/environment identities remain
unknown; counter and registration correspondence is checked instead.

The read-only consumer reconstructs actual result rows, schema, choices, Owner
observations and attempts from digest-bound originals and raw logs. It checks
held-out originals are disjoint from comparison originals. Result readback,
temporary resource release and duplicate close are required for success.

Reuse holds only a bounded, immutable admitted local profile. It saves repeated
original readback and reconstruction; template compatibility and every current
Native request are checked again. A changed revision or measurement condition
requires another fixed comparison campaign. Its recollection cost is not zero.

## Plan fixed before execution

Concurrency is one, metadata capture and physical phase observation are enabled,
and OS cache and unrelated host activity are uncontrolled. Existing result
expectations and resource limits remain; the JOIN experiment tightens its
physical-attempt budget to four, identically for both arms.

| Workload | Checked tasks | Initial admissible positions | Comparison runs | Held-out runs |
| --- | ---: | --- | ---: | ---: |
| Text, 1,000 rows, 1,024-byte text | 3 | 0, 7 | 6 | 9 |
| JOIN/count, 100 narrow rows, one acquired input reused | 4 | 0, 1, 3, 4, 9, 10, 12, 13, 27, 28, 30, 31, 36, 37, 39, 40 | 48 | 9 |

Comparison takes three rounds in ascending, reversed, ascending position order,
using the existing policy/commit path. Held-out arm order is:

1. offline, first-use, reuse;
2. reuse, offline, first-use;
3. first-use, reuse, offline.

All 72 comparison/evaluation runs succeeded at the accepted revision. Candidate
exposure runs and nine functional boundary cases are separate. Failed or slow
slots are never replaced. The whole-Run objective chooses the smallest descriptive
median, then the smallest current position for a tie. It does not optimize the
global search or infer an ETA/p90.

## Measured caller time and cost

The primary clock starts before profile access and ends after Result readback,
Owner release, observation admission, original and checkpoint writes. It includes
Native process startup, Source acquisition, preparation/import, all tasks,
consultation, identity and cleanup. Nested task, physical phase, observer,
readback and template intervals are reported separately and are not added to it.
The independent post-experiment audit is reported separately.

| Workload | Offline median (range), ms | First-use median (range), ms | Reuse median (range), ms |
| --- | --- | --- | --- |
| Text | 686.936 (509.158–704.908) | 1,064.978 (666.601–1,230.744) | 621.842 (607.163–846.071) |
| JOIN/count | 93.676 (92.975–110.607) | 457.266 (369.961–710.348) | 121.610 (107.115–136.538) |

Each arm has three observations. These are observed ranges, not prediction or
confidence intervals. First-use profile readback/validation medians are 145.588
ms (Text) and 332.987 ms (JOIN). Reuse readback is zero; template construction
medians remain 1.361 ms and 6.817 ms respectively. Raw analyses include per-request
consultation, record/checkpoint and observer durations. They are already inside
the primary caller clock. Extra telemetry overhead relative to observation-off
execution is unknown because no off comparison was performed.

Full profile creation uses separately measured enclosing preparation and
comparison processes, including candidate exposure, startup, acquisition,
validation, aggregation and record writes. Common synthetic input database
construction is subtracted once and reported separately (430.134 ms Text,
456.539 ms JOIN). Release build is a common prerequisite, not hidden selection
cost. This cost application is separate from the immutable narrower direct
creation receipt; neither original receipt is rewritten.

| Workload | Profile creation, ms | First-use extra vs offline, ms | Reuse saving vs offline, ms | Conditional recovery uses |
| --- | ---: | ---: | ---: | ---: |
| Text | 5,572.882 | 378.042 | 65.095 | 92 |
| JOIN/count | 12,321.002 | 363.590 | -27.934 | unknown |

The recovery calculation counts creation plus first-use extra exactly once. The
Text number assumes its observed saving continues unchanged; it is not a
deployment recommendation. JOIN has no observed saving and no recovery estimate.
Freshness/condition/revision invalidation requires recollection before another
reference is admissible.

Both arms executed the same task registrations and resident realizations: all
resident DuckDB for Text; all Local for JOIN. Initial assignment positions are
not universally equal: JOIN offline starts at 1 while empirical starts at 0;
offline refreshes future suffix choices through its ordinary current requests.
Their observed actual task realizations coincide. These observations cannot
attribute the Text timing difference to a better physical assignment.

Earlier immutable campaigns at `c8294a4872a9371936bb9e7f3061646d8939e2f1`
and `06baf2324007b7b98105cc20aefef430efe29386` had Text reuse slower by
37.770 ms and 133.304 ms respectively, and JOIN slower by 31.575 ms and
24.676 ms. Those campaigns completed their performance slots but failed their
functional gate. The later diagnostic/consumer corrections required a new fixed
revision, not refilled favorable slots. The opposite Text signs reinforce that
general or causal benefit is unproven. No further resampling was done to seek a
favorable result.

## Functional acceptance and responsible cleanup

Nine accepted functional receipts cover all unknown, partial unknown, condition
mismatch, stale profile, single candidate, modified/old request and state,
physical stop between tasks, real clock expiry, and cleanup failure/retry.
Single candidate is reported as no ranking benefit. Binding and expiry refusal
come from the actual Native request Owner; a diagnostic-only bounded sleep lets
the existing clock observe the original deadline rather than inventing a time.

Physical stop is `stopped-between-tasks`, not public Run `Cancelled`. Its remaining
held resources are released through the existing Owner. The cleanup diagnostic
changes only an owned synthetic directory's access, restores it before asserting,
and exercises real failed task release. Pending held bytes remain, attempts and
holdings do not increase, and dispatch stays closed. Retry must release the same
task successfully; confirmed cleanup leaves reservation/holding bytes zero and
duplicate close leaves counters unchanged.

The ordinary phase validator still refuses any failed phase. Explicit retry
acceptance requires failed task-release intervals matched to later successful
releases; failed compute, environment failure or missing retry still rejects.
The complete fault observation is retained separately rather than relabelled as a
successful performance sample. These counters are declared charges and lifecycle
observations, not a proved physical heap upper bound.

## Local commands and evidence

All Native work used the existing local heavy guard with private outputs and
unchanged release/O2 settings. The archive contains exact command arrays,
timeouts, completion and lock release in `guards/*/summary.json`.

| Guard | Check | Result |
| --- | --- | --- |
| `run-OLHrvN` | Focused JS sidecar/ranker | 7/7 |
| `run-oeZPRo` | Focused Node profile/sidecar | 17/17 |
| `run-kBiirJ`, `run-3nnirf` | Native typecheck, C stub and boundary syntax | passed |
| `run-FhCmrr` | Retry consumer, ordinary phase validator, Owner and profile tests | 45/45 |
| `run-g9W9sJ` | Fresh release producer, Native compiled revision | passed |
| `run-vz3gH0` | Measured revision release check, witness, fixed pilot | passed; exit 0; locks released |

The final guard executed:

```sh
moon build --target native --release src/cmd/native_retained_case_probe --deny-warn
node /private/tmp/g-whole-run-build-witness-final.mjs
node /private/tmp/g-whole-run-pilot-ef9079b83.mjs
```

Node was 22.23.2; MoonBit was the repository-pinned 0.10.12+1634b282e. The
archived `reproduction/` scripts record exact source, candidate controls and
fixed schedules. They bind the original private output paths and require the
recorded clean checkout; a replay needs new private destinations and produces new
originals, never modified old receipts. Read-only reconstruction uses
`compareWholeNativeProfiles(comparisonDirectory, evaluationDirectory)`.

Prior release timeouts, the expiry diagnostic failure, the normal-success
validator's rejection of cleanup failure and an earlier guard supervision failure
remain recorded as failures. They are not performance successes or mutation
detections. Only the owned, token-matched abandoned G lock was recovered after
confirming its process group had ended.

## Handoff and remaining limits

Draft PR #1014 targets main. This finite unit has implementation, actual Native
acceptance, explanation and independent comparison/cost evidence. Economic
benefit remains unestablished; the most visible cost is first-use original
readback/validation, with additional template and request consultation cost on
reuse. A larger benefit claim needs another separately reviewed experiment or
implementation change, not selective reporting of this one.

Hosted CI, the full Core/Wasm/packed/performance matrix, calibrated direct-pair
gates and the deferred Actions-original CI reuse unit were not executed here.
Existing performance gates were not changed. There is no merge approval, CI
dispatch, Ready transition, service write or automatic start of another theme.
