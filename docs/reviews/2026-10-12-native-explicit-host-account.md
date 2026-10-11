# Explicit Native Host Account installation

The original Cloud submit principal is an authenticated identity fact, not an
Account permission. This unit connects an explicitly installed Account file to
the existing Common admission/decision Owner and the original retained consumer
caller. It does not activate the production Effect path.

## Trusted input and call order

The installing Host supplies `NativeEffectHostAccountFile`: a filesystem root,
relative filename, and the original principal, account, configuration CID,
authorization context CID, and separate read/publication connection/resource
selectors. Neither dispatch wire, Source grant, Workspace role nor Reviewer
supplies these inputs. No context CID is newly derived here.

`install_native_effect_host_account(None)` preserves None. A selected missing,
unreadable, malformed, oversized or foreign configuration is an installation
failure. The existing bounded Native reader caps UTF-8 input at 1,000,000 bytes,
checks the exact file generation, and retains physical read/close failures.
`admit_account_configuration_json` supplies the configuration and its CID;
Native does not reproduce JS canonical JSON or Account decisions.

The private `serve_holder_output` operator port pairs that opaque installation
with the existing authenticated Cloud Host identity reader. Admission is selected
from the retained original producer/consumer/journal context. The supplied
context CID must match the existing original Run admission's execution context.
The original consumer dispatch is the decision subject. The unchanged identity
read rechecks the original Cloud principal at every existing fence.

Every current permission call reads and admits the selected file, calls
`bind_dispatch_authorization`, then reads and decides again. Read uses
`read`/Acquisition; publication uses its independent selector and
`write`/Transfer. File deletion, changed configuration/account, malformed input,
explicit denial and missing match close the gate. A delegated configuration
without a currently verified Host answer remains unresolved and is refused;
this installer supplies no cached Permit or always-true current predicate.

Existing original custody/Site/receiver fences remain before and after the
fallible identity read and at the existing signature/send boundaries. Account
selection alone does not approve an Effect or grant Provider access.

## Evidence boundaries

Portable tests execute the Common Account Owner with independent configuration
vectors and a private file-read fault seam. They cover missing versus selected
invalid input, original configuration binding, deny/no-match/delegate, deletion
and revocation after the first decision, read versus publication, and a separate
explicit publication Allow restricted to the original receiver.

The physical Native bounded reader and actual holder caller are compiled, not
executed by these JS tests. No production CLI Account installation, real Native
filesystem acceptance, Cloud DO/TLS, Provider I/O, public approval, Result or
release is claimed. The private production port still defaults to None. A visible
never-constructed operator record documents the remaining production supplier;
it is not hidden by a dummy value or warning suppression.

No Journal, initial Catalog stamp, Ledger, credential Resource or cleanup file
is changed. No wire/CID domain, Run identity, Owner or grant is introduced.
