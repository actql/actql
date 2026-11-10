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

## Installation metadata DATA alternative

The existing field generator separately reads
`InstallationPreparationSubjectFields` and
`InstallationPreparationCredentialScope` from `src/remote_credential`. It emits
`installation-preparation-fields.generated.mjs`: eleven original subject keys
and six per-use request keys. The opaque subject is not flattened into a CID
or primitive constructor. A new Common field, omitted output or unsupported
field shape fails freshness; the ordinary interface check runs this check too.
The old thirteen Run invocation fields remain byte-identical.

| Attribute | Existing authority and executable reference |
| --- | --- |
| Responsibility | `src/remote_credential/installation_preparation_subject.mbt`; `installation_preparation_grant.mbt`: closed DATA only |
| Inputs/outputs | `InstallationPreparationSubjectFields`; `InstallationPreparationCredentialScope`; generated subject/request keys |
| Identity | `InstallationPreparationSubject::cid`; `InstallationPreparationCredentialGrant::cid`; exact original declaration source bytes remain distinct from semantic Contracts |
| Ownership | `installation_preparation_scope_matches`: same opaque original subject; the actual Host/Site/credential and physical journal remain separate |
| Synchronization | Pure DATA construction and admission perform no asynchronous action or current permission check |
| Failure | Existing `RemoteCredentialIssue`; closed/canonical body, original subject and exact per-use mismatch refusal |
| Cancellation | No I/O is started here; this projection cannot acknowledge cancellation or pending physical cleanup |
| Resources | Explicit input/field/writer/decoder bounds and retained originals; these bounds do not supply funding |
| Extension | `generate-credential-scope-binding.mjs`: `checkInstallationPreparationBinding`; normal `interfaceGenerationFreshness` |
| Verification | `installation_preparation_wbtest.mbt`; `installation-metadata-credential-contract.test.mjs`; `installation-preparation-binding.test.mjs` |

The UTF-16 input lower-bound check precedes UTF-8 encoding. Subject/Grant/Use
readers retain their independent 8192/16384/4096 UTF-8 input limits; admitted
field bounds permit complete multibyte values, not a smaller ASCII-only route.
Their source snapshot, encode/decode/hash workspace, canonical wire and
original subject/grant/use references can overlap. Physical supplier and
cleanup custody must cover that actual lifetime before an operational caller
is connected. Cold DATA admission does not supply that operational original,
claim an ordinal or permit retry. The private
`installation-preparation-metadata.mjs` view and its canonical Node/RelA
bridges project these originals without supplying the actual Host request,
current Account/issuer or metadata resource supplier.

The view captures its actual runtime methods and receiver once, retains each
original behind a view-local opaque handle, and binds each returned control to
one same original subject. Grant projection is a named DATA record; the old
Run control and its seventeen-field projection remain distinct. Subject/Scope
constructors and primitive field projections are generated from Common; the
generated kinds preserve numeric fields without hand-maintained layout rules.
The existing compiler-binding shim alone unwraps raised results. The Node
bridge destructures Common tuples before projecting explicit protocol arrays.

The actual-runtime cases in
`adapters/host-node/installation-preparation-metadata.integration.test.mjs`
exercise exact independent subject/grant/use preimages, copied/foreign/mixed
scope refusal, per-operation/current-time/revocation/quota refusal, the existing
signature helper with explicit fixture keys, original callback receivers,
retirement and abnormal-result refusal. A cited test is not its execution
receipt. Fixture signing is not an authenticated operational issuer or a
durable use. The view's records, six maps, aliases, callbacks/receiver, field
snapshots, generated vectors, writer/decoder/preimage workspace and escaped
closures/bytes retain their actual overlapping lifetime independently of any
later physical call and current permission.


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

### Original Run current fences

A Run binding may explicitly capture `assertCurrent` as the original synchronous
Host/Site fence. Selecting it also requires the original awaited
`currentBeforeSend` observation. Both checks run before the nominal claim,
after the resolver await before physical send, and after the response await
before disclosure; the original Journal authorizes the same use again at the
final boundary. The synchronous callback receives no arguments or receiver,
and must return `undefined`. A Promise or boolean is not a current certificate.
Omitting this fence retains the existing caller behavior, rather than supplying
current-Host evidence implicitly.

