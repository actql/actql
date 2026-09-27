# Salesforce on the standard Host read path

This records what connects a Salesforce source to the standard installed Host
(`adapters/host-node/embedded-local.mjs`): installation, publication,
discovery, Program Check, acquisition, computation and the Named Result read.
It covers the read path only. Effects, new decimal or date conversion
contracts and a general manifest redesign are out of scope.

## Installation

The Host profile version selects the installation adapter
(`adapters/host-node/installed-source.mjs`). One Host has one source.

- `actql-installed-duckdb-source/0.1`: unchanged behavior, now behind the adapter.
- `actql-installed-salesforce-source/0.1`: exactly these keys:
  - `siteProfilePath` (absolute; the installed Site profile, which holds secret references only);
  - `publicationPath` (absolute);
  - `connectorId`;
  - `resources` (the target Resources, 1 to 200 names);
  - `accountConfigurationWire`.

An unknown version or an invalid profile is refused before any provider or
Site I/O. The Salesforce adapter and its provider bundle are loaded only for a
Salesforce profile, so DuckDB-only and Workers installations do not load them.

## Publication

`publishInstalledSalesforceSource(profile, options)` is the explicit
publication step. A Host start never runs it.

- **Describe.** It describes exactly the target Resources. No provider sObject listing is read.
- **Write.** It writes one generation file, replaced atomically (temporary file, fsync, rename, directory fsync). The file holds:
  - the observation binding;
  - the Catalog CID and observation CID;
  - the target set and per-target states;
  - the retained describe evidence;
  - `complete: false`.
- **Restore at start.** A Host start restores the generation with no credential or provider I/O. Restoration is refused (`ForeignSalesforceDeclaration`) when any of these differ from the installation now:
  - principal, tenant, environment, org, connection revision, Site key or generation, origin or connector revision.
- **Other refusals.**
  - Another connector id or target set: `SalesforcePublicationTargetMismatch`.
  - Reformatted or edited text: `InvalidSalesforcePublication`.
  - A missing generation: `SalesforcePublicationMissing`.
- **Not authority.** A matching CID is not current authority. Every disclosure and read is decided again.

The Check Environment is the Host's base environment plus the published
declaration: Catalog, source views, contracts and manifest entry. It also
carries the source evidence members generated from the same declaration:
- one schema snapshot per view;
- one connector capability per view, which names the process-evidence contract the broad receipt uses.

Check never describes or regenerates anything. A targeted observation is
never given to a consumer that expects a complete Catalog.

## Catalog metadata authorization

Basis: `docs/spec/protocols/run.md`, account configuration. `read` covers "preparation input capture, acquisition and catalog, metadata or inference reads", and "the boundary kind belongs to the decision subject, never to the operation identifier". No new operation or permission is added.

- **Before any describe.** The Site decides each Resource with the installed gate. The decision is at the `acquisition` boundary, on the tuple (connection, Resource, `read`). Its subject is Site-derived (`actql-salesforce-catalog-describe/0.1`). This happens before any provider I/O; one denial refuses the whole describe.
- **Metadata decisions stay metadata.** These decisions authorize only the describe grant of that Resource. `issueGrant` refuses them for query and record grants.
- **Data-read decisions stay separate.** A data-read decision is never used to skip the metadata decision.
- **Listing.** The provider sObject listing is not used by publication, peek or acquisition, so there is no unauthorized listing path.

## Discovery

`resources`, `resource-inspect` and `resource-peek` are served by the standard
Host on HTTP and in process. Both entries use the same service, the same reply
validators, and the same public error classification
(`publicClientErrorCode`). Discovery answers only from the published
observation. With nothing published it answers `ResourceCatalogUnavailable`
and does not sync the org.

States and replies for a Resource the caller may see:

| State | Listing `outcome` | Inspect `reason` |
| --- | --- | --- |
| Outside the targeted observation (not checked) | not listed | `not_observed` |
| An authorized describe found no such object for this principal | `not_found` | `not_found` |
| The describe failed or the provider refused it (state unknown) | the failure, for example `permission_denied` | `describe_unavailable` |
| A provider listing was cut off by its limits | not listed | `listing_truncated` |
| A complete listing did not include it | not listed | `not_visible` |

A Resource the caller may not read is refused (`ResourceDiscoveryDenied`) and
left out of the listing, so neither its existence nor its absence is
disclosed. A provider permission failure is never reported as `not_found`.

`not_observed` and `not_found` were added to `actql-client-host/0.1` in the
same change: contract, generated validator, SDK types and README. This is a
contract change. A strict 0.1 validator built before it rejects the two new
values.

## Acquisition and runtime composition

The standard runtime (`connectors_builtin_node`, and its RelA variant) links
the pure `connectors/salesforce/catalog` and `connectors/salesforce/host`
packages through `client-program-dependencies.json`, the same way the DuckDB
host is linked.

