# Original Resident Review readback

This connection reads the original confirmed Review through an existing
`ResidentEffectReviewInputContext`. It does not reconstruct a physical
`NativeResidentEffectReview`, restore approval, or authorize Effect execution.

## Trusted selection and checks

The caller must supply the original live consumer context, its Site journal,
the independently installed Store authority and key, and the existing trusted
evidence-disclosure authorization callback. Run admission, Source authorization,
Store authority, CIDs, and matching snapshots do not supply that authorization.
The production CLI's `effect_evidence_read` default remains false.

The context's `facts` operation rechecks the original holder, journal,
retained-input borrow, and request. The journal chooses the original report for
that holder's dispatch; the common Run/Checkpoint binding admission checks its
sealed Checkpoint against the original admitted materials. The Store restores
and confirms the original continuation and paired Checkpoint without accepting
a candidate continuation body.

The bounded continuation codec checks the original Run, compilation unit,
consumer input binding body, Store authority, and all seven original request
fields. Its exact canonical comparison preserves data strings, rejects
duplicate or extra fields, and does not normalize or rewrite the saved wire.
The original sealed continuation and Review byte CIDs must match.

The saved Captured Run passes its existing contract admission. The existing
Preview admission checks the original Run and saved authoring scope, and its
semantic identity must equal the original Checkpoint's required artifact. The
existing Store Owner then authenticates that same saved Preview. After the
authorization callback, the context, original report, paired Checkpoint, and
Preview are read/confirmed again before returning the original Review bytes.
Current disclosure permission and the original consumer facts are checked once
more after that final Store read. Revocation at this last boundary refuses the
read without releasing or replacing original custody.

This read adds no reservation, Store write, Provider operation, new Preview,
Checkpoint, Run, or input capture. It does not retire any evidence custody or
transfer its cleanup responsibility. Missing, retired, conflicting or
unconfirmed original records remain explicit errors; there is no fresh-review
fallback. The codec fixtures alone cannot prove original issuance.

## Validation scope

The portable codec cases exercise exact data preservation, all request-field
substitutions, foreign Run/unit/input/authority, original byte and Preview
identity mismatches, closed fields, duplicate/noncanonical input, and unchanged
byte limits. They use independent codec values, not issued journal evidence.

The existing actual Native retention fixture calls this new method using its
real consumer context, original journal report, and Store. Added assertions
cover denied/revoked disclosure, exact original projection/report, foreign
authority, Store closure during the final authorization callback, successful
subsequent readback, and unchanged Store/Ledger reservations. Those new
physical assertions are compiled only until an explicit Native validation
window is assigned. Matching CLI compilation also does not execute it.
The integration repair additionally checks refusal at the third, final
authorization callback in that same Native fixture; this remains compile-only.

## Remaining boundaries

The context must already be restored by the existing input/consumer Owners.
Reading a projection does not restore the original full computation Receipt
chain, row execution handle, Ledger reservation handles, approval, or physical
stop/cleanup state. The production private installer/upload/resume must use
the formal restored Review Owner before approval and Effect execution can be
claimed. No replacement Preview, original request, or Run is prepared here.

Raw unadmitted Provider response durability and cleanup-only credential-use
observation remain separate unresolved contracts. This change grants neither
permission. Real TLS, Native crypto/Store execution, Provider, Cloud approval,
public Result, and formal release acceptance remain unverified.
