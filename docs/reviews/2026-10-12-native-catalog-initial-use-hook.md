# Original Catalog initial-use hook

The private CLI installation now selects the existing Resource service with
initial-claim and post-save-use callbacks. Its original context comes from the
completed resident producer/consumer and same Journal, not grant/response wire.
The callbacks retain the original nominal claim through Resource selection and
Journal readback. Unknown claim/retention failures remain task-owned; no second
claim or fresh GET is inferred from missing use or Checkpoint evidence.

Saved-use restoration stays independent. Only an original Journal NotFound can
ask the original consumer's funded readiness API whether a separate legitimate
first-use path exists. That read must confirm the original accepted nominal
custody and revision-zero stamp. Resource NotFound, changed binding, stale Site,
or missing funded custody cannot select it. The Resource Owner subsequently
performs the real claim after its current authorization, then repeats its
current/lifetime/revocation fences before the actual GET.

The initial callback matches the complete installed credential scope, grant
and use ID. Its post-save callback accepts the actual nominal Resource use and
uses the same Journal/claim/original grant to retain it. A current-policy failure
after claim retains the claim and duty. The prepared evidence-read callback is
also passed into the existing guarded Resource call, so a current Host denial
inside claim/retention or before send is not replaced by an older installation
or Source permission.

## Remaining acceptance

This depends on #1533 and its #1513/Resource/Local ancestors, with main as the
final merge target after those parents. It does not choose production funding
coefficients or install a new first-accept marker into legacy/recovered work.
The real CLI acceptance must supply the original funded custody before this
legitimate path can become usable. Process-restart custody restoration and
cleanup of unknown response obligations remain required connection work.

The three added caller counterexamples are compile-only and cover missing
original readiness, rejection without consulting readiness for replacement or
changed observations, and every installed original scope field. They contain
no fake positive nominal readiness or Provider response. Matching compilation
does not complete actual Native/SQLite/Provider or public approval, recovery,
Result and release acceptance. Production default denial remains in place.