`src/client_salesforce_host` and the `clientProgramSalesforce*` bridge exports
own, inside that runtime:
- restoring the published declaration from its bytes;
- the read projection (from a describe made under the acquisition's own dispatch);
- the broad query and candidate choice;
- the issued read;
- capture;
- Source Evidence (`actql-source-evidence/0.1`).

Only strings and bytes cross from the Salesforce Site's bundle. MoonBit
objects are never passed between bundles, because JS hash seeds differ per
bundle. The Site adapter supplies describe bytes, query pages, credential
grants and the current read decision.

- **Submit.** It prepares the checked source, read tuple and physical binding (`actql-installed-salesforce-target/0.1`) without provider I/O. A read the account denies is refused there, before any Run exists.
- **Dispatch.** Dispatch then runs these steps:
  - decide the read again;
  - describe the Resource (plan);
  - prepare and start the attempt;
  - read the pages under one query grant;
  - describe again (recheck);
  - capture;
  - issue Source Evidence while the read is still authorized;
  - compute locally.
- **Declared fields only.** The current describe must still fit the published declaration. A Program outside the declaration fails Check.

Bundle size (`moon build --target js --release`, compared with the base commit):

| Artifact | Before | After | Change |
| --- | ---: | ---: | ---: |
| `connectors_builtin_node.js` | 24,766,982 B | 27,190,666 B | +2,423,684 B (+9.8%) |
| `connectors_builtin_node_rela.js` | 22,510,113 B | 24,935,604 B | +2,425,491 B (+10.8%) |

## Shared with the Host owner

The shared points are the installation seam and the authorization handoff. The
Run, Checkpoint and dispatch owners are unchanged.

- **Installed-source adapter interface.** Described in `adapters/host-node/installed-source.mjs`:
  - `realizationKey`, `environmentWire`, `readAuthorization`, `sourceAccess`;
  - `admitsSource`;
  - `prepare`, which has no I/O;
  - `open`, which returns the capture the dispatch owner closes; on failure the adapter releases what it opened;
  - `discovery`, optional;
  - `close`.
- **Files changed on the Host side:**
  - `embedded-local.mjs`: adapter selection, discovery operations, source close, and an unplannable acquisition reported as `ClientProgramUnsupported`;
  - `client-dispatch-owner.mjs`: one call now goes through `sourceProfile.open`;
  - `in-process-client.mjs`: discovery;
  - `client-http.mjs`: `publicClientErrorCode`;
  - `installed-duckdb-source.mjs`: profile parsing split from installation.

## Verified

- Mock HTTPS org, through the public Client (`standard-host.integration.test.mjs`):
  - publish; a Host start with no provider I/O;
  - discovery and inspect, then Check, acquisition, local computation and the Named Result compared with independently expected rows;
  - refusals: an undeclared field fails Check with no I/O; an unsupported acquisition is refused as unsupported; lost read permission (nothing disclosed or acquired); another Site generation, connection revision or org; an altered generation.
- Site and service tests:
  - per-Resource metadata decisions; metadata decisions refused for query and record grants;
  - denial before I/O; permission loss;
  - restart restore; foreign generation and target refusal;
  - the five-state reason mapping; non-disclosure.
- DuckDB acquisition, resume after approval and refusal of another physical target, unchanged behind the adapter (`remote-acquisition-checkpoint.test.mjs`).
- Live, on the approved Dev org, through the embedded standard Host and the public Client:
  - an explicit publication of the dedicated test object;
  - a Host start from it; discovery and inspect;
  - a Program with acquisition and a compute stage, whose Named Result matched the 2 rows created for the check;
  - both rows were deleted, and none of that run remain.
  - Tokens were neither stored nor printed. Identifiers and logs stay in a private record.

## Remaining

- **Local compute input size.** Local compute rejects an acquired input above its inline import size with `FixedComputeIssue::LogicalIdentityUnsupported`:
  - for the test object this is about 2 rows of 9 declared fields with keys of 16 or more characters;
  - it was reproduced offline with the provider's real reply; the live check therefore used short values;
  - DuckDB acquisition is also tightly bounded (it fails while receiving about 60 passing rows);
  - this belongs to the Local managed lane, not to this unit.
- **Checkpoint-resumed read approvals.** The Salesforce Site grants only the installed gate's own decisions. A resumed read approval (`basis: resumed_approval`) is therefore refused (fail-closed), and the held→approve→resume path is not available for Salesforce yet. This needs an agreed handoff from the Checkpoint's resumed approval to the Site: which approval covers the read's describes and query grant in one dispatch.
- **Revocation between submit and dispatch.** A read revoked after submit and before dispatch is refused before provider I/O. The Run still projects `needs_reconciliation`, because the dispatch owner marks physical work as possible before the source opens.
- **Compiler shapes.** Only a scan→filter→select acquisition followed by a compute stage is supported. An `IN` filter over text cannot be planned (now `ClientProgramUnsupported`).
- **Packaging.** The Salesforce adapter runs from a repository checkout. The packaged Local Host does not include it.
