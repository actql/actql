---
spec_id: actql.protocol.discovery
status: adopted
version: actql/0.1
normative_dependencies: [actql.protocol.contracts]
---

# ActQL discovery

[Specification index](../README.md)

<!-- normative-import: actql.protocol.contracts actql/0.1 -->

This document owns publication-snapshot, describe, list, read, cursor, disclosure. It does not define other owners' wire protocols or a particular Host implementation. Cross-owner links outside the declared dependencies are informative navigation to protocol bindings or conformance evidence; they do not import those documents' requirements. Narrow machine contracts remain authoritative for their explicitly referenced values and envelopes.

<a id="discovery"></a>

### Host Discovery protocol

`actql-discovery/0.1` uses the closed descriptor, request, page, reference, and
read envelopes indexed above. `content_cid` hashes the complete canonical
artifact, including any embedded self-CID; it does not replace that artifact's
semantic identity. `page_cid` hashes the page without itself. Snapshot identity
hashes `{version, entries}` in fixed kind/selector order; `scope_cid` identifies
the authenticated disclosure context. The contract CID pins all schemas/laws.

Discovery publishes existing Catalog, Grammar, schema, and profile artifacts.
It is a Host companion, not an ActQL operation. Transport bindings and SDKs
share the following logical protocol; neither HTTP nor a server is required.

<!-- requirement-block: exact-artifact-surface generated-catalog-publication.product-e89a3fdd839b -->
| Operation | Request | Response |
| --- | --- | --- |
| `describe` | version and authenticated Host context | language/Grammar/schema/profile references and Host capabilities |
| `list` | publication snapshot, kind/selector filter, cursor, page size | bounded exact references (`kind`, `selector`, `content_cid`), query scope, completion flag, next cursor |
| `read` | publication snapshot and exact artifact reference | canonical artifact or typed failure |

Descriptors distinguish full profile conformance, partial implementation, and
current authority. Their `host_capabilities` reference names an exact
`actql-host-capabilities/0.1` artifact: advertised profiles carry contract CIDs
and `conformant` or `partial` status; an empty list makes no execution claim.
These claims confer no execution authority. SourceView and Command details
are read from the referenced exact Catalog, not returned inline by `list`.
ModelTask references use their contract CID as the discovery selector; the
Program's task selector is resolved separately against the admitted contracts.
Exact references distinguish published revisions; listing one does not choose
a revision for checking. A future summary projection requires its own identity.

Publication snapshots fix contract publication, not business data or execution
authority. Pages use a fixed selector/ID order. Cursors bind snapshot, filter,
and authorization scope; mismatches fail, and expired snapshots require restart.
`complete` means enumeration of that query's visible scope only, never complete
SourceView resolution evidence. Summaries and redactions have distinct identities.
Exact reads cannot return truncated artifacts. Caches respect current disclosure
authority; secrets, bound values, and private locators are not summaries.

Artifact admission validates kind, selector, ownership, CID/body, and transitive
closure separately from issuer trust. The compiler consumes the explicitly
supplied complete Check Environment. Discovery does not sample rows, invoke
models, or grant execution authority; provider-backed publication refresh is
separately authorized. Discovery CLI commands are transport projections of
this protocol.

<a id="generated-catalog-publication"></a>

### Generated Catalog publication

Discovery MUST expose generated contracts with schema snapshot, type/field
mapping, capability and generator-law identities through authorized publication.
It does not fetch a provider schema during ordinary Program checking. A changed
generation input changes the appropriate lock identities; secret rotation is
separate. Partial discovery projections do not become complete Catalog evidence.

<a id="machine-contracts"></a>

## Machine contracts

These exact schema/law references are owned here. Their identities do not include this document or another owner's aggregate contract.

<!-- requirement-block: machine-contracts.exact-artifacts -->
<!-- normative-code: law -->
```text
../../../spec/contracts/actql-discovery.json#/schemas/host_capabilities sha256:cb8bec73fdbbd866778284090af411502298bbef1d2f472cdaf1caa6cd110423
../../../spec/contracts/actql-discovery.json#/schemas/discovery_reference sha256:0ab236e1f68df896212836a9c4f6d46792595aff2c066e611cfd51b5892a6c16
../../../spec/contracts/actql-discovery.json#/schemas/discovery_descriptor sha256:7eca298d771158cb26d6b2a2e02297755507ca75f4f3c33a68e1c4bab2607674
../../../spec/contracts/actql-discovery.json#/schemas/discovery_list_request sha256:4064c2e50b9baca0978c704c213f544260aa567d46993330a69481a2df763295
../../../spec/contracts/actql-discovery.json#/schemas/discovery_page sha256:6c52fabd737a5ce26f6ac54c23d49c1c1c4b613d9620e4cbe2ada752b474b048
../../../spec/contracts/actql-discovery.json#/schemas/discovery_read sha256:60073d1039f5e7c21eda2b0d35b1afb638f156cf360b42e9c970d39325a23b78
../../../spec/contracts/actql-discovery.json#/laws sha256:12864726ec82b77f53881d35fbfe2ad8b4ca2024ba005df363aaf6e81c8cd4c7
```
