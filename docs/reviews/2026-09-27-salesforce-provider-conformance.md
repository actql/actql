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
| Query read (Acquisition) | One query and its locator chain is one finite observation, not a point-in-time snapshot. Selected-field schema, permission and connection revision are rechecked before any query credential use. Exact `int` comparison is the only prefilter; the Local residual always remains. | `readSalesforceQuery`, managed physical driver | Separate `salesforce:query:read` grant per dispatch; preparation requires the Site's declaration of the checked SourceView. | `salesforce-catalog-sync.test.mjs` (locator chain, page ceiling, schema and permission loss, type violations) | Only peek's single page; a locator chain was not exercised. | The broad Acquisition registration exists only in `src/query_integration/salesforce_broad_wbtest.mbt`; the standard compiler does not plan Salesforce reads. |
| Missing field and NULL | Reads: a missing declared optional property is typed null; missing required or wrong-type values fail. Writes: unselected is omitted, explicit null is a clear. This follows contracts.md "Deterministic Catalog generation". | Query page; write body | as the operation | `query_page_wbtest.mbt` (nullable missing values), `write_body_wbtest.mbt` (omitted versus null) | Verified: an omitted and an explicit-null create and a null clear all read back as null. | None. |
| Create, update by Id, upsert by external ID | Single REST calls for `halt`; sObject Collections (`allOrNone=false`) for `continue`, row-mapped. `full_diff` preview guards rechecked before the first write; mismatch leaves every row `stale_preview`. Not offered: `allOrNone=true`, delete, Bulk. | Installed Effect route, `salesforce-effect-write.mjs`, `salesforce-collection-write.mjs` | Record grants `salesforce:record:create` / `update` / `upsert` issued by `installed.issueGrant` only for the installed gate's own `effect_commit` dispatch; capability issuance also requires the Site's [declaration](#static-declaration-section-225-items-1-and-7). | `salesforce-catalog-sync.test.mjs`, `effect-run.integration.test.mjs` | Verified at the Site write entry points: create, update, upsert insert and update, duplicate external ID rejected (400, not success), Collections partial row outcome. The Effect Run route was not run live. | Standard Host connection; grant issuance after each commit decision (Host handoff). |
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

## Static declaration (section 22.5 items 1 and 7)

A Site generates its static declaration with `installed.declareCatalog({connectorId, resources})`, which is the explicit publication step.
- **Input:** a targeted sync of the selected Resources under the Site's own metadata grants.
- **Output:**
  - one canonical `actql.connector_catalog/0.1` Catalog, with one SourceView `records` per Resource;
  - the connection's `actql-connectors/0.1` manifest entry and its CID;
  - the writable fields of each Resource per operation;
  - the reason for everything left out.
- **Identity:** `connectorId` is the Host's logical connection id (no org identifier), and `connector_version` is the installed revision (`salesforce/0.1`).
- **Excluded from the Catalog and the entry:** the Site binding (tenant, org, Site, generation, origin). It stays with the Site-held declaration, together with the described field metadata.
- **Determinism:** equal selected describes give equal bytes and CIDs, whatever the listing or selection order.
- **Not authority:** generation and admission are not current authority, not an installed implementation, and issue no grant.

| Declared | Rule |
| --- | --- |
| Field types | Text types (`id`, `reference`, `string`, `textarea`, `email`, `phone`, `url`, `picklist`, `combobox`) as `string`, `boolean` as `boolean`, and 32-bit `int` as `number`, each only with confirmed nullability. |
| Not declared | `double` (Salesforce Number, Currency and Percent are decimal): binary64 `number` does not carry them exactly and no existing conversion law admits them as `decimal`. Also `date`, `datetime` and other types, and fields with unconfirmed nullability. Each is listed with its reason. |
| SourceView | `scan`, `read_content`, `snapshot`. Pushdown is `projection` and `filter`: only an exact `int` comparison is pushed as a prefilter and the checked filter always stays residual. `limit` and `order_by` are not declared, so no provider limit can precede a residual filter. |
| Writable fields | Per Resource: create, update-by-Id and upsert candidate fields, the upsert keys (unique, createable and updateable external IDs), and the required create fields. Create and upsert are withheld when a required create field is not declarable or its requirement is unknown. No delete, no `allOrNone=true`, no Bulk. This list is not a Mapping. |
| Commands | None. Salesforce Effects use Mappings. Row versus Collections routing and per-item atomicity stay with the existing Connector write capability evidence. |

**Manifest entry.** A Check Environment may carry the manifest as `connector_manifest`: `{version: "actql-connectors/0.1", connectors}` (contracts.md, "Connector manifest and authorization boundary").
- Each entry is exactly `{connector, connector_id, connector_version}`. Its identity is the canonical CID of the entry alone. The entry deliberately has no Catalog CID, Host path or `auth_binding`, so adding a connection, regenerating a Catalog or rebinding authorization changes no Mapping.
- Check admits a supplied manifest for every environment, whether or not any Mapping names it: strict CID order, unique connection ids, and each entry matching one Catalog of the same id and version. An environment without a manifest is unchanged.
- Every Mapping's `connector_manifest_cid` must resolve to one entry whose connection owns its `target_ref`.
- There is no cycle: a Mapping names an entry, an entry is matched to a Catalog, and a Catalog names neither.

**Execution Mapping.** `installed.prepareExecutionMapping({declaration, resource, write})` builds the Mapping of one Effect's write. Its single permission rule is exactly that write, because the common Effect Check matches a rule's write fields exactly. The write kinds are:
- `update` by Id of the named fields;
- `upsert`, where the external ID selects the record, is not a body field, and is named in the target schema, so the Mapping identity carries the key;
- `create` with an inline payload;
- `create` from a Named Result, with an explicit `row_mapping` whose null behavior is checked against the declared fields. A nullable, non-required field may use `omit`: a row whose source is null leaves that field out of its body, and only such a field may be absent. A required or `reject` field is always present.

The Mapping names the connection's manifest entry. Generated Mappings pass the existing Effect Check and compile for:
- a Name-only update;
- an external-ID upsert;
- a Result-backed create.

A two-member Run from a Named Result with a null and a present label, through a Site-generated Mapping that omits the null, also publishes. The provider receives the null row without the field and the other row with it.

The same Mappings fail Check when used for another write, and when their manifest entry is missing.

Before any I/O, the Site checks each use against its own declaration:
- **Writes:** write capability issuance requires the execution Mapping. The request must be exactly its write (Resource, operation, fields, upsert key), and each row body may leave out only fields the Mapping omits on a null source.
- **Reads:** broad query preparation requires that the checked source is the declaration's SourceView, and that every planned field is declared.
- **Field meaning:** every field a read or write uses, including the upsert key, must still mean what was declared (type, nullability, create/update, external ID, uniqueness, case sensitivity, references). A schema change under the same Site binding is refused with `SchemaChanged` until the Resource is declared again, with no credential use and no request.
- **Binding:** a declaration of another tenant, principal, environment, org, connection, Site, generation, origin or revision is refused, even when names and schema match.

Remaining concrete gaps:
- Exact decimal and temporal reads and writes need conversion contracts.
- The per-field pushdown limit (exact `int` only) is not expressible in the pushdown body. The residual rule keeps a declared `filter` legal.

## Host handoff

Needed from the Host owner, with the provider entry points already present:

- Serve `resources`, `resource-inspect` and `resource-peek` in the standard installed Host from `installSalesforceResourceService({salesforceMoon, sites})`.
  - Case: another principal and an unknown connection are denied before provider I/O.
  - Case: restore after restart runs without provider I/O.
  - Case: a read revoked after restore discloses nothing.
- Publish a connection's declaration explicitly with `site.declareCatalog({connectorId, resources})`.
  - Put its Catalog, SourceViews and contracts, and its manifest entry (under `connector_manifest`), into the Check Environment.
  - Keep the returned `declaration` with the installed Site.
  - After reinstalling, declare again: the same selected schema gives the same CIDs.
  - Never describe during Check.
- For each Effect, publish the Mapping from `site.prepareExecutionMapping({declaration, resource, write})`.
  - Pass that same `mapping` to `issueSalesforceEffectCapability`, and build row bodies with `salesforcePrepareExecutionWriteBody`.
  - Pass the `declaration` to Salesforce broad query preparation.
  - Case: another Site's or org's Mapping, another write's Mapping, a request whose fields or key differ, a row omitting a non-omitted field, and a schema change since declaring are refused before any credential use.
- Issue Salesforce record grants from each `effect_commit` dispatch that the Host gate returns (`installed.issueGrant`), not once per Run as the test fixture does.
- Decide whether Host account policy must be able to deny Catalog metadata I/O, and in which existing vocabulary.

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

Static declaration, 2026-09-27, read-only, at the code of this change (119 of 200 calls in total):
- **Generated:** a declaration, its manifest entry and three execution Mappings of the dedicated object from its describe.
- **Accepted:** the existing Check Environment admitted them. Effect Check and compile passed for a Name-only update, an external-ID upsert, and a Result-backed create that omits a null optional text.
- **Rejected:** using the update's Mapping for an upsert was rejected at Check.
- **Left out:** `Amount__c` (`double`) and the `datetime` fields, including the object's system date fields, each with its reason.
- **Not done:** no write was sent for this check.

This covers that one object only. It is not a result for every org, type or capability.

Not run live: full Catalog sync and the discovery service, a query locator
chain, the Effect Run route (Preview, Ledger, reconciliation), credential
expiry, schema drift, permission loss, rate limits and lost replies. These
remain covered only by local fault injection.
