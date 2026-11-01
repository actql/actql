# Native Effect preflight without a supplier

The public Native Local Effect branch still has no installed capture/reviewer
authority supplier. Its supported preflight outcomes are explicit:

- `AlreadyAccepted` permits observation of the same authenticated retained
  acceptance. It does not authorize a new attempt.
- `AuthoritySupplierUnavailable` means preflight completed, after which the
  public caller rejects with `LocalEffectAuthoritySupplierUnavailable`.

Authorization, selected Policy lookup, clock sampling, retention validation,
first compilation, original material binding, checked-Run binding, supported
shape checks, and the final current authorization remain in their prior order.
The material binding precedes the checked-Run binding. The preflight creates no
accepted Run or physical Source and returns no future execution carrier.

The private first-compilation intermediate contains only the four outputs
actually consumed by production binding calls: request, allowed compilation,
definition, and issued normalization materials. Actual opaque Owner identities
and their admission functions are unchanged. The outer Host/crypto references
remain responsible for cleanup, and a real Policy binding retains its same
Host, crypto and selected context.

Whitebox preflight tests assert the actual status/refusal and accepted-original
lookup behavior. Separate value and acceptance assertions call the existing
Policy and compilation Owners directly. Their same-original acknowledgement
loss, reopen, and foreign-preparation cases do not imply the unsupported public
CLI supplier has been installed. No test-only future assembly wrapper is kept.
