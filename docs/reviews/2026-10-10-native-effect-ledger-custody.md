# Native Effect Ledger custody in the original Site journal

The resident Effect caller needs a durable common Ledger claim before sending,
and must save the physical Provider response before semantic projection. The
existing Node adapter already enforces this order. This change supplies the
corresponding Native SQLite storage seam in the existing Site journal. It does
not add an independent Ledger state machine, database, approval issuer or
scheduler.

## Ownership and ordering

`Journal::claim_effect_ledger_dispatch` accepts the existing typed scope,
locator, dispatch key and `EffectLedgerBasis`. The original dispatch must be
settled with active cleanup custody and have its exact saved Effect Checkpoint
report. The dispatch key must refer to that original semantic Preview.

Inside one existing `begin_immediate` transaction, the journal checks current
Site binding and cancellation, binds the locator to the original dispatch and
report, and records the common prepared/dispatching entries and head. Only the
common `effect_row_recovery_action_from_entry` decides whether to claim. The
successful commit returns `true` only for a newly claimed row. A failed or
uncertain commit returns an error: the caller must send nothing. If the commit
actually succeeded, subsequent claims observe the original dispatching entry
and return `false`; they must reconcile instead of sending again. Reopening
another physical journal does not create a new row or dispatch.

A storage claim is **not a Provider-send permit**. Its production caller must
also admit the original signed Resolution and exact checked Provider row,
validate current independent reviewer/Run authorization, and recheck the
existing Cloud resume fence and original holder/receiver lifetime. A saved
Checkpoint, historical approval signature or completed Compute grants none of
those permissions. These production checks are not replaced here.

`record_effect_ledger_response` stores immutable raw bytes and their credential
use/status/digest atomically. It checks the common dispatch entry and exact
original dispatch binding. A cancellation after sending does not erase the
response-custody obligation. A failed save leaves no response; a lost commit
reply is recoverable by inspecting the same entry or saving exactly the same
response. Conflicting bytes, status or credential use are rejected. No Provider
projection, semantic success, terminal entry, capacity return or release is
inferred. HTTP 409 and non-JSON bytes remain raw evidence. The existing journal
record-size bound applies; this change does not relax holding reservations or
claim that a storage claim reserves Provider/capture capacity.

`effect_ledger_response` reads original custody without sending or refreshing
identity. External evidence-view authorization remains the caller's duty.
Historical custody is readable after a Site binding becomes stale, while new
mutations are fenced. Original records are retained; this change does not
introduce or execute a cleanup/garbage-collection transition.

## Scope and dependencies

The final destination is OSS main. Both #1246's physical
credential transport and #1239's reviewed Resolution admission are now merged
in main; no unmerged parent is required. The latest main integration includes #1245's private Native retained
file test fixtures. No Cloud pin, formal package cohort, deployment binary,
Preview, existing Run or #88 recovery record is changed.

Current acceptance is a scoped Native SQLite diagnostic using protocol-authored
Checkpoint/row fixtures and actual common Ledger entries. It is not a genuine
resident Preview approval, a Provider write, a public SDK Effect Run, or formal
release. Follow-up wiring must use the genuine original review holder and
formal Cloud claim; no fake success/binding or permission fallback may stand in
for that connection.

## Validation

The three focused Native cases cover failed and uncertain claim commit,
competing journal handles/reopen, immutable intent conflict, failed and uncertain
raw-response commit, exact raw response replay, original-dispatch collision,
cancellation, stale Site mutation refusal, and physical record corruption.
Generated interfaces are produced by `moon info`; portable checks establish
compiler/unsupported-entry compatibility only. Hosted CI remains stopped.
The exact submitted SHA, commands and receipts are recorded in the PR body.
