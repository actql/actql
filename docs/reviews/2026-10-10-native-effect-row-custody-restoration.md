# Original Native Effect row custody restoration

This connection extends the original-holder approved-row implementation in OSS
#1257, integrated into main at `179c0e9df04dab7195370d26db87280b05944078`.
The final merge target is main; no unmerged parent dependency remains.
It does not complete public Cloud approval, process reconstruction of retained
inputs, Named Result publication, or formal Run release.

## Original responsibility

`Journal::effect_ledger_custody` reads the original dispatch, confirmed Checkpoint
report, exact dispatch/report binding, immutable common Ledger history and saved
raw response in one existing SQLite transaction. The common Owner validates the
history and row basis. It returns no new claim, Provider-send permission, capacity
return or semantic completion. A missing history entry, orphan binding, foreign
basis or uncertain transaction result is an error, not absence of responsibility.

The reader returns the original Dispatching entry separately from the current
head. A terminal head cannot change the identity used to find the raw response.
Historical custody remains readable after cancellation or Site binding change;
mutating settlement still uses the existing journal's current-Site fence.

## Native connection

`NativeResidentEffectReview::restore_row_custody` derives the original checked row
context and restores pending responsibility before checking new write permission.
It sets the cleanup guard before storage access and retains that guard on error.
An existing dispatch marks a replacement approved row as already started; it
cannot issue another Provider request. A historical terminal without a locally
confirmed common receipt remains pending.

`settle_saved_row` projects only the exact Store-owned raw response through the
existing catalog and common receipt Owner. It does not renew the signed
Resolution, obtain a claim, read the Provider, or send an Effect. Missing response
bytes remain unresolved. Receipt/head persistence failure retains pending
responsibility; confirmed repeated settlement is idempotent. The installed Host
continues to control evidence disclosure independently of current write approval.

Before retiring its bounded single-row review connection, cleanup reads custody
unless this connection already has a confirmed snapshot. Reopening the journal
invalidates that snapshot. Unknown storage is retried by the same connection;
known pending Effect responsibility blocks cleanup until common settlement.
An uncertain custody read does not start holder retirement. The read is
synchronous and invokes no caller callback; retirement starts only after the
pending-responsibility check, before the existing retention cleanup operation.
Cleanup narrows its configured Checkpoint budget to the existing common Ledger
ceilings (1,000,000 bytes, 1,000 nodes and depth 32). It does not pass the larger
Checkpoint budget into Ledger admission or increase either Owner's limits.
This guard protects this connection's temporary pins only; it does not mark the
consumer, producer or entire Run as Released.

## Verification scope

The new Native SQLite case closes and reopens the original journal and verifies
claim identity, exact immutable response bytes, repeated reads, foreign binding
and basis rejection, historical access after cancellation/generation change,
unknown read transaction completion and corrupt history rejection. These are
actual journal boundaries with protocol-authored Checkpoint fixtures; they are
not public Cloud approval evidence.

The original-holder physical Provider case is extended to remove current write
permission after one real write. It restores the same Store response, refuses a
new approved-row permit, retains capacity across terminal-save failure, and
settles/repeats the common receipt without another Provider operation. It still
retains its live original Source/Compute holders; journal reopening is not proof
of whole Host restart recovery.

At source `0fb0fa5bd5edb3c86eeb4e4965923e20a9425c22`, the new actual SQLite
case passed 1/1. The first attempt failed in foreign-fixture setup because a
different dispatch ID still used the original attempt; the corrected fixture
uses a distinct attempt and keeps the expected production rejection unchanged.

The physical Provider case reached one write, saved-response restoration and
idempotent settlement, but failed the existing later retention/admission
regression. A failed custody probe had prematurely marked the holder retiring.
Source `d2d3b9d78ad58e329b80f6a2f78f6014c7ae3ea8` removes that early state
change and adds an original-approval admission assertion after settlement.
At `c38b6bc1435953194427e4d0ab70894cdda8dbf2`, the corrected physical write
case passed 1/1, with physical Provider reads 1, writes 1 and final value 3.
The separate no-write case still failed: cleanup had reused a Checkpoint budget
with 10,000 nodes and depth 64, outside the existing Ledger admission contract.
The fixed-code cleanup diagnostic distinguished that pre-retirement refusal
from the expected physical retention failure. This correction narrows the
cleanup budget and retains the existing retirement fault expectations. Neither
the successful write case nor compilation substitutes for the no-write rerun.
Exact commands, source correspondence and receipts are recorded in the PR body.
Hosted CI, public SDK approval, Preview and formal distribution adoption remain
unverified for this unit.
