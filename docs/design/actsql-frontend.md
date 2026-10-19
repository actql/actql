# ActSQL frontend boundary

ActSQL is a separate MoonBit module, `src/actsql`. Its initial implemented
dialect slice is a literal row projection:

```sql
SELECT 1 AS id, -2 AS debt;
```

The grammar accepts one or more signed 32-bit integer literals, each with an
explicit unquoted ASCII alias, separated by commas. Keywords are
case-insensitive. An optional final semicolon is accepted. Aliases are
case-insensitively unique. The query yields one row with the authored column
order and a named `answer` Result. `FROM`, functions, expressions, parameters,
quoted identifiers, joins, aggregates and other SQL syntax are currently
unsupported; rejection includes the UTF-8 byte offset of the unsupported
token. Source offsets for each accepted literal and alias accompany the
generated document.

`compile_literal_select` emits an ordinary JSON Program document using the
common bounded encoder. The generated Program must still pass normal ActQL
parsing, semantic checking, admission, authorization and execution. This module
does not send SQL to DuckDB or choose a physical backend. Its tests compare a
separately authored Program expectation and pass the output through the
existing Program syntax parser on JS, Wasm and native targets. End-to-end SQL
execution and a public `Client.sql()` entrance remain separate release work;
the existing AQL document path does not depend on them.

## NULL ARRAY type context

The source ARRAY annotation parser is shared by constructors and the immediate
NULL CAST context. INT64 denotes the existing distinct signed64 item contract;
an annotation never converts ordinary Number elements. Full-range values use
the existing typed Parameter path.

`CAST(NULL AS ARRAY<T>)` lowers to the existing lazy conditional with a false
condition, a typed empty-array peer and the original NULL branch. Common
checking supplies nullable-array type evidence and emits its existing checked
typed-null representation. The evaluator selects NULL, so `IS NULL` continues
to distinguish it from an empty array while membership retains the existing
empty-set laws. Parentheses preserve the immediate NULL's source identity.
General ARRAY conversion is a separate implementation gap and must report that
limit rather than manufacture a value or a type error. The scalar CAST table,
old constructor forms and their canonical expression bodies remain unchanged.

## Exact CONTAINS connection

The SQL/Pipe `CONTAINS` call selects the existing Common `contains` expression
with its two original children. The lowerer does not emulate it through STRPOS
or perform a Host string search. Ordinary typed expression execution uses the
existing resumable text matcher with a Boolean terminal value, retaining both
operand roots and the existing per-poll, logical-value and workspace accounting.
NULL propagation follows eager child evaluation; enclosing lazy demand remains
owned by the Common evaluator. The canonical `contains` node already belongs to
the expression contract, so this connection does not introduce another wire
shape or reinterpret older Program identities.

## Public Number conversion

The documented `to_number` function and `CAST AS NUMBER` share the existing
Common CAST contract. Source lowering emits the same target schema and one
original operand subtree for both spellings. Conversion, nullable typing,
invalid text, failure, lazy demand and resource accounting remain in the
existing Common owners. The frontend does not evaluate text or broaden the
Number, Decimal or Signed64 domains. Existing CAST and Program bytes remain
unchanged; only the query-text rules identity advances for the new connection.
