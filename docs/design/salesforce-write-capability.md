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

Compound parents are not write fields. Existing component-field mappings retain
their own declared writable flags, original target/Preview and checked decimal
body; compound read support does not turn a parent into a mutation target.

The retained plan adds bounded component references and tuples under the
original Describe field ceiling. During conversion, original response/decode
material, two canonical decimal strings, converted Object nodes and checked
values can overlap. Original byte/node/depth limits still apply, but these
bounds are neither a reservation nor an adopted normal capacity profile. The
original caller's custody and cleanup own their lifetime.
