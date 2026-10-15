# Bounded pre-v0.1 compatibility inventory

Issue: [#206](https://github.com/actql/actql/issues/206).
Inspected main: `bcbf77049fe4991c9b0f1a18541ac7a7952b01ad`, tree
`8783f3269a0885ea163eaf4c54bff4f72c0ca8bf`.
This is a bounded entry-point/caller review, not a claim to have found every
obsolete implementation. Search terms located candidates; caller, implementation,
contract and test inspection determined the disposition.

## One independently removable forwarding entry

`local_veca.start_nearest_relations` had exactly two tracked references at the
inspected SHA: its definition in `src/local_veca/nearest.mbt:1439` and generated
public interface in `src/local_veca/pkg.generated.mbti:97`. No tracked product,
test, script or public prose called it. A separate default-branch search of
`actql/actql-cloud` returned no reference; that result is bounded search evidence,
not proof about arbitrary external users.

The entry was explicitly a compatibility wrapper. Its complete implementation
was the same private `start_nearest_producers` invocation as the retained
`start_nearest_inputs_with_relations` path, with each of the two Relation reads
wrapped by `nearest_relation_producer`:

- Same control, completion preparation, prepared sequence, step and ordered roles
- Same row, value, control-work (`limits.max_work`), workspace, entry and name limits
- Same exact external input array converted by `trusted_output_relation_input`
- Same result type, common completion port, bounded session and cleanup owner

The wrapper introduced no additional algorithm, input format, promise or stored
state. Its removal deletes the exported forwarding function and generated
signature. It does not add a replacement adapter, change `NearestProducerInput`,
remove Relation/Relation support, change a CID, or reinterpret retained data.
Old MoonBit source naming the removed export must fail at compilation. It is
not accepted under another meaning or retried at runtime.

The current product calls are
`src/local_veca_provider/vectors_pipeline.mbt:1075` and `:1097`, which already use
`start_nearest_inputs_with_relations` and `start_nearest_inputs` respectively.
The latter uses the same producer kernel with its own exact direct input set.
`nearest_relation_producer` remains the current explicit Relation input
constructor, not an obsolete-format reader.

Existing independent fixtures in
`src/query_integration/local_carrier_vectors_wbtest.mbt` cover:

- `direct nearest Relation inputs keep exact work and workspace bounds`
- `fused nearest charges exact Relation inputs and reclaims cancellation`
- Mixed Relation/Vectors roles, reordered Stage inputs and invalid numeric inputs

Those fixtures retain literal 28/27 work and 23/22 workspace boundaries, actual
producer liveness, cancellation and cleanup. The new
`nearest_typed_entry_wbtest.mbt` exercises the public default typed entry directly,
checking fixed expected result cells, exact completed-input affinity, distinct
same-byte binding rejection, literal consumed control work, exact/one-short
workspace, swapped role refusal and
idempotent cleanup after success and cancellation. Existing fixtures retain
failed-execution cleanup coverage. No old test is deleted
or weakened. The normative nearest operation remains in
[the language specification](../spec/language.md#nearest); the resource route
inventory continues to name the current typed entrypoints in
`2026-09-23-local-resource-production-routes.json`.

## Workers invocation forwarding entry retirement

At main `3605d1829df24df9d826efc3e35bb5cbf462306b`,
`adapters/workers/invocation.mjs` only re-exported `withScopedStrategy` from
`adapters/host-common/scoped-strategy.mjs`. The common owner was established by
[#68](https://github.com/actql/actql/pull/68). Product `local-js-host.mjs` and
Workers `finite.mjs` already imported it directly, and the product artifact test
already excluded the forwarding file. The `run-host-core` package's export and
file inventories did not expose it. Bounded searches of `actql/actql-cloud`
found no import or call; this does not prove absence of arbitrary external users.

The remaining imports in Workers `async-conformance.mjs`, `conformance.mjs` and
the Node `finalizer-fixture.mjs` now name the common owner directly. The forwarding
file and conformance artifact allowance are removed. Its alias-identity test is
replaced by an exact missing-module refusal test, and the artifact tests reject
that path in every Workers profile. No compatibility loader or fallback remains.

The common scoped implementation, Host entry names and diagnostic text are
unchanged. Existing runtime snapshot and failed-finalizer fixtures retain their
independent assertions for original causes, pending cleanup ownership, no
successful consumption and exact finalization counts. Workerd's finalizer and
the real conformance cases continue to use the same common owner. These are
retained test obligations, not a claim that every suite ran for this removal.
There is no wire, CID, retained-state, execution-authority or operational switch.

## Native runtime bundle trust input retirement

At main `76beb551606018298e637ed3512979ff3a74fb4e`, the bundle CLI still
accepted `--issuer-authority`, `--key-id` and `--public-key-name`, constructed a
single-key trust list with implicit new-admission permission, and used `--key-id`
as an install-signature fallback. This was documented accepted syntax; its
retirement is intentional, not a claim that the old arguments already failed.

All located CLI callers already use `--trust-config-name` and explicit install
`--signature-key-id`: the native bundle CLI, native HTTP and resident-site
fixtures, plus `actql/actql-cloud/scripts/resident-site-runtime.mjs` at
`9734c3e639f49e15b965de549fb8b87c804799cc`. Bounded searches found no caller of
the removed `--public-key-name` path. Unknown external callers are not covered
by this repository audit.

The three option declarations, synthetic trust branch, signature-key fallback
and unused optional-option helper are removed. The existing bounded
`load_trust_configuration` reader and `open_runtime_bundle_store_with_trust`
remain the only CLI path; the latter retains the same underlying Store owner.
Argument-parser fixtures cover current syntax, retired-option refusal and
missing required arguments. The executable fixture checks refusal before even
loading SQLite and compares both an absent Store and an installed Store's full
file inventory and content hashes. Its existing lifecycle, rotation, historical
verification and multi-component assertions remain unchanged. These are test
obligations; Native execution remains unverified.

Single-key installations use one explicit authority in the same trust document.
The document version, signed manifests, CIDs, catalog records and retained
verification keys are unchanged. No live configuration or Store is rewritten.
The separate credential command's `--key-id` and `--issuer-authority` are current
inputs and are not part of this retirement.

## Retained paths and concrete follow-ups

### Current managed lifecycle retirement

The managed lifecycle follow-up below is historical. Managed preparation, bind
and start now use `ExecutionLifecycleOperations` directly. Local, DuckDB and
reference-compute drivers construct that common type, and task execution adopts
the same hooks without a conversion. `ManagedExecutionOperations` and
`managed_execution_lifecycle` are removed rather than kept as aliases. This
source API retirement changes no lifecycle fields, completion authority,
reservation formula or stored identity. Existing stop, settlement and scratch
release checks remain with their owners.

Materializing preparation is not a backward-compatibility adapter: it is the
current verified retained-input path to installed bounded execution. Its input
admission and output custody cannot be deleted merely because earlier reports
called the path "old".

Paths and line numbers below refer to the inspected main. These are not removals
in this change.

| Candidate | Actual callers, replacement and evidence | Disposition / next step |
| --- | --- | --- |
| `scripts/connector-node-bundles.mjs:35` flat `legacyModule` path allowance | `src/connectors/local/node-bundle.json` actively selects `adapters/local-node/strategy-bundle.mjs`; `reference_compute/node-bundle.json` selects `adapters/reference-compute-node/strategy-bundle.mjs`. Only DuckDB uses the newer connector-owned directory shape. `scripts/connector-node-bundles.test.mjs` exercises selected Local installation; `docs/connector-bundles.md` documents manifests. | Not superseded. A separate layout move must update both manifests, actual modules, imports, generated assemblies, package assets and isolated connector-addition fixtures before narrowing the validator. No provider is removed here. |
| `connector_sdk.ManagedExecutionOperations` and `managed_execution_lifecycle` | `prepared_managed_execution.mbt` still uses this type in stored `prepare`, bind and start signatures. Local, DuckDB and reference-compute managed drivers construct it; `physical_strategy/task_execution.mbt:309` converts to common lifecycle hooks. `ExecutionLifecycleOperations` is the replacement type, but callers have not migrated. | Coordinate with common lifecycle/custody owners. PR #193 directly edits this type, Local driver and task execution. Preserve reserve/settle/release/cleanup semantics; no independent deletion. |
| `connectors/local.start_managed_provider` and `start_managed_provider_with_inputs` | `managed_provider.mbt:253,290` synthesize zero execution ceilings via `unavailable_provider_execution_limits`; the explicit replacement is `start_managed_provider_with_inputs_and_execution`. Graph, Events, time-series and Vectors integration fixtures still call the older forms. | Active API, not fully replaced. Migrate only with the Local Carrier/Graph owners, preserving failures on missing required limits and all custody positives. Do not substitute permissive default ceilings. |
| `capacity_sequence_limit.limit` | Retired by [#380](https://github.com/actql/actql/pull/380), merged 2026-10-04, with implementation commit [`aab269d549d542e7183da36abcd153fbe1e68f87`](https://github.com/actql/actql/commit/aab269d549d542e7183da36abcd153fbe1e68f87). Production and test callers now use `host_limit`; the generated interface and Sequence-capacity design were updated together. | Completed source alias retirement, reconfirmed on main `595102baa2c386a1985a9b981fc2fd2c4977016b`. `host_limit` retains the original Host-only claim; `effective_maximum` retains the authored-guard minimum. This row is an adoption correction, not another implementation removal or fresh execution claim. |
| `platform_native/remote_client.poll` | Retired in the focused follow-up. The only remaining caller was the package-local Native HTTPS test; it now matches a typed `Dispatch` from `poll_operation`. All eight importing packages use the canonical operation API or other client methods. Cloud has no MoonBit package importing this helper. | The Native/unsupported helper and generated export are removed. `poll_operation` retains distinct operation variants; the migrated Native test rejects a foreign poll response before dispatch acknowledgement. Remote protocol, journal and other compatibility candidates are unchanged. |
| Native runtime bundle single-key flags | Retired in the focused CLI follow-up above. All located OSS and Cloud CLI callers already supply the existing trust document and explicit install signature key. | Removed the three legacy flags, synthetic trust branch and install-key fallback together. Argument parsing rejects retired or missing inputs before Store access; retained verification and lifecycle ownership remain unchanged. |
| `execution_relation.execute_selected_relation_step` | Called by `producer_read.mbt:329`. It drains the same bounded selected-row evaluator and preserves cumulative work plus cleanup on all terminal paths; managed Host progression advances that evaluator instead. `docs/design/query-residual-execution.md` still describes supported synchronous fixed-input execution. | Active synchronous API, not duplicate algorithm. A Host execution migration must prove its remaining synchronous callers replaced before deletion. |
| `execution_site.ManagedCandidateLegacyAllowed` | `classify_managed_candidate_fallback` distinguishes tasks with no retained managed producers from tasks whose retained inputs prohibit reconstruction; `candidate_selection_wbtest.mbt` checks the explicit exclusion outcomes. | Legitimate current candidate fallback and custody protection. Not compatibility slated for deletion. Planner #211 is separate and not imported. |
| `pipeline_typing.candidate_key` / `input_key`, detached obligation readers | The scalar readers return a witness only when exactly one remains; current tests use them. `docs/design/relation-evidence.md` distinguishes them from preferred-key selection. `docs/design/contextual-orders.md` explicitly retains detached arrays for callers needing ownership; indexed readers avoid unnecessary copies. | Public read projections with different result shapes, not obsolete wire parsers. Do not remove merely because collection/indexed alternatives exist. Establish a separate API retirement decision and caller migration first. |
| Native `LegacyStoreFormat` refusal | `platform_native/publication_store/store_native.mbt:340–351` rejects, rather than reads or migrates, an old physical Store. `store_native_wbtest.mbt` asserts refusal. `docs/design/versioning.md` requires unsupported catalogs not be treated as empty Stores. | Keep the refusal and tests. Removing them would weaken physical custody, not remove compatibility. Never erase a live catalog to make a new format appear acceptable. |

The completion-storage design still mentions an exported legacy finish surface.
Current `prepared_execution.mbt` instead exposes lifecycle-only
`bind_prepared_materializing_execution`, and the typed task completion APIs feed
a single private commit. This prose is not evidence that an old export still
exists. Reconcile it with the common completion owner before a separate doc/API
cleanup; do not invent a removal from stale terminology.

## Explicit exclusions and coordination

- `json`, `yaml`, `aql-json` and `aql-yaml` are current machine-source formats.
  `packages/client-wire/index.mjs` lists them and its source-format tests assert
  acceptance. The retired AQL/PROGRAM/STAGE text language is already explicitly
  refused. Text is never retried as another format.
- Diagnostic wire/profile/catalog `0.1` bodies, CIDs and contracts are retained
  by the current design. `docs/spec/protocols/contracts.md#diagnostic-profiles`
  is authoritative; the word compatibility is not a deletion instruction.
- Current retries, physical cleanup retries, historical inert fixtures and
  selected planner recovery are not obsolete compatibility engines.
- Graph #164 and frontend #174 own tuple/keyed migration and remaining old
  consumers. #184 owns bounded multi-root strategy work. Common Host completion
  and capacity/custody work remain with their owners, including #189/#191/#193.
- Open-PR file lists were checked before editing. None of #164, #174, #184,
  #189, #191, #193, #211 or #215 touched `src/local_veca/nearest.mbt` or its
  generated interface. The new test is a separate file and changes no shared
  integration package manifest or existing fixture.

This source-only removal performs no deployment, operation switch, Store
migration, Run cancellation or live-journal deletion. Any future incompatible
operational change must first account for and drain or release outstanding Run
and resource custody. Source API cleanup does not authorize abandoning it.
