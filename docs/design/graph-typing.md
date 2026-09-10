# Graph operation checking

`graph_typing` currently checks `normalize_graph`, `degree`, `components` and
`graph_bounds`.
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
