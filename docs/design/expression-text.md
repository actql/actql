# Expression text admission

`expression_text` decodes the [expression EBNF](../../spec/grammar/actql-expression-0.1.ebnf)
and [Language mappings](../spec/language.md#expression-text) into the existing
common structured Expression tree. It does not introduce another public AST.

`parse` returns an opaque Expression. `tree` exposes its immutable owned
`decode_core.Cursor`; `parameter_references` returns detached occurrence records
in source order, including repeated names. A successful parse is syntax evidence,
not a typed expression or execution permission.

`usage` reports consumed input bytes, non-EOF tokens and temporary parser nodes
after success. The [common syntax reader](expression-syntax.md) uses these counts
to debit a shared budget across embedded fragments; limits are not reset for
each child.

## Decoding

The lexer consumes the whole input using ASCII case-insensitive keywords, exact
lowercase function names, SQL-style doubled quote delimiters and ordinary
backslashes. String literals and quoted names receive NFC then LF normalization.
Unpaired UTF-16 surrogates, comments and unlisted tokens are rejected.

Numeric tokens use `source_value.parse_json` on the isolated unsigned token,
with its exact token-byte allowance, one node and zero container depth. This
shares the JSON decoder's exact-significand rebasing before binary64 conversion;
it does not introduce another floating-point parser. Long mantissa/exponent
cancellation, overflow and underflow therefore follow the same rules. Unary
minus folds only a numeric token through grouping alone, rejects negative zero,
and otherwise produces `negate`.

Explicit heap continuations implement precedence, non-associative comparison
families, calls, arrays, searched CASE, CAST and postfix access. Unparenthesized
AND, OR and strict concatenation chains append to private builders; parentheses
stop flattening. The parser checks closed function names and arities, direct
literal-NULL comparisons, IN/LIKE operand shapes, literal-only decimal options,
decimal target bounds, rounding names, vector metric names, time units and
literal/Parameter pattern and delimiter positions. It does not evaluate operands.

## Positions and references

`relation_references` retains both ordinary and qualified field occurrences with
their original token ranges. Property names and literal contents are not field
occurrences. The ordinary-only `field_references` accessor remains available;
both accessors return detached arrays. Structured expression admission resolves
whole-field aliases such as `"left.id"` while retaining these source positions.

`Range` uses half-open **Unicode scalar offsets in the decoded expression**,
before token payload normalization. Invalid UTF-16 reports the position of the
offending unit after the valid scalar prefix. A separately optional
`enclosing_span` identifies the containing Program JSON/YAML scalar.
Neither field claims a byte-accurate mapping through YAML folding or JSON escapes.

The Cursor's generated nodes and keys carry the whole decoded expression span,
not invented token-level source spans. Its `source_path` names that decoded
coordinate space (default `<expression>`). Byte extents are UTF-8; lines count
CRLF once and lone CR/LF once, and columns count scalars, including tabs once.
Diagnostics and Parameter occurrences additionally retain precise scalar ranges.

Parameter occurrences are collected from Parameter tokens only after complete
syntax acceptance. Quoted strings/names are opaque; IN-list Parameter items
remain references. This is not whole-Program use discovery: structured
Expression traversal, template-hole rules, declaration resolution, unknown or
unused Parameter detection, and local used-value selection belong to later
consumers. Raw JSON keys or business strings must not substitute for that traversal.

## Budgets and ownership

The caller supplies all limits:

- `max_input_bytes`: decoded source UTF-8 size, before payload normalization.
- `max_tokens`: non-EOF tokens; EOF is a separate sentinel.
- `max_nodes`: total temporary tree nodes constructed, including subsequently
  folded/replaced literal wrappers; not just final tree size.
- `max_depth`: active expression continuations, with the root at one.
- `tree`: independent owned-tree node, container-depth, individual-string and
  total-string byte limits, using the usual `decode_core` conventions.

Zero budgets are valid and reject work that requires more; negative budgets are
invalid. There is no hidden recursive frame ceiling or multiplied tree-depth
allowance. Sibling operands and long left-associative chains do not accumulate
parser nesting; their retained tree still obeys the independent tree budget.
All work is bounded before an owned result is exposed, but these logical budgets
are not a process heap limit. Temporary tokens, builders and the owned tree may
coexist during admission. Failed parses expose no partial tree or references.

No field/type inference, Parameter substitution, profile admission, regex or
timestamp-pattern compilation, evaluation, Program/Unit identity, or Effect
position authorization is implemented here. In particular, accepting a text-time
or vector call does not admit the corresponding profile.

## Verification

`generate:expression-text` generates MoonBit tests from the existing fixed
[expression corpus](../../portability/corpus/actql-expression-text-v0.1.json).
`check:expression-text` verifies generated-test freshness and generator
regressions; it does not execute expressions or establish runtime conformance.

MoonBit tests compare the decoded tree with those fixed expectations and cover
literal restrictions, normalization, Parameter occurrence locations, independent
budget boundaries, long numeric tokens, malformed UTF-16, deep continuations and
long chains on JS, Wasm and native. These are syntax-admission tests, not evidence
of expression evaluation or complete ActQL conformance.