During a final awaited observation the same binding retains its original bounded
response. Refusal keeps that response with the original binding until confirmed
retirement; it is not returned to a Connector. An unconfirmed outcome remains
with the original Journal and binding, blocks another claim or send, and is not
committed again by the error path. Physical binding retirement does not resolve
an Unknown Journal use, authenticate a saved publication, reclaim escaped
response aliases or supply a resource profile. The callback closure, response
alias, retained error and original control/Journal/material overlap remain in
the acquisition's retention inventory until their actual owners retire them.

The real Owner cases in `https-credential-resource.test.mjs` cover separately
counted identity/page operations, rotation before a page and across resolver or
response awaits, revocation/expiry despite equal material, every generated scope
field, bounded UTF8 material, cleanup before/after send, and response loss with the
original `unknown` use. Local TLS and SQLite cases are physical component evidence;
they do not establish live HubSpot identity permissions or installed public E2E.

### Private kintone API-token presentation

The same trusted binding installer may select
`secretPresentation: 'kintone-api-token'` for the original `kintone` Connector
registration. The default remains Bearer. The closed selector is captured in
the private binding, cannot be changed per operation, and cannot be combined
with the separate Google authentication dependency. Unknown presentations and
other registrations refuse before resolution or claim. No Connector-visible
secret, arbitrary header factory, public credential reference or new grant is
introduced.

