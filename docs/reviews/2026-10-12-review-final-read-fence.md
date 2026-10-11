# Review projection final-read fence

`ResidentEffectReviewRetention.review_projection` authorizes before evidence
access and reauthorizes before its final paired Store confirmation. Previously
that last confirmation returned the original Review plaintext directly, without
rechecking current evidence permission after the fallible read.

Keep both earlier checks and the same original report confirmation. Add the
current permission fence immediately after the final read and before returning
plaintext, then recheck live input/retirement custody after the callback. A
denial returns the existing `EvidenceDenied`; no original report, reservation,
borrow, persistence state or cleanup handle is discarded or rewritten.

The existing real Native retention fixture now includes a callback that permits
the first two fences and refuses the final fence. Before this change the call
would return `Ok` after only two checks. The new assertion expects
`EvidenceDenied`, three checks, unchanged reservation usage and the exact same
durable original report. The fixture's existing later successful projection and
normal cleanup remain required.

The new assertion belongs to the existing real holder/Provider/SQLite/crypto
fixture. Matching Native compilation is not execution of that assertion; no
physical acceptance is claimed until the fixed fixture is actually run in an
allocated validation window. This change does not install authenticated Host
admission, enable the production evidence gate, or complete internal
persistence/signing fences, Review/row restoration or public Cloud Effect.
