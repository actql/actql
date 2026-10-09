# Collection-only Mapping admission

## Completion unit

The shared Mapping contract now supports an explicitly declared collection
create without inventing a provider row identifier. This is the prerequisite
for Sheets AppendCells, not completion of the Sheets connector or its public
read/write acceptance.

Base: `b40818e09295dba39de6b570b977610e95c75b1e`.

`primary_identity` remains required. A string selects the existing nonnullable
scalar row key. Explicit `null` means there is no provider row identity;
omission, unresolved identities and inferred row positions are not accepted.
Every permission rule in this shape must be `create` with selector `none`.
The common permission owner rejects all row-addressed operations, including
update, upsert, delete and ID selectors, before provider dispatch. There is no
row-reference capability conferred by this shape.

The provider-neutral write declaration additionally supplies a nonempty typed
`collection_identity` object. The common Mapping factory binds those facts,
the connector registration, Resource kind, exact target and connection
boundary into `actql.collection_resource_identity/0.1`. The Mapping reference,
Mapping CID and Preview therefore change when the collection changes. Existing
row-addressable declarations and their preimages are unchanged. This does not
change Source read keys or admission for other capabilities.

Effect, request, attempt, receipt, approval and Ledger identities remain
separate from provider row identity. An append acknowledgement cannot establish
a future unique row lookup. Neither row numbers nor equal-valued readback may
be used to settle an unknown write.

## Owner and evidence map

| Boundary | Implementation | Executed evidence |
| --- | --- | --- |
| Required field, explicit null, every rule, exact work | `src/check_environment/mapping_contracts.mbt` | `mapping_contracts_test.mbt`: exact three units and two-unit refusal; omission, invalid rule/selector and modified CID refusal |
| Requested operation and selector | `src/check_environment/mapping_permissions.mbt` | Collection-only create accepted; update/upsert/delete/store and non-none selectors rejected |
| Declaration and reconstructed physical binding | `src/client_row_source_host/mapping.mbt` | `mapping_wbtest.mbt`: no invented ID, changed collection changes identities, invalid declarations refused |
| Existing static Effect candidate | `src/stage_results` | `effect_static_candidate_test.mbt`: literal create reaches the existing checked owner |
| Normal Program preparation and fresh owners | `adapters/host-node/collection-mapping.test.mjs` | Values/create Program prepares; reconstructed declaration has identical Mapping; invalid addressing and CID tampering refused |
| Independent contract vectors | `portability/corpus/collection-mapping.json` | Node SHA-256 checks and generated MoonBit canonical tests; collection key, target and omission mutations cannot reuse the pinned identity |
| Existing row-ID Mapping | Existing GitHub declaration and common fixtures | `github-comment-mapping.test.mjs` and unchanged row-identity fixtures |

The Node tests are included by the existing Check Environment and installed
Check Environment test entrypoints. They are not a new heavy CI campaign.

## Local validation

The pinned MoonBit toolchain and Node 24.21.0 were used. Tests ran through the
repository's bounded, nonzero-test wrappers. Runtime JS was regenerated from
this worktree and remains ignored by Git.

```sh
node scripts/local-checks.mjs test moon -- --target js \
  src/check_environment src/client_row_source_host \
  src/stage_results/effect_static_candidate_test.mbt \
  src/canonical_json/identity_vectors.generated_test.mbt
node scripts/local-checks.mjs build moon -- --target js --release \
  src/connectors_builtin_node
node scripts/local-checks.mjs test node -- \
  scripts/check-environment.test.mjs \
  adapters/host-node/collection-mapping.test.mjs \
  adapters/connectors/github/test/github-comment-mapping.test.mjs
node scripts/check-environment-contract.mjs
node scripts/catalog-body-dependencies.mjs
node scripts/check-canonical-json.mjs
node scripts/check-actql-spec-family.mjs
node scripts/check-owned-contract-versions.mjs
```

Focused MoonBit selection: 642 passed, zero failed. Initial Node selection:
15 passed, zero failed. Canonical checker: 382 fixed identities. Spec-family
freshness: 10 documents, 1,392 requirements, 267 machine imports; its existing
global conformance status remains false. No full Core, Wasm/native execution,
packed campaign, hosted CI or real-service write was run for this unit.

The first focused attempt retained under `_build/local-checks/attempts/`
failed on stale dependency fixture literals. Catalog/lookup fixture references
now use the generated Check Environment pin. The expression fixture now uses
the independently pinned expression body already present at the base SHA,
`sha256:bdfd03bfd57f9b3d65e0c53bc122fd86235809dc16be7cd7ec08616c18d7242d`.
This is not an expectation inferred from a successful product result.

## Remaining connector acceptance

Sheets read/append, registered physical I/O, formal package export, public
Local/HTTPS, approval, process restart, response loss, saved-response replay,
revocation and cleanup retry belong to the dependent connector work. The
preparation/reconstruction tests above do not claim durable write recovery.
No change to retry permission or unknown settlement is made here.

Real-service acceptance additionally needs an explicitly authorized test
spreadsheet/tab, credential reference and operation scope. No such environment
has been supplied; fixtures must not be reported as Google service acceptance.
