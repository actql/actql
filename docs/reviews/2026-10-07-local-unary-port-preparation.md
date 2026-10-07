# Resumable unary completion-port preparation

## Scope and existing owner

The source base is `3a01ebcea5af032bb22cfe5b55132d0e36ad4b77`.
This unit uses the private `TrustedOutputPreparation` owner merged in #749.
It does not depend on the unmerged Values/binary preparation unit in #758.
Current Graph identities, public APIs and stored contracts remain unchanged.

The following bounded providers previously validated all output names and
retained-target spellings synchronously inside start. They now retain the
same owner's cursor and drive it in `PrepareCompletionPort` before row work.

| Operation | Existing bounded execution | Next phase |
| --- | --- | --- |
| General group, analytic, pivot | `bounded_group.mbt` | `ChargeInput` |
| Keyed and global COUNT | `bounded_global_count.mbt` | `ResolveInput` |
| Relation row window | `bounded_row_window.mbt` | `ResolveInputField` |
| Unpivot | `bounded_unpivot.mbt` | `ResolveInputField` |
| Unnest | `bounded_unnest.mbt` | `ResolveInput` |

No operation algorithm, scheduler, holding ledger or synchronous fallback is
added. Exact receiving/input bindings are still checked by the existing owner.
One resume transition scans at most one Unicode scalar or identity code unit.
The existing stop and input-availability checks run between transitions.
Only completed preparation issues a trusted output port. Its verifier captures
the existing live/rows references, not the execution state itself.

Pending preparation remains owned until cleanup. Cancellation clears only its
pending names; it does not retire borrowed inputs. On success the name backing
transfers to the completed port without copying. Later cleanup preserves that
output and its names. Repeated cleanup reports no further reclamation.
Pivot initialization failure also closes the pending preparation cursor.

## Independent boundaries

The seven checked/lowered private fixtures require these exact UTF-8 budgets:

| Fixture | Exact / one-short bytes |
| --- | --- |
| Group | 16 / 15 |
| COUNT | 22 / 21 |
| Sliding row window | 42 / 41 |
| Unpivot | 35 / 34 |
| Unnest | 35 / 34 |
| Analytic | 37 / 36 |
| Pivot | 20 / 19 |

Each target occurs twice and each canonical schema name once. The expectations
are literal fixture quantities, not usage measured from a successful execution.
The long group key repeats `é😀` 32 times: 192 UTF-8 bytes and a total port
boundary of 207/206. Quanta 1/7/256 must produce the same canonical rows,
cumulative physical work, logical budget remainder and workspace peak.
Stops inside all four cursor phases retain borrowed inputs, publish nothing
and reclaim their own cursor once. Unicode is not normalized.

The pre-existing logical exact/one-short work and workspace limits stay fixed.
Moving preparation into resume adds physical poll steps. The old COUNT total
is augmented by three scans of `count_0`, three phase transitions, the literal
schema lengths, three name pushes and one finish: 38 transitions. Its logical
work budget does not change. The other small fixtures derive their additional
watchdog allowance in the same way, rather than increasing logical limits.

## Product boundary and evidence gate

Five ordinary Programs place a unary operation followed by derive/select in
the producer Stage and pass its retained output to two consumer Stages. They
use 513-character names, fixed rows including NULL, real retained Store access
and the existing public Embedded Local harness. That harness checks exact
published names, ordered rows/schema, request reuse, delivered positive-progress
cancellation, the distinction between request and physical stop, retained
custody until stop, no additional dispatch and final snapshot reclamation.
These new Host cases are registered but are not yet execution evidence.

The route gate requires operation-specific limit, quantum and stop roles for
all seven fixtures and public roles for the five product cases. Removing any
of the 26 roles must fail. Production snapshots also include all five kernel
files; removing start, advance, finish or cleanup cursor connections must fail.
These source guards supplement runtime tests; they do not prove arbitrary
control-flow correctness by matching names alone.

## Executed checks and unresolved verification

All commands below used the bounded `scripts/local-checks.mjs` wrapper and the
pinned toolchain. Receipts refer to a dirty working tree at the base above,
not a clean submitted SHA or hosted CI success.

- The six-file JS selection (new preparation tests plus the five existing
  kernel fixture files) passed 63/64 at `run-FDimiv` / `focused-test-LKIJED`.
  All ten new cases passed. The remaining large-boundary window case still had
  its pre-resume poll watchdog. That watchdog now includes the independent
  58-transition preparation allowance; its final execution is unverified.
- The operation inventory and role-removal gate passed 6/6 at `run-H1SWmV` /
  `focused-test-ZVDjcR`, before the additional production-source guard.
- The first source-guard test found missing files in its source snapshot
  (`run-McdnSd` / `focused-test-pAXpUq`, 1/2). Those five production files are
  now explicit snapshot inputs. The corrected gate, all 20 production-call
  mutations and snapshot custody checks passed 4/4 at `run-i9BluX` /
  `focused-test-8DIRMN`.
- The final six-file JS attempt `run-vbA3Bt`, the narrowed window attempt
  `run-QFoh2x` and the seven-package Host runtime dependency build `run-VvskBw`
  timed out at 180 seconds. They are incomplete, not product success. The last
  build produced no usable runtime. No old runtime is substituted for it.
  Its stopped owner and process group were independently confirmed absent
  before reclaiming only its residual lock; original receipts were preserved.

The ordinary Host cases and final window correction remain pending.
Full Core, Wasm/Native, packed Local/HTTPS, stop-latency and
performance campaigns were not run. Native fixed-record/allocation/lifetime
correspondence is not certified by these portable checks.

Other synchronous completion preparation remains in Join, Nest, interval/as-of
Join and Sequence Match. Values, Append, Set and Cross Join have a separate
pending implementation in #758. Group's other initial metadata/evaluation
setup, general producer preparation and installed availability callbacks are
not certified by this unit. This is not Local Compute completion.
