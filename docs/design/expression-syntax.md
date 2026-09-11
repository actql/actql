# Common Expression syntax admission

`expression_syntax.admit` accepts one general Expression slot as an owned
`decode_core.Cursor`. The slot may contain expression text, a structured form,
or structured forms with text at grammar-owned Expression children. It returns
an opaque Expression containing an owned normalized Cursor and detached
Parameter occurrences; it does not introduce a second public AST.

`emit_source` writes that same normalized source to an enclosing bounded
canonical writer (text, measurement or hash sink). It does not lower to
`{op, body}` nodes or compute a standalone Program/Fragment identity. Parameter
references remain unbound; template remains a source template; literal null
does not become typed_null. Literal payloads are serialized as data without
interpreting `$param`, `literal`, `meta`, or other business keys. Only the
already admitted normalization and canonical object-key order apply. Origin
sidecars, spans and text ranges never enter the emitted value.

This provides the source-value boundary needed by Program semantic projection
and later canonical root placement without assigning AoA slots that a consumer
contract has not defined. Ordered derive's row-kernel and other consumer
bindings remain distinct from the Relation Fragment root table; local slot
indices are not used as global Fragment root indices.

Emission is iterative, preserves array order and repeated occurrences, and
sorts each object's field handles in UTF-16 order. It does not materialize a
second JSON tree or a complete output string for the hash sink. The writer's
byte/node/depth budgets include the enclosing semantic body; object sorting
uses memory bounded by the previously admitted source, not a whole-heap limit
derived from max_bytes. Tests cover round trips through the existing admission
cases, fixed canonical bytes and an independent digest, exact sink budget
boundaries, depth 10,000 and width 10,000.

