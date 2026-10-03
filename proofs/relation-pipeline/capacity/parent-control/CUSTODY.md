# Installed scratch retirement

The Local driver previously confirmed physical stop and credited disposed task
scratch before asking its provider to clean up. A stopped DISTINCT can still own
its keep/index/term state. Stop is permission to attempt cleanup, not confirmation
that the owned state or its holding references have been released.

Both installed lifecycle operation types require an explicit pure
`scratch_released` confirmation. There is no omitted-condition success default.
The existing task owner observes that confirmation separately from physical stop
and output retention. Local drops its installed provider reference only after
successful cleanup and preserves cumulative work; false/error keeps the reference
and reservation. The observation callback does not poll cleanup. Success,
settlement and disposal therefore do not consume the provider's retry sequence;
explicit `cleanup_refresh` drives the existing provider cleanup boundary.

`settle_completed_output_reservation` uses the existing ledger. Before exposing
an accepted task output, it checks reservation ownership, the exact holding's
origin reservation and bytes, and the remaining scratch amount. A zero-byte
output can explicitly have no holding. It returns unused transfer and retention,
keeps the independently admitted holding and consumed/uncertain usage, and
preserves unreclaimed scratch. Relation, Carrier and materialized task completion
share this boundary. Identical notifications cannot refund twice; changed ones
are rejected before any usage change. Final successful cleanup releases the
remaining scratch once. Ledger tests cover the historical early credit and
unused-retention retention, invalid owner/holding/range and duplicate calls.
There is no new owner, ledger or allocation-byte formula.

## Actual execution boundary

The typed corpus supplies the numeric/NULL `distinct/filter` operation pair and
empty three-column input. The probe constructs a source-free checked program
containing Values, DISTINCT and filter, opens the real source-free DAG, and uses
the installed Local dispatch module. It requires one physical task with neither
a selected step nor a selected prefix, and records actual chain construction.
Cancellation occurs after Values and DISTINCT have started but before filter
starts. A scalar-only observer counts child starts; it retains no provider,
payload or backing object. Existing backing/workspace observations identify the
actual DISTINCT cleanup transition. Observation strings and numeric counters are
instrumentation overhead, not measured production heap bytes.

Normal and false/error/retry cases require reservation retention until cleanup,
unchanged cumulative work, no child restart, no successful result publication,
and idempotent cleanup/credit. The pending case temporarily makes the actual
selected Session-backed child's cleanup return false and then error before
delegating to its original cleanup. It does not replace the provider or ledger.

The older diagnostic committed at `60c85b299` used a captured multi-stage
program. Its original sequence contained two steps, but the physical planner
selected only one step for the executed task. That diagnostic is evidence for
the same driver retirement defect on a selected DISTINCT child; it is **not**
serial-parent correspondence. The final regression rejects that route by
requiring actual chain construction and the unsplit source-free task.

## Evidence and remaining obligations

The existing capacity CI command runs `custody-check.mjs all`: two actual JS
mutations bypass the installed scratch confirmation or credit scratch at output
completion. Restored normal, pending and success correspondence runs on JS,
Wasm and native. Success uses the actual accepted-output completion boundary,
checks retained output and zero unused retention, and exercises false/error/retry
cleanup without restarting its three started children. The auditor binds each
requested target and cleanup mode independently to the reviewed fixture/input,
source overlay, command, log and archived target artifacts. Whole internally
consistent native reports cannot substitute for JS or Wasm. Audit unit fixtures
are synthetic verifier tests, not claims that MoonBit executed on those targets.

The JS mutation detects premature retirement at the actual task reservation
boundary. It does not establish mutation detection on other targets or a new
shrinking guarantee. Existing generator/shrinker resource checks remain intact.

This correction concerns owned/held scratch reservation, not GC completion.
Accepted output retention remains independently tracked by the existing owner;
this cancellation probe does not prove the last-holder boundary for successful
accepted outputs. Complete child/runtime allocation-byte bounds and the parent
256-byte allowance remain open. Conditional Lean parent-core propositions are
unchanged; this finite regression is not an implementation refinement proof.

Reproduction from a clean checkout with the pinned MoonBit toolchain:

```sh
node --test proofs/relation-pipeline/custody.test.mjs
node proofs/relation-pipeline/capacity/parent-control/custody-check.mjs all
```

Local development can use the single `js` argument. Full three-target evidence
belongs to the pushed-SHA CI campaign. Successful receipts, source/fixture/input
snapshots, logs and content-addressed artifacts are retained under
`.artifacts/relation-pipeline/capacity/custody/`.
