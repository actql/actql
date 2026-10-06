# Graph naming migration: first compatibility unit

## Scope

This change establishes `Graph` as the canonical internal vocabulary for the
admitted structural carrier. It adds `GraphDefinition`,
`GraphNodeDefinition`, `GraphEdgeDefinition`, `GraphIssue`, and
`GraphKeyDescriptor`, together with `graph_*` constructor and accessor
functions in `carrier_contract`.

The historical `PropertyGraph*` type names and `property_*` functions remain
available as compatibility aliases and forwarding entry points. No caller
migration is included in this unit. The aliases do not copy, re-number, or
reinterpret a definition.

## Inventory and contract boundary

The implementation was inventoried from the latest `main` before editing.

| Area | Current owner or surface | Treatment in this unit |
| --- | --- | --- |
| Core carrier metadata | `src/carrier_contract/property_graph.mbt`, `carriers.mbt` | Canonical internal type names added; old type names remain aliases. |
| Graph admission and contract | `src/graph_contract`, `src/graph_typing` | No semantic or call-site migration. |
| Equality and identity | `src/local_sga/property_graph_equal.mbt`, `src/graph_snapshot_identity`, `src/bounded_graph_snapshot` | No change to comparison, identity, definition spelling, key descriptors, or snapshot bytes. |
| Presence and storage | `src/managed_graph_storage`, `src/managed_graph_runtime`, `src/query_integration` | No change to missing, NULL, actual values, reload, or cleanup behavior. |
| Delta boundary | `src/graph_typing/delta.mbt`, `src/bounded_graph_diff`, `src/pipeline_check_context/graph_delta_execution.mbt` | Delta implementation remains unchanged; existing unsupported/refusal boundary remains in force. |
| Generated interfaces | `src/carrier_contract/pkg.generated.mbti` | Regenerated with the pinned MoonBit toolchain; no hand-edited mirror. |
| Public wire and schemas | `actql-property-graph-constructor/0.1`, `actql-property-graph-contract/0.1`, `actql-property-graph-snapshot/0.1`, `BRIDGE.rows.to_property_graph`, and `property_graph` JSON fields | Names and shapes remain unchanged. |
| SDK, public Host, docs, and fixtures | `scripts/property-graph-*`, packed acceptance, public Host fixtures, historical evidence | No public rename or fixture rewrite. Historical names remain evidence and compatibility vocabulary. |

`PropertyGraph` therefore remains part of the public compatibility surface for
this release. The new names are internal/API additions, not a wire or schema
version change. In particular, definition names, typed identity descriptors
(including `ArtifactRef.media_type`), CIDs, pins, and snapshot bytes remain
the same.

## Independent compatibility fixture

`src/carrier_contract/property_graph_test.mbt` constructs the same node and
edge definitions through the old and new entry points and compares their
domain, definition counts, names, endpoints, and refusal for an invalid domain.
The fixture uses the existing admitted definition rules and does not derive
its expected result from a new serializer.

The existing Graph contract and snapshot fixtures remain the independent
checks for canonical CIDs and bytes. The existing public Graph composition and
source snapshot fixtures cover equality, typed identity, NULL/missing/value
behavior, Store reload, and the current Delta refusal boundary.

## Deliberately deferred work

The following are separate migration units and must not be folded into this
change:

- changing JSON fields, wire version strings, operation/profile identifiers,
  pins, or CIDs;
- implementing or relaxing Delta;
- changing identity normalization, identity numbering, key descriptors, or
  presence semantics;
- moving all imports and call sites at once;
- deleting the compatibility aliases.

The next safe unit can migrate one owner or package at a time to the
`graph_*` API while retaining the comparison fixture. Removal of the old names
requires a separate deprecation decision and a complete consumer inventory.

## Verification

The focused Core suites passed on all three targets:

```text
moon test --target js src/carrier_contract src/graph_contract \
  src/graph_snapshot_identity src/bounded_graph_snapshot src/graph_typing
101/101
moon test --target wasm src/carrier_contract
26/26
moon test --target native src/carrier_contract
26/26
```

The Node Graph composition fixture passed (`11/11`). The local Graph source
snapshot fixture passed for its Local Result case. The remote HTTP case could
not bind a loopback listener in the restricted runner; it is an environment
limitation, not a product result. No hosted CI run was available because the
repository billing gate stopped jobs before product steps.

`git diff --check` and the foundation/history check are required before the
PR is published. This change does not claim hosted CI success or complete
three-target/public packed acceptance.