The authority is [common expressions](../spec/language.md#common-expression-contract),
the [text mappings](../spec/language.md#expression-text), and their pinned
[machine contract](../../spec/contracts/actql-expressions.json), including the
row-local vector forms. This guide does not add vocabulary.

The [restricted selector syntax boundary](selector-syntax.md) reuses this
decoder for Effect where elements and then checks the smaller allowed-node
grammar. Common decoding alone does not admit a general computation as an
Effect selector.

## Admission and normalization

Admission checks singleton tags, closed named bodies, required members, arities,
field and Parameter names, cast targets, decimal precision/scale and rounding,
literal time units and vector metrics, and literal/Parameter pattern and
delimiter positions. Ordinary comparisons reject direct literal null operands.
Boolean input types, comparison compatibility, and evaluation-time domains such
as negative subscript indices are not decided here.
The separate [Expression type checker](expression-typing.md) checks types against
supplied scopes and Parameter declarations; evaluation-time domains remain later work.
`field_references` retains ordinary field occurrences and unqualified template placeholders,
while `relation_references` additionally retains normalized join-field occurrences
for downstream Relation checking, with their original path/span/text range.
The ordinary-only accessor remains available,
excluding join fields and opaque literal payloads. Text field occurrences retain
the original scalar slot's path and span plus the identifier token's half-open
Unicode scalar range within the decoded text; property names are not separate
row-field references. `usage` reports consumed
syntax nodes, text bytes and tokens for callers sharing a larger budget.

`to_*` becomes `cast`. A whole-field alias such as `left.customer.city`,
whether text-decoded or structured, becomes a join field followed by property access. No constant folding,
reassociation, Parameter substitution, or semantic extension lowering occurs.
Object constructors remain nonempty; array constructors may remain untyped and
empty until checking supplies evidence. `empty_array.items` uses the existing
author value-contract reader, including required `nullable` at every type node;
it is retained in author form, not expanded to a checked contract.

Template placeholders accept ordinary fields and exact `left.name`/`right.name`
join references, not nested properties or expressions. Qualified placeholders
are included in `relation_references` and excluded from `field_references`;
typing resolves the corresponding side scope and propagates nullability.
Template brace syntax and static placeholder names are validated, but templates
are not expanded and their placeholders do not become Parameter references.
Field existence and whether each placeholder's type is printable require later
context. Literal JSON is opaque to Expression interpretation. The sole exception
is the immediate list under an IN/NOT IN RHS `{literal: [...]}`: its items are
scalars or exact singleton `{$param: name}` holes. Nested objects or lists there
are not arbitrary Expression operands.

Source parsing owns NFC/LF normalization. For manually constructed owned input,
static strings and literal data must already be canonical; admission rejects
noncanonical strings, malformed Unicode, nonfinite numbers, and negative zero
rather than repairing them. This is not a signed-artifact byte-admission API.

## Text provenance and locations

Only a successful call to `expression_text.parse` creates the private
text-decoded origin. It preserves diagnostic coordinates and Parameter occurrence
provenance, not a different normalization policy. Both origins undergo the same
alias normalization and closed validation. There is no public trust flag or
validation bypass.

For example, `left.id`, `"left.id"`, and structured `{field: "left.id"}` all
normalize to the same `join_field`; the same rule applies to `right.id`.
Quotation suppresses lexical qualifier recognition, not subsequent whole-field
alias normalization, as required by the common expression contract's
`normalization_fixed_point` law. By contrast, `"left".id` remains property access
on ordinary field `left`, because its decoded receiver has no whole-field alias.
Remaining field and property names obey the
[field-name contract](../spec/language.md#field-paths).

Normalization is idempotent on accepted structured output: another admission
with sufficient work limits retains the same expression value. Passing a raw
text-parser Cursor through common admission applies the same aliases as admitting
the corresponding expression string. Keep the returned opaque Expression for
its original occurrence locations; re-admitting a Cursor cannot reconstruct the
original token ranges. This is not canonical artifact byte or signature admission.

Structured failures and occurrences retain original Cursor paths and spans.
Embedded-text failures identify the original scalar slot and a separate
half-open Unicode-scalar range in the decoded expression. Text parser node ranges
survive common admission and alias expansion, not only Parameter/field tokens.
`origin(expression, cursor)` resolves any normalized node to its original
`Location`: an immutable source Cursor and optional decoded-text range.
Synthetic alias nodes inherit their source expression, while retained operands
keep their own locations. No synthetic canonical path is presented as authored.
No range pretends to map through JSON escapes or YAML folding to original bytes.

Unchanged structured nodes and keys preserve source spans. Rewritten nodes use
their containing expression span; text-generated nodes retain the text parser's
decoded coordinate space. Use the origin sidecar for source
locations, not a reconstructed path through the normalized output. Output-tree
budget failures refer to that retained tree and its supplied spans.

Parameter records are syntactic occurrences in source order, including repeated
names. Literal data, quoted names, template text, and structural option strings
do not contribute references. Records hold read-only `location` handles, not
expanded path arrays. `location_path` materializes one detached path on demand;
`location_span` returns the supplied original span. Array accessors copy only
handles. `relation_reference_count`/`relation_reference_at` support indexed
checking without exporting arrays. Ordinary fields index the same records as
relation references, rather than retaining a second copy of each origin.
There is no bulk expanded-path export. Callers displaying many paths must budget
their output; requesting one path costs its ancestry length.
Neither successful admission nor occurrence discovery proves declaration,
binding, actual runtime use, or Program/local-unit identity membership.

`collect_parameter_occurrences` separately enumerates Parameter nodes in the
normalized expression tree. Its opaque result retains that exact Expression;
indexed records contain the name and an owned Cursor. For `$p + $p`, the two
normalized paths are `/add/0` and `/add/1`, although both diagnostic locations
refer to the same source scalar slot. Cast rewrites likewise use `/cast/value`.
Use `origin` for original path/span/text range; a normalized path is not an
authored diagnostic location.

This traversal reuses grammar roles, visits expression children in retained
object/array order, and preserves repeated references. It skips literal payloads,
templates, cast targets and item contracts, except for the specified immediate
IN/NOT IN Parameter holes. Indexed child navigation and explicit continuations
avoid full child-array copies, recursive traversal and eager expanded paths.
`max_work` bounds popped traversal frames, including skipped nodes and collection
continuations; equality is accepted, negative limits fail, and exhaustion returns
no partial result. The reported work belongs to this pass, not admission.
The result is not a canonical reference index: enclosing grammar-slot discovery,
declaration/type attachment, RFC 6901 pointer encoding and canonical sorting still
belong to the Program/stage identity boundary.

The internal `source_map` builder keeps annotations outside semantic values and
owns the normalized tree with a preorder sidecar. Both conversion and admission
are bounded by output-tree node/depth limits; indexed lookup checks arena identity
before using a local coordinate. Sidecar storage and pending builder frames are
linear in tree size. `origin_count` exposes the retained node count for structural
regressions. These logical limits are not RSS quotas, and temporary builders and
owned trees may coexist.

## Bounded work

Traversal uses explicit continuations and one shared budget. `max_nodes` counts
every visited source or text-decoded node, temporary text-parser allocations,
and newly constructed normalization nodes. Pending siblings reserve nodes before
scheduling. `max_text_bytes` counts visited keys/string values and text-parser
input; decoding and then visiting a fragment are separate charged work.
`max_tokens` is shared across all fragments; EOF is not a token. A child never
receives a fresh copy of the whole remaining-work allowance.

`max_depth` bounds structural edges from a root at zero, and the remaining depth
also bounds each embedded parser's active expression continuations. The retained
tree has independent `decode_core.Limits`. Explicit item contracts undergo a
bounded contract-validation pass followed by the ordinary charged copy; this is
a constant additional pass, not an unbounded per-child allowance.

These are work and retained-value ceilings, not heap-memory limits. The input,
private builders and retained output can coexist. No streaming row-data path,
whole-Program traversal, type checking, profile admission, regex compilation,
evaluation, template expansion, semantic lowering, or CID computation is added.

## Verification

The [fixed structured corpus](../../portability/corpus/actql-expression-syntax-v0.1.json)
includes mixed syntax, constructors, aliases, quotation boundaries, opaque data,
IN holes, and rejected shapes. Every accepted structured corpus case also checks
normalization idempotence. Generated tests also pass the existing expression
text corpus through the common admission boundary. `check:expression-syntax`
checks generated-test freshness and generator regressions; it does not execute
MoonBit or establish evaluation conformance.

MoonBit tests cover all textual families in both entry forms, source positions,
detached results, cumulative budgets, retained-output limits, depth 10,000 and
wide mixed input on JS, Wasm and native. These are syntax-admission checks only.
