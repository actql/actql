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

The remaining scalar function spellings `to_string`, `to_boolean` and
`to_timestamp` use the same boundary and their respective existing CAST target
schemas. No conversion runs during frontend lowering. Timestamp precision and
admission, civil/offset domains and operational clocks remain independent
existing-owner responsibilities; connecting the spelling does not widen them.

## Fixed DATE_TRUNC source order

SQL/Pipe uses the documented `DATE_TRUNC(value, literal_unit)` order and emits
the existing Common unit-first node. Only an admitted literal unit moves; the
original value subtree is neither evaluated nor copied. Legacy expression-text
and structured Program bodies remain unit-first. There is no type-based order
fallback. Common owns exact UTC bucket floor, Date day-only identity and all
runtime failure, lazy-demand and resource behavior.

### Fixed-unit DATE_ADD source connection

SQL/Pipe DATE_ADD retains its authored value, amount and literal unit as the
existing ordered Common operation. Parameters remain original operands, never
unit selectors. The frontend does not evaluate or quantize a duration. The
Common Number/temporal owners apply exact evaluated-binary64 duration admission,
Date day-only rules and the existing result, demand and failure boundaries.

### Explicit Decimal conversion calls

TO_DECIMAL(value, precision, scale) selects the same Common CAST target as
explicit DECIMAL(P,S) syntax. Precision and scale retain literal semantic roles;
only the original value subtree is an evaluated operand. The frontend checks
the existing bounded target shape and never evaluates or rounds the value.
The public lookup's omitted-target spelling is not resolved by fabricating
precision/scale: it keeps its implementation limitation. Explicit TRY_DECIMAL
retains its existing distinct Common body and nullable target. The same target
context resolves immediate NULL without changing its value. Explicit QUANTIZE
retains its original Decimal operand, static target and closed rounding String.
The public two-argument QUANTIZE spelling has an explicit authoring policy:
precision 38 and half_even. SQL/Pipe and authored Common expression text emit
the same complete existing body, preserving the original value subtree and
static scale role. A data-independent maximum precision avoids selecting the
output contract by evaluating the operand; half_even reuses one existing exact
rounding mode. Neither default is guessed by a structured reader or evaluator.
The original Decimal-only, NULL, overflow and demand boundaries still apply;
an unrepresentable result is not clamped or silently converted to NULL.
Complete four-argument bytes and the five explicit modes remain unchanged.
Only a direct literal NULL receives the nullable declared result Decimal
context. This scoped quantize rule reconciles the original signature with its
normative typing rule; it proves no non-null Decimal and does not type an
unknown field or unresolved Parameter. Decimal division's separate NULL-domain
conflict is not resolved by this unary rule.
Explicit DECIMAL_DIVIDE preserves two original children,
the same literal target roles and a closed rounding mode. The existing Common
binary evaluator owns demand, exact division, domain refusal and root release;
the frontend never evaluates the ratio or reinterprets numeric source tokens.
