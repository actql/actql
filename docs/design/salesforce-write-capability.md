# Salesforce write capability evidence

The registered Salesforce implementation owns its REST write profile. The
common Effect owner still owns Preview admission, row progress, durable claims,
unknown outcomes, and completion. A capability is not a mutation permit.

## Issuance and current use

`issueSalesforceEffectCapability` obtains the accepted grant from the existing
credential journal. The journal verifies its issuer signature and applies the
MoonBit scope, expiry, revocation, and remaining-use checks without consuming a
use. The runtime bundle identity comes from that verified grant. The Site checks
the exact org, request scope, operation, and current Catalog before exposing an
opaque capability handle. Copying its public CID/body does not copy the owner.

The Host Preview author requires that handle. Current-use refresh checks the
handle against every member request, the refreshed Catalog, and the actual
serial or Collections route. It supplies those authenticated facts to common
whole-set admission, which compares them with the approved Preview. Physical
dispatch still claims a credential use and rechecks current authorization.
Neither preflight success nor a previously issued capability authorizes I/O.

This is the existing trusted registered-implementation model. A signed grant
binds the admitted runtime and scope; it does not independently prove the
correctness of the loaded program or a malicious provider's computation.

## Internal 0.1 identity

`actql-salesforce-write-capability/0.1` is a provider-internal canonical JSON
body, hashed with SHA-256. It is not a new portable wire artifact or a decoder
for untrusted capability declarations. The body contains:

- API version; namespace, principal, environment, connection revision, org,
  Connector registration/revision, runtime bundle, origin, and Site generation.
- Resource and operation; selected fields sorted by name and the external-ID
  target field, if applicable. Each field includes its admitted type, null and
  default constraints, write/read flags, identity flags, and sorted references.
  Both sorts use UTF-16 code-unit order, the canonical lexicographic order
  (language.md, "Every lexicographic ordering"); not length first.
- Implemented route and profile: per-item mutation/failure, exact row errors,
  serial request ordering only for single-record execution, unavailable
  idempotency, and manual unknown reconciliation.

`write_capability.mbt` defines the complete canonical key inventory; its
white-box test fixes an independently calculated digest. No caller supplies
these flags or the evidence CID to the product Preview author.

Catalog occurrence, observation time, Run/dispatch identity, row target and
payload are not capability content. Different rows can use the same profile;
refreshing an equivalent Catalog does not invalidate an approved Preview.
Their exclusion does not remove execution binding checks: each request still
matches the owned grant and Catalog execution context. Payload/target identity
remains in the existing Preview and dispatch contracts. Metadata, runtime,
API, route, or stable connection-profile changes require new capability content
and cannot silently reuse approval.

## Recovery

Ready-row recovery reconstructs typed requests from retained evidence, checks
current signed authority, and reissues the profile. Common admission compares
its identity with the persisted Preview before sending. No-ready-row recovery
does not acquire mutation authority merely to inspect saved outcomes. It still
requires current evidence-read admission. Success and unknown are never made
retryable by issuing a new capability.

The Salesforce-specific Site hooks forward the same managed Effect owner to
both capture and recovery. Projecting the Host facts must not discard its
Request/Plan association: the installed row owner checks that original before
constructing requests or starting credential children. An equal Plan, a copied
record or the continued existence of saved capture DATA cannot replace it.

## Managed constructor placement

The described-record recipe composes the existing Native constructor
quantities with the same Host input, HTTP, credential and saved-response
owners. Body DATA uses the preserving parser; only the existing external-ID
URI constructor normalizes its target. A path refusal occurs after the
original API/resource prefix was constructed and does not erase that work.

Returned Describe metadata belongs once to the member capture. Its private
parser/writer workspace belongs to the Run's existing synchronous control
frame. The three member Describe HTTP occurrences retain their own bounded
response and secret material; they do not each retain another metadata parser
workspace. Targeted writes likewise preserve distinct capture, apply and
resume target reads. A create does not select a target-read capacity.

