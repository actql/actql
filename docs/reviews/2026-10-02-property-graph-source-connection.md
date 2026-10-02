# Property Graph source: common-owner connection

This is the Frontend boundary for PR #174, dependent on the development
checkpoint of #164 (`321684933dce17afb0edc40f8877d2d7460c3da2`). It does
not approve either PR for merge or establish all Graph migration obligations.

## One Property Graph implementation

The adopted direction is one new Property Graph implementation within ActQL.
Backward compatibility does not require a legacy adapter, fallback or a
second Graph runtime. An existing consumer must use the new contract or reject
it explicitly. The independent edge keys, typed composite keys, NULL exclusion,
static label sets and retained definition-domain identities remain unchanged.
No external AoA repository implementation is adopted by this source work.

## Entry points and ownership

| Boundary | Current entry / type | Ownership and unification work |
| --- | --- | --- |
| Public source routing | `source_frontend.lower(Text)` → `query_syntax.parse_query_script` → `query_program.compile_query_script` | B. SDK/CLI transport and Host preparation already call this common entry. No extra parser in the SDK. |
| Syntax and mapping | `query_syntax.PropertyGraphConstructor`, `PropertyNodeDefinition`, `PropertyEdgeDefinition`; `query_program.lower_property_graph_step` | B. Emits the existing `property_graph` Program body. Any common constructor-body adjustment is isolated to this emitter; it must not convert to the old `graph` body. |
| Program admission and checking | `stage_syntax.admit_generated_source` → `run_publication_host.prepare_effect_free_client_program` → `program_check.check_parsed` | Common Host/checker owner. Client input is admitted normally, never trusted as already checked. |
| Constructor definition and domain | `pipeline_typing.check_property_graph_step` / `property_definition_domain` → `graph_typing.check_property_construction` | C. Checked producer definitions, mapping, keys/labels/properties issue the domain; B emits none. External acquired producer provenance remains a common-owner gap. |
| Graph Carrier | `carrier_contract.Graph` / `PropertyGraphDefinition`; `property_graph_usage`, `graph_property_definition` and definition accessors | C. B reads the new definition contract through existing checker/lowering. C owns removal of the transitional legacy/optional representation. No downgrade to endpoint tuples is permitted. |
| Static node matching | B's `keyed_start_match` → `match_nodes {definition,label,bindings,where,fields}` → `graph_typing.check_property_match_scope` → `local_sga.start_match_nodes[_view]` | B owns source binding; C owns common matching. Full identity is a private binding; declared properties alone form public columns. Label membership cannot be replaced by property equality. |
| MATCH paths / TRAIL | B's `lower_script_keyed_graph_query` → common `traverse` with identity Relation selector, `emit: paths`, bounds and `path_mode` → `graph_typing.check_traverse` → `local_sga.start_traverse[_view]` | B owns source lowering; C owns Graph/traversal execution. Keep complete edge identities, including parallel instances, through WALK/TRAIL/ACYCLIC. |
| Bounded constructor and capacity | `pipeline_check_context.property_graph_construction_execution_check`; `local_sga_provider.graph_pipeline` → `local_bridge.start_rows_to_property_graph` | C. Preserve existing capacity, cancellation, input retention and handoff owners when making consumers uniform. B does not edit these modules. |
| Public Result | Ordinary prepared task/Run/publication owners, then `Result.all()` / `Result.describe()` | Existing Host owners. B compares authored rows, ordered columns, type/nullability and request replay via the packed acceptance app. |
| Snapshot save/reload | `bounded_graph_snapshot.prepare_property[_view]` / `take_property_output`; `local_bridge.start_property_snapshot_reload` | C supplies the public connection. These internal functions are not a public snapshot API. B will connect and accept it after the fixed handoff; no independent format or constructor replay substitutes for reload. |

The other Graph query entry, `query_program.compile_graph_query`, contains the
historical property-based label adaptation. It is not used for DATA's new
Property Graph values. Its remaining consumers and source-context bindings
must be adapted or explicitly rejected as part of the unified direction;
the historical adaptation is not the desired final language semantics.

## Narrow common gaps

- Rich keyed patterns need definition-scoped element binding, projection and
  predicates. For example, `(a:Node)-[:R]->(a:Node)` must compare the full node
  identity. The current new-profile identity is `JsonType`, while ordinary
  relational `value_contract.key_comparable` does not admit JSON. B currently
  returns `UnsupportedGraph` for repeated variables rather than stringifying,
  joining endpoint tuples or broadening global equality. This is a concrete
  common binding boundary, not a request for another Graph executor.
- Multiple node definitions and named edge/intermediate bindings are separate
  from anonymous traversal. B does not infer a homogeneous property schema
  for a heterogeneous Graph or replace a label with a selected field.
- Source acquisition must retain its existing admitted producer and authority
  owner. A source name/schema alone is insufficient definition provenance.
- Public snapshot input admission and retained identity/domain/content checks
  are C's connection. Result reattach does not discharge that obligation.

## Independent Frontend work

DATA Relation set bodies use the same column-alignment, duplicate operation
selection and evaluated-slot ORDER/LIMIT emitter as ordinary SQL/CTE sets.
They compose existing append/distinct/intersect/except steps in a normal
pipeline. Binding DATA adds no Stage Result, acquisition, durable artifact,
physical-task request or placement decision. The common checker remains
responsible for the operand type contracts.

The independent one-stage Program in `query_program/data_set_test.mbt` checks
this structural obligation. The packed source fixtures add same-definition
parallel edges, node/edge composite keys, NULL key and endpoint exclusions,
multiple static labels, empty typed output and duplicate-key failure. These
are authored expectations, not generated product outputs. Initial scoped
checker success is not recorded as executed Host acceptance.

Reproduce the source acceptance with:

```sh
node scripts/test-packed-public-query.mjs --property-graph-source-only
```

The pinned compiler is required to prepack; the external installed app uses
the standard SDK/Host without MoonBit at runtime. It exercises both Embedded
Local and HTTPS, obtains Named Results and real descriptions, checks refusal
before admission/provider I/O and confirms same-request resend/reattach does
not rerun work. A separate source SHA and tarball digest record accompanies
each execution; pending cases remain pending until that run passes.
