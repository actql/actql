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
