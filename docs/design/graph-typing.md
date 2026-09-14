# Graph operation checking

Conditional query identity propagation is described in
[Graph query evidence](graph-query-evidence.md).

`graph_typing` currently checks `normalize_graph`, `degree`, `components` and
`graph_bounds`, plus binary `graphs_equal` and `graph_diff` through dedicated
closed-contract checkers. Structural `graft_graph`, `union_graphs` and
`subtract_graphs` use the same pair admission and pipeline operand resolution.
The normative owner is [Graph operations](../spec/language.md#graph-operations).
This is not the complete SGA operation family or an evaluator.

`GraphMatchCheck` binds the retained typed match operation to its Primary input,
selected policy and Relation output ceiling. Selector membership, nullable
predicate evaluation and canonical ordering remain separate execution rules.
The indexed ID/type readers preserve repeats and distinguish absent type filters
from an empty filter without copying arrays. Physical comparison work includes
predicate and ordering work; retained-state and input/temporary byte limits must
also be enforceable before input use. The resource phase prepares enforcement;
it does not check the output ceiling only at entry or permit partial publication.
The explicit Relation-output association fills the generic resource obligation's
previously unspecified scope, consistently with other Graph-to-Relation bridges.
The fixed reference compiler adds no separate match count option; that absence
does not waive selected capacity or supply runtime order evidence.

## Property-match implementation boundary

The `check_match` boundary shares typed semantic scopes and the
existing expression checker. Unlike the explicit row bridges, these scopes do
not add undeclared `id`, `src`, `dst` or `rel` columns. Unknown and untyped
properties remain distinct; only referenced fields must have known contracts.
Predicate diagnostics retain source paths, spans and embedded-text ranges.

Selected fields retain their source order and must be nonempty, unique and
statically known. Node selectors retain explicit typed ID occurrences without
string conversion; membership deduplication and existence remain execution
obligations. Empty and repeated edge-type filters are retained, not rewritten
to absence. Expressions and scopes consume the same remaining work/node/text
and token budgets. This does not establish order or publication evidence.

Pipeline dispatch now connects both match operations to Relation consumers and
retains the predicate's exact diagnostic location and cumulative token budget.
The grammar/schema now fix the previously implicit selector and projection
shapes: one node selector, nonempty unique fields, and optional edge filters.
Accepting empty edge types as an empty selection is an explicit membership-law
decision, not an alias for an absent filter. Static predicate errors remain
errors even when the type filter selects no edges.

Direct Ref-typed IDs encounter `value_admission`'s UnsupportedReference rejection:
the opaque-reference owner forbids authored JSON alone from establishing a valid
Ref. This does not restrict Graph identity types to strings or to constructible
values. Selection from issued Relation values uses the shared selector boundary
below; fabricated tagged objects do not replace it. Traversal consumers remain
separate work.
The pinned Sketch reader supplies the closed source forms, but its string-only
IDs, implicit carrier aliases and silent duplicate-column removal are not used.

Normalization requires `true` and preserves the structural Graph contract,
including partial property knowledge, semantic identity type and labels.
It does not assert that untrusted data has already been normalized.

`GraphExecutionCheck` binds common Graph-data admission and operation-specific
ordering to the retained `CheckedGraph`, its Primary input and its exact
requirement occurrence. It consumes checked options through the existing reader
rather than reconstructing the source body.

| Requirement | Execution rule | Boundary and interpretation |
| --- | --- | --- |
| ValidateGraphData | AdmitGraphData | Before input use; validate Graph data under its retained identity/property evidence without inventing absent type information. |
| ComponentIdentityOrder | OrderComponentIdentities | Before output; choose the canonically least semantic node identity as component identity and emit component identity then node identity order. |
| BoundsReportOrder | OrderBoundsReport | Before output; emit node-count, edge-count, then degree violations in canonical semantic node-identity order. Zero thresholds remain valid diagnostic conditions. |

These rules follow the Graph component and structural-report semantics in the
Language specification. Admission or execution failure rejects operation output,
but a reported `graph_bounds` violation is not itself an execution failure.
Source enumeration is not an alternative order witness. Profile selection,
Parameter range validation, output guards and resource resolution stay separate;
an unresolved one still prevents complete closure. The five-case
`graph_execution_wbtest.mbt` test covers all four operation kinds, both component
kinds, an authored guard, zero report thresholds, unknown property evidence and
invalid occurrences. Binding these checks is not runtime conformance.

`GraphResourcesCheck` binds normalization, degree and bounds-report resource
scope to the exact Primary input and admitted policy. `PreserveGraph` adds no
Relation-output ceiling. `RelationRows` retains the selected
`max_relation_output_rows` ceiling, not the components/traversal row ceiling.
Graph producer admission and capacity remain prerequisites through the existing
producer closure; this binding neither rechecks external-input ceilings on
internal Graphs nor fabricates observed counts. Bounds thresholds still only
select diagnostic rows, which may themselves exceed the Relation output cap.

This explicitly fixes the resource association left unspecified by these
operations' generic pending requirement. The fixed reference compiler emits
no extra Graph count parameters for these three operations; that absence is not
an exemption from selected consumer or backend budgets. Components retains its
separate node/output limit consumer. Whole-Program closure rejects a missing
producer check before these bindings can represent a prepared Program.

Degree requires a literal `in`, `out` or `both` direction. It produces exactly
`node` with the semantic graph ID type and non-null `degree: number`.
Components requires literal `weak` or `strong` and produces `node_id`,
`component_id` with that same ID contract and non-null `component_size: number`.
The latter is the member count, not a narrowed integer value contract.
Property fields are not implicitly projected into either result.

Opaque Graph inputs remain opaque under normalization. Fixed-role Relation
outputs have a closed field set but retain unknown ID types; they do not claim
a complete schema. Known identity types remain available even when property
domains are unknown. Pipeline and Result consumers enforce their own missing
type/evidence requirements.

`components.max_output_rows` is an optional positive safe-integer literal or a
whole non-null number Parameter. It is retained, not treated as an observed
bound or a truncation instruction. Parameter defaults are not read here; binding
and count validation remain obligations. Graph data admission, SGA profile,
resource resolution and component identity ordering are also explicit pending
checks, not proof objects or permission to execute/publish.

`ComponentsLimitsCheck` consumes the retained components capacity application
from the same producer visit. Its input-node and output-row claims remain
separate, including their candidate dependencies, units, subjects and selected
policy. The binding does not reconstruct minima or turn an equal-valued foreign
pipeline's claims into applicable evidence. The existing capacity consumer
remains responsible for candidate completeness and authored-guard support.

The execution binding has an atomic output gate: no operation output is exposed
unless both selected limits are enforced. This does not defer input-node
enforcement until after running the component algorithm. Graph-data admission,
component identity ordering and other execution budgets remain independent.
An absent capacity application leaves resource resolution incomplete; it is not
an exemption or a request for the lowerer to infer replacement bounds.

`CheckedProgram` retains a `ComponentsLimit` for each local component operation.
Its count/index readers return the stored result; they do not redo capacity
selection or proof traversal. Imported prerequisite visits refer to the original
producer's Unit. The two canonical claims use the `/components/nodes` and
`/components/output` Unit-operation subscopes, independently of internal claim
indices. Candidate proof graphs are reidentified through the existing bounded
Unit conversion, while Host witnesses keep their identity. Repeated candidate
occurrences survive sorting by the converted CID; a duplicate does not strengthen
the minimum. The indexed proof reader retains the converted dependency graphs
alongside the original selected checks. These canonical claims remain conditional
execution requirements, not observed Graph counts or execution permission.

The reference implementation's string ID outputs and mandatory resolved graph
bounds are not authoring rules: typed semantic IDs and optional authored guards
follow the current Language specification. Backend ID encoding and resolved
Host resource ceilings belong to lowering. No implicit string/CID substitution
is introduced. `components` does not acquire an authored `max_nodes` option.

`graph_bounds` has separate diagnostic thresholds: at least one of `max_nodes`,
`max_edges` or `max_degree`, each a nonnegative safe integer or a whole non-null
number Parameter. Zero is meaningful; absence is retained rather than filled.
The fixed output is `kind: string`, `node_id: nullable semantic ID`,
`actual: number`, `max: number`. Unknown IDs remain untyped. A report is not a
proof that the graph satisfies its bounds and its thresholds are not Host
resource ceilings. Parameter checks and report ordering remain explicit obligations.

The fixed nullable ID column is an explicit specification decision: AoA omits
node_id on whole-graph violations, whereas ActQL's closed row contract requires
every field. The lowering adapter inserts null for those cases without changing
violation selection. Specification-only corpus cases cover zero bounds, exact
thresholds, self-loop degree, report ordering and non-string IDs; no graph
evaluator is implemented here.

Source traversal is iterative and budgeted for nodes, depth, work and text.
Already admitted recursive contracts are shared; pipeline input preflight
accounts for their structures separately. Diagnostic paths/spans identify the
specific body slot. Collections returned from checked values are detached.

## Shared selectors and induced subgraphs

`check_selector` admits closed nonempty literal IDs, named Relation ID fields,
and node predicates. `check_subgraph` composes it with an optional edge predicate
and returns the input Graph contract unchanged. The optional selector Relation
is independently resolved by the pipeline and retained after the primary Graph
input; neither it nor its current row count is confused with the output Graph.
Unknown names and future/self references fail at that source slot.

Selector obligation groups expose their retained checked selector through
`operation_obligations_selector`; the group scope still distinguishes node,
start, source and target roles. This reader neither rebuilds the selector nor
resolves its input edge. Literal occurrences are available through
`selector_id_count` / `selector_id_at`, so consumers can budget each visit
before retaining a value without copying the complete ID array.

Relation selectors retain the actual field provenance and compatible semantic
identity contract, including Ref types, without string conversion. Unrelated
open or untyped columns do not block selection. Compatibility does not prove
that any actual value is non-null, within the graph identity domain, authorized,
or present in the Graph. Those checks remain explicit selector obligations,
along with typed deduplication. An empty Relation/predicate selection is valid.
An authored tagged JSON object does not issue a Ref; issued Relation values
retain their separate revalidation boundary.

Subgraph evaluation must induce both endpoints before applying its edge
predicate, preserve endpoint nodes after edge removal, and retain properties,
identities, labels, policy and observation scope. The checker preserves partial
property evidence rather than manufacturing completeness or reduced count facts.
Source, selectors and both predicate scopes debit cumulative work/node/text/token
budgets. Child predicate obligations are accessible through their typed expressions.
Graph materialization and selector evaluation require resolved resources.
This implements static checking, not traversal, induction or publication proofs.

## Path result contracts

`check_path_contract` is the shared output builder for node traversal, path
traversal and shortest paths. The pinned SGA identity law defines edge identity
as the source/target/label tuple, so path output uses closed `{src,dst,rel}`
records with typed endpoints and nullable labels, not string IDs or an assumed
`edge_id` property. The new normative paragraph fixes that formerly unstated
wire representation. Tuple comparison uses the law's component order, and
incoming traversal does not reverse the identity record's endpoints.

New arrays and records are budgeted; existing admitted scalar contracts are
shared. The builder does not prove path existence, simple-path constraints,
cardinality, ordering, weights or execution bounds. It is not yet a complete
traversal checker or pipeline operation.

`check_traverse` now composes that builder with shared start selectors and either
homogeneous bounds or an ordered nonempty pattern. The closed modes are mutually
exclusive. All source/predicate/output work shares one cumulative budget, including
tokens across the selector and every edge/node predicate. A named start Relation
is retained as a separate pipeline input. Guards preserve literal/Parameter
forms; they do not establish actual output cardinality.

The mode and empty-filter rules are now explicit in Language and the machine
schema. Unlike the pinned reference decoder, no max_paths source option or
default output ceiling is admitted. A present edge-type filter requires semantic
label evidence even when empty; a mere property or closed domain is insufficient.
Minimum node depth, simple paths, exact path deduplication, canonical order,
binding checks and execution resources remain separate obligations. No evaluator
or lowering is included.

## Shortest-path checking

`check_shortest` composes typed single identities or shared selectors with the
path result builder. Each Relation selector has its own pipeline edge, even when
both refer to the same Relation. Predicate tokens and source/output work are
cumulative across both endpoints. Returned contracts preserve semantic identity
types; authored JSON cannot issue opaque references.

The closed body and explicit direction/hop bound clarify the existing bounded
search contract. Unlike the pinned reference decoder's single-string endpoints,
the checker supports the specified selector forms and typed IDs. It introduces
neither max_paths nor default output limits. A weight must resolve to a known
non-null number edge field; unrelated unknown properties need not become known.

Graph admission, endpoint membership, all-edge finite/nonnegative weight checks,
rounded cost accumulation, atomic rejection of selected overrange paths, simple
hop-bounded selection, tie-breaking and canonical output order remain explicit
execution obligations. Guard binding, profile and resource resolution remain
separate. Static acceptance is not weighted-search execution support.

## Bounded reach checking

`check_reach` requires a typed explicit start, direction and positive finite
integer-valued depth. It neither supplies the reference decoder's `both` default
nor imports its string-only ID restriction. The depth is a semantic bound,
not a claim that exploration resources are resolved; no safe-integer ceiling
is added to the specification's integer domain merely for convenience.

The normative clarification reconciles the traversal expansion with semantic
name restoration: retain `start_id`, `node_id`, `depth`, plus any distinct
declared node-ID alias. Distinct-role collisions fail, and source properties
are not silently added. The pipeline exposes this Relation to ordinary typed
consumers. Actual membership, minimum-depth traversal, canonical order,
expansion journaling and Host/profile checks remain explicit obligations.

## Typed graph equality

`graphs_equal: {with: name}` resolves both Graph inputs and returns the complete
one-column Relation `equal: boolean` (non-null), with exactly one row on successful
evaluation. Both operands require known semantic identity and complete closed node
and edge property contracts. Opaque, open or untyped property evidence cannot
discharge the existing specification's compatibility requirement.

The checker reuses bounded recursive schema alignment for both property domains
and the identity domain, sharing the remaining budget between them. Compatible
extents and nullability are joined for domain checking; declarations need not
have identical bytes. Different property names or incompatible value domains
fail even for empty runtime graphs. Label-domain differences are not a static
false result: canonical admitted identities, labels and property values must be
compared at execution. Input order, acquisition identity and graph isomorphism
are not substitutes for that equality law.

The checked operation retains both typed Graph contracts and the authored right
reference. Pipeline connections retain Left and Right occurrences, including
self-comparison; no constant folding or equality proof is created. Result rows
can feed ordinary boolean expressions. Data admission, comparison, SGA profile
and work/byte resource validation remain explicit obligations.

`GraphEqualityCheck` binds admission, canonical comparison and resource
requirements to the retained operation and its exact Left/Right occurrences.
Self-comparison retains both roles and still requires admission; it is not
folded to true. The indexed resource reader requires finite comparison work,
retained comparison state and input/temporary byte limits from the selected
physical implementation before input use. The one-row result bound is not a
bound on those quantities. A backend without enforceable limits is not runnable;
static closure records the obligation, not backend admission or execution.
Failures prevent operation output, including an apparent `false` comparison
result after failed operand admission. Producer prerequisites and the selected
policy remain attached independently of comparison outcome.

The pinned Sketch compiler has structural binary graph dispatch but no
`graphs_equal` checker; this operation follows the newer normative Graph equality
section. The shared comparison boundary is also needed by later diff/apply work;
application and structural merge policies are not implemented by equality.

## Weighted graph means

The source-option reader retains ordered sample occurrences, explicit finite
nonnegative weights, node/edge support thresholds and each property's complete
missing/null strategy. Repeated graph names are distinct samples. Positive total
weight is tested by the presence of a positive weight, not by a binary64 sum:
the exact sum of finite samples can exceed the largest finite binary64 number
without invalidating support ratios or a finite weighted mean. Empty property
maps are allowed at this boundary; graph checking must still require exact
coverage of every admitted property, including zero-weight input contracts.

The pinned AoA `meanStructuralSgaGraphs` implementation supplies default weights,
uses a rounded support quotient and returns stringified property means. Those
are compatibility gaps, not ActQL semantics. ActQL requires explicit source
options and exact-rational support and property reduction with one final rounding.
No default weight, numeric coercion or last-input winner is imported.

`check_mean_options` checks only source options. `check_mean` additionally aligns
every sample's complete identity/property contracts, requires exact strategy
coverage and constructs nullable number properties for weighted means. Exact
equality properties retain their aligned contract. The checks use the existing
bounded recursive domain alignment, including compatible nullability and extents;
they do not equate a declared schema with admitted graph data.

Semantic row aliases survive only when every sample carries the same role names,
so reordering samples cannot select a different alias winner. Known output label
domains are the union of positive-weight sample domains; zero-weight samples still
undergo contract checks. Runtime support and label agreement do not follow from
that static domain union. Exact arithmetic, canonical order, input admission,
observation/policy and resolved-resource obligations remain explicit.

The pipeline requires `as`, rejects step `from` and records every declared graph
as an ordered `Sample(index)` input occurrence, including repeated targets. There
is no implicit current operand. The generated Graph can enter the existing
explicit row bridge; it is not a Relation that can be published directly.
The machine schema enforces the closed option grammar; equal list lengths,
finite binary64 admission and contract-dependent coverage require the checker.
None of these checks is evidence of a numerical evaluator.

## Structural graph composition

Binary structural operations retain both input occurrences, including repeated
references to one input. They require compatible complete identity/property
domains; no missing property is repaired with null. Source bodies remain available
without deleting empty strategy maps or deduplicating authored operations.
The common-field-set requirement now explicitly includes graft: an add-only
union cannot produce a complete uniform property contract from mismatched field
sets without the forbidden missing-field repair. This clarifies its contract
boundary rather than adopting AoA's looser optional-property representation.

Union and subtraction admit separate closed node/edge strategy maps. Unknown
properties, unknown strategies, non-number numeric domains and non-array set
domains fail statically. Nullable declarations remain nullable: an actual null
operand fails the execution strategy, while untouched one-sided records retain
their original values. A nonempty subtraction map retains transformed shared
entities; an empty map retains the complete-payload removal obligation instead.

`set_union` widens the output array bound to the sum of both known input bounds.
If either bound is unknown or the sum exceeds the representable safe-integer
contract bound, no array bound is claimed. Other strategies retain the compatible
common extent. These are type envelopes, not cardinality or resource proofs.
Field maps, label domains and source traversal share the remaining budget;
recursive admitted child contracts are shared.

The pinned AoA structural implementation supplies the union/difference strategy
semantics, not its string-only identity restriction. Typed canonical equality,
strategy execution even on equal values, finite numeric results, canonical set
ordering, subtraction endpoint closure, policy, profile and resources remain
explicit obligations. This checker does not execute graph composition.

`check_union` additionally accepts the normative nonempty reference list. It
retains each binary fold, starting with the current Graph and consuming each
listed occurrence in order, without reassociation or deduplication. The source
tree is scanned once; each fold consumes the remaining shared budget. Operand
arrays are owned copies and indexed access does not expose mutable storage.
The pipeline retains one authored step with ordered connections (left input,
then each listed occurrence), each fold's obligations and the final contract.
Node/edge upper bounds include repeated occurrences; an unknown bound prevents
a sum claim on that axis. Scalar syntax remains supported, and subtraction and
graft remain binary. This implements existing Language and operation-binding
rules; it does not implement their runtime strategies or lowering.

## Graph Delta typing

`check_diff` retains the recursively joined common Graph contract and constructs
the complete typed Delta object specified by Language. Node records are
`{id, props}`; edge records are `{src, dst, rel, props}`. Property objects remain
closed and nested even when empty. Updates contain complete before/after records,
not partial patches. This is a representation decision filling the previous
record-shape gap; AoA's optional members and partial updates are not equivalent.
Properties with identity-like names stay under `props`, and IDs keep their type.

The common label domain is the union when both domains are known, otherwise
unknown. New wrappers and property maps consume the remaining work/node/text
budget; admitted recursive child contracts are shared. Output is a one-row
Relation with non-null `delta`, connected to ordinary Relation consumers.
Its string-typed headers do not alone prove the version or CID values: execution
must emit the specified version and computed common contract CID, and bind both
snapshot CIDs. Action ordering, unique identities, exact complete records and
resource resolution remain explicit obligations. This does not implement Delta
evaluation or make arbitrary structurally matching JSON safe to apply.

The [Graph contract identity boundary](graph-contract.md) now provides bounded
CID construction for a complete Graph contract and pins the identity/value law
body. Diff retains this opaque checked contract alongside its typed Delta output.
Canonical contract emission debits its exact value-node and UTF-8-byte counts
from the shared budget; each emitted value node also consumes one work unit.
The remaining depth bounds this traversal independently. Runtime emits the stored
CID rather than selecting or inferring another contract from Delta payloads.
Apply integration remains separate, as do all outstanding snapshot obligations.

`GraphDiffCheck` binds each Delta obligation to the original base/target input
occurrences and the stored `CheckedDiff`; readers use its retained common Graph
contract rather than reconstructing it from payloads. Snapshot admission precedes
input use. Version, contract identity, runtime snapshot identities, complete
records and ordered unique actions gate output. Even a self-diff retains both
operand roles and all checks; an empty action list is not a static shortcut.

The resource reader lists Graph-node, Graph-edge, action-record, value/temporary
byte, work and retained-state scopes. Runnable realization requires enforceable
finite limits for these scopes before input use, under the retained policy and
producer prerequisites. A one-row Delta is not a one-record or bounded-byte
payload; updates retain both before and after values. Static closure binds these
requirements but neither selects an unprovided backend budget nor claims actual
counts. Failed admission, generation or resource enforcement exposes no Delta.

## Delta application checking

`check_apply` accepts the closed `{with, field}` body, a typed base Graph, a
Relation containing the selected field, and an independently resolved opaque
`graph_contract.CheckedContract`. It retains that exact contract and uses it
for the output Graph and expected complete Delta record type. It never derives
a replacement contract from action payloads or a matching self-CID.

Base identity/property domains must be known and compatible. Extents and
nullability can differ: execution admits the actual base under the pinned
contract, rather than replacing it with the joined type used for compatibility
checking. Label-domain membership is also a data-admission obligation. The
output therefore follows the supplied contract, not the narrower base snapshot.

A selected JSON-typed field requires complete runtime shape admission. A known
object contract additionally undergoes recursive domain compatibility checking;
other known value kinds fail statically. Nullable declarations are not proof of
a usable Delta: actual null fails the mandatory closed-shape admission. This
uses the language's explicit additional semantic admission for ordinary data,
not a new authority-bearing Delta type. Unknown/untyped fields cannot silently
become JSON. Unrelated Relation fields need not be complete. Qualified field
references retain their left/right provenance.

The checker retains separate obligations for exactly one row, version and closed
shape, exact contract/base/target identities, action ordering and uniqueness,
before-record equality, existence rules, atomic node/edge changes, endpoints,
complete result admission, policy dependencies, SGA profile and resources.
No row count or successful application is inferred from a static type.

`GraphApplyCheck` binds those checks to the exact base Graph and Delta Relation
occurrences. The stored operation supplies the independently resolved contract
and selected field. Pre-application checks gate input use; atomic changes,
result admission and target-identity matching gate output. `BeforeOperationOutput`
does not permit publishing a prefix or mutating an exposed input in place.
Policy dependencies remain mandatory even when no action changes a value.
The indexed resource reader shares Delta's graph/action/byte/work/state
categories, applying them to the base, supplied actions and candidate result.
The selected realization must provide finite enforceable limits before use;
no one-row or self-application shortcut waives them. Static closure does not
claim that the Delta was applied, nor authorize persistence or provider access.

Diff and Apply share the complete-record type builder. Compatibility traversal,
contract emission and new record wrappers share work/node/text budgets with
source admission. Contract hashing does not materialize serialized text.

Reference review: pinned Sketch accepts an embedded `{delta: ...}` and preserves
the base shape. Pinned AoA application skips missing updates and deletes incident
edges on node removal. Neither behavior implements the current language's
Relation input, exact before records and explicit endpoint validation. Those
behaviors are not copied into this checker or its obligations.

Pipeline dispatch now resolves `with` as a separate right operand and requires a
retained expected contract for `field`. Diff creates the expectation on `delta`.
Value-preserving unary row operations retain it; select/rename/drop transfer it
to every surviving alias. Derive removes expectations for overwritten fields.
Expectations do not survive unsupported transformations by accident: broader
binary/aggregate propagation remains part of the shared-evidence audit.

Captured input Relations can receive explicit `delta_contracts` bindings of
input name, provenance-aware field name and an opaque checked Graph contract.
These select the contract to validate against; they do not attest that the
actual input's `graph_contract_cid` matches or that the Delta is otherwise valid.
Bindings are validated and preflighted, including unused bindings, and duplicates
fail. Ordinary matching object types alone do not create expectations. Missing
contract resolution fails before a successful pipeline is exposed.

Producer-bound pipeline inputs inherit these expectations from their selected
target, including every retained alias. Receiver maps are copied under the
shared budget before explicit bindings are added; additions cannot alter the
producer, and explicit duplicates cannot replace an inherited expectation.
The original producer and its unresolved obligations remain attached. Importing
the same Carrier as an ordinary input does not inherit its Delta contracts.

Expectation maps are private and shared across unchanged row operations; alias
maps and derive invalidation are bounded and charged once per step. Public lookup
returns only an opaque contract, never the mutable map. All runtime admission,
identity and resource obligations remain. This is checking support, not an
implementation of Graph Delta execution.

## Graph row projections and names

`carrier_projection` checks `node_rows: true` and `edge_rows: true` on typed,
partially known and opaque Graphs. The fixed roles and restored source aliases
follow [Graph rows](../spec/language.md#graph-rows). Opaque Graphs produce open
Relation knowledge with untyped identity columns, not an invented closed schema.
Typed properties, including nullable and structural children, are preserved.

`GraphRowNames` is validated source-role metadata, separate from value domains
and graph law evidence. It does not establish a semantic edge-label role or a
closed label domain. Graph contract serialization excludes it. Diff carries base
names and Apply preserves current base names, regardless of names attached to
the separately resolved contract. Projection returns both bridge roles and
non-identical semantic aliases; collisions fail instead of dropping properties.

This clarifies the former brief AoA-bridge reference using Sketch's restoration
behavior, while retaining actual non-string identity types and complete property
knowledge. An undeclared optional AoA display label is not a typed property.
Source graph construction attaches these names from the selected role fields.
Projection is connected to the ordinary pipeline and Relation consumers, without
inventing order/uniqueness/resource proofs. Lowering must implement these admitted
typed rows rather than copy a string-only or property-dropping reference shape.

`GraphProjectionCheck` binds the exact checked projection, input edge and
requirement occurrence. Its interpretation follows the two Graph-row requirement
blocks, without interpreting a future check as completed Graph admission:

| Rule | Required behavior | Execution boundary |
| --- | --- | --- |
| AdmitGraphRecords | Validate the input Graph against its retained identity and property contracts; partial static knowledge does not waive runtime admission. | Before input use |
| RejectColumnCollisions | Reject collisions among distinct bridge roles, source aliases and properties, including collisions not decidable from an open field set. | Before output |
| RestoreIdentityNames | Emit the fixed bridge roles and known source aliases with the retained types and values; absent edge labels are explicit null and no display-label property is invented. | Before output |

Failure rejects the operation output without partial publication. These bindings
do not preserve an arbitrary Graph enumeration as Relation order or establish
completeness, observed uniqueness or a resource bound. Candidate-key derivation
remains conditional on its original Graph producer obligations, and completeness
retains the projected operation-result scope and input dependency.
`ResolveGraphProjectionResources` is separate from those three rules.
`GraphProjectionEnvelope` binds the selected policy's `max_relation_output_rows`
to the exact projection and input occurrence. This explicitly selects the
Relation output scope rather than the Graph-query output scope; the former
brief bridge rule did not specify this policy mapping. The choice follows the
output Carrier, without treating input nodes/edges bounds as output rows.
The output ceiling is enforced before output exposure (equality is allowed).
Unknown counts are not static failures. Input Graph preflight, value admission,
physical budgets and retained-copy budgets remain independent. This binding is
not a successful runtime measurement or permission to skip another requirement.

`graph_projection_execution_wbtest.mbt` fixes node/edge and closed/open-property
branches, exact retained handles, invalid occurrences, execution phases and the
separate resource binding with the exact selected policy. This map is not a
runtime conformance certificate.

## Graph construction

`check_construction` supports explicit named branches and the concise edge-list
form, both connected to pipeline resolution. Explicit branches are generators
with ordered Nodes/Edges operands (represented by Left/Right roles); repeated
input names are retained. The concise form consumes current or step `from`.
The normative source grammar and completion rules are in
[Graph construction](../spec/language.md#graph-construction).

This fixes previously unstated field-selection/default and completion details.
Explicit fields default to no properties; concise edges retain non-role fields.
Duplicate selected references fail, while a role listed once is not copied into
the property map. Known selected types are shared, unknown property evidence is
preserved, and identities require compatible known non-null domains. Qualified
properties require a flat upstream alias; semantic role aliases retain provenance.

The concise label priority follows the pinned Sketch compiler. Its extension of
that completion to explicit branches disagrees with the current language's rule
that merely retained properties do not become labels, and is not copied.
`graph_label_contract` records a validated string role independently of row-name
aliases and a closed label domain. It is source/type evidence, not observed data.
No string-only ID restriction or branch-level authored distinct is introduced.

Endpoint-node completion, explicit induced-graph closure, equal-payload duplicate
collapse, conflicting-payload rejection, profile and resource resolution remain
distinct obligations. The checker performs no joins or graph construction on
actual rows. Source admission, identity-domain alignment, selected-field inspection
and retained names share budgets; pre-admitted property children are shared rather
than recursively copied. Pipeline preflight still checks supplied Carrier contracts.

`GraphConstructionCheck` retains the construction, exact requirement occurrence
and its ordered input targets. The ordinary indexed input-occurrence reader on
the retained step exposes Left/Right for explicit nodes/edges and Primary for
the concise edge input. Equal targets do not merge the two explicit roles.
No additional dependency array or reconstruction of the source is needed to
recover the checked input topology.

| Requirement | Execution rule | Required behavior |
| --- | --- | --- |
| Input row admission | AdmitInputRows | Admit the selected input rows and their identity/property values before input use; static type agreement is not observed validity. |
| Explicit endpoint closure | CloseDeclaredEndpoints | Retain edges only when both endpoints belong to the declared node universe; do not create missing nodes. |
| Concise endpoint completion | DeriveEndpointNodes | Derive the distinct union of endpoint identities with no undeclared node properties. |
| Endpoint completion record | JournalEndpoints | Retain the completion associated with this exact construction and source form. |
| Implicit label completion record | JournalLabels | Record the selected conventional label role; an explicit label does not create this implicit completion. |
| Equal identity/payload declarations | CollapseEqualPayloads | Collapse only declarations with equal complete canonical payloads under the fixed node/edge identity rules. |
| Conflicting identity/payload declarations | RejectPayloadConflicts | Reject identity-equal declarations with unequal payloads rather than select a representative. |

These rules follow the Graph-construction requirements above. Completion,
collapse and conflict handling are required before exposing construction output;
failure rejects that output. The bindings are future execution requirements,
not observed graph uniqueness, total order or completed execution evidence.
Resource resolution and SGA profile selection remain separate requirements and
cannot be discharged by these rules.

`graph_construction_execution_wbtest.mbt` covers explicit distinct/repeated inputs,
concise construction, implicit versus explicit label selection, exact retained
handles, invalid occurrences and execution phase/failure classification. This is
a connection test, not runtime graph-construction conformance.

The source-driven Program entry routes `graph`, `node_rows` and `edge_rows`
through the same owned requirement closure as other operations. Routing is not
a claim that construction resources have been resolved: an unbound construction
resource requirement rejects the complete Program at its exact operation site,
including for empty `values` input. No partial `CheckedProgram` is returned.
External Graph-input preflight ceilings do not define the resource contract of
constructing a new Graph from Relation operands. The construction-specific policy
selection in the normative Graph-construction section fills that previously
unspecified mapping without repurposing an input/preflight scope. Input row
occurrences and output distinct node/edge counts have separate ceilings; optional
policy fields preserve existing policy bodies and their identities when unused.
The extended policy contract has a new CID. No new observed-count witness law is
introduced merely by binding an enforcement ceiling.

`EnforceConstructionEnvelope` retains the exact policy and three typed ceilings.
Its output phase is the final exposure gate, not permission to postpone input
accounting: the lowerer enforces the input count incrementally before each row's
use and the entity counts during construction. The ordinary admission and
payload rules remain required, and physical budgets retain their own scopes.

The formal Program connection also retains construction requirements when a
Relation Result is imported into another Stage: the requirement's pipeline and
ordered operands still belong to the original producer, not a reconstructed
consumer-local copy. The `graph_branches_wbtest.mbt` matrix exercises empty and
nonempty input, shared and distinct explicit operands, and both Graph row bridges
through Result import. It checks retained role types (including nullable `rel`)
as well as the producer ownership of endpoint closure and resource enforcement.
This does not claim that the runtime has executed endpoint closure or measured
the constructed entities.
