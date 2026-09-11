# Canonical regex pattern admission

`regex_pattern.parse` implements the closed
[regex grammar](../../spec/grammar/actql-regex-0.1.ebnf) and
[scalar AST contract](regex-ast.md). It returns an opaque owned Pattern, not a
Host regex object, a matching engine or a discharged Program obligation.

The source must already be NFC/LF and well-formed UTF-16. Admission rejects
noncanonical source rather than repairing it. Diagnostics use zero-based UTF-16
offsets in that source; the future expression resolver retains its original
source location separately. Escaped CR is scalar 13 and remains distinct from
LF, even though raw source CR is noncanonical.

## Construction and reference differences

Sketch `87dc7144` contains the corresponding TypeScript parser in
`src/actql-text-time-grammar.ts` and MoonBit parser in
`moonbit/src/text_time/text_time.mbt`. Both inform the admitted structure, but
neither legacy string-valued AST nor recursive traversal is reused. Main uses
an indexed arena, explicit group frames and an iterative canonical emitter.
Nullable information is computed once per constructed node, not by recursively
rescanning each quantified subtree. Captures use opening-parenthesis order;
one-element sequence/alternation wrappers are omitted, groups are never removed.
Repeated class items and branches remain repeated.

Three boundaries are recorded explicitly in the normative owner:

- The old TypeScript parser accepts an unescaped hyphen outside a class despite
  listing it as a metacharacter. Main follows the grammar and rejects it.
- First/last class hyphens retain the references' literal meaning. The grammar
  now names that context and allows scalar escapes as range endpoints; shorthand
  classes such as `\d` cannot be endpoints. Scalar ranges may cross the surrogate
  gap but never select a surrogate, since their universe consists of scalars.
- The old MoonBit parser bounds integers to nine digits; TypeScript uses safe
  integers. Neither limit is a normative requirement. Main admits exactly
  representable finite binary64 integers above 2^53, but rejects an integer that
  would be rounded. It checks the parsed result against an exact integer, with
  at most 309 decimal digits (every finite binary64 integer fits that length).
  This avoids interpreting two different authored bounds as the same AST number.

Quantified anchors and nullable operands are rejected, including `{0}` on a
nullable operand. This checks operand consumption, not whether the repeat as a
whole is nullable. Captures, sequences and alternations propagate nullability;
an unquantified nullable root remains valid. Matching, capture existence for
extract/replacement and policy admission are separate checks.

## Budgets and access

Limits cover source UTF-8 bytes, semantic nodes (including class items), semantic
AST depth (root node depth one), full serialized AST bytes and full JSON nodes.
Class items add one semantic level. Array containers in serialization do not add
semantic depth, but do consume the separate JSON node budget. The output budgets
include `ast_cid`; the identity preimage excludes only that field.

Nodes and pending group frames are bounded before allocation. Source storage,
arena storage and emitter stacks are distinct from serialized output limits;
`max_ast_bytes` is not a heap ceiling. Internal depth arithmetic supports limits
through 1,073,741,822; larger values are invalid limits, not language rejection.
There is no fixed 256-group limit. Very wide sequences/classes and 10,000 nested
groups are tested without recursion. Integer checking has a fixed-size operand
bound, so it does not introduce unbounded big-integer work.

`node_at` returns shallow node views with copied child/class-item arrays.
Indices are local to the owning Pattern, not persistent identities. No external
constructor can create a Pattern. `emit`, `emit_preimage`, the measuring sink
and hash sink share canonical emission, without building another JSON tree or
serializing the entire AST just to hash it. Writer failure remains terminal.

## Evidence and next integration

`portability/corpus/regex-pattern.json` has handwritten expected ASTs, canonical
bytes/CIDs and rejected source/diagnostic pairs. `check-regex-pattern.mjs`
independently checks their structure, nullability, capture numbering and hashes;
it does not call this parser or a Host regex engine to generate expectations.
Generated tests compare product results to those fixed expectations on all three
targets. Handwritten tests cover ownership, malformed UTF-16, output budgets,
wide and deep input. They do not establish matching conformance.

Next, `pipeline_check_context` must derive each pattern and static option from
its exact expression visit and bound parameters, require the selected text-time
policy, and connect capture/replacement validation and AST CIDs. A standalone
Pattern is not a substitute for that ownership boundary or a completed
HostEnvelope. Main does not implement the lowerer or matcher in this package.
