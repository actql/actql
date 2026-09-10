# Graph operation checking

`graph_typing` currently checks `normalize_graph`, `degree`, `components` and
`graph_bounds`, plus binary `graphs_equal` and `graph_diff` through dedicated
closed-contract checkers. Structural `graft_graph`, `union_graphs` and
`subtract_graphs` use the same pair admission and pipeline operand resolution.
The normative owner is [Graph operations](../spec/language.md#graph-operations).
This is not the complete SGA operation family or an evaluator.

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

The pinned Sketch compiler has structural binary graph dispatch but no
`graphs_equal` checker; this operation follows the newer normative Graph equality
section. The shared comparison boundary is also needed by later diff/apply work;
application and structural merge policies are not implemented by equality.

## Structural graph composition

The three structural operations retain both input occurrences, including repeated
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