The physical request uses the same privately retained original material in
`X-Cybozu-API-Token`, without a Bearer or password header. This follows
[kintone's authentication contract](https://kintone.dev/en/docs/common/authentication/).
It does not prove that a token covers an App, its related Apps, or any operation:
the existing nominal scope, signed admission, current Host callback, expiry,
ordinal and Journal authorization remain mandatory. Each Form or Records call
is a separate authorized Provider I/O use. Resolver changes cannot select a
replacement token or trigger an automatic account re-probe. Rotation,
revocation, response loss and retirement keep the original binding/Journal
responsibility and socket-close acknowledgement.

Both `x-cybozu-api-token` and `x-cybozu-authorization` are reserved at the shared
HTTP boundary against Provider request injection and response observation.
The controlled TLS fixture redacts both from route input and retained request
observations. Reserving the password header does not implement password
authentication. The secret ceiling, simultaneous header/response retention and
original acquisition funding obligations remain unchanged; this private
presentation is neither normal numerical funding nor complete installed
kintone read/write acceptance.

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


## Installed Row Site physical custody

`openRowSourceCredentialSite` and the Salesforce compatibility entry share
`openRowSourceCredentialCustody` for the original credential journal, Common
scope preparation, signing and physical retirement. The trusted installation
still validates its profile and key before opening that journal; the helper
is a private Host port and does not decide or widen any operation's authority.
The existing original decision, current issuer and Checkpoint entry fences
remain with their respective Site admission paths.

The shared signer preserves all scope members and the original task attempt.
Ordinary Row Sites keep task attempt 1; Salesforce retains its explicit task
attempt, org facts, origin and diagnostic classifications. Its private profile
projection adds the original `instanceOrigin` as `resourceOrigin`; it does not
regenerate the Account context, Site binding or any canonical contract. The
original profile and this projection, key/control/journal, pending scope and
signed envelope can overlap in the caller lifetime. This code movement is no
numeric reservation, baseline or zero-cost assertion.

Closing rejects new operations before the original journal closes. A failed
close retains the same journal and cleanup responsibility. Salesforce's
existing compatibility entry skips a confirmed close; the generic entry keeps
its original idempotent journal-close invocation. Neither a cancellation,
closed Site nor thrown diagnostic is a physical release acknowledgement.

## Credential Site failure handoff

The installed Host lifecycle module owns the synchronous Credential Site
failure handoff used by Salesforce's compatibility entries. It keeps the
original Site, primary failure and earlier cleanup handle; an unavailable
observation remains pending. The Site's independent journal release may proceed
while that earlier owner remains pending. This is the existing Site protocol,
not the ordered Host initialization protocol that gates downstream resources.
A completed Site or earlier owner is not closed again by this handoff.

The compatibility entry supplies its original fallback diagnostic code. It
neither retries provider work nor changes Checkpoint/current authority. The
same original aliases, error snapshots and retry closure remain with the
returned failure; relocation does not supply a reservation, numerical profile
or whole-Host funding proof.

## Google service-account assertion preparation

The Google setup consumes the existing Credential and installed Site owners.
`google-service-account-assertion.mjs` prepares private RS256 assertion/form
material from an already-owned native RSA private KeyObject, its declared
service-account identity, optional key ID and delegated subject, and an explicit
scope list. It loads no key file, parses no credential JSON, selects no scopes,
creates no account or grant, and makes no authentication or resource request.
Its protocol is the [Google service-account assertion exchange](https://developers.google.com/identity/protocols/oauth2/service-account).

The assertion fixes `alg=RS256`, the token endpoint audience and the form grant
type. Issue time and lifetime are explicit original seconds; the one-hour
protocol maximum and safe arithmetic are checked without reading or rounding a
clock. Absent delegation/key ID stays absent. Inherited optional fields cannot
add delegation, required fields must be own properties, and scope order and
cardinality are preserved. Unknown options, sparse/inherited scopes and Proxy
material are refusals. The signature uses Node's native RSA PKCS#1 v1.5/SHA256;
no caller-provided signing callback or algorithm name is a trust proof.

An empty private handle retains the native original key reference, bounded
original identity/scope strings and prepared secret form body. Copied or
serialized handles cannot retrieve request material. The key matcher checks
only physical correspondence with that same original KeyObject; equal exported
key bytes, issuer text or a fingerprint do not replace it. Neither matcher nor
successful signature establishes current permission, the key's external owner,
Google acceptance or installation currency. The existing credential supplier
must retain and check those original relationships independently.

The installer supplies explicit ceilings for scope count/total bytes, identity
bytes, claim bytes, signed assertion bytes, complete request bytes and native key
bits. Header/claim JSON, UTF8/base64/message/signature/form representations can
overlap during preparation. The private handle retains the key graph, metadata
and complete form body; a request projection adds wrappers that can escape to
its caller. These are not a transfer allowance, normal retained/workspace
profile or cleanup ACK. The original acquisition/Effect Ledger must cover those
allocations together with auth response/token backing, API material and reader
custody through confirmed physical retirement. The helper has no dispose or
mark-clean shortcut.

### Authentication use and resource use are distinct

A trusted installed declaration may register only its exact required Google
authentication dependency: `https://oauth2.googleapis.com`, POST `/token`, the
original service-account/key generation, optional delegated subject, declared
scopes and explicit bounds. Program text or a returned token cannot choose it.
The same existing Site issuer must separately scope an original auth grant/use
of the existing Credential types to that declared dependency and its authorized
parent acquisition/Effect request, original assertion bytes, Run/task/attempt,
expiry and current authority. The original API grant/use cannot be retargeted:
Common rejects a supplied origin/operation different from the original grant.

The physical Credential boundary must place the assertion in bounded private
form-body material, never a Bearer key/assertion or an arbitrary unauthenticated
send option. Do not hide its HTTP exchange in `resolveSecret`. Auth and API
operations retain separate nominal use, current/expiry checks and byte/request
accounting. Auth response loss remains that original journal/use's Unknown;
there is no resend, fresh assertion or reconstruction from current config for
that same use. Token issuance grants no API rights. A physical or installed
acceptance receipt must prove these connections independently of the pure
signature/reference controls.

### Original grant of an authentication claim

The existing SQLite Credential Journal's private `claim` result includes the
same signature-admitted `grant` it supplied to the original claimed `use`.
This is an alias of that original opaque grant, not a second admission, an
issuer, a public credential reference or an authority derived from equal data.
No stored grant/use bytes, CIDs, ordinals or transaction predicates change.
The alias adds one retained reference to the same claim result; its lifetime
and wrapper overlap remain part of the caller's original holding inventory.

The physical authentication caller prepares its bounded actual body and checks
its original parent/current/capacity before claiming. It then binds the
Common authentication request to that claim's original grant, parent use,
material and body, followed by the existing final authorization fences before
sending. Re-admitting the same signed JSON or using an equal issuer grant does
not substitute for that original. A `replayed` claim still refuses a new send;
returning a grant does not change response-loss Unknown or allow a new token
exchange. If COMMIT outcome is unknown, the call throws without returning a
claim result, even if a subsequent observation sees its durable row. Original
journal/custody and no-resend responsibility remain with the existing Owner.

### Native authentication material in the original binding

An internal trusted installation can register an authentication selection with
its existing opaque HTTPS Credential binding. `authentication` supplies an
explicit original resolver, its synchronous `assertCurrentMaterial`, original
service-account identity, ordered scopes, optional delegated subject, actual
key generation, positive lifetime and the existing signer's seven explicit
ceilings. There is no public profile/wire fallback or inferred generation from
a key ID, equal key bytes or Site generation. Unregistered preparation and an
incomplete registration refuse before resolving material.

`prepareHttpsCredentialAuthenticationMaterial` uses the actual original parent
claim, current/capacity callback and Journal authorization before lookup and
after the material/current awaits. The resolver returns its original native RSA
KeyObject, identity/scopes/subject/generation and explicit material expiry. Its
current callback checks that original selection; equality alone is not current
Account, grant or key authority. The original native reference and metadata are
checked again before the existing vendor signer runs. Signing lifetime is
clamped to that same signed parent grant, selected material and explicit signer
lifetime, without a new grant or token-derived API permission.

The returned material is an empty same-process opaque original, with no key,
form body, assertion, token, digest or CID getter. Private native material and
the original signer's request are retained by that binding until its operation
and request/socket references retire. Binding retirement is not GC/RSS recovery
or a failed resolver Reader's cleanup ACK. Resolver failures propagate unchanged
with their original cleanup handle to the existing caller's failure carrier.
No second lookup or new signing attempt is made on the same binding. A binding
with an auth registration cannot use the legacy Bearer port to bypass its still
separately completed original authentication exchange.

This preparation component does not send an auth request, claim/settle an auth
use, install a normal profile or mint a token. Its separately scoped exchange
is described below; preparation without that connection is unavailable for API
use. The actual Site issuer and installed material supplier remain separate
responsibilities. The resolver's material must carry actual generation and
current facts; a test fixture providing those facts is not an installed secret
supplier. The original native key/selection, registration and copied ordered
scopes/limits, parent claim/grant, resolver/current Promises, opaque reference,
signer JSON/UTF8/base64/signature/form backing and overlapping frames add to the
same original retained/workspace inventory. Positive local ceilings do not
supply numerical funding; normal supply remains None until that composition is
proved by its existing Owner.

### Private Google token-response projection

The Google vendor codec in
`src/connectors/google_service_account/catalog/token_response.mbt` reads a
received token response through the existing strict, bounded source JSON and
decode owners. Its private Node projection is for the physical Credential
supplier, never a Connector-visible Result or token-bearing diagnostic. It
requires HTTP 200, an explicit Bearer token type, a nonempty header-safe token,
and a positive, bounded integer `expires_in`. Error envelopes refuse even if
they also contain success fields. Duplicate decoded JSON keys, malformed UTF8,
unknown-depth and oversized extension trees refuse before token material is
returned. Unknown OAuth extension members are ignored only after the complete
response passes the same byte, node, depth and string admission.

The original physical exchange bounds `expires_in` from its trusted clock
sample immediately before the authorized POST, conservatively preceding the
server's response generation. Neither network delay nor awaited post-response
current checks restart that duration. The same post-response and final current
checks remain mandatory; an expired response retains the original Unknown use
and never installs a token or triggers another claim/send. This follows the
response-generation lifetime in [RFC 6749 section 5.1](https://www.rfc-editor.org/rfc/rfc6749#section-5.1),
without trusting a remote timestamp or replacing earlier grant/material expiry.
The retained send-time scalar replaces the former receive-time scalar in the
same original exchange frame; it does not add a timer, reservation or Owner.

An optional response `scope` is observed as an ordered token array without
sorting or deduplicating the original response;
absence remains absent. The codec neither substitutes requested scopes nor
authorizes a scope appearing in the response. The trusted original issuer must
check correspondence with its declared dependency. The advertised lifetime is
not an expiry decision: the physical owner applies its trusted clock and the
original parent, material, grant, request and current-authority deadlines. No
default duration, clock, refresh, retry, additional request or grant is created.
Non-200, malformed or rejected responses do not settle an earlier lost reply;
the original journal and Unknown semantics remain independent of this codec.

The private response object retains token and optional scope strings. Parsing
can overlap the original complete response, strict source tree, decode index,
UTF8 strings and scope array; projection returns the same token string and a
fresh scope-array wrapper. The installer must fund and retain these with its
original transport response, material, signing and API lifetime. Local codec
ceilings are not a normal capacity declaration, physical retirement, release
ACK or proof that a token is no longer reachable. There is no disposal shortcut
or public JSON serialization of this material.

### Original authentication exchange and token custody

The same private binding may complete its fixed Google authentication dependency
with `exchangeHttpsCredentialAuthentication`. Trusted preparation supplies the
original `authenticationGrant` and `authenticationScope` before resolving/signing
material. The existing Journal's signed prospective check verifies that scope,
expiry and current authority; it issues no durable use. The assertion lifetime
also respects that auth grant. The exchange must use the captured original grant
CID and full generated invocation scope, with its separately declared operation.
Neither the API grant's origin nor an arbitrary body/endpoint is substituted.

After the original current/capacity callback, the exchange owns the exact bounded
form bytes and claims its separate auth use. It supplies that claim's actual
signature-admitted grant, original parent use, opaque material and actual bytes
to the existing Common authentication request/bind/check functions. A second
equal-data admission cannot replace the original claim grant. Final authorization
follows every awaited callback and the supplier's synchronous current check;
reentrant retirement/cancellation also refuses before the POST. The request uses
the fixed HTTPS Google host and `/token`, form content type and exact content
length. No assertion is placed in a Bearer header and no unauthenticated-send
option is exposed to the Connector.

The trusted installation must supply the actual private vendor `tokenRuntime`
namespace and seven explicit positive `responseLimits`: `maxBytes`, `maxNodes`,
`maxDepth`, `maxTokenBytes`, `maxLifetimeSeconds`, `maxScopes`, `maxScopeBytes`.
The existing strict vendor codec consumes the complete bounded response. Scope
observations cannot enlarge the original declared set; absence stays absent and
does not become a grant. The binding retains the original response/codec object
and token privately. Its expiry is the smaller of the observed duration and the
original assertion, auth grant and material deadlines. Only confirmed outcome
COMMIT permits the token to be used. Its result exposes only the original use CID.

The first API request consumes the already claimed original parent use exactly;
it does not claim another first use or turn a replay into a send. Later pages
still claim their own uses. Each send retains original Site/current/expiry,
material membership and actual Journal authorization; no legacy secret lookup,
implicit refresh, replacement key/token or new assertion occurs. Response-await
current checks also precede returning the API response. A private token is not
Account authority, API scope or policy classification.

Response loss remains the original sent use's Unknown. A later refused exchange
cannot settle a previous completed/Unknown use; only the claim actually acquired
by that invocation enters its failure path. A fallible outcome COMMIT is not
automatically repeated or interpreted as unsaved. An unknown API outcome reply
remains held with that same token and original failure, even if a later durable
read sees success; a different page use cannot bypass that unresolved ACK. A
failed outcome recording also retains both its original request failure and
the outcome failure. Request/socket retirement and
binding close remain separate from durable Unknown resolution. The original
parent/claim/pair, body backing, full response and codec tree/string/scope backing,
token, native key, callbacks and overlapping frames remain in the original
retention inventory through their real retirement. No new Owner, queue, Ledger,
normal capacity or numerical profile is supplied by this connection.

The component TLS fixture routes the fixed Google HTTP/TLS server name only to
its own local server; it uses actual RSA, Common, signed Journal and SQLite while
issuing no live Google request or installed material authority. That qualification
does not establish ordinary installed or public authentication acceptance.

### Same-journal installation metadata admission

The existing SQLite Credential Journal selects the closed
`installation-metadata` control explicitly. Its frozen named grant projection
retains the same control's original Subject and Scope tokens. The Common
control checks their membership and same-Subject correspondence; JSON, equal
CIDs, inherited fields, copied tokens or a legacy array do not substitute those
originals. The original Run control still uses its exact 17-member projection,
and both controls retain the existing four-member use projection. Unknown
control purposes are refused, rather than interpreted as the Run layout.

Signature admission still uses the existing configured issuer/public-key map
and canonical Common signature reader. The existing tables, bounds,
transactions, use ordinals, revocation, outcome and close protocol do not
change. The actual signature-admitted claim grant remains beside its original
use. Reopening the same Journal does not refund an already claimed or Unknown
use or make a replay eligible for another physical send. A lost COMMIT reply
retains the existing typed uncertainty and original cause; it does not trigger
an automatic second acceptance or claim.

This admission is not an operational Host preparation, Account authorization,
current Site/material observation, egress decision or resource grant. Each
metadata operation still needs its own original occurrence and actual current
authority. The trusted Host must retain the actual publication request and
original declaration/database selection; later query/property reads use their
own authority. Retaining signed DATA does not restore a retired preparation or
create a new request for an old Run.

The named projection, its own-property descriptors, six-field snapshot and
Common Subject/Scope field projections overlap the original grant/wire,
signature, original tokens and prepared transaction state. These are bounded
DATA workspaces, not an adopted normal numerical profile. The existing
Journal remains the sole persistence/claim Owner; the actual Host/Site and
resource suppliers retain their independent duties.

The actual Common/SQLite counters are in
`adapters/site-node/installation-metadata-credential-journal.integration.test.mjs`.
They exercise original operation correspondence, copied/foreign refusal,
purpose separation, durable claim/Unknown/reopen, expiry/revocation and COMMIT
uncertainty. Explicit fixture Subjects and signing keys do not prove physical
metadata acquisition, installed authentication or the complete publication to
Run recovery path.

### Original installation metadata HTTPS binding

The existing scoped invocation envelope retains an installation Scope token
through its original Common control. `ownInvocationAuthorization` and
`invocationBindingsMatch` accept that control explicitly; the latter checks
both tokens against the same retained Subject. `invocationScopeFields` provides
only the original request DATA needed by the driver. It neither clones a token
into a primitive record nor interprets an empty opaque object as absent legacy
Run fields. Existing Run scope envelopes retain their primitive snapshot rules.

The same HTTPS Credential binding retains that control, journal, resolver and
the Subject fields projected with the generated declaration vector. Every
metadata call still has its own signed grant, exact operation/occurrence,
GET/origin/path/empty-body correspondence and nominal journal use. A missing
binding, foreign Scope, substituted request or unsupported authentication
dependency refuses before sending. No metadata operation falls back to a Run
grant or to an unavailable authentication exchange.

A metadata binding requires the original private synchronous `assertCurrent`
fence in addition to the awaited `currentBeforeSend` observation. The Host/Site
supplier must bind these to the actual publication request, checked profile,
current Account/issuer/Site/material/egress and original resource preparation.
The publication request alone proves none of those permissions or resources.
The physical boundary checks the synchronous fence after awaited observations,
immediately before claim, after secret resolution and before request
construction, and after the response/socket acknowledgement before disclosure.
Promise and boolean returns are refusals. Reentrant retirement and cancellation
are checked again after the fence; its return value never issues authority.

The first selected secret stays private in that original binding. Later calls
re-observe the same resolver under current authority and refuse replacement
material rather than sending it or re-probing another account. Response-loss
and post-response current refusal retain the original Unknown use. A fallible
outcome COMMIT is not repeated by the exception path; the original failure is
retained and blocks another send through that binding. Retirement closes new
admission and retains active work until the existing physical request/socket
and invocation release protocol acknowledges it.

The simultaneous inventory adds only an original Scope/control alias in the
owned invocation, the generated Subject-field snapshot and synchronous callback
in the existing binding, and its original pending-outcome error reference. A
resolver call overlaps its grant CID, Subject and request DATA envelope with
the original bounded secret. The response body/header backing survives the
awaited current check; original socket/callback cleanup remains independent.
This inventory does not establish a numerical reservation, material provenance
or a normal profile. Component fixtures use actual Host publication selection,
Common, SQLite and controlled loopback TLS with explicit private fixture
Account/current/signing material; they are not operational installation or
live-provider acceptance.

### Original Run response correspondence

The existing HTTPS Credential Owner can explicitly retain correspondence for a
legacy Run-purpose response. This is independent of installation-metadata
Subjects: neither control nor use is converted between those purposes.

- Run response responsibility: the Credential Owner retains the actual claim's
  signature-admitted grant and use. It does not re-admit a use CID to fabricate
  a physical acquisition or supply a new publication issuer.
- Run response inputs and outputs: `retainRunResponseOriginal` opts one call
  into private correspondence. The exact returned response, same control and
  same Journal admit a synchronous private receiver; ordinary response keys and
  default calls are unchanged. No secret, resolver or token material is exposed.
- Run response identity: the original response is a nominal WeakMap member.
  Copied responses, foreign control/Journal references and installation-metadata
  controls refuse. The original immutable Run-scope envelope, actual method,
  exact path, body length and response digest accompany the actual opaque pair.
- Run response ownership: one private record retains the original grant/use,
  control/Journal/scope aliases, response/body backing and fixed request facts.
  Escaped receiver references remain in the caller's original lifetime and
  capacity inventory; alias retirement is not physical release or Store ACK.
- Run response synchronization: correspondence becomes receivable only after
  confirmed outcome recording. It is historical DATA, not current Site,
  Account, credential-generation, approval, dispatch or publication authority.
- Run response failure: response loss and unconfirmed COMMIT expose no original
  response, and the capture path does not repeat the outcome COMMIT. Changed
  response bytes permanently refuse that record. A receiver exception cannot
  reclassify the confirmed Journal outcome or trigger another provider request.
- Run response cancellation: original claim, Unknown/non-resend, active socket
  and cleanup duties remain with the existing acquisition and Credential Owners.
  Receiving DATA adds no cancel, close, reservation return or release ACK.
- Run response resources: the opt-in record and frozen fact record overlap the
  original bounded body, grant/use/scope, control and Journal references. One
  SHA-256 workspace and digest String cover at most the original response bound;
  verification repeats that bounded hash without copying the body. Caller-held
  responses and escaped originals require whole-phase supply; this is no normal
  numerical-profile adoption or independent byte grant.
- Run response extension: this private legacy-purpose connection does not issue
  an installation-metadata Subject/use, saved publication holding, cold local
  Catalog, Provider success, terminal Run state or independent cleanup Owner.
- Run response verification: actual Common/SQLite/TLS cases check same-claim
  physical identity, copied/foreign rejection, byte mutation, receiver errors,
  lost replies, COMMIT uncertainty and purpose separation. These components do
  not establish complete installed publication, recovery or live service.


### Original bounded response byte observation

- Response reader responsibility: the existing HTTPS Credential Owner may take
  an internal synchronous `observeResponseBytes` callback from its original
  funded operation. It changes no grant, request, Journal owner or outcome law.
- Response reader inputs and outputs: the opt-in path uses paused binary
  `response.read(size)` with a fixed quantum of 16384 bytes and at most the
  remaining protocol body bound plus one. The callback receives each actual
  consumed chunk length before copying or checking body acceptance. No secret,
  raw body, quota-derived observation or terminal Effect outcome is returned.
  The binary read size follows the pinned [Node.js 22.22 contract](https://nodejs.org/download/release/v22.22.0/docs/api/stream.html#readablereadsize).
- Response reader identity: the callback is captured for that same call and
  requires its original Credential binding. It cannot replace the original
  grant, current checks, scoped request, use identity or saved claim.
- Response reader ownership: original request/socket and invalid callback
  borrowing remain with the existing binding. No result, error, callback
  settlement or numeric extent can supply a close acknowledgement.
  If native callback registration fails, the first unresolved original and
  cause stay in that same binding. Acquisition refuses before another claim
  or send, even when no current callback was selected and close has not yet
  been requested. Later failures cannot replace the retained original.
- Response reader synchronization: a conforming callback returns only
  `undefined`. A returned Promise/thenable is refused, but remains joined to
  the same request promise until it settles and the actual socket/request
  close events arrive. No rejection is detached to make cleanup appear done.
  Native registration precedes a replaceable public `then` observation. A
  constructor/species refusal supplies no native settlement witness: socket
  close or a caller-held resolver cannot acknowledge that unresolved duty.
- Response reader failure: every consumed chunk, including the final offending
  byte, reaches the callback before protocol refusal. A callback throw remains
  the original failure and stops the same response; callers retain unresolved
  accounting as pending. A partial lost reply never refunds its observed prefix
  or enables resend; existing Journal Unknown/non-resend law remains.
- Response reader cancellation: original signal/current and binding retirement
  still stop the same physical request. Pending socket or callback settlement
  keeps that binding pending; cleanup never starts another read or request.
- Response reader resources: `httpsCredentialResponseWindowBytes(B)` describes
  the implementation's B+1 consumed-byte refusal window, not actual usage or a
  larger accepted body. The selected Plan must fund that window, request/body,
  chunk headers/copies/concat, secret, response projection and failed-child
  overlap before I/O. Opaque Node/TLS buffers are not an all-wire/RSS claim.
- Response reader extension: omission retains the existing flowing reader and
  its original protocol cap. This internal observation does not enable an
  installed Effect, admit an initial parent or supply missing Source/service
  backing. The actual operation still selects and charges its same native slot.
- Response reader verification: actual TLS cases in
  `https-credential-response-accounting.test.mjs` cover binary lengths, a real
  offending byte, a consumed prefix before reply loss, both invalid callback
  settlements, charge failure and absence. Authority/Journal are explicit
  ports; these are not normal Account, Common funding or ordinary acceptance.


### Same original secret across Resource bindings

A separately authorized Resource can retain its actual parent binding as
`originalSecretBinding`. The Credential owner accepts only its same-process
opaque original with identical invocation/Site identity, control, Journal,
resolver, secret bound and presentation. Metadata-purpose, authenticated,
foreign, unfenced, changed, closing and retired originals refuse. No packet or Source
configuration selects this private connection. It neither shares a Grant nor
changes each child's current, physical request or Journal outcome duties.

The parent owns the sole pinned static secret. A first child send pins that
same original; every later parent or child resolver result is compared at the
existing before-send fences. A replacement latches refusal on the parent and
current child before a request can be constructed. There is no token cache,
secret copy in the Source driver, inferred Account decision or grace period.

The existing Credential state retains each dependent original reference and
one parent dependency count. Parent close remains pending until all such
children have really closed; child retirement clears its reference and allows
the original parent's existing retirement to run. Independent child bindings,
grants, current checks and pending/Unknown outcomes remain separate. The
selected native Source constructor quotes these reference/count fields; this
association supplies no physical cleanup acknowledgement. Focused real TLS and
Journal controls cover replacement-before-data-send, foreign invocation and
parent-close-before-child-close; the registered HubSpot caller retains its
original cross-binding resolver-change control.
