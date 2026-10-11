# Original consumer stamp cleanup

## Changes

The original consumer stamp can retain a charge in its completed producer's
CapturedDAG Ledger. Producer close requires that Ledger to have zero live
reservations, so waiting for producer Released before returning the stamp charge
would deadlock cleanup. The private holder now follows its existing actual
Review/Catalog/Resource, consumer Runtime, borrow and receiver cleanup, then
retires the same consumer's stamp and returns its exact original charge. The
formal Journal release guard belongs to the consumer; producer Released is not
required. The producer closes only after the consumer's cleanup finishes.

The retained consumer acceptance seam accepts an optional **actual original
completed producer** and a trusted Host-declared byte envelope. It verifies the
same Runtime/handoff/request and original Source Owner before selecting that
producer's CapturedDAG Ledger. Failed initial acceptance retains the same nominal
custody; duplicates mint nothing. No nonexistent Source funds producer initial
acceptance, no new Ledger is created for the stamp, and no production byte
coefficient is supplied here. The production CLI does not install this optional
funding path without its actual Host policy.

SQLite `remove_exact` requires an active, unfenced transaction and matching
scope/key/revision/body. The Journal verifies its original nominal custody and
formal consumer Released record in that transaction. Successful removal starts
one nominal cleanup continuation. Commit/readback must confirm absence on that
same Journal before the original reservation is settled. Arbitrary absence,
foreign/reopened Journal, failed acceptance and unresolved commit do not return
capacity. Settlement failure keeps the reservation; successful replay does not
settle twice. The API does not accept a caller boolean as physical cleanup proof.
The Journal step only confirms this control row; the private holder must first
complete the actual existing physical Owners.

An entered Catalog read with no original-use observation now queries the same
Resource Owner before closing its database. Unknown/missing use, a response
without confirmed Store cleanup, or cleanup failure retains the original duty.
It does not infer unsent from missing data, retry Provider I/O, or discard an
unknown claim to release the stamp.

## Scope and compatibility

Final merge target: OSS main. Submitted #1510 is an unmerged parent; its base
#1499 and D's Local preparation ancestry remain separate unmerged dependencies.
This branch normally includes accepted main d3555139c482d024d98ae9effd4bc5f3f73a8690.
The Native-only nominal custody fields are on the actual Native target, with an
opaque unavailable type on unsupported targets; no warning suppression or dummy
Ledger was added. Generated interfaces come from the existing generator.

Original dispatch/cancel/catalog-use/Review/Receipt/Result records and their
retention policies are unchanged. Cleanup does not grant read/write/approval,
prove Provider success, restart Source/Compute, or turn unknown into unsent.
Production evidence access remains default deny. Original Journal restoration,
actual Host permission supplier, installed byte envelopes and public Effect
acceptance remain separate incomplete connections.

## Validation

Use the fixed submitted SHA and the retained command receipts for final results.
The bounded non-heavy guard selects two JS exact-byte/revision counterexamples,
Native Journal and SQLite checks with --deny-warn, matching Resident and holder
compilation, C syntax checking, and whitespace checking. Native fixtures cover
transaction and exact-row mismatch, rollback, consumer-release fencing, lost
cleanup commit reply, foreign Journal, arbitrary missing stamp, replay and
original dispatch/cancel preservation. These Native cases are compile-only.
No Native executable, Provider, package producer, Heavy, deploy or Hosted CI is
run by this unit. JS predicate tests are not physical cleanup acceptance.

Preserved preparation failures: the old JS envelope selection discovered zero
tests after the accepted Native-only move; a new Native test helper initially
omitted its checked error signature. Neither failed run is a pass. The selector
and helper were corrected without relaxing discovery, warnings or limits.
