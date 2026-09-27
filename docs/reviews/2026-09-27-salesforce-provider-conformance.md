# Salesforce provider conformance

Base: `095b8b8c27c65dafb318dcfd83288595263c1ce4` (`origin/main`), branch
`feat/salesforce-provider-conformance`.

This record states, for each Salesforce capability the provider presents, its
constraints, provider entry, current authorization, local tests, live-org
tests and what remains. It replaces the "current" reading of earlier status
records; where [the R2 status](2026-09-25-salesforce-r2-status.md) says
discovery or Effects are "served" or "connected", read it as "assembled in a
test Host" as stated below.

"Local" means the HTTPS fixture org in `adapters/connectors/salesforce/test`.
It is not evidence about Salesforce. Live-org cells name only what was run in
the approved isolated org; identifiers, raw responses and data from that org
are kept outside this repository.

## Product reach

| Layer | Discovery (`resources`, `resource-inspect`, `resource-peek`) | Effects (create, update, upsert) |
| --- | --- | --- |
| Public wire and SDK operation | Defined in `spec/contracts/actql-client-host.json`, `packages/client-wire` and `packages/sdk`. | Ordinary Effectful submit; the standard checked Program still rejects nonempty Effects (agreement SF-3). |
| Assembled in a test Host | `installSalesforceResourceService` behind `createClientHttpHandler` (`salesforce-resource-service.test.mjs`). | The installed Effect route behind the public submit matrix (`effect-run.integration.test.mjs`). |
| Standard installed Host (`embedded-local`) | Not connected: `hostOperations` has no discovery handlers. | Not connected: the standard Host is Effect-free. |

