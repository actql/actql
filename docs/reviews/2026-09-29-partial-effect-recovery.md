# Partial Effect recovery

## Scope

This correction is independent of acquired-input Effect compilation. The
Salesforce acceptance fixtures were imported from
`25df0205d9517598c41b6ed4cf04f07de09388a8` as `9e44915cf` without changing
their expectations.

Initial apply continues to inspect all Preview target guards before mutation.
Recovery derives an opaque guard selection from admitted durable Ledger heads
bound to the exact Preview, request, member, row, dispatch key, and basis.
Missing heads and mismatched evidence are rejected, not treated as exclusions.
Prepared rows retain their original guard requirements. Already dispatched rows
do not compare their changed targets against the original pre-write guard.
This selection is not a send permit: existing frontier, claim, current authority,
Site, Mapping, capability, and reconciliation checks remain in force. Unknown
and dispatching rows do not become ready, and applied rows are not resent.

There is no wire, canonical preimage, or contract version change. The common
MoonBit recovery entry now requires the opaque Ledger-derived evidence; the
Node bridge and generated interfaces are updated together.

## Local evidence

The following passed on the working correction after `9e44915cf`:

- D's unchanged partial-apply acceptance cases plus unknown no-resend: 4/4.
  These use simulated HTTPS Salesforce, not a live org.
- `effect_application` JavaScript tests: 39/39, including direct missing-head,
  foreign-basis, foreign-request, and distinct-Preview-owner rejection.
- `physical_strategy` JavaScript tests: 24/24.
- Node Effect Ledger, physical dispatch, and installed Effect Site tests: 46/46.

Release runtimes were rebuilt before the provider tests. At
`123878be834e1b792736dbe26eb8af5428d6e377`, the public MoonBit interface check
passed and the complete core JS and Wasm jobs passed 6,936 and 6,933 tests.
At `37e4ff5cf5ae0297214f7905ee417ed499b07c0c`, the complete native core job
also passed 6,995 tests (791.4 seconds for the test step). Full affected
Host/Client jobs and pushed-SHA CI are not established by these results.
The acquired dependency inventory remains separate work in progress.

## Actual Compute call probe

Run, after building the release runtimes used by the provider suite:

```sh
node adapters/connectors/salesforce/test/run-computation-probe.mjs
```

This runs the unchanged partial-apply and unknown-recovery acceptance tests
with a test-only Node module wrapper around the real shared
`runCapturedEffectComputation` entry. Both cases passed with exactly one call:
initial computation runs, and recovery makes zero additional calls. Provider
dispatch assertions remain in the original tests. The Client CI job runs this
probe after the provider suite. It requires the pinned Node's experimental
module-mock flag in the child process; there is no new public SDK API or
production metric.

For an acquired-input or packed Host test, preload
`scripts/fixtures/effect-computation-probe-preload.mjs` before importing the
Host, using `--experimental-test-module-mocks --import <preload-file-url>`.
Set `ACTQL_TEST_EFFECT_ENTRY` to the actual installed Host entry's file URL
and `ACTQL_TEST_EFFECT_CALL_LOG` to a test-owned log path. The parent creates
the empty log once, before the first Host start, and preserves it across
restarts. Each process appends `probe`; every actual entry call appends
`compute` synchronously. A logging failure fails the test rather than losing
an observation. Do not use this preload for production. Assert initial Compute
is positive and that the count does not increase during recovery; an entirely
unused probe cannot prove zero recomputation. These Values-based probe results
do not yet establish acquired-input recovery.

## Separate Frontend recovery report

B reported `crash-resume_claimed` returning `preparing` instead of `succeeded`
at `5ee0dec1747d6465e3829719a0adeca66caf427b`, in
`node scripts/test-packed-client-checkpoint.mjs`, reached from the Client gate.
The supplied saved log confirms that assertion with Node 22.23.2. Its cause is
not established and is not identified with this partial-apply defect.
Investigation must use that revision's packaged artifacts and inspect the
post-claim transition and completion-wait condition. Increasing a delay alone
does not establish a correction.

The saved evidence is B's `_build/public-routing-client-gate.log` and
`docs/reviews/2026-09-29-frontend-projection-review.md` in the Frontend worktree.
The log records 243 Node tests and packed Node/browser success before the
Checkpoint failure. Its Host output contains readiness, but no transition
trace sufficient to identify the cause. At the failing revision, `finished()`
already polls lookup and terminal status separately, each for up to 400
iterations with a 25 ms delay; the crash case uses a 2-second claim lease.
Neither these constants nor the observed `preparing` status prove a timing
defect. Reproduction must preserve the failed revision in a separate worktree
and distinguish lease recovery, Run admission, dispatch, and terminal
observation. This is also distinct from the later transient-observation test
correction in `91636b5df`.

Frontend integration remains after the acquired-input and partial-apply work.
Its fixed series is `ba34b719516f108f80e78cf7d5024f30c7a86c31`; merge the series
rather than cherry-picking its Graph-dependent commits. Raw Local/HTTP acceptance
is distinct from B's already-tested lowered-Program packed path.
