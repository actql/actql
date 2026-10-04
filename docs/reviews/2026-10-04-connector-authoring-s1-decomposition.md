# Connector author foundation S1: Salesforce Read/Effect decomposition and minimal entry

S1 of the connector author foundation work order (`docs/reviews/2026-10-04-connector-authoring-foundation.md`, published separately),
against OSS main `1ae27a69c` (#290, which includes A's exact DuckDB target from #291). This note records the decomposition tables,
the contract deltas and the migration targets; it is paired with the Draft PR
that implements the registry table, the typed exchange, the fixture and the
Salesforce Read through the new entry.

## 1. What S1 delivers and what it leaves out

Delivered in this PR:

1. Connector-owned `host-bundle.json` manifests and the generated table
   `adapters/connectors-builtin/installations.generated.mjs`. The version-string
   switch and the provider-named dynamic imports in `installed-source.mjs` are
   replaced; Salesforce is the first entry.
2. The common typed HTTP exchange (`adapters/host-common/http-exchange.mjs`):
   request `{method, path, query, headers, body}` and a response header
   observation limited to the declared allowlist, connected to the existing
   `invokeScopedCredentialOperation` and `callHttpsCredentialResource`.
3. A provider-neutral HTTPS fixture (`adapters/site-node/https-exchange-fixture.mjs`):
   route table, a request log that never keeps credential values, lost-reply and
   rate-limit faults, `Link` pagination. It drives the existing I/O boundary and
   replaces no authorization or Effect owner.
4. The Salesforce Read (query pages of one declared Resource) runs through the
   new entry; the existing expectations (`standard-host.integration.test.mjs`
   and others) are unchanged.
5. Effect: the capability contract type and the mapping to existing owners
   (§4). **Not connected.** `installed-effect.mjs` keeps its execution path.

Left to the next units: the Effect installer's registry entry (a unit with its
own approval, execution and recovery acceptance); removal of
`src/client_salesforce_host` (the provider-named package inside the common
runtime, 441 lines) and the 25 hand-written `clientProgramSalesforce*` exports
in `client_program_bridge.mbt`; declaration-fed registration literals in the
Site; a DuckDB manifest (its built-in entry keeps A's exact physical target as an identity part).

## 2. Read path decomposition (Salesforce, Embedded Local, one Resource)

Layers: **D** static declaration / **H** common helper / **P** provider MoonBit /
**I** platform I/O / **O** existing Run and Effect owners.

| # | Layer | Symbol (file) | In → out | Handle lifetime / where failure returns |
| --- | --- | --- | --- | --- |
| 1 | O | `connectEmbeddedLocal` → `loadInstalledSources` (`embedded-local.mjs`) | profile path → source adapter | Host lifetime; failure via `retainInstalledHostInitializationFailure` |
| 2 | **D→O** | `installedConnectorFor` + `loadInstalledConnectorModule` (`installed-connectors.mjs`, this PR) | `profile.version` → table entry → connector module | unknown version refused before any I/O (`InvalidInstalledSourceProfile`) |
| 3 | D | `checkInstalledSalesforceSourceProfile` / `installedSalesforceSourceIdentityParts` (`installed-salesforce-source.mjs`) | Host profile → shape check, identity parts (profile, Site profile, publication) | no credential value, no provider I/O |
| 4 | D | Site profile `loadInstalledSalesforceSite` (`installed-salesforce-site.mjs`) | secret references, origin, org, generation → `site` handle | Host lifetime, released by `adapter.close()`; failure via `retainSalesforceSiteCleanup` |
| 5 | D | `StaticDeclaration` restore `clientProgramSalesforceRestoreDeclaration` from retained describe bytes | published generation → declaration (catalog_cid must match) | load time only, no provider I/O |
| 6 | O | `prepare` (`installed-salesforce-source.mjs`) ← `installedSourceFor`/`prepareAcquisition` | checked owner → `{checkedSource, readTuple{connection, resource, 'read'}, physicalBinding{version, org_id, instance_origin, site_key, site_generation, connection_revision, catalog_cid, resource, fields}}` | `WeakMap preparations`; an account deny is refused here |
| 7 | O | `installNodeClientDispatchOwner.acquireSource` → `adapter.open` | prepared → captured source | closed by the dispatch owner; failure classified by `acquisitionFailure(not_started/stopped/unknown)` |
| 8 | P/H | `acquire`: currentRead → admitCheckpointReadApproval → `describeForAcquisition('plan')` → `clientProgramPrepareSalesforceAcquisition` → `AcquisitionStart` → `issueGrant(maxUses = maxPages)` → `readSalesforceIssuedBroad` → `Capture` → `OpenCapturedLocalHost` | declaration + requirement + observation → run handle → captured | `run` closed by `BroadClose` on success and failure |
| 9 | H | `driveQueryPages` (`salesforce-query-read.mjs`) | `nextPath()` → GET → `acceptPage(path, body)` → `complete()` | the page loop holds no semantics; failure calls `owner.interrupt()` |
| 10 | P | `SalesforceBroadAttempt` state machine (`host/broad_evidence.mbt`); `QueryRead`/`QueryPage`/`ReadProjection` (`catalog/query_read.mbt`, `query_page.mbt`, `read_projection.mbt`) | `(status, bytes)` → rows / next path / issue | pagination, limits, NULL/omission and row identity all live here |
| 11 | **H (this PR)** | `invokeScopedCredentialOperation` (`owned-invocation-context.mjs`) + `ownHttpRequest` (`http-exchange.mjs`) | `{method, path, query, headers, body, responseHeaders}` → one scoped invocation | invalid headers or query are typed refusals before sending |
| 12 | I | `callHttpsCredentialResource` (`https-credential-resource.mjs`) | operation → `{useCid, accepted, statusCode, headers (observation), body}` | journal claim → authorize → send → finish(succeeded/failed/unknown); 3xx refused, 401 invalidates the secret |

Salesforce declares `responseHeaders: []`, so its behavior is unchanged (the
observation is an empty array).

## 3. Effect path decomposition (single-row update), not connected

| # | Layer | Symbol | Owner |
| --- | --- | --- | --- |
| 1 | O (**Salesforce-fixed**) | `loadInstalledEffect` (`installed-effect.mjs`): the only accepted version is Salesforce's | common Host; **unchanged in S1** |
| 2 | H | `salesforceEffectSiteHooks` → `prepareCaptured` / `prepareRecovered` | connector |
| 3 | D | profile `writes[]`, publication `mappings`, `prepareExecutionMapping({resource, write{kind, fields, key, sources[{target, field, nullBehavior}]}})` | connector |
| 4 | O | `createInstalledEffectSite(...).execute` (`installed-effect-site.mjs`): openComputation → prepareCaptured → authorization gate → completeCapturedEffectRun; `EffectRunNoUncertainSend` | common Host |
| 5 | H | `refreshPreflight` → target observation GET → `check_effect_preview_target_guards` (a missing value is stale) | connector / common MoonBit |
| 6 | O | `bindDispatch` → `issueGrant(effect_commit, maxUses 1)` | gate decides, connector binds |
| 7 | **O** | `captureClaimedEffectResponse` (`effect-physical-dispatch.mjs`): `ledger.claimDispatch` (CAS) → `beginPhysicalFlight` → `execute()` once → `recordResponse` | **send-once is the common Host's** |
| 8 | P/I | `sendRawSalesforceSingleRecord` → `invokeScopedCredentialOperation` | connector Site driver |
| 9 | P | `write_rejection.mbt` (only 400/401/403/404/428 with a parseable body is `RowFailed`; everything else stays unknown), `write_single_response.mbt` (update = 204 with empty body) | connector MoonBit |
| 10 | O | `recordAdmittedRowOutcome` / `effect_row_recovery_action` (Dispatching → ReconcilePossibleDispatch, never resend) | common MoonBit |

## 4. Contract deltas (with counter-examples) and the Effect capability contract

| Delta | Current counter-example | S1 treatment |
| --- | --- | --- |
| Response headers reach JS and nobody reads them | `https-credential-resource.mjs` returns `response.headers`; Salesforce callers pick `{useCid, statusCode, body}`. Nowhere to read GitHub's `Link` or `x-ratelimit-*` | **Implemented**: declared allowlist (manifest `responseHeaders`), common caps (16 entries, 1024 B per value, 8192 B total), overflow is `HttpHeaderObservationExceeded` and never "last page" |
| A provider cannot set request headers | `accept: application/json` fixed, no `User-Agent`. GitHub requires `User-Agent` and recommends `X-GitHub-Api-Version` | **Implemented**: allowlisted non-secret headers (reserved names refuse with `ReservedHttpRequestHeader`); the driver declares them, nothing is hidden in provider JS |
| Query parameters are hand-embedded in the path string | `query_read.mbt` percent-encodes SOQL into the path | **Implemented**: `requestTarget(path, query)`; Salesforce keeps its locator paths (migration in S2) |
| Installer version switch | `installed-source.mjs:59,127,163` / `installed-effect.mjs:32` | **Implemented** for sources; the Effect installer is the next unit |
| Grant scope `connector_registration/revision` set as Site literals | `installed-salesforce-site.mjs:228,308,503,769` | **Partial**: the Host verifies the manifest declaration against the adapter's self-identification (`InstalledConnectorRegistrationMismatch`); declaration-fed literals are S2 |
| Idempotency and route asserted by provider JS | `installed-salesforce-effect.mjs:846` `'unavailable'`, `salesforce-effect-current-use.mjs:108` `clientProgramEffectApplyCapabilityFromCodes(…)` | **Type only** (below) |
| Multiple sources fixed to `realizationKey === 'duckdb-acquired'` | `installed-source.mjs` `loadInstalledSources` | unchanged; the first GitHub slice is a single Source (independent of #292) |

Effect capability contract, per operation. The declaration states a supported
capability; it is never evidence of this Run's success or of resendability.

```text
EffectOperationCapability
  operation            : String            -- grant operation name (e.g. salesforce:record:update)
  route                : SingleSerial | CollectionContinue
  failure_granularity  : Row | Set
  idempotency          : Unavailable
                       | Native { key_scope : String      -- where a key is unique (tenant/resource/...)
                                , validity_ms : Int64     -- how long the key is honored
                                , same_key_different_payload : Reject | Unknown
                                , recovery : ExactRead | Manual }
  reconciliation       : Exact | Manual | None
```

Mapping to existing owners: `route`, `failure_granularity`, `idempotency` and
`reconciliation` map one to one onto the fields of
`EffectApplyCapabilityObservation` (`src/effect_application/apply_capability.mbt`)
and replace the `'unavailable'` argument of `ledgerBasis(...)` and the code
arguments of `clientProgramEffectApplyCapabilityFromCodes`. GitHub's comment
creation is `Unavailable` / `Manual`; a lost reply stays unknown; no success
inference from body matching and no automatic resend. The connection happens in
the Effect installer unit.

## 5. First rate-limit and stop rules (implemented in S2)

- The connector classifies 429, and a 403 distinguishable by headers, as
  `RateLimited(retry basis)`; a 403 without those headers is an authorization
  denial.
- A 200 with `x-ratelimit-remaining: 0` is accepted as a page; the acquisition
  stops before the next request.
- The stop returns through the existing `acquisitionFailure(..., 'stopped')`
  with a typed reason; accepted pages and the unfetched range stay in the
  evidence. No new waiting mechanism, no automatic resend.
- The quota scope is recorded per authentication method; shared-quota
  enforcement is unimplemented at first and real acceptance limits concurrency.

## 6. Salesforce migration targets (S2 onward; each PR removes the old path)

| Target | Location | Destination |
| --- | --- | --- |
| Effect installer fixed to one version | `adapters/host-node/installed-effect.mjs` | manifest `effect` section + table |
| Provider-named package in the common runtime | `src/client_salesforce_host/` (441 lines) | provider bundle |
| Hand-written bridge exports | `src/connectors_builtin_node/client_program_bridge.mbt:6100-6431` (25), `client-program-dependencies.json`, `_rela` copy | generated provider bridge |
| Site registration literals | `installed-salesforce-site.mjs`, 4 sites | declaration-fed (verified by the Host) |
| Hard-coded read limits | `installed-salesforce-source.mjs:33-39` | declared limits |
| Operation name literals | `salesforce-query-read.mjs:8` `'salesforce:query:read'` and others | declared operations |
| Asserted capability codes | `salesforce-effect-current-use.mjs:108`, `installed-salesforce-effect.mjs:846` | the §4 contract type |
| Provider-only mock | `salesforce-effect-site.fixture.mjs` (never emits `nextRecordsUrl`) | Salesforce routes on the common fixture, with pagination faults |

## 7. Verification

Recorded in the PR description. Three-target MoonBit verification of provider
logic does not apply: this PR changes no MoonBit. Per-Host real I/O is the Node
Embedded Local path against the fixture only.
