# Credential interface references

This index projects the existing Remote Credential Owner; it adds neither a
permission rule nor a grant schema. Original invocation equality and current
per-operation authorization have distinct responsibilities. The generated
subject keys replace the previous adapter list in its original order. Operation,
expiry, quota and grant CID retain their separate existing Owner checks.

| Attribute | Existing authority and executable reference |
| --- | --- |
| Responsibility | `src/remote_credential/credential.mbt`: `prepare_credential_use`, `authorize_credential_use`; `adapters/host-common/owned-invocation-context.mjs`: `invocationBindingsMatch` |
| Inputs/outputs | `src/remote_credential/credential.mbt`: `RemoteCredentialGrant`; `scripts/generate-credential-scope-binding.mjs`: `credentialInvocationFields` |
| Identity | `src/remote_credential/credential.mbt`: `grant_cid`; `adapters/host-common/remote-credential-control.test.mjs`: `Remote Credential use admits only the exact active scope` |
| Ownership | `adapters/host-common/owned-invocation-context.mjs`: `ownInvocationContext`; `adapters/site-node/sqlite-credential-journal.mjs`: `claim` |
| Synchronization | `adapters/site-node/https-credential-resource.mjs`: `journal.authorize`; `adapters/site-node/https-credential-resource.test.mjs`: `revocation during secret resolution` |
| Failure | `adapters/site-node/sqlite-credential-journal.mjs`: `finish`; `adapters/host-common/sqlite-transaction.mjs`: `unknown`; `adapters/site-node/sqlite-credential-journal.test.mjs` |
| Cancellation | `adapters/site-node/https-credential-resource.mjs`: `signal`; `adapters/site-node/https-credential-resource.mjs`: `signal?.throwIfAborted` |
| Resources | `adapters/site-node/https-credential-resource.mjs`: `maxResponseBytes`; `adapters/site-node/sqlite-credential-journal.mjs`: `close` |
| Extension | `scripts/generate-credential-scope-binding.mjs`: `checkCredentialScopeBinding`; `packages/local-node/package.json`: `prepack`; `scripts/local-node-package-inputs.mjs` |
| Verification | `scripts/generate-credential-scope-binding.test.mjs`; `scripts/credential-final-fence-mutation.test.mjs`; `adapters/host-common/remote-credential-control.test.mjs`; `adapters/site-node/https-credential-resource.test.mjs` |

The generator reads the actual Owner declaration and refuses unsupported field
shapes. Adding a subject field or dropping a generated comparison invalidates
the independent freshness checks. The runtime scope negatives use the compiled
credential Owner, rather than replacing its decision with the projection.
The post-await revocation test uses the real credential journal and a local TLS
server; removing the final authorization must fail its no-request assertion.

A referenced test is not an execution receipt. Compiled runtime source, adapter
source, toolchain, actual counts and mutation results retain their individual
qualifications. No new compiled runtime, installed public product acceptance,
Provider service operation, or numerical profile is established by this index.


## Same-acquisition private credential binding

`openHttpsCredentialBinding` is a private physical adapter entry in the existing
Credential Owner. Its empty opaque handle binds the generated original invocation
fields to the exact control, journal and trusted resolver. Construction performs
no resolution, claim or Provider I/O. The installer must supply an explicit
positive `maxSecretBytes`; it is not a grant, a numerical profile, or a substitute
for the original acquisition's retained/scratch resource reservation.

Passing this handle as `binding` to `callHttpsCredentialResource` retains the first
authorized secret privately. Before **every** send the original journal claims a
separate nominal use, the actual trusted resolver is awaited, the complete secret
is bounded and compared privately, and the original current authorization is
checked. The physical request uses the retained original material. A different
resolver identity or invocation is refused before claiming. A changed resolved
material makes that acquisition binding permanently unavailable for further
calls; neither a replacement-token send nor an automatic account re-probe occurs.
No secret, digest, public reference, or equality oracle is exported to Connectors.

An account identity request is real Provider I/O, not static admission. It must
have an actually authorized grant and pre-registered operation, and consumes its
own original nominal use and response budget. A subsequent page has its own use
and current checks even if the material is equal. Observation of an account or
portal is not permission, policy classification, or evidence of current authority.
No extra identity permission or operation is inferred by this adapter.

Only calls selecting the new handle use an owned one-request connection. Their
full response or original transport error is held until both the request and its
socket have emitted close. `closeHttpsCredentialBinding` stops new calls and
returns `pending` while a resolver/call or physical request remains. It destroys
only that original active request; a sent request's interrupted response remains
`unknown` in the same journal. Repeated cleanup makes no new request or resolver
lookup. `closed` is returned only after the same original call and its observed
physical custody have retired; then the private retained secret is detached.
The ordinary caller must retain the opaque handle on its existing cleanup carrier
until this result. An unresolved resolver can therefore remain pending, rather
than becoming a fabricated close ACK. GC/RSS reclamation is not claimed.

The explicit secret ceiling bounds admitted complete UTF8 material. The trusted
resolver remains responsible for its own allocation and lookup: checking its
returned string is not a bound on an oversized string it already allocated.
Original/current material, Bearer-header construction, request/response buffers,
and the physical request/socket controls can overlap. The installer must account
for these along with the original acquisition and cleanup-pending lifetime.
This entry does not adopt a normal funding profile or classify legacy unbound
calls as same-acquisition evidence. No public wire, grant, retry or timeout changes.

The private physical call can additionally carry the original Host's
`currentBeforeSend` callback. It runs after the secret resolver await, receives
no credential material, and refuses by throwing its original current-access
failure. Its return value is not a grant. After that await, the same binding's
retirement/material checks, cancellation check and original journal
authorization run again; no await separates that final journal fence from
constructing the request with the retained original secret. A denied or failed
callback cannot turn into an unsent proof for an earlier attempt or bypass the
original nominal use. Legacy omission remains compatible, not evidence that a
call checked current Host policy across the resolver await. HubSpot account
observation selects its already captured original current callback here.

The real Owner cases in `https-credential-resource.test.mjs` cover separately
counted identity/page operations, rotation before a page and across resolver or
response awaits, revocation/expiry despite equal material, every generated scope
field, bounded UTF8 material, cleanup before/after send, and response loss with the
original `unknown` use. Local TLS and SQLite cases are physical component evidence;
they do not establish live HubSpot identity permissions or installed public E2E.

### Non-row observation response accounting

An accounted ordinary row acquisition exposes the private driver callback
`consumeObservation(charge)`. The driver first passes the complete received body
to `chargePage`, then uses this callback to consume that exact original ticket
after its own observation validation. Common's
`consume_row_run_observation_charge` accepts only the same accounted, reading
RowRun and an unconsumed ticket. Foreign, replayed, omitted, closed, or unaccounted
use cannot complete the read. Actual received bytes remain charged to the same
Ledger through capture and cleanup; the callback adds no data row or data page.
Unaccounted legacy drivers receive no such callback.

This separates an identity response from a data page without issuing identity,
permission, Source completion, or physical cleanup evidence. The installer still
must authorize and count each actual request, fit identity and data responses
within its original total transfer/request limits, and retain all overlapping
response, decode, credential and cleanup controls. This entry selects no extra
operation, permission, retry, numerical profile, or live Provider support.
`row_observation_accounting_wbtest.mbt` exercises the real RowRun/Ledger and
original bounded capture/cleanup. `installed-row-observation.test.mjs` consumes
the compiled Node bridge with an in-process driver; it does not test HTTP,
credential authorization, a normal tarball, or live HubSpot.