The standard Host connection is owned by the Host owner; see
[Host handoff](#host-handoff).

## Capability table

| Capability | Constraints | Provider entry | Current authorization | Local tests | Live org | Remaining |
| --- | --- | --- | --- | --- | --- | --- |
| Catalog sync (list and describe) | Bounded listing; the first `maxSelected` listed objects are described. A truncated listing, failed describe or rate-limited describe leaves the observation incomplete, never absent. A targeted sync (`resources`) describes only named objects and is always marked truncated; it cannot be retained. | `installed.refreshCatalog`, `syncSalesforceCatalog` | Site credential grants `salesforce:catalog:list` / `describe`, signed by the Host credential authority and bound to Site, generation, org and dispatch. No Host policy decision precedes a refresh (see [Catalog authorization](#catalog-authorization)). | `salesforce-catalog-sync.test.mjs` (org binding, rate limit, cancellation, invalid describe, truncation); `installed-salesforce-site.test.mjs` (targeted sync) | Targeted list and describe of `Account` and the test object verified. Full sync not run: it would describe up to 200 objects, beyond the approved scope. | Host policy has no metadata operation: Host handoff. |
| Discovery list and search | One current Catalog observation per Site; snapshot truncation and display truncation are separate; a missing name is not absence. | `service.resources` over `installSalesforceResourceDiscovery` | Caller must be the principal the Site was installed for; each Resource is shown only under a current `acquisition`/`read` dispatch. | `salesforce-resource-service.test.mjs`, `salesforce-catalog-sync.test.mjs` | Not run: the service's `refresh` is a full sync. | Standard Host connection. |
| Inspect | Typed metadata as described (type, nullability, create/update, filter/sort, external ID, unique, case sensitivity, references). It is provider metadata, not an offer to read or write every listed field. | `service.inspectResource` | As list, per Resource. | as above | Not run through the service; the same describe summary was verified from a targeted sync. | Standard Host connection. |
| Snapshot restore | A retained snapshot must reproduce its observation CID and match tenant, principal, environment, org, Site key and generation, connection revision, origin and connector revision. Binding is not permission: disclosure is rechecked at each use. | `service.restore`, `recoverRetainedSalesforceCatalog` | No credential use; current `acquisition`/`read` per Resource. | `salesforce-resource-service.test.mjs` (foreign bindings; revoked read after restore) | Not applicable | None. |
| Peek | `maxRows` ≤ 200, one page, one-use query grant. Plans and rechecks on targeted syncs of the previewed Resource only. `ORDER BY Id` where the current describe reports `Id` as a sortable `id` field (`order: 'id'`), otherwise provider order (`order: 'provider'`). `limited` is true when the reply reached `maxRows`: more rows may exist. Readable types: `id`, `reference`, `string`, `textarea`, `email`, `phone`, `url`, `picklist`, `combobox`, `boolean`, `int`, `double`; others fail with `UnsupportedReadType`. | `installed.peek`, `service.peekResource` | Installed gate's own `acquisition`/`read` dispatch for this exact Resource. | `installed-salesforce-site.test.mjs`, `salesforce-resource-service.test.mjs` | Verified on `Account` (5 rows, `limited`, Id order) and the test object (all rows unlimited; 2 rows `limited`). | Decimal, currency, date and datetime reads need explicit conversion contracts. |
| Query read (Acquisition) | One query and its locator chain is one finite observation, not a point-in-time snapshot. Selected-field schema, permission and connection revision are rechecked before any query credential use. Exact `int` comparison is the only prefilter; the Local residual always remains. | `readSalesforceQuery`, managed physical driver | Separate `salesforce:query:read` grant per dispatch. | `salesforce-catalog-sync.test.mjs` (locator chain, page ceiling, schema and permission loss, type violations) | Only peek's single page; a locator chain was not exercised. | The broad Acquisition registration exists only in `src/query_integration/salesforce_broad_wbtest.mbt`; the standard compiler does not plan Salesforce reads. |
| Missing field and NULL | Reads: a missing declared optional property is typed null; missing required or wrong-type values fail. Writes: unselected is omitted, explicit null is a clear. This follows contracts.md "Deterministic Catalog generation". | Query page; write body | as the operation | `query_page_wbtest.mbt` (nullable missing values), `write_body_wbtest.mbt` (omitted versus null) | Verified: an omitted and an explicit-null create and a null clear all read back as null. | None. |
| Create, update by Id, upsert by external ID | Single REST calls for `halt`; sObject Collections (`allOrNone=false`) for `continue`, row-mapped. `full_diff` preview guards rechecked before the first write; mismatch leaves every row `stale_preview`. Not offered: `allOrNone=true`, delete, Bulk. | Installed Effect route, `salesforce-effect-write.mjs`, `salesforce-collection-write.mjs` | Record grants `salesforce:record:create` / `update` / `upsert` issued by `installed.issueGrant` only for the installed gate's own `effect_commit` dispatch. | `salesforce-catalog-sync.test.mjs`, `effect-run.integration.test.mjs` | Verified at the Site write entry points: create, update, upsert insert and update, duplicate external ID rejected (400, not success), Collections partial row outcome. The Effect Run route was not run live. | Standard Host connection; grant issuance after each commit decision (Host handoff). |
| Lost reply, rate limit, partial success | Lost reply after possible dispatch stays `unknown` and the Run `needs_reconciliation`; never resent automatically. Rate-limited and rejected rows keep their provider reason and are not success. | Effect route and Ledger | as above | `salesforce-catalog-sync.test.mjs` (lost reply across restart, rejected and malformed writes, partial Collections) | Fault injection only; not induced in the live org. | None. |
| Credential expiry, alias retarget | Session refresh after expiry; invalidation is token-specific; an alias retarget cannot redirect an authorized request. | `salesforce-cli-secret.mjs` | Site secret resolver | `salesforce-cli-secret.test.mjs` | CLI-resolved credential use verified; expiry and retarget not exercised. | None. |

## Changes in this branch

- Peek describes only its Resource. Before, each peek sync described the
  first `maxSelected` listed objects under a two-use grant, so any org
  listing more than one object exhausted the grant before the target was
  described. The local larger-org test reproduces that failure without the
  fix.
- Peek orders by `Id` where the describe allows it, and the recheck rejects
  the plan if a refresh no longer reports a sortable `Id`. This fixes the
  order of one reply only; reruns against a changing org may differ, and it
  is not a snapshot.
- The default list budget admits a full listing. It was 1,000,000 bytes;
  the live Developer org lists 1,603 objects in 1,865,419 bytes, so every
  default Catalog sync, and therefore every peek, failed there. The default
  is now 4,000,000 bytes, enough for the 2,000-object ceiling.
- The CLI secret resolver allows a cold `sf` start. A refresh runs three
  `sf` commands in sequence, and a cold start took 11 s against the 10 s
  per-command default; the default is now 30 s.
- Denial tests: discovery by another principal or for an unknown connection
  makes no provider request; a restored snapshot discloses nothing once the
  current account configuration no longer allows reading its Resource.

## Catalog authorization

A refresh is reached by the installed-for principal (the service refuses any
other principal before provider I/O) and uses that principal's own org
credential under Site metadata grants. Salesforce itself limits list and
describe to what that user can see, and ActQL discloses each Resource only
under a current `acquisition`/`read` dispatch. That meets
[discovery](../spec/protocols/discovery.md) for a Site installed for one
principal. It does not let the Host account policy deny metadata I/O on its
own: the policy vocabulary has no metadata operation, and
[execution](../spec/execution.md) lists no metadata boundary. That is a
shared authorization question for the Host owner; the Connector does not add
a Catalog operation class.

## Section 22.5 items 1 and 7

Item 1 asks for a canonical, recomputable static Connector Catalog and lock;
item 7 asks that the Catalog advertise nothing unimplemented. The existing
`actql.connector_catalog/0.1` can express the Salesforce reads (SourceView
with projection, filter and limit pushdown) and the three write Commands
(single target; Collections as `bounded_many` with `provider_best_effort`)
using existing values. Not offering `allOrNone=true`, delete or Bulk needs
nothing new. Three concrete common gaps keep this open rather than out of
scope:

1. No Catalog generator from a provider-schema snapshot exists for any
   Connector; Salesforce Resources are org-dependent, so a static Catalog
   needs one.
2. No contract field links a SourceView or Command to an installed provider
   entrypoint, so item 7 cannot be checked from the Catalog alone.
3. There is no machine contract for a Resource Catalog Snapshot; the
   Salesforce observation is connector-private.

The per-field pushdown limit (exact `int` only) is not expressible in the
pushdown body; the residual rule keeps a declared `filter` legal.

## Host handoff

Needed from the Host owner, with the provider entry points already present:

- Serve `resources`, `resource-inspect` and `resource-peek` in the standard
  installed Host from `installSalesforceResourceService({salesforceMoon,
  sites})`. Cases: another principal and unknown connection denied before
  provider I/O; restore after restart without provider I/O; revoked read after
  restore discloses nothing.
- Issue Salesforce record grants from each `effect_commit` dispatch the Host
  gate returns (`installed.issueGrant`), not once per Run as the test fixture
  does.
- Decide whether Host account policy must be able to deny Catalog metadata
  I/O, and in which existing vocabulary.

## Live org

Run on 2026-09-27 at `b29d5b356` against an isolated Developer org, with
`sf` 2.151.7, within the approved scope and a 200-call budget (109 used).
Identifiers, raw responses and record data are kept outside this repository.

- Read-only preflight: API remaining checked; a targeted Catalog sync of
  `Account` and the test object; an `Account` peek of `Id` only, 5 rows, not
  retained.
- Schema: `ActQL_Test_Record__c` with `External_Key__c` (Text 80, required,
  unique, case-sensitive external ID), `Optional_Text__c` (Text 255),
  `Amount__c` (Number 16,2), `Observed_At__c` (DateTime) and `Read_Only__c`
  (Text formula), plus a dedicated permission set granting only this object
  and its fields. No existing object, profile or permission set was changed.
  The schema and permission set remain; every record this run created was
  deleted and a count by its unique tag returned 0.
- Writes and read-back: the capability table's live cells.

Findings beyond the two fixes above:

- `org auth show-access-token`, which the CLI resolver uses, is missing from
  older `sf` releases (it failed on 2.118.20); 2.151.7 works.
- Fields deployed through the Metadata API are invisible to the API user
  until field-level security is granted; only the required field was
  described before the permission set was assigned.
- Salesforce describes `Number(16,2)` as `double`, so peek reads it as a
  Number and writes admit it. Values beyond about 15 significant digits
  are not exact as a double; exact decimal handling needs the explicit
  conversion contract already listed as remaining.
- `datetime` fields are neither readable nor writable yet; a write naming
  `Observed_At__c` is refused before I/O.

Not run live: full Catalog sync and the discovery service, a query locator
chain, the Effect Run route (Preview, Ledger, reconciliation), credential
expiry, schema drift, permission loss, rate limits and lost replies. These
remain covered only by local fault injection.
