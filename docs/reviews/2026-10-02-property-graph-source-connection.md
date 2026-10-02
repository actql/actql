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

## Observed acceptance and remaining strategy boundary

The package set below has identical bytes at source SHAs
`37f9020f25779b1e0c3d96a80f3f540eaf1f87cc`,
`89bb4e0dce54a0b8d27df41fcca05880b36dbc3b` and
`60190950c75a980c744fa6aae5a6ec3005020308`. The intervening changes correct
test pins/history and acceptance selection/counting, with no product change.

| Package | Tarball SHA-256 |
| --- | --- |
| client-wire | `c9882e6300c184e7086e86a56cc70b1be3f65e059d0b97364ea49b379eac3a86` |
| sdk | `90e09482027f878bc8e755825afa6090c8c5c10efd8ea428cc010992c20cfe97` |
| run-host-core | `9991551a82acf4e05f8ece9c9d5c732bec8a3d35320a1522b61a4e5130e5df76` |
| local-node | `cfba0b19b4bba681f91766dfa24e2e171750a4f511fc72fd3c39d6be71b0824d` |
| node | `5ee3b433edde987b6007f337aafe71af71c565135a16cae3de1debdebc4f1d67` |

- At `37f9020f2`, the external Embedded Local app completed 16 successful
  source cases, including same-definition parallel edges (WALK/TRAIL/ACYCLIC
  4/2/0), composite node/edge keys, NULL exclusions, static label sets and
  typed empty output. The subsequent DATA ordered-set case failed; this was
  not a successful complete acceptance run.
- At `89bb4e0dc`, those 16 cases completed through HTTPS with the same
  independent rows and real Result descriptions. Three duplicate-key cases
  and nine preparation refusals also completed, but the final aggregate
  incorrectly assumed one source read for each source-free failure case.
  That overall run is retained as failed, not relabeled as successful.
- At `60190950c`, a focused run of those three execution failures and nine
  preparation refusals passed in **both** Embedded Local and HTTPS. Each
  execution failure admits one Run, publishes no Result and does not acquire
  a source; attach/retry does not recompute. Preparation refusals admit no Run
  and perform no provider I/O. The 16 successful cases were not needlessly
  repeated after a test-count-only correction.

The remaining DATA set example is:

```aql
DATA n = SELECT 2 AS id UNION ALL SELECT 1 AS other
  ORDER BY id + 1, id + 1 DESC LIMIT 1;
FROM n |> SELECT id |> RESULT nodes
```

Its required result is `[{"id":1}]`, with one nonnullable number column `id`
and no internal sort field. Lowering and the ordinary checker pass. The
installed execution has no completed task and fails at
`physical_host.prepare_next_compute_task` →
`prepare_next_installed_task` → `Dispatch(NoStrategy)` because the captured
DAG has no strategy revision. `StrategyNotComplete` during publication is a
secondary error, not the first failing boundary.

The same emitted Program fails when submitted as JSON, bypassing Frontend.
An [independently authored smaller JSON Program](../../spec/frontend/fixtures/data-set-strategy/repro-program.json)
also fails there. Single sort terms and visible sort fields are failing
controls; removing duplicate ordering terms does not solve it. This establishes
a common strategy-selection boundary. B owns closing this reproduction and
its public acceptance; it is not an unassigned C/A wait. B has not changed
the shared dispatch, provider or capacity owners.
No order clause, capacity requirement or Result validation was removed to make
the source case pass.

### Current preparation refusal and separate strategy follow-up

The public source route now returns the existing typed
`ClientProgramUnsupported` for an ordered DATA set whose final query is
Relation-only. This is a temporary installed-profile limitation, not invalid
GoogleSQL ordering or a change to the adopted DATA meaning. The common query
lowerer and independent JSON reproduction retain the original ordered Program
and expected `[{"id":1}]`. Ordinary SQL set queries and DATA producers consumed
by a typed Graph query are not covered by this refusal.

The packed fixture classifies `data-set-order-reuses-hidden-slot` as a
preparation refusal, with the exact error code, unchanged Run/admission and
source-I/O counters, and request lookup returning `not_found`. It is no longer
listed as a successful execution case. The 16 successful Graph/DATA source
cases above remain separate historical execution evidence; neither a known
NoStrategy failure nor the new refusal proves ordered-set execution.

Source inspection isolates the next common selection check to
`physical_strategy/carrier_tasks.mbt::carrier_segment_prefix_end`: its stage-0
guard returns before the later multi-source Relation split conditions when
there is no Carrier construction or intermediate Result. The saved JSON has
two independent Values roots followed by append, derive, sort, projection and
take. Those occurrences advertise selected managed execution, but the early
guard keeps them fused. The installed Local candidate then has no usable
strategy revision. This narrows the proposed adjustment; it is not a tested
common fix or permission to accept an unchecked split. B will coordinate that
small selection change separately and require the exact JSON/source output
`[{"id":1}]` through packed Local/HTTP before removing the refusal.

C dependency `321684933dce17afb0edc40f8877d2d7460c3da2` remains provisional.
The newer public `402e6ea04e5ae65aba23a20b90233c9ee3e490b9` is not an offered
unification-complete SHA and is not adopted as one. Updating #174 requires C's
complete fixed SHA, changed common boundaries, public snapshot acceptance and
that SHA's CI evidence. B does not implement C's Graph unification.

Reproduce the source failure alone with:

```sh
node scripts/test-packed-public-query.mjs --property-graph-source-only \
  --case data-set-order-reuses-hidden-slot
```

Use `--mode local` or `--mode http` to limit transport, and `--keep-artifacts`
only when inspecting the retained installation/Store. These are test-driver
options, not new execution APIs. The public snapshot boundary, acquired
definition provenance, richer pattern bindings, remaining SGA consumers and
formal INFER handoff remain incomplete independently of this evidence.
