# Original Native Review current-access seam

This is a private Host connection to the existing execution authorization
Owner. It does not install production access or complete Cloud Effect acceptance.

## Original admission and current decision

`serve_holder_output` now accepts `effect_host_admission`, selected with the
existing `HolderEffectOriginalPolicyContext`. The default returns `None`, so the
production entry still refuses protected evidence operations. No CLI principal,
account configuration file, poll field or inferred authority is added.

The installing authenticated Host must return `HolderEffectHostAdmission` from
its original admission custody. It contains the exact original context, original
principal/account/configuration/authorization context, fixed application
selectors, receiver origin, observation route and Site generation. The private
connection compares the original task, producer, consumer, journal, complete
materials and request references, and the fixed receiver/Site scope. This record
has no wire decoder or public issuer. Its fields alone are not authentication.

`read_current(purpose)` must read the actual current Host admission and decision
Owners, including authentication, policy revision and delegated permission
expiry/revocation. Its returned `current` fence must still validate that exact
admission after decision binding. An unavailable lookup refuses without retry.
The original configuration is pinned; a later configuration cannot replace it
even if it would independently allow the tuple.

The connection calls `execution_authorization.bind_dispatch_authorization` for
the original consumer dispatch and original Host authorization context:

| Purpose | Operation | Existing boundary | Resource selection |
| --- | --- | --- | --- |
| Private captured evidence | `read` | `Acquisition` | Original Host private-evidence selectors |
| Coordinator publication | `write` | `Transfer` | Original Host recipient selectors |

No new Core operation, permission Owner, Ledger, hash domain or public CID is
introduced. Delegated actions remain subject-bound by the existing Owner. A
Source grant, Store authority, Reviewer or unchanged material cannot supply this
permission. Read authority is checked independently of publication authority.

## Calling boundaries

Local Review progress, Catalog/Review preparation, Current observation and
completed Result projection select retained original context before calling the
gate. A remote Current query can only select an existing task; it supplies no
principal. The Review publication connection combines the separate current read
and publication decisions with the original installation fence. The existing
projection upload Owner receives that combined callback and rechecks it around
its protected reads and sends. Losing permission does not discard cleanup
handles, clear a saved outcome or release reservations.

## Concrete missing production source

The current `main.mbt::run_admission` returns
`remote_resident_host.ResidentRunAdmission`: compilation manifests, checked
execution profiles and limits. It contains no authenticated principal/account.
`run_publication_host.ClientRequestIdentity` contains the authority-scope CID,
logical request and checked intent, not authenticated identity. The existing
Site delegation contains execution/evidence capabilities, not the original Host
principal. These are not interchangeable admission sources.

The actual authenticated Host installation/request entry must retain and supply
its original principal/account/configuration and authorization context to
`serve_holder_output.effect_host_admission`, then implement `read_current`
against its current Identity/Account/decision Owners. The present CLI entry has
no such source and leaves the seam uninstalled. Cloud Reviewer authorization for
an issued Checkpoint is a different operation and is not used as a fallback.

Additional persistence/signing internals must receive the same current fence
before production access is enabled: outer publication checks do not establish
checks at every nested Store read or capture/report signing operation. This
seam does not claim that those internals are already connected.

## Limited evidence and remaining acceptance

Four authored Native caller cases cover read/publication separation, foreign
principal/resource/account/configuration, unavailable or revoked admission, and
revocation between binding fences. Matching Native checks compile these cases;
they are not executed physical tests. The existing portable Account binding
case separately exercises exact delegated subject/boundary and denial.

Actual authenticated installation, Native crypto/TLS/Provider reads, durable
Store and signing fences, original Review/row restoration, public approval,
Effect, Result and release remain required. Keep the existing finite
I/N/R/U/F/C/L acceptance scope and original failure evidence; this seam adds no
new completion condition and enables no deployment or Provider operation.
