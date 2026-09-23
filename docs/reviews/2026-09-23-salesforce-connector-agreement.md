# Salesforce Connector implementation agreement

Base SHA: `8cae50b6c6c3d9ae5c5cf215e5820358d94b59fe`.

- Salesforce is the first external provider. Complete its declared capabilities
  against the individual Connector criteria in proposal section 22.5; do not
  treat PostgreSQL or Cloud staging as a prerequisite. Keep provider names out
  of common Engine decisions.
- Separate the static Connector Catalog from connection- and authority-bound
  Resource Catalog observations. A resource is usable only when the required
  fields, relationships, permissions, and completeness evidence are present.
  An inaccessible or failed describe is not proof of absence. Retain the exact
  Run-dependent observation and recheck current authority and schema before use.
- Use `Account` as the read-only comparison and a configurable dedicated custom
  object for read/write tests. Test a unique external ID, omitted versus NULL
  fields, types, and write constraints. No object name belongs in Connector
  product logic.
- Push down only semantics proven equivalent for the exact type and operation.
  A broader prefilter requires a no-false-negative proof and residual evaluation.
  One query and its complete locator chain form one finite observation, not a
  point-in-time Salesforce snapshot. A failed chain cannot be extended by a new
  query under the old observation identity.

The first implemented predicate pushdown is a bound, checked comparison of a
selected `int` field against an exactly representable 32-bit integer. It also
requires current `filterable` metadata and the admitted SOQL length bound.
Unsupported predicates keep the broad query; all queries retain the checked
Local residual. In particular, text comparison is not advertised as exact:
Salesforce normally applies case-insensitive, user-locale comparison, unlike
ActQL text equality ([Salesforce comparison operators](https://developer.salesforce.com/docs/platform/salesforce-soql-sosl/guide/sforce-api-calls-soql-select-comparisonoperators.html)).
- Implement single-record REST, then sObject Collections, for create, ID-based
  update, and external-ID upsert through the existing Effect contract. Bulk is
  later. Collections group eligible rows within one Effect Set member, map each
  response to its row identity, and never conflate row `continue` with the
  Effect Set's `attempt_all`. `halt` uses ordered single-record calls. An
  explicit `allOrNone=true` request is one provider-atomic typed command only
  where the existing contract represents it; multiple HTTP batches are not
  atomic as a set. Salesforce rollback is not a guarantee about every external
  side effect.
- Standard REST writes have unavailable automatic recovery. A response lost
  after possible dispatch remains `unknown` and keeps the Run in
  `needs_reconciliation`; do not infer historical attempt success from a current
  row or unique external ID. Preserve exact request, row and attempt identity,
  observations, and known outcomes without secrets. No automatic resend of an
  uncertain write. An intentional repeat is a new authorized business request
  with a new caller request ID, linked to but not erasing the original unknown.
  Administrative investigation does not relabel the Effect or terminate its Run.
- For update and update-side upsert, use `full_diff` and recheck every preview
  guard before the first write. A mismatch leaves every row unattempted with
  `stale_preview`. Do not claim atomic compare-and-swap for the custom object or
  extend Account-only `If-Match` behavior to other endpoints. Reject operations
  that require provider-atomic version conditions when unavailable; do not switch
  the approved create/update branch of an upsert after target drift.
- The live test org, custom object, external-ID field, and credentials are not
  assigned. Salesforce schema creation and writes are not authorized, and the
  Smooth Cloud connection must not be reused. Continue product implementation,
  local HTTP tests, independent fixtures, and a reviewable setup/minimum-rights
  guide. Mark live-provider verification incomplete until a dedicated org and
  Site secret-resolver reference are supplied; never store secret values in
  source, chat, or logs.

## Effect Set completion boundary

The Salesforce milestone includes a checked multi-member Effect Set through
the standard Host, not only a single REST write or response parser. This uses
the existing language and execution contracts; it introduces no ordered
cross-member workflow.

- Members of one Stage are an unordered `attempt_all` intent set. Failure or
  uncertainty in one member does not suppress another independent member.
  Actual dispatch order is evidence, not authored member order.
- `halt` and `continue` govern the stable row sequence **within one member**.
  Under halt, a failed or unknown row leaves later rows of that member
  unattempted. Under continue, other rows may proceed, but an unknown row is
  never silently resent.
- Before any mutation, the Host must check every member's preview, current
  authority, capability and target guards, plus the structured write
  footprints of the complete set. Unprovable overlap is a preflight rejection
  with zero writes. Multi-member partial-application risk requires the
  authenticated acceptance bound to the exact complete Preview.
- Each member retains its own input, target, identity, result and reconciliation
  responsibility. A member's rows remain distinct from Effect Set members;
  sObject Collections may batch eligible rows of one member but may not merge
  members or turn `halt` into an unordered batch.
- `accepted` needs a valid OperationRef and may satisfy the Run's outcome rule.
  Unknown takes precedence for reconciliation; cancellation does not erase
  applied results or relabel possible dispatch as never sent. There is no
  cross-member transaction, rollback or compensation graph.

Required product tests include: all members succeed; one member halts after a
row failure while another proceeds; continue after a failed or unknown row;
known success mixed with unknown; overlap rejected before every write; lost
response and restart without resending successful or uncertain work; and
cancellation that distinguishes unattempted from possibly dispatched rows.
Each test must assert the exact request count and order, member/row outcomes,
durable evidence and remaining reconciliation responsibility. The current
MoonBit identity and progress helpers do not by themselves meet this product
boundary: the checked Program, Preview, authorization, durable journal,
physical requests and final receipts must be connected before completion.

## Salesforce target and transport identity

The admitted connection records an exact Salesforce org ID. Catalog
observations, read/write projections, current schema checks, and the Site
credential configuration must retain that binding. An instance origin alone
does not identify an org. A change of org must fail before a credential use or
durable Effect send claim.

The Connector derives two distinct identities:

- The physical request CID binds the exact origin, method, request-target, and
  body. The HTTPS adapter sends that target without URL path normalization;
  unrepresentable paths fail before the credential use claim.
- The provider target identity is for whole-set overlap admission. The
  boundary CID binds the canonical org ID. The scheme CID binds RecordId versus
  external-ID field and its confirmed matching rule. The object CID binds that
  boundary, scheme, resource, and canonical target value. These are bounded,
  versioned canonical JSON preimages; they are not physical request CIDs.

An admitted single or Collections request retains its own target values and
exposes the corresponding footprint identities. Whole-set preflight must use
these request-derived identities, not a second caller-supplied target list.
Create requests have no existing exact target and require collection or opaque
footprint handling under the common Effect contract.

RecordIds use case-sensitive 15-character values with validated 18-character
extensions. A 15-character value and its valid 18-character extension have one
target identity. Distinct 15-character casing is not collapsed. For unique
text external IDs, the observed `caseSensitive` fact is retained and rechecked.
Case-insensitive ASCII values can be compared by ASCII folding. Without that
fact, or for case-insensitive non-ASCII values whose provider equivalence is
unproved, exact-target admission rejects rather than assuming disjointness.
The original target spelling remains in the physical request.

The common Effect Set footprint checker consumes these Connector-issued CIDs.
Create targets remain opaque until a provider record identity is known. Two
different schemes in one org cannot prove independence merely because their
hashes differ: an external ID and a RecordId can select the same record.
Every member's target inventory still has to be derived from its checked
Preview and admitted source rows before the first mutation.

## Fixed-SHA review disposition

The review in `02-salesforce-effects.md` inspected `66b42189d2bb17407776fd74ca0e7ea9ddf73d01`.
Its findings are a verification list, not a claim that every finding remains
open at later commits. At `eb451c24bb98c83bfa14fbff1119436f71820043`:

| Finding | Current disposition | Evidence and remaining boundary |
| --- | --- | --- |
| SF-1: external-ID dot segments changed after request identity | Fixed by `52feb781e` | The HTTPS adapter sends the admitted request-target without URL path normalization. Local HTTPS tests compare the actual method, target, and body with the request CID, including dot segments and encoded characters. |
| SF-2: unproven RecordId and external-ID target independence | Fixed at the Connector target boundary by `6b4fc8c40`, `311921b14`, and `ceea8df1a` | RecordId aliases and external-ID matching metadata produce org-bound, request-derived target identities. Unknown equivalence fails closed. This does not itself establish whole-Program Effect preflight. |
| SF-3: complete multi-member product path | Open | The standard checked Program still rejects nonempty Effects, and the standard Host remains Effect-free. The shared Run port, complete-set admission, Collections custody, final receipts, and restart fault matrix remain required. |

The Salesforce Site and common Effect tests pass 88/88 at the stated HEAD.
These are component and local HTTPS tests, not a standard Host multi-member
acceptance run or a live Salesforce-org test. The exact shared boundary and
acceptance matrix are recorded in
`docs/reviews/2026-09-24-effect-run-shared-port.md`. Do not close SF-3 or the
Salesforce milestone on the basis of the first two fixes.

Subsequent work added an atomic all-row Collections send claim (`8bcbbd105`),
one durable response body with per-row custody (`5fab9ad56`), a local HTTPS
send/restart fixture (`2e78a67c6`), and a MoonBit-owned same-member/Preview
batch check (`c8b2a1872`). These close physical batch-custody gaps, but they do
not establish the checked Program inventory, whole-set apply admission, final
Effect receipts, or the standard Effectful Run path. SF-3 remains open. The
isolated Salesforce org and write permission also remain unavailable, so no
live-provider verification is claimed.

The send binding checks the exact admitted Preview member, operation
kind, contiguous ordered row CIDs, logical row correlations, and derived keys
before durable claim. A local HTTPS fixture verifies zero sends for foreign
member, row range, row order, or locator and one send across a ledger restart.
The single-record REST path now uses the same MoonBit row rule for a `halt`
or `continue` member; Collections additionally require `continue`. Preview
admission builds the row index once, so each later send checks only its bounded
slice rather than rescanning the member's complete row inventory.
This is not yet an apply permit: checked input provenance, exact Preview-to-
physical payload equivalence, all-member preflight, current authorization,
and final receipts still require the shared Effectful Run port above.

## Capability comparison with Smooth Cloud

This is a design comparison, not an import of Smooth Cloud contracts. The
ActQL specification and machine contracts remain authoritative.

| Concern | Decision | Reason |
| --- | --- | --- |
| Static capabilities vs. observed resources | Already reflected | ActQL separates content-addressed Connector Catalog contracts from authorized observations and forbids partial discovery from establishing complete evidence. |
| Operation and field constraints | Adopt missing product projection | Smooth Cloud projects describe-level field permissions, keys, and write constraints. ActQL already requires typed capability and preview evidence; its Salesforce implementation still needs exact resource-level facts and conservative incompleteness. |
| Pushdown | Keep ActQL contract | ActQL requires value/type/order/duplicate preservation. Smooth Cloud's curated field allowlists and provider-specific preflight are useful comparison cases, not authority for semantic equivalence or a common Engine branch. |
| Authentication scope | Already reflected | ActQL's credential grant and use bind tenant, principal, Site generation, operation, origin, attempt, expiry, and use count more exactly than a generic readable/writable flag. |
| Partial results and retries | Already reflected; connect product path | ActQL distinguishes per-item failure, `unknown`, idempotency, reconciliation, and Effect Set policy. Smooth Cloud's per-row errors and repair reasons inform fixtures, but its operation labels must not replace ActQL outcomes. |
| Catalog sync and resource resolver | Adopt missing product path | Smooth Cloud separates metadata sync, selection, readiness, and repair diagnostics. Implement these for ActQL with exact snapshot and current authority checks; do not import Cloud tenant, billing, OAuth, or curated display policy. |

Comparison sources: Smooth Cloud `connector-spi` catalog sync, resource
resolver and write capability contracts; Salesforce catalog, read, write and
capability modules. ActQL sources: `docs/spec/protocols/contracts.md`,
`docs/spec/protocols/discovery.md`, `docs/spec/execution.md`, and
`src/remote_credential`. No new shared Capability abstraction is introduced
solely for this comparison.

## Optional local Salesforce CLI authentication

The local Site may use an existing `sf org login web` session. Connection
admission records the selected alias, org ID, username, and instance origin,
without a token. A Site execution session uses the public `sf org display`
and `sf org auth show-access-token` interfaces and checks the alias binding
before and after token resolution. A successful token is reused only in that
exact session for a bounded monotonic interval; concurrent refreshes join one
flight. Retargeting the alias affects future sessions and the next refresh,
not an already pinned session. A 401 invalidates the matching cached token
without replaying the request. Every HTTP use still has its own grant claim
and current authorization check. The token stays in the Site credential
adapter. CLI credentials and refresh remain CLI-owned;
ActQL never reads CLI private files or copies a refresh token. A changed token
for the same exact binding is allowed, but it does not retry an uncertain
Effect.

This optional Node adapter does not alter the Node-free native profile or the
explicit Site secret-resolver path. Failure does not fall back to Cloud. Live
CLI and Salesforce verification remain pending until the isolated org and
authorized scope are supplied. Controlled CLI and HTTPS fixtures cover the
local failure and redaction behavior in the meantime.
