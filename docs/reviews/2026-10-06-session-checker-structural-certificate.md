# Session checker: structural kernel certificates

## Behavior and boundary

The final consumer still requires a real pinned Lean proof of
`IncrementalEvidence.check submittedRequirements submittedApplications = true`.
Previously a single `decide` reduced every application, including long String
identities, through the checker. The new generated proof establishes the same
`ValidPlan` structurally and applies the existing `checker_complete` theorem.
Each identity and Boolean premise is checked by kernel reflexivity; the
execution-unit inequality is checked by `decide`. The final fresh-origin or reused
closed/main-origin premise is proved separately for each application.

The model, five theorem types, axiom audit, toolchain pin, data decoder, input
bounds and production 30-second limit are unchanged. JavaScript constructs a
proof skeleton from the independently required list length; it does not accept
an application. Missing or extra applications, false premises and unequal
identities cannot inhabit that proof. There is no native evaluator, unchecked
axiom, timeout increase or alternate acceptance path.

The generated proof bytes intentionally change the Lean input digest. Existing
original receipts and certificates remain immutable. Normal input identity and
policy checks still determine whether any old evidence applies; this change
does not authorize reuse of an old-policy receipt.

## Fixed local comparison

Measured candidate: `a7bf54e7cb0fe689415db5ff797b7ebb97c474fd`.
Reference checker and frozen Git input revision:
`a3f551fd1f02cbb86aef45710311962df47bcd90`.
The comparison uses all 30 registered requirements with real Git source input
identities and explicitly supplied model observations. Runtime remains open;
these are not actual producer executions or authenticated Actions originals.

The profiler checks that the model, claims and pin match the reference, and
that generated declarations before the final proof are byte-identical. It
loads the actual prior checker from Git, relocating only module resolution.
This is a measurement utility, not a production compatibility path.

Three serial alternating-order pairs were declared before execution, with no
warmups, favorable-trial replacement or performance matrix. Each trial uses
the unchanged production timeout. Node was 22.23.2; Lean was the repository pin
`leanprover/lean4:v4.30.0-rc1`. The same local host ran all six trials.

| Pair | Reference | Structural proof | Difference |
| --- | --- | --- | --- |
| 0 | Timeout after 30,875.934 ms | Accepted in 4,106.187 ms | Censored; no exact saving |
| 1 | Accepted in 15,376.086 ms | Accepted in 4,522.245 ms | 10,853.841 ms shorter |
| 2 | Accepted in 13,854.212 ms | Accepted in 1,939.553 ms | 11,914.659 ms shorter |

The timeout is neither a scientific refusal nor an accepted comparison. With
only two uncensored pairs, this report makes no population confidence claim.
All accepted trials returned the same axiom-audit output digest and five
theorems. Raw trials, input/output digests and errors are retained in
[the comparison record](2026-10-06-session-checker-structural-pairs.json).

The timed interval includes JS proof generation, Lean version invocation,
model/claim/axiom checking and the candidate proof. Git fixture preparation,
Actions authentication, transfer and physical execution are excluded. This
is evidence of a local checker improvement, not net CI runner savings.

## Scoped verification and reproduction

At the measured SHA, the bounded selection of `check-structural.test.mjs`,
`check.test.mjs` and `final.test.mjs` passed 8/8, using actual Lean. The structural
regression includes all 30 fresh obligations at the production timeout, plus
14 kernel refusals: authentication, success, action, kind, target, scope,
premises, inputs, minimum units, closed scope, main origin, wrong fresh origin,
missing application and extra application. A timeout is not counted as a
negative detection. The existing real checker and certificate tests remain.

For the comparison, with the pinned Lean binary available on PATH:

```sh
node --input-type=module -e 'import {runLocalCheck} from "./scripts/local-checks-guard.mjs"; process.exitCode = await runLocalCheck({root: process.cwd(), heavy: false, timeoutSeconds: 240, graceSeconds: 5, steps: [{name: "profile-one-frozen-full-catalog-plan", command: process.execPath, args: ["scripts/profile-session-checker.mjs", "/private/tmp/session-checker-pairs.json"]}]});'
```

The output must be new (`wx`), and tracked source must be clean. The bounded
guard records custody and completion. Original run evidence is
`run-jfFiSy`; the 8/8 gate is `run-Us5Bue` / `focused-test-ofPgKu`.

The integrated archive-consumer regression from #636 must also pass against
this checker. It exercises the actual ZIP decoder, final consumer and real
Lean certificate, while API responses and physical experiment observations
remain explicitly controlled fixtures. Exact submitted-SHA commands/results
are recorded in the PR body; prior-SHA results are not relabeled.

## Remaining completion criteria

Compatible authenticated main originals, actual main comparison, normal PR
reuse, related-change fresh execution and net savings over multiple real PRs
remain distinct operational evidence. This change reduces a measured checker
cost without weakening their acceptance requirements. It is not completion
of the overall incremental evidence task.