Provider capability, footprint and request recheck constructors use that same
control frame. Request JSON projection occurs after the request child's Native
constructor returns, so it also needs the control frame before parsing the
returned value/target. It cannot borrow workspace already dropped by the
completed child. The recipe retains the Native and Host results while reusing
only completed synchronous scratch. Failed/async construction keeps its
original prefix until the existing owner retires it; consumed attempts and
work are never refunded by this placement.


## Multi-select value projection

The existing Salesforce codec projects Multi-select Picklist API text into the
existing Array Contract with non-null String elements. Explicit provider null
stays null. Empty text becomes an empty array; otherwise exact semicolon tokens
retain order, duplicates, whitespace and empty elements. This is a vendor
physical projection, not a new Array type rule or permission. The provider's
[documented semicolon representation](https://help.salesforce.com/s/articleView?id=000387814&language=en_US&type=1)
and [duplicate-value limitations](https://help.salesforce.com/s/articleView?id=sf.picklist_limitations.htm&language=en_US&type=5)
do not justify sorting or deduplicating observed values.

An approved empty array is sent as empty text. A literal semicolon inside one
item and the exact singleton `[""]` are refused through the existing field
`InvalidValue` before request issuance: they cannot round-trip under this
projection. Other empty elements, including `["a", ""]`, `["", "a"]` and
`["", ""]`, are preserved. No escape or provider choice is guessed; provider
validation remains separate. Input, conversion and emitted Array nodes/text
consume the original caller's bounded budgets. These checks are not capacity
reservation, current authorization or a physical success acknowledgement.

Target observation and Preview keep the actual projected original value. A
provider returning null after an empty-text write is observed as null, never
substituted with the requested `[]`; existing Effect outcome and reconciliation
rules still apply. Fresh declarations use the existing Owner to issue their own
bodies/CIDs; saved original declarations and contract versions are not relabeled.

## Compound geolocation projection

A geolocation parent is read as one closed Object Contract. Its `latitude` and
`longitude` properties retain the existing Decimal Contracts of the actual
Describe components, including their declared precision, scale and nullability.
The original `compoundFieldName` association is required before the documented
component-name suffix identifies either role. A matching suffix alone, a
missing component, ambiguous roles or missing digit metadata cannot supply the
parent contract. Neither a generic Number fallback nor another metadata lookup
repairs that absence.

Provider numeric cells are converted from their exact original source lexemes
through the same checked Decimal Owner used for standalone Number fields.
Explicit parent null remains null; child nullability is checked independently.
Extra or missing properties and coerced string coordinates are refused. The
same original components remain with the read plan and are rechecked against
current metadata; digit, type, association and nullability drift cannot attach
to the old declaration. Current Site and read authority remain separate.

The emitted Object Contract includes the existing required closed-object flag
and passes the same checked Contract reader as other published fields. Binding
the caller's original Contract compares the Object and its two retained Decimal
children; its pair bound follows that fixed structure, while scalar and Array
plans retain their previous bound. A changed component Contract is still refused.

Compound parents are not write fields. Existing component-field mappings retain
their own declared writable flags, original target/Preview and checked decimal
body; compound read support does not turn a parent into a mutation target.

The retained plan adds bounded component references and tuples under the
original Describe field ceiling. During conversion, original response/decode
material, two canonical decimal strings, converted Object nodes and checked
values can overlap. Original byte/node/depth limits still apply, but these
bounds are neither a reservation nor an adopted normal capacity profile. The
original caller's custody and cleanup own their lifetime.

## Compound Address projection

An Address parent uses the same original Describe association boundary as
geolocation. Its documented component roles are selected only after
`compoundFieldName` identifies that exact parent. The scalar components keep
original API names, native types, declared Decimal digits and nullability.
Standard country/state integration values and country/state ISO codes are
separate text properties. The observed configuration selects standard label,
custom code, or combined properties; neither a code-to-name lookup nor a missing
component supplies another field or an executable grant.

The parent is one closed Object Contract. Its JSON and checked Contract reader
agree on the original fields, and caller binding compares the Object plus every
retained scalar component. Response projection keeps original text (including
whitespace, Unicode and leading postal zeros), explicit nulls and numeric source
lexemes. Missing/extra properties, coerced values, unsupported or ambiguous
roles and changed current metadata are refused, never truncated or re-probed.
Parent writes remain unsupported; mutations use only the originally declared
component mappings with the same target observation, Preview, authority and
cleanup responsibilities.

The existing ReadProjection retains the component references and bounded role
names. The original Describe fields, response bytes, decoded nodes, converted
text/decimal cells, Object nodes and checked values may overlap. Their original
byte/node/depth and caller lifetime bounds still apply; deriving the Object's
comparison work from the observed component count is not a new capacity grant,
normal numerical profile or claim that the entire whole-phase envelope is funded.


## Salesforce managed operation recipe

The installed Effect restores its original Mapping and Environment, then uses
the existing Source initializer to construct the original driver and its three
kind recipes. Native/Core recipe methods and their receivers are captured before
the initializer's reserve/current boundary; only their builder runs inside the
funded projection. The recipe's operation labels come from the same Describe and
write implementations. Labels and implementation limits do not issue a grant,
select a member, supply a row count or replace the current Account/Site check.

The native provider returns one opaque request/target/response/metadata
constructor quartet and its fixed/row capture quantities. The existing Core
composer consumes those original values without a Host tuple or Option
reconstruction. Core's checked Program supplies member and row multiplicity.
Capture, apply and resume Describe reads are distinct member occurrences;
target reads are distinct row occurrences for update/upsert. Each write retains
its own physical occurrence. A create does not acquire target-read authority.

Metadata output and decode workspace stay on the same input-staged Describe
child. Synchronous constructor scratch for other operations uses the original
control frame; an awaited HTTP child retains its own response, credential and
physical cleanup. Returned material remains charged when scratch
finishes. Failed or invalid asynchronous construction keeps the complete
original prefix until its existing retirement confirms release.

Hot and cold reconstruction use the distinct, originally quoted recovery
construction occurrence on the same Plan. It retains the original capture
extent and the same complete request constructor, including Host output parsing; the
completed capture coordinate stays spent. Existing Describe and row indexes
remain unchanged. It preserves both named
Describe and historical whole-Catalog recovery. Whole-Catalog metadata is
bounded cumulatively by the original raw-byte inventory, rather than multiplying
one full response by every Resource. The standard Node Store's object bound
also bounds an authenticated inner recovery wire; that byte bound is not a
memory allowance or a substitute for parser, Catalog and Preview construction.
Provider-specific identity admission remains separate from current authority.

The original initializer retains the driver and recipe projection before any
later Run uses them. Original native refusals propagate before child creation.
No replacement Ledger, submission, grant, mutation retry or physical ACK follows
from reading the quantities. Store custody, Unknown, pending cleanup and Saved
restoration remain with their original owners and must be exercised through the
matching ordinary installation in addition to focused constructor/caller tests.

## Original DELETE metadata projection

Salesforce's [Describe result](https://developer.salesforce.com/docs/platform/api/guide/sforce-api-calls-describesobjects-describesobjectresult.html)
reports the resource's `deletable` flag independently of `createable` and
`updateable`. The Catalog Owner retains that original Boolean as optional
metadata. Only explicit `true` can support a DELETE projection. Missing or
malformed deletion metadata cannot acquire that meaning; independent read
projection retains its existing behavior.

- Responsibility: `DeleteProjection` is a pure eligibility projection within
  the existing Salesforce Catalog Owner. It is not an execution capability,
  sealed Preview, credential use or physical deletion acknowledgement.
- Inputs and outputs: an admitted original Catalog observation, its existing
  Site or Local execution binding and the resource name produce an opaque
  projection only with explicit deletion proof and the existing record identity
  rule: exact `Id`, native `id`, and confirmed non-null metadata. No proposed
  value, writable-field mapping or fabricated absent value is required.
- Identity: the projection retains the original observation CID, execution
  binding and resource. Its observation identity follows exact original provider
  bytes. Existing Catalog bodies, declarations, Contracts and CIDs do not add
  the new flag or change their canonical serialization.
- Ownership: Describe decoding, native record identity and projection remain
  Salesforce-owned. Common Effect, Account, Credential Site and Journal retain
  their original Preview, authority, dispatch and outcome responsibilities.
- Synchronization: recheck uses the existing execution-binding comparison and
  the current admitted observation. A refreshed occurrence can have its own
  dispatch identity, but another org, connection revision, Site generation,
  namespace, original Run or authority scope cannot replace the original scope.
- Failure: absent, false or malformed deletion proof, missing or invalid native
  identity and foreign current observations refuse the projection. A successful
  read or an update flag does not repair those refusals.
- Cancellation: this synchronous projection performs no I/O and acquires no
  cleanup duty. Cancellation, Unknown and retained physical cleanup remain with
  the original acquisition and Effect owners; projection success cannot close
  those duties or make a mutation retryable.
- Resources: the existing bounded Describe decoder and field inventory own the
  optional Boolean and retained binding/resource references. Rechecking uses
  their existing resource-copy boundary. Byte/node/depth bounds do not issue
  capacity or authority, and dropping a projection is not physical release.
- Extension: this projection does not expand the existing write operation or
  request enums. A DELETE request must separately preserve its actual target,
  before/version facts, absent after-state, original grant and conditional-send
  semantics; an object or null stand-in is not a DELETE value.
- Verification: owner-level positive and refusal cases cover explicit proof,
  native identity, scope and current metadata changes, both Site and Local
  bindings, and unchanged existing Catalog identities. These boundaries do not
  establish a provider send, approved Preview, recovery or installed service.


### Input-staged constructor backing

The Salesforce recipe retains an initial extent and an immutable maximum for
its existing member capture and Describe occurrences. The maximum preserves
all installed codec limits; it is neither an up-front reservation nor a grant.
The checked Plan resolves both templates with the same original Effect ID and
row inventory. Its control quote includes the original maximum holders and one
fixed synchronous quantity frame before any input-dependent growth.

Warm capture excludes cold JSON/Catalog reconstruction. Its generated
capability inventory follows the original writer's fixed root and selected
field schema, including the possible external target and bounded reference
names. This changes constructor quantities without changing writer acceptance.
The original HTTP child already holds the complete receive window. After its
exact response arrives, the original native metadata quantity uses that owned
byte extent and the unchanged logical field/name/depth limits. The same child
grows before the response reaches provider decode, and keeps that backing
through its original release.

Cold reconstruction sizes its nested JSON/Preview/Catalog work from the exact
authenticated retained wire and Preview before the existing native callback.
The original capture child grows on the same parent, with no new occurrence,
attempt, transfer, Ledger or cleanup owner. Capacity refusal keeps that child
and all consumed work. Completing a synchronous constructor returns only its
workspace; currentness, failed-prefix duties and physical cleanup remain with
the original owners.


Target reads use the same input-staged physical child before their original
native observation/Host projection. Salesforce's selected outcome writer also
bounds the embedded typed outcome. The existing common Ledger/Receipt envelope
adds its original fixed fields to that byte bound; the existing codec refuses
larger foreign prefixes before parse. Other composed implementations select the
existing full-control fallback. This preserves the selected writer's complete
accepted output and the original maximum-codec path, without granting extra
bytes or treating arbitrary provider messages as a closed outcome.

### Current Describe construction geometry

The original physical Describe child passes its same received body to the
captured native quantity method before any provider decoding. That method uses
the existing Source lexical preflight, shared with the Source reader, to bound
only the next Describe parser/index workspace. A long scalar is not one JSON
node per encoded byte. The original metadata families, observation limits,
field/name/depth rules, grammar validation and failure paths stay unchanged.
A refused lexical scan retains the complete prior envelope; geometry does not
admit a Catalog or grant access.

The same initial staged metadata extent backs the bounded decoded Source String
and fixed preflight controls before the quantity callback. Preflight and the
later parser use sequential workspace peaks, while existing raw response,
metadata and physical-child custody remain held. The actual selected response
then grows only that original operation token. Refusal keeps its received body
and cleanup duties; this does not refund transfer, issue another attempt, alter
the parent limit or acknowledge physical retirement.
