# Graph operation checking

`graph_typing` currently checks `normalize_graph`, `degree`, `components` and
`graph_bounds`, plus binary `graphs_equal` and `graph_diff` through dedicated
closed-contract checkers.
The normative owner is [Graph operations](../spec/language.md#graph-operations).
This is not the complete SGA operation family or an evaluator.

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
