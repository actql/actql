# Query text profile

The [query grammar](../../spec/grammar/actql-query-0.1.ebnf) describes the
GoogleSQL-derived SQL and Pipe surface of ActQL 0.1. It is a source form for an
ordinary Program, not a separate execution model. Parsing and lowering do not
authorize an input, certify a Plan, or bypass ordinary Program admission and
the common checker. The grammar alone does not promise every form is
currently executable. The [frontend design mapping](../design/frontend-r1.md)
records implemented boundaries and intentional differences.

## SQL and explicit Pipe boundaries

Begin with ordinary SQL or an initial `FROM` clause. Each subsequent operation
consumes the preceding output through its own explicit `|>`. The initial
`FROM source { JOIN ... }` includes its attached JOINs without a Pipe; the
same source, alias, ON/USING, MAX_OUTPUT_ROWS, correlated UNNEST and range rules
apply as in SELECT's FROM clause. A FROM-headed query does not include a bare
WHERE, ORDER BY or LIMIT. After the first Pipe, every further JOIN or other
operation requires another Pipe.

For example:

```sql
FROM left_input AS l
JOIN right_input AS r ON l.id = r.id MAX_OUTPUT_ROWS 10
|> WHERE l.amount > 0
|> SELECT l.id AS id;
```

Ordinary SELECT retains its SQL clauses without Pipes. Clause arguments and
modifiers remain internal: AGGREGATE's GROUP BY, JOIN's ON/USING/bound,
INFER's ITEM KEY/INPUT/KEEP/AS, NEAREST's roles and options, LIMIT's OFFSET,
OVER's window specification and SERIALIZE's FORMAT/order/OPTIONS do not gain
extra Pipes. Existing standalone `|> AS` and `|> ORDER BY` remain operations.
There is no implicit continuation mode after INFER, WHERE or a Carrier call.
Keywords in strings, comments and quoted names are not delimiters.

Pipe denotes logical input/output composition, not a new Task, Stage,
materialization, acquisition, checkpoint or authorization boundary. The
existing planner/checker retains its observation, resource and Effect duties.
JOIN still requires Relation inputs. A later Graph/Vectors/Events row bridge
cannot repair a JOIN that already consumed a non-Relation; use the explicit
bridge before joining. The Graph marker retains its original type expectation.
FROM-only retains its existing row/value-table/range semantics and does not
insert SELECT star, rename collisions or reset parsing budgets.

WITH bodies, derived tables and pure set operands retain their Pure rules;
CTAS retains its existing Compute and whole-wrapper rules. Top-level sql versus
aql-text selection is unchanged. Command postludes after the terminating
semicolon are declarations in the same Stage and Effect Set, not arbitrary
statement chaining or an implicit current-input Pipe.

## Content serialization

`SERIALIZE FORMAT CSV` or `SERIALIZE FORMAT JSONL` consumes the current Relation
through the ordinary Program Content barrier, not a Frontend encoder. It takes
an internal `ORDER BY` or `PRESERVE ORDER`, followed by `OPTIONS (...)`:

```sql
SELECT 2 AS id, CAST(NULL AS FLOAT64) AS p
|> SERIALIZE FORMAT CSV PRESERVE ORDER OPTIONS (
     name = 'selected.csv', header = TRUE, null_marker = r'\N',
     encoding = 'UTF-8', line_ending = 'CRLF', max_rows = 3, max_bytes = 128
   )
|> RESULT file;
```

The output columns are exactly `name`, `content`, `media_type`, `size_bytes`
and `row_count`. A terminal RESULT binds this output without another computation
after the barrier. Input fields and range aliases do not survive it.
The common [Content profile](language.md#serialize) owns option domains and
defaults, presence, ordering evidence, bounds and byte laws in every source
format. Options are static scalar literals; the two bounds additionally accept
declared parameters. Row expressions, duplicate or unknown options are refused.
CSV requires explicit `header` and `null_marker`; the latter is either empty
text or the exact `\N` value. Generating Content does not upload it or grant
Model/Command access. Runtime support is established separately from parsing;
acquired input, explicit ordering and downstream components require their real
execution/custody connections.

## Decoding and expression rules

Input must be strict UTF-8 scalar text. A leading BOM follows the existing
source policy. Keywords are ASCII case-insensitive. Column, field and alias
lookups are ASCII case-insensitive whether or not the name is backtick-quoted;
the original spelling remains in the parsed source and authored output name.
Published Source View paths use their separate rule: an unquoted component
matches without ASCII case, while a quoted relation component requires exact
spelling.
Unquoted names match `[A-Za-z_][A-Za-z0-9_]*`. Backticks quote names and do
not switch column lookup to exact-case mode.

Single and double quotes delimit query STRING literals, following the selected
[GoogleSQL lexical rules](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/lexical#string_and_bytes_literals).
The opposite quote can appear unescaped. Both forms decode backslash, either
quote, backtick, question mark, `a`, `b`, `f`, `n`, `r`, `t`, `v`, exactly
three octal digits with a first digit in `0`–`3` (maximum `\377`, U+00FF),
`x`/`X` with exactly two hex digits, `u` with four hex
digits, and `U` with eight hex digits. These escapes produce Unicode scalars;
surrogates, out-of-range values and incomplete or unknown escapes are rejected.
In decoded plain and triple-quoted STRING chunks, `\400` and `\777` are
invalid escapes; raw chunks preserve them as literal backslashes and digits.
Plain quoted literals cannot contain a raw CR or LF, including an escaped
physical newline. A decoded CR, LF, CRLF or decomposed Unicode sequence is
preserved exactly through the ordinary String value contract. Escape decoding
does not apply identifier normalization to the resulting value.

Triple single or double quotes also delimit STRING. They permit physical
newlines and individual matching quotes; three unescaped matching quotes close
the chunk. Unescaped source CR and CRLF in these chunks decode to LF, following the
pinned [GoogleSQL literal decoder](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/googlesql/public/strings.cc)'s
newline interpretation. Escaped `\r` remains CR;
this source interpretation does not normalize decoded or stored values.
An escaped physical newline is rejected in a non-raw chunk.

An immediately adjacent `r` or `R` prefix makes one plain or triple-quoted
chunk raw. A backslash and the following scalar are both retained, including
an escaped quote; a raw chunk cannot end with an odd number of backslashes.
Plain raw chunks still reject physical newlines. Raw mode does not extend to
later chunks.

Consecutive STRING chunks separated by whitespace or comments form one
literal whose value is their concatenation. They may mix quote styles, plain
and triple quotes, and raw and decoded chunks. Without separation they are
rejected. Quoted identifiers do not concatenate. Decoded byte, token and work
budgets apply to every chunk, and the resulting expression's source range
covers the original chunks and intervening trivia.
In an explicit STRING_AGG delimiter, grouping parentheses around these literal
chunks preserve the decoded String value. This applies to ordinary and window
aggregates. The delimiter remains a non-NULL String literal in the selected
profile; grouping does not admit parameters, NULL, other scalar types or
computed delimiter expressions. The ordinary aggregate's WHERE/ORDER and the
window's OVER/frame keep their independent scope and bounds.

Double quotes do not quote identifiers: `"id"` is a value, while `` `id` `` is
a name. Graph labels come from the admitted Graph definition; no query-local
property annotation changes their membership.
Backtick identifiers use the same non-raw escape repertoire as STRING,
including the `\\377` octal ceiling. They must be nonempty and may contain
physical newlines and control scalars. Source CR and CRLF decode to LF;
escaped `\\r` remains CR at decoding. Raw prefixes, triple quotation and
chunk concatenation do not apply to identifiers. Decoded names still pass
through ordinary name resolution and the common authored-name contracts;
quoting does not bypass field-name restrictions or confer authority.
Comments are line `--` and non-nested block `/* ... */` comments. Query
parameters use `@name`. Bytes and raw bytes are not yet implemented in this
profile and are rejected, including mixed STRING/bytes chunks, rather than
decoded as STRING. They remain GoogleSQL coverage gaps, not restrictions of
the reference language. Interpolation and multiple statements are rejected.
The JSON/YAML machine-expression text dialect keeps its own quotation rules.

Expressions use a shared parsed tree and lower directly to the existing
structured Expression form. Operator precedence, searched CASE, closed scalar
functions, casts and the `OVER` subset follow the adopted profile. New query
`CONCAT` and `||` use strict STRING concatenation with NULL propagation;
`ACTQL.CONCAT` names the legacy null-skipping function explicitly. Unsupported
overloads and numeric domains are rejected before a Program is issued.
Expression text is never concatenated and reparsed with the legacy dialect.

Integer tokens follow the selected [GoogleSQL lexical forms](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/lexical#integer_literals): decimal digits or `0x`/`0X` followed by one or more hexadecimal digits. Hexadecimal digits are case-insensitive; the token and AST retain the exact authored spelling and original source span. Unary `+` and `-` remain expression operators. The existing common `number` profile admits integer magnitudes through `9007199254740991` (`0x1fffffffffffff`) exactly, before conversion to finite binary64. Larger integer tokens are refused without rounding; this profile does not claim GoogleSQL's full INT64 value domain. Negative zero remains invalid under the existing common value contract. Hexadecimal fractions, binary exponents, digit separators and incomplete prefixes are not integer tokens in the selected profile.

The same unsigned exact-integer decoder supplies literal LIMIT/OFFSET, bounded type arguments, ORDER/GROUP column positions and navigation offsets. Each context retains its own positivity, column-range, parameter and role checks; hex spelling does not bypass them. Named numeric operation arguments use the ordinary expression numeric admission. Integer UNPIVOT row aliases still reach the existing explicitly unsupported lowering boundary; accepting an integer token is not evidence of integer-label execution. No separate numeric runtime, cast or execution owner is introduced.

`ABS(expr)` in SQL and Pipe has exactly one finite binary64 `number` operand
and lowers to the common `abs` node. It returns the exact magnitude, including
subnormal and maximum finite values, and canonical positive zero. NULL
propagates and result nullability follows the operand, including on empty
input. The operand is evaluated once on demand under the common lazy-demand,
first-failure, cancellation and logical-budget rules. The adopted subset has
no implicit conversions, decimal overloads or non-finite numeric values.

`STARTS_WITH(value, prefix)` and `ENDS_WITH(value, suffix)` each take exactly
two STRING operands and lower to the common `starts_with` and `ends_with`
nodes. The selected [GoogleSQL prefix](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/string_functions#starts_with)
and [suffix](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/string_functions#ends_with)
rules use default binary comparison of retained strings. Empty prefixes and
suffixes match every non-null string, including the empty string. Matching
applies no normalization, case folding, trimming or locale conversion. Either
NULL input yields NULL; both children are evaluated once in authored order
under the common failure, cancellation and budget rules. Result nullability
is the union of operand nullability, including on empty input. BYTES overloads
and explicit collations remain GoogleSQL coverage gaps.

The adopted canonical `vector_score(left, right, metric)` scalar takes exactly
three positional arguments. `metric` must be a decoded STRING literal equal to
`'cosine'`, `'dot'` or `'l2'`; ordinary parentheses preserve this literal role.
A Parameter, column, CASE, concatenation expression or folded uppercase value
cannot select the operation. Rejections retain the authored third-argument
range. `vector_score(..., 'l2')` returns the existing negative-distance score,
while `VECTOR_L2_DISTANCE` below negates it. `vector_concat(first, second, ...)`
uses the same installed lookup and existing two-or-more typed-Vector contract.
Both canonical names are the already adopted ActQL scalar forms, not new
GoogleSQL function claims.

The adopted ActQL vector scalar forms are
`VECTOR_COSINE_SIMILARITY(left, right)`, `VECTOR_INNER_PRODUCT(left, right)`,
`VECTOR_L2_DISTANCE(left, right)` and `VECTOR_CONCAT(first, second, ...)`.
The score forms require exactly two typed Vector operands; concatenation
requires at least two. They lower to the existing `vector_score` cosine/dot
forms, negated `vector_score` l2, and `vector_concat`, respectively. The existing
common VecA profile, dimension checks, binary32 input law, NULL propagation,
zero-vector behavior and bounded evaluation remain authoritative. L2 distance
changes only the direction of the existing negative-distance score; these
ActQL spellings do not assert GoogleSQL distance-function compatibility.
Concatenation preserves operand order and multiplicity and sums the declared
dimensions. An ordinary ARRAY is not implicitly cast to Vector, and ordinary
Parameter declarations still exclude Vector. Quoted function names use the
same installed case-insensitive lookup. Metric names remain distinct public
function identities when deciding expression reuse. See
[the existing vector expression contract](language.md#scalar-expressions).

`STRPOS(value, subvalue)` takes exactly two STRING operands and lowers to the
common `strpos` node. The selected [GoogleSQL STRPOS rule](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/string_functions#strpos)
returns the first match's 1-based character position, or 0 when absent. ActQL
counts Unicode scalars; an empty subvalue yields 1 even for an empty value.
Comparison is default binary and preserves exact retained strings. Both
children evaluate once in authored order before strict NULL propagation;
nullable operands imply a nullable result, including on empty input. The
common failure, lazy-demand, cancellation and budget rules apply. ActQL uses
an exact integer-valued finite `number` within its bounded string domain;
GoogleSQL's INT64 result type, BYTES overload and explicit collation remain
coverage gaps.

`SUBSTR(value, position[, length])` and `SUBSTRING(value, position[, length])`
are aliases of the common named-body `substring` scalar. Their selected
[GoogleSQL STRING rule](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/string_functions#substr)
counts Unicode scalars, uses one-based positive and end-relative negative
positions, and treats zero or overly negative positions as one. Omission
retains the suffix; length zero or a position beyond the end returns empty.
A negative/nonintegral/unsafe length or nonintegral/unsafe position fails on a
demanded non-null call, after every supplied operand has evaluated once.
Strict NULL, lazy demand and resource/cancellation laws belong to the common
owner. Result nullability combines all supplied arguments; known input String
upper bounds are preserved, including on empty input. Canonical omission is
preserved without a synthetic length expression. The admitted number indices
are safe-integer-valued finite binary64 numbers; full INT64 and BYTES remain
coverage gaps. Quoted/case variants retain the same function identity.

`SIN`, `COS`, `TAN`, `ASIN`, `ACOS`, `ATAN`, `SINH`, `COSH`, `TANH`,
`ASINH`, `ACOSH` and `ATANH` select their direct unary common expressions;
`ATAN2(first, second)` selects the ordered binary `atan2` common expression.
The [GoogleSQL mathematical function rules](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/mathematical_functions)
apply within the existing finite Number domain: circular angles and inverse
results are radians, ASIN/ACOS require [-1,1], ACOSH requires >=1 and ATANH
requires strict (-1,1). ATAN2 preserves authored first/second ordering and
quadrant signs rather than dividing or swapping; canonical public (0,0) is
positive zero. NULL propagation precedes value-domain checks after demanded
children succeed. The selected target's pinned core primitive and finite-result
validation remain authoritative for execution; all prior numerical obligations
remain unchanged. No reciprocal functions, implicit conversions, new numeric
overloads or SAFE prefix are added by this increment.

`CBRT(value)` selects the direct unary `cbrt` common expression, following the
[GoogleSQL cube-root rule](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/mathematical_functions#cbrt)
within the existing finite Number domain. Positive and negative finite inputs
produce their real cube root, either zero sign produces canonical positive zero,
and NULL produces NULL. The pinned MoonBit math primitive supplies the numerical
operation with existing finite-result validation; this does not promise general
last-bit equality across targets or live BigQuery. No implicit conversion,
Decimal, distinct INT64/NUMERIC/BIGNUMERIC, non-finite overload or SAFE prefix is
added. Arity, type, once-only child demand, failure, resources, cancellation and
canonical identity remain with the common expression owner.

The finite Number scalar functions `POW(x, y)` and `POWER(x, y)` lower to the
same `pow` operation. `EXP(x)`, `LN(x)` and `LOG10(x)` are unary. `LOG(x)` is a
synonym of `LN(x)`; `LOG(x, base)` is binary and retains its ordered arguments.
The common expression finite-domain, NULL and arithmetic-failure rules apply.
No distinct INT64/NUMERIC/BIGNUMERIC or non-finite overload is added. `MOD` is
not admitted as a GoogleSQL FLOAT64 function; internal `%` remains unchanged.

`LEFT(value, length)`, `RIGHT(value, length)`, `LPAD(value, length[, pattern])`
and `RPAD(value, length[, pattern])` select the common String scalar operations
with the same ordered argument arrays. Side slices select at most the requested
number of Unicode scalars. Padding truncates to an original prefix or repeats
the omitted U+0020/explicit nonempty pattern at the corresponding side, retaining
only the needed final pattern prefix. Zero, NULL, failure, finite safe-integer
length validation and cooperative resource rules belong to the common owner.
Every supplied child remains present exactly once; quoted and case variants
retain function identity. BYTES, explicit collation and the full INT64 length
domain remain coverage gaps. No frontend evaluator or expansion that repeats
the length child is introduced. Unquoted `LEFT` and `RIGHT` select function
calls only when immediately followed by the opening-parenthesis token. They
remain reserved as bare identifiers; `LEFT JOIN` and `RIGHT JOIN` retain their
query syntax and are not reclassified as scalar calls.

`SPLIT(value[, delimiter])` selects the common `split` expression, following the
[GoogleSQL STRING rule](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/string_functions#split).
The optional delimiter is an ordinary STRING expression; literal matching
excludes regular expressions but does not require a literal-valued argument.
Omission selects comma and remains a one-element ordered argument array.
Empty input produces one empty String; an empty delimiter on nonempty input
selects Unicode scalars. The nullable Array result has non-null String elements
and the common conservative input-derived bounds. Every supplied child remains
once-only and ordered before strict NULL propagation; child errors, lazy demand,
resource admission and cancellation remain with the common expression owner.
BYTES and collation remain coverage gaps. No `split_part` profile or frontend
split evaluator is introduced.

`BYTE_LENGTH(value)` and its `OCTET_LENGTH(value)` alias select the same unary
`byte_length` common expression for STRING UTF-8 byte counts. `UNICODE(value)`
selects `unicode`, returning the first Unicode scalar code point or zero for
empty input/leading NUL. `CHR(value)` selects `chr`, accepting integral finite
Number code points from 0..0xD7FF or 0xE000..0x10FFFF. Zero returns an empty
String; every other admitted code point produces one scalar. Fractional,
negative, surrogate and out-of-range inputs fail after strict NULL propagation.
These follow the [GoogleSQL STRING rules](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/string_functions),
within the existing bounded String/finite Number domains. BYTES and distinct
INT64 overloads remain coverage gaps. All spellings preserve one common child,
operand nullability, lazy demand, failure, resources and cancellation.

`CURRENT_TIMESTAMP()` selects the zero-argument Common
`{current_timestamp: []}` operation and a non-null Timestamp type. Case-insensitive
lookup and parentheses preserve this same node; arguments or foreign namespaces
do not introduce an overload. Checking, explaining, emission and compilation
retain its dependency without sampling time. Runtime evaluation reads the same
admitted original query-invocation value across rows, fragments and recovery,
as specified by [Query invocation time](language.md#query-invocation-time).
It is not a frontend clock read, Timestamp literal, authored Parameter or
authority for a Source/Effect or an operational clock. A missing original
execution context remains an implementation limitation.

SQL fixed intervals use `TIMESTAMP_ADD(value, INTERVAL amount UNIT)`,
`TIMESTAMP_SUB(value, INTERVAL amount UNIT)` or Timestamp `+`/`-` that interval.
The original integral token is retained exactly, and dynamic amounts require
int64 fields or Parameters. The shared Common `timestamp_add`/`timestamp_sub`
consumer uses fixed ns/us/ms/s/m/h/d durations without binary64 conversion,
calendar-month or timezone interpretation. It preserves strict NULL, original
child failure and enclosing lazy demand. This does not change DATE_ADD's
existing Number-bit duration meaning or introduce a standalone Interval value.

`DATE_TRUNC(value, literal_unit)` is the SQL/Pipe spelling for fixed UTC
truncation. The unit is an original string literal in `ms`, `s`, `m`, `h`, `d`;
parentheses may preserve that literal but a Parameter, expression, alternate
case or reversed argument order is not a unit overload. Lowering emits the
unchanged Common `{date_trunc: [literal_unit, value]}` body. The legacy
expression-text `date_trunc(unit, value)` and structured Program representation
retain their unit-first order and complete preimages. No frontend evaluation,
type-guessed fallback, duplicated value or synthesized temporal value is used.

Timestamp truncation returns the start of the containing fixed UTC bucket,
using the existing exact seconds/nanoseconds and canonical Value domain. Thus
an instant 1ns before the Unix epoch truncates to the preceding millisecond,
second, minute, hour or UTC day, rather than toward epoch zero. Date admits only
`d` and is unchanged. NULL, original demanded failure, enclosing lazy demand,
value/work limits and cancellation retain their Common owners; operational
clock domains and the separate quotient law of `date_diff` do not change.

`DATE_ADD(value, amount, literal_unit)` preserves the three original Common
children in that order. The literal unit is exactly `ms`, `s`, `m`, `h` or `d`;
a Parameter or computed String cannot choose the operation unit. The existing
Common temporal owner evaluates the original Number amount and interprets its
binary64 bits exactly as a fixed-unit duration. A result not representable in
nanoseconds or within the original calendar fails without rounding. Date allows
only integral day amounts. No frontend temporal evaluator or decimal spelling
reinterpretation is introduced. Existing structured Program and expression-text
forms retain their bytes and meanings.

`TO_DECIMAL(value, precision, scale)` uses the existing explicit Decimal target
form. Precision and scale are original integral Number literals with
`1 <= precision <= 38` and `0 <= scale <= precision`; transparent parentheses
retain the literal role. A Parameter, field or computed Number cannot select
the target contract. Lowering emits the existing `cast` with the original
operand and `decimal(precision, scale)` target, exactly as explicit
`CAST(value AS DECIMAL(precision, scale))`. The ordinary Common conversion
retains exact coefficient/scale checks, NULL and failure laws; no frontend
value conversion, rounding or numeric-domain promotion is introduced.

`TRY_DECIMAL(value, precision, scale)` retains the same literal target roles
and emits the existing `try_decimal` body with the original operand. Its
nullable Decimal result uses the Common exact conversion boundary: only an
invalid or unrepresentable conversion becomes NULL. A child evaluation failure,
control limit or admission failure remains a failure. Immediate NULL receives
the explicit target context and stays NULL. No omitted precision/scale is
fabricated, and ordinary CAST retains its existing failure behavior.

`QUANTIZE(value, precision, scale, rounding)` keeps the same literal target
roles and additionally requires one original String literal from
`half_even|half_up|toward_zero|floor|ceiling`. Lowering preserves the existing
`quantize` body and evaluates only its original Decimal operand. The Common
Decimal owner rounds the exact coefficient, rejects result overflow and
preserves NULL and demanded-child failure. No frontend evaluator, binary64
intermediate or implicit conversion is introduced.

SQL and Pipe `QUANTIZE(value, scale)` MUST normalize to the existing complete
`quantize(value, 38, scale, 'half_even')` body. The scale keeps its original
integer-literal target role in `0..38`, including transparent parentheses; a
Parameter, field or computed expression cannot choose it. The original value
subtree remains the only evaluated operand and retains Decimal-only admission,
NULL, demand, failure and overflow behavior. Structured and machine bodies still
require every field, and the complete four-argument source path is unchanged.

`DECIMAL_DIVIDE(left, right, precision, scale, rounding)` preserves both
original operands in source order. The left is Decimal; the right is Decimal
or an original Number whose evaluated value is a safe integer. Precision,
scale and rounding retain the same literal target roles as `QUANTIZE`, with
`exact` admitted only for division. The original five named rounding modes retain
their old explicit behavior. SQL/Pipe `DECIMAL_DIVIDE(left,right,scale)` MUST emit
the complete body with precision38, original integer-literal scale in `0..38`
and `rounding: exact`, including transparent parentheses. Parameter, field and
computed scale expressions cannot choose the target. Common requires zero
remainder in the original coefficient ratio and a fitting result coefficient;
inexact quotients fail instead of selecting a hidden rounding policy. Structured
bodies still require all five fields. No omitted-scale policy is supplied.
Lowering retains both original child subtrees in source order. Zero divisors,
unrepresentable results and invalid Number divisors fail. Immediate
NULL uses the explicit Decimal target and original peer context, remains NULL,
and never suppresses a demanded child error. No frontend arithmetic, implicit
domain promotion or intermediate binary64 product is used.

`TO_STRING(value)`, `TO_BOOLEAN(value)` and `TO_TIMESTAMP(value)` each take
exactly one operand and lower to the existing Common `cast` node with target
`{"type":"string"}`, `{"type":"boolean"}` or `{"type":"timestamp"}` respectively.
Each is the same checked conversion as the corresponding scalar `CAST`, with
one original operand and no frontend evaluation. Case-insensitive and quoted
lookup, arity, nullable typing, invalid input, child failure, Parameter binding,
lazy demand, work and value limits retain their existing owners. In particular,
`TO_TIMESTAMP` does not broaden the admitted timestamp spellings, precision,
offsets or operational clock domains. Foreign namespaces remain unsupported;
no old CAST expression body or machine contract changes.

`TO_NUMBER(value)` takes exactly one operand and lowers to the existing Common
`cast` node with target `{"type":"number"}`, exactly as `CAST(value AS NUMBER)`.
It preserves the original operand, Parameter binding, nullable type, evaluation
failure and bounded conversion; the frontend neither parses numeric text nor
converts a nonliteral Number, Decimal, Signed64 or String on the Host. Existing
Common CAST typing determines which input domains are admitted. Ordinary
case-insensitive and quoted function lookup applies; a foreign namespace does
not select this conversion. This spelling does not add another machine node or
change any previously admitted canonical expression body.

`TRY_NUMBER(value)` takes exactly one original operand and lowers to the
existing closed Common `{try_number: {value: operand}}` body. It does not
parse, evaluate, duplicate or replace the operand in the frontend. The existing
text-time owner retains String-domain typing, nullable Number result, canonical
number grammar, strict child demand and the rule that only a non-null
unparsable String becomes NULL. Parameter binding, missing/foreign names,
profile admission, finite input/output envelope, Host policy and ordinary
control/workspace limits remain with their existing owners; lowering a call
supplies none of those facts. Ordinary case-insensitive and quoted lookup
applies, with no foreign-namespace alias. No Common expression contract or
previously admitted body is changed.

`CONTAINS(value, part)` selects ActQL's existing ordered binary `contains`
String predicate. It performs exact substring matching without normalization,
case folding or collation; an empty part matches every non-NULL String.
Both operands use ordinary String typing, are demanded once in authored order,
and propagate child errors before strict NULL propagation. Source lowering does
not replace the predicate with a position function, repeat an operand or add a
frontend evaluator. The existing Common bounded text matcher retains the two
original operand roots and charges each comparison until the Boolean result or
an original control, workspace, cancellation or value limit. Function names use
the ordinary case-insensitive/quoted lookup; argument count remains exactly two.

`TRANSLATE(value, source, target)` selects the ordered ternary `translate`
common expression for STRING only. Its simultaneous Unicode scalar mapping
leaves absent scalars unchanged, deletes source scalars without corresponding
targets, ignores surplus targets and rejects duplicate source scalars.
`INSTR(value, subvalue[, position[, occurrence]])` selects ordered `instr`
with two to four authored operands. Defaults are one; canonical bodies retain
omission rather than adding children. It returns 1-based scalar positions or
zero, searches backward for negative position, and counts overlapping matches.
Empty subvalue matches the length-plus-one scalar boundaries: positive position
selects that boundary, negative position selects length plus position plus two.
Both numeric operands require integral finite Number values, position nonzero
and occurrence positive. This explicitly adapts the
[GoogleSQL INT64 parameters](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/string_functions#instr)
to the existing finite binary64 domain without an INT64 or safe-integer cap;
large unreachable valid values return zero before narrowing. The
[TRANSLATE reference](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/string_functions#translate)
and common strict NULL, child-error, typing, resource and cancellation owners
apply. BYTES, collation, regex and implicit coercion are not added.

`REPEAT(value, count)` selects the ordered binary `repeat` common expression;
`REVERSE(value)` selects direct unary `reverse`. REPEAT accepts a STRING and
nonnegative integral finite Number count, returning empty for zero or an empty
input after strict NULL propagation and domain validation. GoogleSQL's INT64
count is explicitly adapted to ActQL's existing finite Number domain without a
safe-integer or INT64 cap; nonempty outputs remain bounded by existing resource
owners. REVERSE reverses Unicode scalar order, preserving astral scalars and
combining marks without normalization or grapheme segmentation. These follow
the [GoogleSQL STRING rules](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/string_functions)
within the admitted STRING surface; BYTES and distinct INT64 remain coverage
gaps. All demanded children run once in order before NULL propagation, preserving
failure, enclosing lazy demand, resources, cancellation and canonical nodes.

`SIGN(expr)` takes exactly one finite binary64 `number` operand and lowers to
the common `sign` node. Following the selected [GoogleSQL SIGN rule](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/mathematical_functions#sign),
it returns the number -1, positive zero or 1 for a negative, zero or positive
operand. Both zero signs yield canonical positive zero. Subnormals and the
largest finite values are admitted. NULL propagates and preserves operand
nullability, including on empty input. Evaluation demands the child once and
retains the common lazy-demand, failure, cancellation and budget rules.
This implements the finite FLOAT64 subset. INT64, NUMERIC, BIGNUMERIC and
non-finite overload domains remain unsupported; no implicit conversion is
introduced by the frontend.

`GREATEST(expr, ...)` and `LEAST(expr, ...)` require at least one finite
`number` expression and lower to the corresponding common nonempty argument
array, retaining order, repetitions and singleton calls. They return the numeric
maximum/minimum; any NULL yields NULL after every demanded child succeeds.
A NULL operand does not suppress a later arithmetic error. Enclosing lazy
conditional and COALESCE demand still applies. Immediate untyped NULL has the
unique number signature, including all-NULL calls, and result nullability is the
union of operand nullability. Empty calls are rejected before checking.

Only the finite Number subset is implemented. STRING, BOOLEAN, decimal,
temporal, BYTES, non-finite and mixed-type overloads, implicit conversions and
collation are unsupported. GoogleSQL's Unicode-code-point STRING order differs
from the canonical ActQL UTF-16 order; these functions do not redefine that
shared ordering owner. No GoogleSQL NUMERIC/BIGNUMERIC support is implied.

`ROUND(expr[, n])` and `TRUNC(expr[, n])` take one or two finite binary64
`number` expressions and lower to the common `round` or `trunc` node.
The omitted-position forms retain their unary body and value rules: ROUND
selects the nearest integer with halfway cases away from zero, while TRUNC
selects the nearest integer toward zero. Already-integral unary inputs remain
unchanged, including the largest finite magnitudes. With an explicit position,
the common source body is the ordered array `[expr, n]`, including when `n` is
zero. The result is nullable exactly when any operand is nullable, including
on empty input. Evaluate both children once in authored order, even if the
first is NULL; propagate NULL only after both evaluations succeed. Common
failure precedence, enclosing lazy demand, cancellation and budgets remain in
force.

With both operands non-null, `n` must be integral at evaluation; a fractional
position fails with the arithmetic error. This representation is ActQL number,
not a distinct GoogleSQL INT64 signature, and does not exactly represent every
INT64 position. Positions greater than 323 preserve the input and positions
less than -308 yield positive zero before any integer narrowing. The selected
decimal-position algorithm is `DecimalRounding` from
[GoogleSQL revision `81c15b796138185c046aefe852321011fdf96615`](https://github.com/google/googlesql/blob/81c15b796138185c046aefe852321011fdf96615/googlesql/common/round_decimal.cc),
using that revision's portable non-FMA `Full<double>` Dekker operations, fixed
high/low power-of-five pairs and final two-stage binary scaling, as specified
in [Scalar expressions](language.md#scalar-expressions). An ordinary binary64
multiply by `10^n` or ideal exact-rational decimal rounding is not an equivalent
replacement. This is a selected finite-FLOAT64 algorithm, not a live BigQuery
or all-target execution claim. ROUND overflow fails; TRUNC does not overflow
for admitted finite inputs and integral positions. Every zero result follows
the existing positive-zero rule.

The selected forms correspond to
[GoogleSQL ROUND](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/mathematical_functions#round)
and [TRUNC](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/mathematical_functions#trunc).
A third `rounding_mode` argument, distinct INT64/NUMERIC/BIGNUMERIC overloads
and non-finite values remain outside this profile. Wrong types and arities
other than one or two MUST be refused rather than ignored or coerced.

`SELECT * EXCEPT (name, ...)` uses the adopted
[GoogleSQL column-exclusion syntax](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#select_except).
It expands the current visible star columns, removes all matching named
columns under ordinary column-name resolution, and preserves the remaining
column order. The exclusion list is nonempty and every name must resolve in
that star scope. It is not the EXCEPT set operation. Exclusion does not apply
to separately written expressions elsewhere in the SELECT list, and it does
not alter row multiplicity or NULLs. Ordinary projection and DISTINCT checking
still apply; no execution operation or special Source acquisition is added.

After SET, DROP, RENAME or AS, exclusions use the same current Pipe slots as
star. They do not restore a removed column or range alias. In SQL GROUP
queries, the retained star columns must be grouped; excluded columns need not
be grouped. A GROUP BY ordinal counts the expanded, excluded SELECT list in
its final order. WITH-bound Relations use their current declared columns.
`alias.*`, including an EXCEPT list, expands an existing Relation range alias
in its declared column order. The receiver is a source Reference with ordinary
alias quotation/name resolution, not a string interpreted as a schema. SQL,
Pipe, CTE and JOIN ranges share the same physical-slot scope. SET/DROP/RENAME
retain a surviving range's original values. SET/DROP remove a range whose name
matches a target column; RENAME rejects a target hidden by a range name.
Pipe AS replaces the range scope. SELECT
materialization ends its input range scope, while a deferred query ORDER may
still consume the admitted SELECT input snapshot before that materialization.
SQL GROUP ordinals count the expanded and excluded range columns, and every
retained star column must be grouped. LEFT JOIN nullability belongs to the
common joined schema. A missing or displaced range is refused, including a
star that would otherwise appear to be an identity projection. The selected
[GoogleSQL star reference](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#select_expression)
also permits expression/STRUCT receivers. A named closed object column or
qualified property path, for example `payload.*` or `o.payload.*`, now expands
its admitted common fields through ordinary property projections. Its field
order is the common object's canonical order, independently of authored JSON
key order, as for closed object UNNEST below. A nullable receiver propagates
NULL through the common property checker; fields are never inferred from rows.
EXCEPT and REPLACE use the same input snapshot. SET's current column and a
retained range's original column remain separate values; SELECT and AS still
end or replace ranges. Type inspection follows the actual lowered prefix and
never adds a runtime probe, acquisition, Result or schema evidence. Existing
range stars retain their range resolution. A computed scalar expression with a
closed object contract, for example `COALESCE(payload, other).*` or
`(CASE WHEN payload IS NULL THEN other ELSE payload END).*`, uses the same
field expansion and common type checker. The receiver is evaluated in an ordinary
private derive once before its retained field projections; those private columns
are removed by SELECT and never exported. EXCEPT/REPLACE still see the SELECT
input snapshot. Already evaluated GROUP/QUALIFY fields use their existing slots,
and ORDER reuse retains the original receiver expression and resolved scope.
A scalar or unknown-field receiver is refused through the existing typed boundary.
GoogleSQL's ordered/anonymous STRUCT contract remains unconnected coverage; a
computed closed object is not reinterpreted as a Relation range.
Direct Graph star and FULL JOIN chains retain explicit implementation gaps,
not restrictions of the selected reference. Supported INNER/LEFT/RIGHT/CROSS
joins expand unqualified star from their complete current visible row.

`SELECT * REPLACE (expression AS column, ...)`, also following a supported
range star and EXCEPT list, changes selected values/types while retaining the
star's column names and order. Every target must occur exactly once in the
retained star list; exclusions are applied before replacement, and duplicate
targets are refused under ordinary field-name resolution. The expressions all
see the same SELECT input snapshot, rather than earlier replacement values.
Expansion yields ordinary projections and reuses their checker, GROUP/HAVING,
analytic and ORDER semantics. A new output alias refers to its evaluated slot;
qualified input references still denote the input snapshot where that scope is
available. GROUP ordinals count the final expanded SELECT list. No replacement
constructs type, identity, uniqueness or order evidence. The
[GoogleSQL star REPLACE clause](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#select_replace)
is distinct from the scalar STRING function of the same spelling.

`LIMIT` and `OFFSET` accept an exact integer literal or a whole named
parameter, including transparent grouping and numeric unary plus such as
`LIMIT +((@count)) OFFSET (+1)`. The selected GoogleSQL positive integer sign
retains the literal/parameter role; it does not introduce an expression into
the common `take` operands. Grouping and each unary-plus wrapper use the existing
expression budgets and do not evaluate arithmetic,
casts, calls or row references. Names lower to the ordinary `take.count` and
`take.offset` Parameter
slots; declarations and values follow existing Program checking, with no
Frontend evaluation, coercion or default for an invalid/missing binding.
Omitted OFFSET is the literal zero. The current common `take` contract still
requires a positive count, a nonnegative offset, safe integers and proven input
order. GoogleSQL also allows zero count and more general constant expressions;
these remain coverage gaps, not restrictions of GoogleSQL. Row-dependent and
arithmetic operands are rejected by this implemented literal/parameter subset.

`CAST(value AS DOUBLE)` and `ARRAY<DOUBLE>` use the same existing Number
contracts as `CAST(value AS FLOAT64)` and `ARRAY<FLOAT64>`. Type names are
ASCII case-insensitive and unquoted. The selected [GoogleSQL language reference](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/docs/data-types.md#floating_point_types)
defines FLOAT64 as an alias for DOUBLE; this is not a claim about every deployed
Google product. The alias introduces no conversion, precision, failure or NULL
rule. FLOAT/FLOAT32 are separate reference types and remain unsupported here.

`IFNULL(expr, null_result)` has exactly two arguments and lowers to the common
two-argument `coalesce`. Only a NULL first value selects the fallback; a
non-NULL first value leaves the fallback unevaluated. Both operands still
undergo the existing static name, arity and type checks, including skipped
operands. This adopts [GoogleSQL's IFNULL conditional semantics](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/conditional_expressions#ifnull)
within the common checker's supported type signatures; it does not add
GoogleSQL's wider implicit-coercion or type families. Use explicit supported
casts where required. Result type and nullability come from common `coalesce`
typing, including on empty input. The Frontend does not expand the first
operand or install its own conditional evaluator.

`REPLACE(value, search, replacement)` connects the adopted
[GoogleSQL STRING replacement function](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/string_functions#replace)
to the common three-argument `replace` expression. Operand order, parameter
references and clause scope are preserved. Replacement is literal,
case-sensitive, non-overlapping and left-to-right; an empty search leaves the
original value unchanged. Any SQL NULL operand produces SQL NULL. No Unicode
or line-ending normalization is implicit. The STRING overload is connected;
BYTES and explicit collation remain separate coverage gaps. The scalar function
is independent of the SELECT star REPLACE clause described above.

For `ARRAY_AGG` and `STRING_AGG` with DISTINCT and aggregate-local ORDER BY,
each ordering expression must denote the aggregate argument in the same input
scope. This follows the selected [GoogleSQL aggregate-call rule](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/aggregate-function-calls).
Qualification, grouping parentheses, quotation and equivalent static property
access preserve the resolved receiver. A current Pipe column and an older range
snapshot are different values after SET. The Frontend does not drop DISTINCT,
replace the requested order or add another argument to admit a mismatched key.
Non-DISTINCT collection calls retain their independently authored ordering.
Aggregate-local keys also admit comparisons, Boolean AND/OR/NOT and IS
predicates, BETWEEN/NOT BETWEEN, IS [NOT] DISTINCT FROM, and scalar
membership keys whose entire operand trees meet the existing total-expression
profile. They lower once into private input slots and use the common Boolean
ordering, NULL propagation, property typing and parameter contracts. They do
not resolve sibling SELECT aliases. Membership uses the same literal-list,
unannotated literal IN UNNEST and array-parameter contracts as ordinary
expressions; it does not turn computed or annotated lists into literal data.
Common checking retains operand comparability, parameter binding, the
three-valued IN rules and nonnullable IS DISTINCT FROM. Per-call filters still
guard aggregate
arguments; potentially failing arithmetic/casts/calls are not hoisted from
aggregate demand merely because they occur under a Boolean expression.
Broader computed aggregate order expressions remain an unconnected profile;
they are not made invalid by this rule. Machine Program aggregate contracts
retain their existing meaning.

In the implemented inline `OVER` profile, `PARTITION BY` accepts ordinary
row-dependent expressions, including comparisons, CASE and supported scalar
calls. The ordinary expression parser retains each key's source origin and
budget. Each key is evaluated over the SELECT input snapshot into a private
slot, then passed to common `analytic.partition_by`. Repeated expressions
within that immutable scope share the evaluated slot with OVER ordering and
other windows; the authored partition-key list retains its order and repeats.
Private keys are removed before Named Result publication.

Navigation `LAG`/`LEAD` offsets retain a nonnegative safe-integer literal or
whole numeric parameter through parentheses and unary `+`. The selected
[GoogleSQL integer lexical rule](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/docs/lexical.md#integer_literals)
admits a positive sign, and the pinned numeric unary-plus resolver retains its
operand rather than introducing an evaluated call. Thus `+2`, `+(+2)` and
`+(@offset)` reach the same common offset contracts as `2` and `@offset`.
Each wrapper still consumes bounded expression work and retains source origin.
This does not fold arithmetic, a row field, NULL or another scalar type into an
offset atom. Common checking still rejects invalid parameter values before
execution; the numeric domain, navigation nullability and window limits do
not change.

Literal/parameter-only partition expressions are rejected; numeric literals do
not denote SELECT positions here. This follows the selected [GoogleSQL window
specification](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/window-function-calls),
which permits partition expressions but excludes constants and sibling SELECT
aliases. Member access, operand and equality-key types remain common-checker
obligations. NULL computed keys share their existing common NULL partition;
CASE/IF/COALESCE retain ordinary demand semantics and expression failures do not
publish a partial Result. This connection retains ActQL's existing finite
number and recursive type contracts; it does not claim Google's complete type
profile, including its floating-point partition exclusion. Optional ordering,
default frames and nested window calls remain outside this implemented inline
profile. Named-window resolution is described separately below.

DISTINCT aggregate calls are not admitted to the implemented explicit-ROWS
analytic path. The selected GoogleSQL resolver forbids a DISTINCT window call
with window ORDER BY or an authored frame, including inherited clauses. The
Frontend rejects these combinations instead of dropping DISTINCT, discarding
the frame or executing a different window. Default/unordered DISTINCT analytic
calls remain a separate unimplemented connection; their refusal is a coverage
gap, not a claim that GoogleSQL prohibits every DISTINCT window. SQL, Pipe,
QUALIFY and query ORDER window calls share this lowering boundary. Ordinary
non-DISTINCT analytic and grouped DISTINCT calls retain their common contracts.
See the pinned [analytic resolver](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/googlesql/analyzer/analytic_function_resolver.cc)
and its independent ORDER/frame refusal cases.

In the implemented inline `OVER` profile, numeric `ROWS` boundaries
accept an integer literal or a whole named parameter, including bounded
transparent grouping and numeric unary plus, for example
`ROWS BETWEEN (+@before) PRECEDING AND ((@after)) FOLLOWING`. The shared
integer-operand parser retains the ordinary literal/Parameter role without
evaluating arithmetic, casts, calls or row references. Each wrapper uses the
existing expression depth/node budgets. Direction remains
syntax; the parameter is lowered to the common `preceding`/`following`
Parameter slot. Declarations and bound values use ordinary Program checking,
including safe-integer and interval-order validation; no default replaces a
missing or invalid binding. This connection retains the current common
contract's positive parameter distances. Literal `0 PRECEDING` and
`0 FOLLOWING` retain their authored direction in syntax and lower to the
existing common `current_row` boundary: the physical offset is zero. Authored
boundary categories are checked before this projection, so an illegal
`CURRENT ROW ... 0 PRECEDING` or `0 FOLLOWING ... CURRENT ROW` interval is not
made legal by collapsing its endpoints. The same rule applies to named-window
frames and the single-boundary `ROWS 0 PRECEDING` form. Bound parameter zero
remains a common-contract coverage gap and is rejected; it is not replaced by
an inferred default or special execution. Row-dependent and arithmetic boundary
expressions, RANGE and GROUPS are not implemented in this profile.

The selected GoogleSQL single-boundary `ROWS` form has an implicit
`CURRENT ROW` upper boundary. `ROWS 2 PRECEDING`, `ROWS @before PRECEDING`,
`ROWS CURRENT ROW` and `ROWS UNBOUNDED PRECEDING` lower to the same common
frame contract as their explicit `ROWS BETWEEN ... AND CURRENT ROW` forms.
The authored lower boundary and parameter remain unchanged. This is an
explicit physical-row frame, not an implicit RANGE frame or an added order
guarantee. Interval and bound-value validation remain in the common checker;
a start after the implicit upper boundary is rejected before Run admission.

Grouped `COUNTIF(DISTINCT predicate)` accepts the ordinary nullable Boolean
predicate and counts distinct TRUE observations: the result is one when any
qualifying observation is TRUE, otherwise zero, including empty/all-NULL input.
The syntax AST retains DISTINCT. The common COUNT_IF operation has no DISTINCT
modifier, so this call lowers to common COUNT with DISTINCT on
`IF(predicate, TRUE, NULL)`. The existing conditional owner preserves Boolean
type checking and evaluates the authored predicate once per demanded
observation; FALSE/NULL do not contribute a non-NULL count argument. No input
DISTINCT step, predicate duplication or new aggregate evaluator is introduced.

Per-call WHERE stays in the common aggregate filter and retains its demand
boundary. Ordinary COUNTIF, COUNT/SUM in the same group, input scope, parameters,
HAVING, ORDER and LIMIT/OFFSET remain independent. The output is a non-NULL
number under the current numeric profile. The pinned GoogleSQL
[`aggregation_distinct_countif_1` through `_4` and grouping examples](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/googlesql/compliance/testdata/aggregation_distinct_queries.test)
anchor the one/zero behavior. This connection covers grouped SQL SELECT and
Pipe AGGREGATE. DISTINCT analytic COUNTIF remains an unsupported profile;
do not infer default/unordered window support from the existing explicit ROWS
frame implementation or discard DISTINCT on an authored frame.

Grouped `MIN(DISTINCT expression)` and `MAX(DISTINCT expression)` retain the
authored modifier in query syntax and lower to ordinary common MIN/MAX calls.
Removing duplicate observations does not change these extrema in the admitted
value domains. The common operation forbids a `distinct: true` modifier on
MIN/MAX; the Frontend therefore omits that redundant modifier without adding a
deduplication step or evaluating the operand again. Other aggregates in the
same group still observe every input occurrence unless their own modifier
requests DISTINCT. Arguments, per-call filters, grouping, HAVING, parameters,
order and LIMIT/OFFSET retain their authored meaning. NULL observations are
excluded, and empty/all-NULL groups produce nullable typed NULL.

This selected behavior is anchored by the pinned GoogleSQL
[`aggregation_12` and `aggregation_14` compliance cases](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/googlesql/compliance/testdata/aggregation_queries.test).
It applies to SQL grouped SELECT and Pipe AGGREGATE, including scalar aggregate
expressions. It does not add new comparable domains, collation, NaN/infinity or
NUMERIC/BIGNUMERIC behavior. DISTINCT analytic MIN/MAX remains an explicit
unsupported profile: the existing explicit-frame implementation is not the
separate default/unordered DISTINCT analytic contract. This connection also
does not close the statistical DISTINCT gap.

The statistical aggregate entry points `VAR_POP`, `VAR_SAMP`, `STDDEV_POP`,
`STDDEV_SAMP`, `VARIANCE` (alias of `VAR_SAMP`) and `STDDEV` (alias of
`STDDEV_SAMP`) lower to the existing common aggregate functions. They work in
SQL SELECT, Pipe AGGREGATE and the existing explicit ROWS-frame OVER profile.
Arguments retain ordinary input scope and expression demand; there is no
Frontend variance evaluator. NULL observations are excluded. Population
variance/deviation returns zero for one non-NULL observation and typed NULL
for none; sample functions return typed NULL for fewer than two. Output is
nullable number, including on empty input. These cardinality rules and aliases
follow [GoogleSQL statistical aggregates](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/statistical_aggregate_functions).

This connection uses the common finite binary64 number contract and its pinned
canonical observation order and rounded arithmetic, defined in the language's
statistical aggregate section. It does not add NUMERIC/BIGNUMERIC coercion,
NaN/infinity results, default analytic frames or DISTINCT support. The current
common checker rejects statistical DISTINCT; GoogleSQL's broader signatures
remain coverage gaps. Common expression failures propagate without a partial
successful Result. No authored WHERE, grouping, HAVING, order, parameter or
LIMIT/OFFSET is removed to admit a statistical call.

## Scope and lowering

Pipe `PIVOT(aggregate(expression) [AS prefix] FOR axis IN ('value' [AS name], ...))
[AS range]` connects the selected
[GoogleSQL PIVOT profile](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/docs/pipe-syntax.md#pivot_pipe_operator)
to the ordinary common `pivot` operation. This initial surface supports one
SUM, AVG, COUNT, MIN or MAX of a scalar expression over current or range-qualified
input columns, parameters and existing scalar operations, or COUNT(*), a
String axis and a nonempty list of static String bucket values. Parentheses
around a bucket String literal are transparent, including nested parentheses.
Grouping does not extend this selected subset to parameter, numeric, NULL or
computed bucket expressions. The current
columns not consumed by the aggregate argument or axis become implicit group
keys in their current order. All input slots referenced by the argument, including
receivers of property access, are consumed. A constant or parameter-only argument
consumes no input columns. Existing evaluated slots are reused, including
SET/RENAME slots. The common checker owns key, aggregate, numeric, type and
NULL evidence; no fill, cast, default ceiling or uniqueness is invented.

PIVOT exposes the implicit group columns followed by pivot columns in authored
IN order, even though the common operation stores generated columns in canonical
order. An explicit bucket alias changes only the output name, not the compared
String value. An aggregate prefix produces `prefix_bucket`. Name collisions
are checked under existing case-insensitive column lookup. The result is a
fresh ordinary Relation scope: previous ranges, the consumed aggregate column
and axis are unavailable unless also produced as new output columns. The
optional range binds only this result. The ordinary final projection retains
the declared public column order and removes private fields.

SUM/AVG/MIN/MAX ignore NULL input values and return typed NULL for an empty
non-NULL bucket; COUNT(column) returns its non-NULL count, including zero for
an empty bucket. Undeclared or NULL axis values create no declared bucket but
retain their implicit index group. Empty input with no implicit keys has one
global group; empty keyed input has no groups. These are existing common pivot
rules, not frontend implementations of aggregation.

COUNT(*) references no input column. All current columns other than the axis
remain implicit group keys; NULLs in those columns do not exclude the row from
counting. Lowering derives one private nonnullable row witness and counts that
witness with the existing pivot operation. It is neither an index column nor a
public field. COUNT(column) retains its existing NULL-excluding argument and
consumed-column behavior. Empty global input returns zero for each declared
COUNT bucket; keyed empty input has no groups. No other aggregate accepts star.

Scalar arguments use the ordinary expression lowerer and one private derive before
pivoting. That private value is neither an implicit group key nor a public column.
Current and immutable-range references retain their existing resolved slots: a
reference to an old value does not consume a different current replacement slot.
Nested aggregate calls are refused; property typing and NULL propagation remain
owned by the common checker and expression evaluator.

The same selected PIVOT clause is supported as a FROM postfix, on a named
Relation/CTE or a parenthesized query, before surrounding JOIN, WHERE and SELECT.
A parenthesized PIVOT input may omit its input alias. References inside PIVOT
resolve against that input and its optional alias. The postfix result exposes
only its output columns and optional result alias; input ranges and consumed
columns do not escape. This follows the fixed GoogleSQL analyzer's fresh PIVOT
NameList. Quoted names remain names, including `PIVOT` and `ORDER` aliases.

A postfix becomes an ordinary projected producer through the existing query
binding path, so both left and right JOIN inputs use their transformed Relation.
No SQL rewriting, new acquisition/storage owner or physical-placement selector
is introduced. The existing Program Stage/result dependency carries the value;
WHERE on the pivot output remains downstream. All predicates and explicit JOIN
bounds retain their original expressions and values. Other postfix operators,
correlated outer-row inputs and the broader multiple-aggregate surface remain
separate coverage, rather than being approximated by this connection.

Multiple aggregates, aggregate modifiers,
non-String axes and NULL bucket constants remain unimplemented
surface coverage. The common requirement that bucket values also be admitted
output field names, with unique values and no collision with physical index
fields, is a recorded restriction of the existing contract. This does not
claim that such forms are invalid GoogleSQL or completed standards alignment;
unsupported forms are rejected rather than coerced, renamed as data or dropped.

SQL `QUALIFY boolean_expression` filters the evaluated inline-window outputs
after WHERE, grouping/HAVING and analytic computation, before final DISTINCT,
ORDER and LIMIT/OFFSET. At least one window function must occur in SELECT or
QUALIFY. Only TRUE retains a row; FALSE and SQL NULL discard it. Calls in
QUALIFY use the same supported inline OVER signatures and common analytic
contract as SELECT; their private output slots are omitted from Result fields.
Window calls need not appear in SELECT. Group aggregates inside the condition
use the ordinary grouped input and aggregate checking rather than a separate
query evaluator. Broader OVER signatures remain existing profile gaps. This follows the selected
[GoogleSQL QUALIFY clause](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#qualify_clause).

SQL `WINDOW name AS specification, ...` declares query-local window
specifications. `OVER name` and `OVER (name ...clauses...)` resolve against
that SELECT's declarations and lower to the same ordinary analytic operation
as an inline specification. Declarations can inherit only earlier declarations;
name lookup is case-insensitive, including backtick names. Duplicates, unknown
references, forward references and cycles are refused without falling back to
a Relation producer. CTEs, derived tables and set operands each have
their own window scope. The specifications do not create execution slots,
acquire data, or add a storage boundary.

Inheriting a window forbids a new PARTITION BY; an inherited ORDER BY cannot
be replaced or repeated. A specification that inherits a frame cannot add
ORDER BY or another frame. Plain aliases retain the inherited frame. Names
inside partition/order/frame expressions continue to use SELECT's input
snapshot, never its output aliases. Missing ordering, frame and signature
support remains subject to the current common analytic contract; naming a
window does not add RANGE or default aggregate frames. Explicit ROWS boundary
support follows the frame rules above.
Unused declarations are checked for declaration conflicts but do not execute
their expressions. These rules follow
[GoogleSQL named windows](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/window-function-calls#rules_for_using_a_named_window_in_the_window_specification)
and the selected resolver's declaration flattening. Parsed operation snapshots
copy mutable window/aggregate lists and cannot mutate the admitted syntax owner.

Pipe `EXTEND expression AS name, ... [WINDOW ...]` also accepts the supported
window calls, directly or inside ordinary scalar expressions. It adds outputs
after all current visible columns, in authored order; nullable input columns
retain their contracts, including on empty input. All sibling expressions and
their OVER specifications see the same input snapshot, not aliases introduced
by this EXTEND. Existing immutable range bindings remain distinct from columns
changed by SET. Output-name collisions are refused.

Each EXTEND's optional WINDOW declarations are local to that operator and use
the same inheritance and conflict checks described above. They do not become
visible in a later EXTEND. Window outputs are computed by the ordinary analytic
operation; direct outputs reuse their evaluated slots, and scalar operands use
private window slots. Final projection removes private columns. No additional
acquisition, sorting or Result boundary is implied: an explicit ORDER BY is
required when the public row order matters. Ordinary GROUP aggregation is not
introduced by EXTEND. Supported analytic signatures and frames still follow the
common contract. This connects the selected
[GoogleSQL Pipe EXTEND](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/pipe-syntax#extend)
without a separate window executor or a new alias scope.

Pipe SELECT accepts its own optional WINDOW clause after the projection list.
Direct window outputs, scalar window operands and star replacements resolve
against those declarations and the SELECT's input snapshot. Names follow the
same declaration inheritance/conflict rules as SQL WINDOW, including quoted
case-insensitive lookup, but cannot leak into the next Pipe operator. A later
SELECT or EXTEND can declare the same name for a different window. Projection
and DISTINCT retain their existing scope, evaluation and hidden-slot rules.
Unused declarations do not introduce a GROUP or evaluate aggregate keys;
used ordinary aggregates cannot introduce implicit grouping in Pipe SELECT.
This connects the selected
[GoogleSQL Pipe SELECT](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/pipe-syntax#select)
to the same common analytic signatures, frames and output contracts as inline
window specifications.

Pipe SET accepts supported inline window calls as direct assignment values or
inside scalar expressions. They use the same common analytic operation as
SELECT/EXTEND. All sibling assignment expressions and window specifications see
the same pre-SET snapshot; replacing an earlier target does not change a later
assignment's input. Each target must still exist exactly once and cannot be
assigned twice. SET retains visible column order while the replacement value's
checked type and nullability determine that column's new contract. Existing
range variables retain original values unless their names match a SET target.
Such ranges are removed after all sibling assignments have been resolved.

Window calls are evaluated before the existing assignment derivation. Their
private slots are visible only to that SET and are removed by normal final
projection. Authored names cannot be captured; subsequent AS sees only current
public columns. SET does not inherit another operator's WINDOW declarations or
introduce implicit GROUP. Analytic signatures, frames, expression demand,
parameters, failure and capacity remain common-owner contracts. Public ordering
requires an explicit ORDER BY after window evaluation; no previous order is
invented. This connects the selected
[GoogleSQL Pipe SET](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/pipe-syntax#set)
without a new executor, wire format or range-binding rule.

Pipe `UNPIVOT [INCLUDE NULLS | EXCLUDE NULLS] (value_column FOR name_column
IN (column [[AS] row_value_alias], ...)) [AS alias]` connects the selected
[GoogleSQL UNPIVOT](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/docs/query-syntax.md#unpivot_operator)
to the common `unpivot` operation. The input columns are unqualified current
column names, not expressions or references through a former range. Unmentioned
columns remain in their original order, followed by the value column and then
the name column. Generated labels use the resolved input column names, including
current RENAME outputs; private slot names are never labels or public fields.
The operator establishes a fresh output scope. An optional alias binds that
scope; removed columns and prior ranges do not remain accessible through it.

Default and explicit EXCLUDE NULLS omit rows whose unpivoted value is SQL NULL;
INCLUDE NULLS retains them. This uses the common expansion and an ordinary
`IS NOT NULL` filter without changing common `unpivot` semantics. Duplicate
input rows and repeated selected columns retain multiplicity. Only an authored
ORDER BY establishes public order; no sort, Result or persistence boundary is
added. The common checker owns exact value contracts, expansion/key evidence,
capacity and incompatible input rejection. In particular, its current exact
type/nullability requirement is a recorded common-profile gap for inputs whose
selected columns differ only in nullability; the Frontend does not cast or infer
types from rows to bypass it. Empty input retains the declared output contracts.

Multi-column `UNPIVOT ((value_column, ...) FOR name_column IN
((column, ...) [[AS] row_value_alias], ...))` rotates corresponding positions.
Each input set MUST have the same arity as the output value columns. Component
positions may have different types from one another, while corresponding
positions across input sets retain the common exact type/nullability contract.
The Frontend constructs an ordinary non-NULL closed object for each input set,
expands those objects through common `unpivot`, and projects the components
through ordinary property expressions. It does not add an evaluator, a cast,
or a new wire/storage representation. Default and explicit EXCLUDE NULLS omit
a tuple only when **all** emitted components are SQL NULL; partially NULL
tuples survive. INCLUDE NULLS retains all tuples. Omitted row-value aliases
join the current resolved input names with `_`; compiler slot names never
become labels. The output scope consists of the unselected input columns in
their original order, followed by the value columns in declared positional
order and the name column. Existing fresh-scope and name-collision rules apply
to every component. Integer row-value aliases remain outside the exact common
value profile, as for single-value UNPIVOT. Differing corresponding nullability
remains the recorded common-profile gap; it is not normalized by this lowering.

String row-value aliases are decoded literal values, not identifiers. They may
be empty, repeated, contain escapes, or differ only by Unicode normalization.
They are preserved through the existing value contract. Omitted aliases use the
resolved current column name. Each selected occurrence receives its own private
projection slot before common UNPIVOT, then an ordinary conditional projection
maps the emitted private name to its authored String label. Repeating the same
input column with different labels therefore creates separate output rows;
neither values nor labels are deduplicated. The copies reuse evaluated input
slots and do not reevaluate input expressions. Private names remain unavailable
as public labels or Result fields.

The same single-value and multi-column operations are accepted as a FROM postfix on a named table,
CTE or parenthesized Relation: `FROM input [AS original] UNPIVOT (...) [AS shaped]`.
It transforms only that input before surrounding JOIN, WHERE or SELECT. Its output
alias replaces the input range; selected columns and the old range do not survive.
The existing lowerer rejects value-table inputs, consistent with the selected
GoogleSQL rule. Explicit projections of UNNEST values form ordinary Relations.
Mixed CTE/ordinary JOIN ports use the existing producer-binding path and retain
the authored JOIN kind, predicate and maximum output rows. No extra acquisition,
new execution owner or inferred schema is introduced.

This connection does not yet cover multiple value columns or INT64 row-value
aliases. Integer literal syntax is retained and explicitly refused by lowering
as an implementation limit: the current common numeric value contract is
binary64, not exact INT64. The Frontend does not round an integer or reinterpret
it as a String. Mixed alias types, or omitted aliases beside integer aliases,
are syntax errors under the selected GoogleSQL rules. These forms remain unimplemented coverage,
not permanent language prohibitions. They are not reinterpreted as this form.
Value/name columns must differ from each other and from selected input names,
under the existing identifier rules. Kept-name collisions remain ambiguous;
a public Result still requires distinct field names.

Pipe WHERE accepts supported window calls inside its Boolean predicate. Each
call observes the current input rows, including preceding filtering, grouping
and projection, and uses the existing common analytic operation. Only rows
whose predicate is TRUE survive; NULL predicates do not. Sequential WHERE
operators evaluate their windows over the rows retained by preceding operators.
The output is the unchanged current row, with the same visible columns and
immutable range bindings. A generated window slot is private to that predicate:
it is not available to later operators and is removed before Result publication.
Authored names cannot be captured by generated slot names.

Pipe WHERE does not declare WINDOW names or inherit declarations from a previous
SELECT or EXTEND. Ordinary aggregates cannot introduce an implicit GROUP here;
use the preceding AGGREGATE output. Existing analytic signature/frame limits,
parameter typing, capacity and failure rules remain common-owner decisions.
An explicit ORDER BY remains necessary when public row order matters. This
connects [GoogleSQL Pipe WHERE](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/pipe-syntax#where)
to the common analytic and filter operations without changing SQL WHERE's
restriction on window calls, rewriting Source predicates or adding an executor.

QUALIFY resolves SELECT aliases to their evaluated slots before same-name
inputs. Qualified input references retain their input meaning. A scalar alias
needed by the condition is evaluated once against SELECT's input snapshot and
reused by final projection; unrelated scalar projections are evaluated after
the condition. No alias is made visible inside its own or a sibling SELECT
expression, or inside a SELECT-owned OVER specification. Ordinary Boolean and aggregate
typing, failure, capacity and parameter rules remain common-owner decisions.

`WHERE` and siblings in one SELECT list see the input snapshot, not aliases
introduced by that list. In `GROUP BY`, `HAVING`, `QUALIFY` and the query's final
`ORDER BY`, a visible SELECT alias takes precedence over an input column of
the same name. Duplicate aliases, qualified references and aggregate
visibility still undergo their own ambiguity and validity checks. Names in
a SELECT-owned analytic `OVER` clause resolve against the input snapshot.
Inline windows in the query ORDER BY instead resolve SELECT aliases before
same-name inputs, including function arguments and OVER partition/order keys;
qualified input columns retain their range meaning. An alias containing a
SELECT window cannot feed another window. New window calls after SELECT
DISTINCT and named-window references in ORDER BY are refused. The inline
ORDER windows execute with the other windows before QUALIFY; their private
outputs and demanded scalar aliases are removed by final projection. Pipe
ORDER and post-set ORDER run windows over the current projected/combined rows,
without recovering a removed input range. Existing common signatures, frames,
NULL and order evidence still apply; no default frame or ordering guarantee is
invented by this connection. These rules follow the adopted GoogleSQL query and window
scopes; they do not confer general GoogleSQL compatibility.

SQL `GROUP BY ALL` infers keys from SELECT expressions in the original FROM
scope. It excludes expressions containing aggregates or windows, constants,
parameters, and expressions whose input paths are covered by other inferred
simple-path keys. The shortest resolved column/property path wins even when
selected later; qualified and unqualified paths use their input-slot meanings.
Computed keys do not supply prefixes for other computed keys. Inferred keys
retain SELECT order and do not undergo GROUP alias or positional lookup. Stars
use the same input snapshot, EXCEPT and REPLACE rules as ordinary projection.
An empty key set uses the existing global `group` operation, including one
group on empty input. The common checker owns key admissibility; unsupported
functions and types do not gain permission through inference. These rules follow
[GoogleSQL GROUP BY ALL](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#group_by_all).
An aggregate alias that collides with a retained input key has a separate
physical result slot. SELECT siblings still see the input key; HAVING and final
ORDER see the evaluated alias. Private keys and aggregate slots are removed by
ordinary projection before Result publication.

In a grouped SELECT, a grouping expression may occur inside a larger scalar
expression. Its input references must resolve to the same pre-group value slots
and property members as the grouping key. The evaluated key is reused; retaining
`payload.score + 1` does not restore `payload` or permit `payload.score` alone.
SELECT siblings still use the input scope, including when an output alias shadows
an input receiver. Nullable keys keep their common value contract and NULLs.

Pipe range variables bind immutable input value slots. `SET` replaces the
current unqualified columns; every assignment sees the same pre-SET row.
`DROP` removes current names, and `RENAME` changes current names. These three
operations retain a surviving range variable's original column names and
values. Under the selected GoogleSQL Pipe rules, SET and DROP remove a range
variable whose name matches an authored target under the existing identifier
comparison. SET removes it only after every sibling expression has resolved
against the pre-SET snapshot. A subsequent property reference with that name
therefore uses the new current value, not the removed range. RENAME requires
its target to be a current column unambiguously resolved in scope: a same-named
range hides that column and causes rejection. Other range names remain bound.
A removed or renamed current column does not become available through
an unqualified reference simply because an older range variable retains it.

Pipe `AS name` replaces all preceding range variables with that name, bound
to the current visible columns and values. Reusing the same name is allowed
and establishes a new binding. References to a displaced initial or
intermediate range variable are rejected, including references inside
expressions, WHERE and ORDER BY. AS does not restore dropped names or expose
compiler helper slots. These are the adopted
[GoogleSQL Pipe scope rules](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/pipe-syntax).

A bare surviving range over an ordinary Relation denotes a non-NULL closed
object of that range's declared columns, read from its evaluated value slots.
NULL field values do not make the row object NULL. Within the input scope, a
range name shadows a same-named column, including an object column. Value-table
ranges still denote their original whole-value slot: their kind comes from the
admitted scope, not from a column name or sampled value. An ORDER output alias
belongs to a nearer overriding scope and takes precedence over an input name.
Column-selector positions such as USING and ITEM KEY remain distinct from
expression reference lookup. The expression uses the common object form;
AS itself neither derives an object nor changes an acquisition boundary.

JOIN row expressions use this same scope and common object construction. A
row receiver denotes the complete declared fields of its operand, including
the original qualified USING keys. Null extension changes those fields'
nullability; it does not make the constructed ordinary row object NULL.
Whole-row references inside predicates retain their authored evaluation point,
and ORDER aliases override input row receivers before SELECT-expression reuse.
Row lookup does not manufacture key, uniqueness or order evidence: FULL JOIN
continues to require its existing checked identity premises.
SET, DROP and RENAME retain a surviving range's original field names/slots;
AS rebinds only the current visible columns. A removed range or unavailable
post-projection slot cannot be recovered through whole-row construction.
A single value-table range still denotes its original scalar or object value,
not a one-field wrapper. Common typing owns property validity, field presence
and nullability. This follows the selected
[GoogleSQL range-variable rules](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#range_variables).

Ordinary SELECT may order by a visible non-output input expression. After
DISTINCT, ordering must be resolvable from the selected expressions or their
aliases. Helper slots do not participate in DISTINCT equality or Named Result
publication. A selected expression is evaluated once; resolving an alias must
not duplicate its evaluation, failures or resource accounting. Unqualified
joined fields must be unique. `USING` exposes one coalesced key for FULL JOIN
and does not invent an arbitrary representative row.

For the supported shared INNER/LEFT/RIGHT JOIN scope, USING columns lead an
unqualified star in the authored USING order, followed by remaining left then
right columns. INNER/LEFT use the left key; RIGHT uses the preserved right
key. Qualified input ranges keep their own original column names/order and
values, including nullable unmatched-side keys. Duplicate USING names are
refused under ordinary case-insensitive field lookup. Star/EXCEPT/REPLACE and
later projections still produce unique Named Result fields; duplicate public
names are refused rather than silently renamed or discarded. All expansion
uses existing slot/type/NULL/identity checks, not schema or evidence inference.

`RIGHT [OUTER] JOIN` uses the existing common LEFT JOIN after exchanging
input ports and equality-key sides. Projection keeps the original SQL range
names and column meanings: unmatched original-left columns become nullable,
while the original right side is preserved. Explicit MAX_OUTPUT_ROWS and
pre-/post-join predicates retain their original logical boundary. RIGHT USING
exposes the preserved right key unqualified; qualified left/right keys remain
distinct. Its visible USING columns lead the row in authored USING order,
followed by remaining left then right columns. Normal checked projection,
nullability, ordering and output-name rules remain in force, including explicit
refusal when a public Result cannot represent duplicate field names. No second
join implementation, source re-acquisition or evidence fabrication is added.
The selected [GoogleSQL RIGHT JOIN](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#right_outer_join)
is a logical outer join, not a new placement or authorization instruction.

Supported SQL and Pipe set operators also accept `BY NAME ON (column_list)`.
This is strict name matching, equivalent to GoogleSQL `STRICT CORRESPONDING BY`:
each input must have exactly the listed column names, with no duplicate input
or list names under case-insensitive column lookup. The list specifies output
column order and authored spelling, including backtick-quoted names. Both
operands are projected to that order using evaluated fields before the existing
append/intersect/except operation; expressions are not reevaluated. SQL chains
require the same ordered list and retain the first modifier's spelling. Each
successive Pipe set operator can declare its own list against the current
Relation. ORDER BY and downstream Pipe operators see only the combined output.
Normal type compatibility, NULL, duplicate and equality contracts remain with
the common checker and operations. WITH-bound sets use the same rules without
additional acquisition. FULL/LEFT name propagation remains a separate unimplemented surface; omitting those modes does not
implicitly drop unlisted columns or add NULL-filled columns.
The selected [GoogleSQL set modifier](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#by_name_or_corresponding)
defines that equivalence. The pinned resolver and pipe-set fixtures corroborate
strict matching and ON-list spelling; parser acceptance does not establish
backend execution coverage.

`INNER UNION ALL BY NAME`, `INNER UNION DISTINCT BY NAME`,
`INNER INTERSECT DISTINCT BY NAME` and `INNER EXCEPT DISTINCT BY NAME`
retain only common column names. Without ON, output order and spelling follow
those common names in the first input. With `BY NAME ON (column_list)`, only
the listed common names remain, in authored list order/spelling. At least one
column must remain. Duplicate names in any input or list, and listed names
missing from any input, are refused under the same case-insensitive lookup.
The INNER prefix requires BY NAME; it never means positional matching.

A SQL chain resolves the common output names across all its operands before
checking set compatibility. A column absent from a later operand is excluded
from every set input, even if its types differ in earlier operands. Sequential
Pipe set operators instead consume their current intermediate Relation; a
column retained by the first Pipe set must meet that intermediate type contract.
Projection drops unmatched names using evaluated input slots, and the existing
checker and set operations still determine types, NULL and duplicate behavior.
ORDER BY and later operators cannot recover dropped names or input ranges.
No source acquisition, execution owner or placement boundary is introduced.
FULL/LEFT name propagation remains unimplemented.
This subset follows the same pinned GoogleSQL reference above; selected local
checks and packed acceptance establish only their recorded execution scope.

`CORRESPONDING` uses the same common-name alignment as `INNER ... BY NAME`;
`INNER ... CORRESPONDING` has the same meaning. `STRICT CORRESPONDING`
uses the exact-name-set rule of unprefixed `BY NAME`. The optional
`CORRESPONDING BY (column_list)` corresponds to `BY NAME ON (column_list)`:
default CORRESPONDING selects listed common names, while STRICT requires the
list to match each input's complete field set. List order and authored spelling,
case-insensitive lookup, duplicate-name rejection and evaluated-slot reuse are
unchanged. SQL chains and sequential Pipe sets keep their existing scope and
common typing rules. These are selected GoogleSQL spellings of the existing
set semantics, not a new execution or acquisition mechanism. FULL/LEFT variants
remain unsupported pending common nullable-padding evidence.

Set operands containing ordinary JOINs use the same shared-input assembly as
WITH bodies. This applies to standalone SQL/Pipe, nested set operands and
CTE bodies. JOIN predicates, key mappings and declared output ceilings remain
with the existing JOIN lowerer; final ORDER BY/LIMIT sees only the combined
output. Input binding does not add another source read or materialization.

WITH may precede either a SELECT query or a FROM-starting Pipe query. A CTE
body uses the common producer composition described below, including Graph
primaries. A FROM/JOIN table subquery or set operand must return Relation.
Existing Relation composition admits SELECT or FROM-starting Pipe, set expressions,
optional ORDER BY/LIMIT, and a pure Pipe tail. Parentheses retain the inner
query's scope and ORDER BY/LIMIT placement. A Pipe operator following a set
consumes the combined output, not its left operand; input range variables and
non-output columns of the operands are not visible there. Set operands may
refer to previously bound CTE Results without re-expanding their producer.
They use the same expression and column-scope rules as the corresponding query
head. A nonrecursive WITH binds each declaration after its body; later bodies
and the containing query may reference it. Nested WITH declarations can shadow
outer bindings but are not visible outside that query expression. When a
nested producer is retained as a Stage Result, its private producer identity
does not replace the authored range qualifier or expose its name to an outer
scope. CTE names are query-local aliases: reference and duplicate-name lookup
are ASCII case-insensitive, including backtick-quoted names. This is distinct
from published Source View path resolution. This is lexical producer binding,
not SQL rewriting or repeated execution. Each body ends at its
own closing parenthesis; a statement terminator is allowed only after the
complete query. INFER and RESULT declarations are excluded from CTE bodies.
A table subquery's alias is optional. On an ordinary row, an explicit alias
replaces input ranges with one range over the current output. A single value
table retains its value kind and replaces its receiver name: a scalar remains
a scalar and a nullable object remains the original nullable object, not a
new STRUCT of projected fields. Apply the existing AS rules before retaining
this scope. OFFSET or other added columns make an ordinary row with qualified
columns; scalar receiver star remains invalid. Without an alias, surviving query ranges
and value-table receivers are preserved using the existing private scope binding.
A completed SELECT or set exposes only its current projected columns, so omission
does not revive displaced aliases, hidden slots or removed inputs. Transparent
query parentheses preserve that same scope; set operands still close their input
ranges. Generated producer identifiers do not become authored range aliases.
Subquery ordering is not an outer SQL order promise: keep explicit ORDER BY and
LIMIT placement, and compare an unordered outer Relation as a multiset.

Recursive declarations,
forward references and references to a displaced range variable remain
invalid. Parsing shares the existing syntax-node, CTE-count and work budgets.

Nonrecursive CTEs and noncorrelated FROM subqueries use checked producer
references, so reusing a source does not imply another physical read.
Standalone query assembly can retain a producer as a Stage Result. A CTE
inside a WITH body may instead reference an existing pipeline step;
the binding alone does not require another Stage, acquisition or saved Result.
JOIN, grouping, sets, analytic and Pipe operations lower to existing Program
operations and AoA meaning. No connector receives the original SQL as a raw
query. Finite bounds, stable-order evidence, identity requirements, captured
source grants and current authorization remain ordinary admission obligations.
Unsupported shapes must be rejected instead of approximated by a second
checker or evaluator.

Pipe grouping items accept an optional output alias, with or without AS,
including backtick-quoted names. Each grouping expression and aggregate argument
resolves against the pre-group input scope. A grouping alias does not rebind a
sibling grouping expression. The existing group operation retains its physical
keys; the subsequent ordinary projection names the grouped output. Output columns
are grouping items in authored order followed by aggregates. Duplicate output
names are rejected under the selected case-insensitive name rules. Repeated key
references with distinct aliases retain the repeated `by` entries and project the
same grouped value twice; they do not strengthen uniqueness or duplicate rows.
After AGGREGATE, only those output columns are visible, and the old input range
is closed. These aliases belong to Pipe; SQL GROUP BY does not acquire the Pipe
output-alias grammar.

Pipe aggregate outputs may contain scalar expressions around aggregate calls,
including multiple calls in one expression. Each named output must contain an
aggregate call; analytic calls are not admitted in this expression list. Calls
resolve against the pre-group input and lower to the existing group operation.
Identical calls may share an evaluated slot only when their input bindings and
arguments agree. The enclosing scalar expression uses ordinary derive after
grouping and before output aliases are installed. It can read retained grouped
inputs and proven evaluated grouping subexpressions, including nullable property
paths, but cannot read ungrouped inputs or sibling output aliases. Reusing a
key requires the same resolved input meaning, not just matching text. Private
aggregate and scalar fields are removed by the output projection. Output order
remains grouping items followed by authored aggregate expressions, and ordinary
WHERE/ORDER/LIMIT operate on that output scope. These rules do not introduce an
aggregate evaluator, new numeric law or row-based type inference.

Pipe AGGREGATE accepts the adopted shorthand ordering. `GROUP AND ORDER BY`
sorts every grouping output, left to right, using ASC NULLS FIRST by default.
A grouping item's ASC/DESC and NULLS FIRST/LAST suffix overrides its default;
without AND ORDER, only suffixed grouping items participate. Ordering suffixes
on aggregate outputs follow all ordered grouping outputs, regardless of their
source-list placement. Aggregate suffixes require ASC or DESC; grouping suffixes
may specify NULLS FIRST/LAST alone, as in the pinned GoogleSQL parser profile.
The Frontend emits an ordinary Order operation on evaluated output positions:
no grouping expression is recomputed, old range revived or hidden value exposed.
No suffix and no AND ORDER means no implicit ordering. Empty global grouping has
no grouping output to sort; an explicit aggregate suffix still orders its output.
These forms do not extend SQL GROUP BY's grammar. See the pinned reference
[shorthand ordering](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/docs/pipe-syntax.md#shorthand_order_pipe_syntax).

Pipe `|> DISTINCT` compares the complete current visible row using the common
keyed `distinct: [visible slots]` operation. It preserves column order, types, NULL
equality and surviving range bindings without reevaluating expressions. Private
slots and values displaced by SET or removed by DROP are projected away before distinct;
range columns survive only when their evaluated slots remain visible. Thus a
current `t.y` may remain usable while a removed `t.x` does not. RENAME preserves
the evaluated value slot. Closed value-table receivers are explicitly unsupported rather than expanded
into fields with different equality.
Unlike `SELECT DISTINCT *`, this operator does not reset every table alias.
Empty input remains empty; no ordering, representative-row choice or new
execution owner is invented. Existing common type and publication checks still
apply. The selected rules follow the pinned GoogleSQL
[DISTINCT pipe operator](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/docs/pipe-syntax.md#distinct_pipe_operator)
and its resolver's mapping of surviving range columns. This does not establish
support for all GoogleSQL value-table types or their grouping rules. Explicit
keys use the existing common KeyComparable domains; broader object/array
groupability remains a separate conformance dependency. Complete-row Program
distinct is not substituted to admit non-groupable GoogleSQL JSON values.

Pipe `AGGREGATE GROUP BY` may omit the aggregate expression list. It lowers
to the ordinary group operation with an empty aggregate map: each distinct
group contributes its grouping columns, in authored key order, with their
checked types and NULL grouping semantics. Subsequent operators see that new
output scope, not the previous input range. A nonempty key list on empty input
produces no groups; `GROUP BY ()` denotes one global group and produces one
empty object even on empty input. It can feed a subsequent explicit EXTEND;
publication of a zero-column Result remains unsupported by the common Result
contract. An AGGREGATE with neither expressions nor a GROUP BY clause remains
a syntax error. This connects the selected GoogleSQL
[grouping aggregation](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/pipe-syntax#aggregate)
without synthesizing COUNT, DISTINCT, ordering or an alternate execution path.

A Pipe JOIN consumes the completed left Relation, including its projected or
aggregated columns, predicates, ordering and LIMIT. A preceding Pipe AS names
that current row; ranges and columns removed by projection are not restored.
The parser connects such a prefix through the existing producer-binding model,
without evaluating SELECT expressions again. A single WHERE between JOINs stays
on the joined left input before the next JOIN. Explicit MAX_OUTPUT_ROWS remains
the common JOIN argument. See the selected
[GoogleSQL Pipe JOIN rules](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/pipe-syntax).

A private Pipe continuation preserves the current visible columns and each
surviving range variable's immutable value slots across the JOIN input boundary.
SET/DROP/RENAME/EXTEND do not rebind those ranges to changed values, and a JOIN
may retain several earlier input ranges. The JOIN remaps the carried slots once;
ordinary projection and Result export expose only the declared visible columns.
Authored CTEs and derived tables remain projected producers and do not export
private range bindings. Pipe AS and SELECT retain their existing scope rules.
INFER, retained RESULT and Graph carrier operations keep their own placement
contracts and are not moved into a CTE to make a JOIN parse.

## File listing Sources

`LIST_FILES` is a table source in SQL and Pipe, including a JOIN input. Its
first argument is a statically resolved `connection.listing` Source name, or a
bare connection with exactly one published listing Source; zero or multiple
listing Sources are refused rather than guessed. It is not an expression,
URI or WITH producer. The normal Source publication and Catalog determine
its authority and file-list contract; a matching column shape alone is not a
file-list capability.

```sql
SELECT resource, version, path
FROM LIST_FILES(files, paths => ['reports/a.csv', 'reports/b.csv']);

FROM LIST_FILES(files, glob => r'reports/*.csv')
|> SELECT resource, version, path;
```

The selector is exclusive: `paths`, `glob`, or no selector. Unknown arguments,
extra arguments and computed Source names are rejected. The initial lowering
accepts literal arrays of strings for paths, string literals for glob, or a
declared nonnullable parameter of the corresponding type. Computed selector
expressions are not initially supported. `paths => ARRAY<STRING>[]` is an
explicit empty selection, not selector-free listing. Selector-free listing
requires the installed profile to permit it. A Host-fixed selector is not
silently replaced by the query's selector.

Lowering preserves the published Source declaration and its other Request
fields. It supplies both Request alternatives, with explicit NULL for the
inactive one, and validates them through the ordinary Request owner. The
profile determines which selector is permitted. A nullable selector parameter
does not prove that a selector will be present; it is rejected rather than
allowing NULL to widen the selection. These rules also apply to structured
Program Requests and do not introduce a second file-specific binding owner.

Decoded paths and glob data retain case, Unicode normalization distinctions and
literal object-key spelling. SQL string chunks retain their raw/nonraw origin:
nonraw glob chunks containing a source backslash are rejected before decoding
can hide an ambiguous escape. This source-origin restriction does not apply to
already decoded parameter or structured Program data. Glob matching follows
the common file-list contract, not the provider's native glob language.

A file-list profile supplies finite physical-limit candidates, not a proof of
actual item count, snapshot isolation or successful acquisition. The installed
acquisition must enforce its resolved limits and complete the declared selection
protocol before exposing the Relation. LIMIT, a page boundary or a continuation
token cannot turn an unfinished listing into a complete one. A limited partial
listing can be used only where the selected contract admits partial results;
it does not carry complete-listing evidence.

The listing metadata includes `resource`, `version`, `path`, `media_type` and
`size`, with types, presence and available version guarantees declared
by the published Source contract. Listing does not download bytes.
`connection.contents` is the corresponding keyed Source: JOIN binds both
`resource` and `version` to fetch exactly that Resource version, returning the
columns `resource`, `version`, `content` (a `content_ref`) and `media_type`.
Joining on resource alone does not establish
version-pinned acquisition. Failed acquisition or version mismatch is an
acquisition failure, not an absent INNER JOIN row.

## Source-free SELECT

A SELECT may omit FROM, following the adopted
[GoogleSQL query syntax](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax).
Its expressions evaluate over one logical row. A false WHERE produces an
empty Relation with the declared output contracts. Parameters remain ordinary
typed Program parameters; SELECT siblings and WHERE cannot refer to aliases
introduced by that SELECT. A star without visible input columns is invalid.

The frontend lowers this case to existing Values and ordinary expressions.
Values requires a nonempty schema, so a private Boolean witness represents the
single row. It is excluded from the query's name scope and selected Result
columns. It is neither an external Source nor a captured input Artifact.
Installed aliases are not acquired simply because they appear in the Host's
published environment. The normal checker and Host capacity owners still
validate every constructed step and output.

Source-free SELECT terms may feed a supported set query, nonrecursive CTE or
named subquery. Standard SELECT queries and FROM-starting Pipe queries share
the same Pipe-tail parser and column scopes. CTE bodies keep their existing
restrictions on INFER and top-level lifecycle declarations. A set or CTE form
not yet implemented is reported as an implementation gap rather than a
permanent language restriction. Anonymous output expression labels remain a
separate profile gap; authored examples give their output expressions aliases.

## ARRAY constructors

For `[NOT] IN UNNEST`, an unannotated literal ARRAY of scalar literals and
immediate scalar parameter references uses the existing `in`/`not_in` literal
list contract. Both `[item, ...]` and `ARRAY[item, ...]` are supported, including
parentheses and signed numeric literals. Order, duplicates, NULL atoms and
parameter references are preserved; the Frontend does not evaluate general
expressions to build the list. A matching value takes precedence over a NULL
item. An empty list yields FALSE for IN and TRUE for NOT IN, including a
typed nullable left operand, under the common empty-set rule. These rules follow
the selected [GoogleSQL IN operator](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/operators#in_operator).

Array parameters retain their existing membership contract. General element
expressions and annotated ARRAY constructors retain ordinary common admission;
they are not rewritten into literal lists or stripped of their annotations.
The existing common membership owner checks the ARRAY item domain and preserves
its NULL and empty-set rules. Incompatible item domains are rejected. An
ordinary SELECT ARRAY remains an `array` expression.

`[expression, ...]` and `ARRAY[expression, ...]` preserve the authored element
order and duplicates through the ordinary finite `array` expression. Elements
use the common checker for compatible types, NULL context, parameters and
constructor capability checks; the Frontend does not stringify values or
infer a second type system. The parser's existing work, node and depth limits
also cover array children. An empty list needs unique type context.

The explicit annotation subset is `ARRAY<BOOL>`, `ARRAY<BOOLEAN>`,
`ARRAY<STRING>`, `ARRAY<NUMBER>`, `ARRAY<FLOAT64>`, `ARRAY<DOUBLE>`,
`ARRAY<INT64>`, `ARRAY<TIMESTAMP>` and `ARRAY<JSON>`.
Annotations use the existing typed `empty_array.items` evidence. A nonempty
annotated array uses an ordinary constant-true lazy `if` with that empty-array
peer, so the common checker checks the declared item type and evaluates the
actual elements once. It does not add an element CAST. NULL elements retain
their nullable contract even when the annotation provides a nonnullable peer.
`INT64` selects the distinct exact signed64 domain. Neither the annotation nor
ordinary constructor common typing promotes Number, Decimal or String elements
into int64; full-range values can use typed int64 Parameters. Membership's
immediate lossless integral comparison-literal context is a separate rule.

`CAST(NULL AS ARRAY<T>)` uses the same closed annotation grammar. Parentheses
around that immediate NULL are permitted. Source lowering preserves the NULL
branch in `if(false, empty_array<T>, literal(null))`; the typed peer supplies
context only. Common checking, typed-null emission and re-admission remain the
sole type authority. This value remains distinct from `ARRAY<T>[]` under
`IS NULL`. Other ARRAY CAST operands retain an implementation-limit result;
they are not rewritten to NULL or silently converted. Parsing, original spans
and bounded work apply equally to this context.

After ordinary checking, source preparation rejects resolved ARRAY types whose
immediate item type is ARRAY. This includes constructors, references to typed
columns or parameters, and Relation outputs such as ARRAY_AGG; inspecting
literal syntax alone is insufficient. Recursive type inspection is bounded by
the source profile's work limit. An intervening closed object is permitted,
but does not hide a directly nested ARRAY elsewhere within that object. JSON
payload arrays are JSON values, not SQL ARRAY types. Recursive arrays in
JSON/YAML Program input retain their common contract. Source-profile rejection
occurs before durable Run admission and provider I/O. Expression refusals retain
the common expression's original location; producer-schema refusals identify
the existing Unit, input/step and field without inventing an expression origin.

The selected [GoogleSQL array reference](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/data-types#array_type)
also supports `ARRAY<JSON>` and defaults otherwise untyped empty literals to
`ARRAY<INT64>`. Those behaviors remain coverage gaps here: the common constructor
capability contract currently rejects JSON item types, and an unresolved `[]`
does not acquire a default item contract. Explicit `ARRAY<INT64>` is distinct
from that defaulting rule. Other annotations retain their implementation gaps;
an unresolved `[]` is not silently assigned Number, int64 or JSON. The source and independently authored Program rejection of
JSON arrays are dependency evidence, not execution acceptance. ActQL's
nullable-array Result serialization remains its existing delivery profile;
it is not a claim about BigQuery's Result serialization.

## Declared UNNEST value tables

Direct `FROM UNNEST(@items) AS element [WITH OFFSET AS position]` accepts
bounded array parameter contracts. Scalar stars select the value column and
optional offset. For an admitted closed object element, `SELECT *` expands
its admitted fields in the common object's canonical field order and appends
the offset; `element.*` expands only the object fields. Field expansion and the
separate whole-value range follow the selected
[GoogleSQL STRUCT UNNEST rules](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#unnest_operator).
The range `element` also denotes the original object value without adding a
public column to star. Field access uses ordinary common `property` expressions;
the common checker determines nullable receivers and field contracts.

Scalar UNNEST also introduces a range name, although it has no member columns.
Pipe RENAME cannot rename that original value-table range. AS preserves a
single value table and replaces its range name; it does not project or compute
values. On a table with additional columns, AS replaces old ranges with one
row range and admits former value-table aliases as current whole columns.
Those columns retain their field-expanding star layout, distinct from whole-value
expression lookup. SELECT creates an ordinary output column scope; SET of a
whole value column removes its original range and permits a later RENAME.
DROP removes the matching range. Current column edits do not rewrite values or
star layouts captured by a surviving row range.
The range kind is retained across JOIN continuations and checked for duplicate
UNNEST aliases. A scalar `element.*` remains invalid; scalar DISTINCT continues
to compare the visible scalar values, rather than object-field expansions.

The same expansion accepts declared parameter property paths, for example
`FROM UNNEST(@payload.nested.items) element`. Parentheses and backtick property
names retain their ordinary expression meaning. The Frontend follows the
ordinary common expression checker to the ARRAY element contract; it
does not sample parameter values or fold a nullable receiver to a different type.
The same lookup admits finite ARRAY constructors, typed empty ARRAYs and
computed ARRAY expressions such as `IF(TRUE, [], ['x'])` or
`IF(TRUE, @items, @items)`. It does not invent Frontend-specific types or
discharge the expression's runtime obligations and required profiles. Ordinary common property and
UNNEST checking still validates the path, values and declared bounds. A NULL
object anywhere on this path produces a NULL ARRAY and therefore zero rows,
with the same element-field contracts and column order as nonempty input.
Expression lowering and common type inspection use the existing bounded
construction and expression work limits. Exhaustion remains a work-limit
error, rather than a guessed or truncated output schema.

NULL or empty arrays produce zero rows with the same declared schema. NULL
elements produce rows whose projected properties are NULL. Duplicates remain
rows; a declared OFFSET can be used for ordering. Implicitly exposed object
fields are expression/star names, not Pipe SET/DROP/RENAME column targets.
Project them with SELECT first to create ordinary editable columns. SET can
replace the whole value-table column named by its range; the replacement is an
ordinary column and its old implicit fields are no longer current columns.
DROP of that value-table column removes its implicit fields and range. RENAME
cannot rename the value-table range. Other current columns remain editable and
surviving ranges retain original value slots, with the same-name target
exceptions defined above. SELECT or AS
establishes the ordinary new Relation scope and removes that original range,
except for the existing directly following SELECT-owned ORDER boundary.
No witness, array, element or property implementation slot is publicly exported.
This connects the existing named-object parameter contract; it does not add
GoogleSQL's ordered STRUCT type. Reordering that contract's authored JSON keys
does not change its field order. Anonymous/duplicate STRUCT fields, positional
STRUCT equality and author-selected STRUCT order remain a common-contract gap,
not a guarantee supplied by this expansion.
Unresolved, non-ARRAY and inadmissible element contracts remain explicitly
unsupported for star. ARRAY typing comes from the common expression checker;
this connection does not extend the common ARRAY constructor capability profile.

`CROSS JOIN UNNEST(array_expression) AS element [WITH OFFSET AS position]`
expands each current row through the existing common `unnest` operation. SQL
FROM clauses and Pipe JOIN operators use the same sequential expansion. The
array expression resolves against preceding input columns and range snapshots,
not subsequent SELECT aliases. Parent columns and their evaluated slots remain
available, including the original ARRAY column. NULL and empty arrays produce
no child rows; NULL elements and duplicates remain child rows. OFFSET is zero
based and does not by itself promise output order. Use an explicit ORDER BY
when ordering matters. Type, key transfer and expansion bounds remain the
common checker's responsibility; a parent key alone is not a unique child key.

The original parent range survives Pipe SET/DROP/RENAME and correlation unless
its name is removed by the same-name target rules above. A
SELECT or AS replaces that scope using the existing rules above. Successive
closed object value-table ranges retain their own receivers; adding another
expansion does not rebind an earlier object's fields or value. Qualified parent
stars remain supported independently of an unknown child contract. An unknown
ARRAY expression's element/whole-result star still requires a common schema
connection and is explicitly unsupported, rather than inferred from rows.

The correlated profile supports explicit CROSS JOIN UNNEST after preceding
ordinary JOINs and successive CROSS expansions. A subsequent ordinary Relation
JOIN consumes the expanded row in both SQL and Pipe. Its explicit bound, parent
ranges, object value-table receivers and OFFSET are retained through private
producer references; expansion is not moved after the JOIN. An authored SELECT
or AS still replaces scope. Correlated expansion after Pipe UNION ALL
consumes the retained set output; ARRAY/object stars use its common checked
schema, including CTE column aliases and nullable object fields. The set's
multiplicity, declared ARRAY bounds and subsequent predicates remain unchanged.
Explicit `[INNER] JOIN UNNEST` uses the same correlated expansion in SQL and
Pipe. An optional ON expression filters the expanded pairs at that point,
using ordinary current-column and immutable-range resolution. A NULL or false
predicate excludes the pair; NULL elements and duplicate elements otherwise
remain rows. Without ON, INNER expansion is equivalent to CROSS expansion.
Empty or NULL arrays produce no child rows. A subsequent ordinary JOIN
consumes the filtered expansion rather than applying the predicate after that
JOIN. This follows the selected [GoogleSQL array-flattening profile](https://docs.cloud.google.com/bigquery/docs/arrays).
LEFT correlation and implicit comma expansion remain coverage gaps, not
GoogleSQL language restrictions. Correlated expansion does not accept USING
or MAX_OUTPUT_ROWS; it inherits the declared ARRAY bound and common Host
capacity policy without raising either limit.

## Named intermediate Results

`|> RESULT name` registers the complete current Relation as a named Result
and passes that same Relation to the continuing Pipe. This is an ActQL
publication/retention extension, not a GoogleSQL relational operator.
It does not grant access, write a business table, choose a physical location,
or require another Stage or process. Ordinary Result owners enforce retention,
publication, current authorization, resource limits and cleanup.

Each Result retains the rows, duplicates, visible columns in declaration order,
types/nullability and existing key/order evidence at that point. A later WHERE,
SELECT or LIMIT cannot change its content, schema, required acquisition or
validation. No partial successful Result is published on resource failure.
Compiler-private slots and immutable range snapshots are excluded from the
public Result while remaining available to subsequent valid Pipe references.

Multiple names are permitted; redefinition is rejected after ASCII
case-insensitive name resolution, including backtick-quoted names. Authored
spelling is retained for the public Result name. Names must also be distinct
from the configured primary export when that export is needed. If the last
operator is `RESULT x`, the primary output references that same `x`; no second
anonymous export is constructed. Otherwise the continuing Relation uses the
existing configured primary export.

A terminal `CREATE TABLE` or `CREATE OR REPLACE TABLE` is the explicit
exception: only authored public Results are exported. Its final Relation feeds
the existing private Table input, without another primary export. With no
authored Result its public `results` map is empty. This exception does not change
ordinary Relation queries or UPDATE's primary-tail rule.

RESULT declarations belong at statement level (and adopted BRANCH bodies), not
inside CTEs, derived queries or set operands. The separate adopted `RESULT(name)`
source reference is not a declaration and has its own preceding-statement
rules; listing it here does not assert its implementation. The current Graph
query profile requires an explicit public Relation projection before RESULT,
so graph occurrence slots cannot become public columns.

Lowering uses ordinary named step producers and Stage/Program Result
definitions. It does not expand a producer or re-acquire its Source. Keeping a
prefix Result can require bounded retention and is not a cost-free alias.

## INFER KEEP source projection

The adopted INFER Pipe form requires `INPUT` and result `AS` clauses, with
optional `ITEM KEY`, `KEEP`, `MAX ITEMS n` and `ON FAILURE FAIL`. The contract name is carried unchanged
to ordinary `infer.contract` resolution in the same Check Environment;
backticks can delimit a complete existing reference such as
`model-task:risk-score.v1`. Parsing a name does not resolve a ModelTask, select
a newer version, or authorize model egress. An empty INPUT is checked against
the resolved closed input contract, not treated as permission to omit fields.

Each INPUT entry is `name = expression`, `expression AS name`, or a single
same-name identifier: `INPUT (notes)` is equivalent to `INPUT (notes = notes)`.
All three spellings may be mixed; `notes = a.description` and
`a.description AS notes` produce the same input mapping. Shorthand uses the ordinary binding identifier role, so
reserved words require backticks; explicit assignment keys retain their closed
ModelTask schema-key role. Dotted references and other expressions require an
explicit assignment or AS mapping. All forms keep the original expression source ranges and
use the same closed input contract checks, including missing, extra, duplicate,
ambiguous, unknown and wrong-type fields. Shorthand sends no additional field.

`MAX ITEMS n` is a positive safe-integer literal or a whole declared Parameter
of that contract, not a row expression. It guards the distinct checked input
keys submitted by this INFER occurrence and composes with Contract and Host
ceilings; specifying a key does not prove uniqueness. `ON FAILURE FAIL` is a
publication rule, not an unbounded retry or a rollback of model calls. After
the existing bounded retry policy, any unsuccessful row prevents the step from
publishing success. No partial successful result reaches later steps or
Effects; already made calls, their outcomes and their costs remain recorded.
Omission retains the existing per-row outcome contract.

KEEP accepts column references, optional output aliases, and known-schema
`*` or range `.*`. Expansion retains visible declaration order, and explicit
items retain authored order. Calculations belong in SELECT or EXTEND.
A collision with the result AS name, unresolved references, repeated explicit
output names, and repeated ITEM KEY value slots are rejected. Admitted positional
unnamed and duplicate-display occurrences retain their separate physical slots,
original order, types and provenance. The common checker still proves the
complete non-null scalar candidate key; specifying ITEM KEY never supplies that
proof. Only INPUT mappings are sent to the model.

When ITEM KEY is omitted, the original checked prefix must establish exactly
one eligible non-null scalar tuple through the existing Common INFER checker.
Its CheckedInfer witness and ordered bindings supply the completed key; aliases,
composite tuples, foreign or stale witnesses, and multiple candidates keep the
common checker's existing rules and refusals. No row samples, row numbers,
implicit DISTINCT, or canonical-order choice establish a key. An explicit
ITEM KEY retains exact tuple checking. ASSERT UNIQUE BY remains available and
its runtime guard must succeed before Model dispatch.

Omitted-key completion retains the last authored name bound to each selected
physical value slot. A RENAME or same-slot alias names that same original key;
SET binds its replacement to a different value slot and never retargets the
earlier key's name, value or type. An older surviving range name cannot override
a newer name authored for that original slot. Real projection/remapping follows
the existing slot correspondence; a reused physical spelling is not an earlier
slot generation. Retaining a hidden key label does not restore a column or range
to SQL lookup or visibility.

The original Common-proven values, types, ordered composite components and their
selected names are fixed when INFER adopts the tuple. Later column edits do not
rewrite that information; retention and recovery reuse the same emitted tuple
and captured correspondence rather than resolving names again. Key names are
identity-bearing parts of the ordinary Program and result-object projection,
not cosmetic display metadata or a new capture format. Retaining the original
Program preserves that projection with its existing capture correspondence.
Identical normalized key metadata preserves
explicit/default identity, while a different authored key name can change a CID.
Conflicting or ambiguous output names, including the existing reserved result
roles, cause the existing typed refusal; completion never invents a replacement
name or chooses a different candidate key. Explicit ITEM KEY keeps its authored
tuple and existing name semantics.

The new visible scope consists of KEEP columns followed by one result object:
`input_key` (named fields in the completed or explicitly authored key tuple),
`outcome`, and `value`.
Omitted KEEP is exactly KEEP (*): all visible input columns retain their order
and layout, followed by the result object. Explicit KEEP remains an authored
subset; a later SELECT can retain only the result object. Prior range aliases
cannot recover omitted input fields. KEEP is a checked one-to-one correspondence with the
same retained input producer, not a new read or a row-position join. The common
infer output remains flat keys, outcome and value. Ordinary join and object
projection construct the surface shape without changing its capture format.
The original producer is retained once, with no refetch or second Model
invocation. Its simultaneous holding and join-back consume the existing budgets.
The default applies only when compiling new text; stored Programs, signed
identities and old Runs are not reinterpreted.

Success value is the existing non-null closed ModelTask output object, retaining
each field's nullability. Non-success value is typed NULL, and outcomes retain
the fixed [infer contract](language.md#infer) enumeration. Nested references
lower to ordinary property expressions after resolving a visible column or
range prefix. Known properties on a nullable receiver propagate NULL; unknown
properties require the common type error. Outcome/value refinement and capture
provenance remain common-owner obligations, never facts fabricated by a name,
projection or assignment. Frontend construction of a Program is not evidence
of model execution support. Until common infer and object-expression execution
are available, normal Host preparation rejects these Programs before Run
acceptance and provider I/O.

## NEAREST KEEP source projection

NEAREST consumes the current Relation or typed Vectors as queries and an
explicitly named candidate Relation or typed Vectors. Each side independently
admits an optional complete KEY/VECTOR pair: `QUERY KEY (...) VECTOR ...` or
`CANDIDATE KEY (...) VECTOR ...`. A missing half is a syntax error; absence is
retained in the typed AST, never an empty key list or a fabricated vector field.
Typed Vectors may omit the pair and retain their admitted identity and component
roles. An explicit pair must restate those roles. Relation sides use the existing
Common nearest completion: the sole known vector field in a closed field set,
and a sole eligible proven string key from that exact input target. Missing or
ambiguous evidence refuses. Numeric and composite implicit-key completion is a
current Common gap, not a permanent language restriction. No spelling or observed
row value is key evidence.

`USING expression` supplies the query vector without a QUERY role pair. The
ordinary expression owner evaluates it against the current query scope; a typed
Vectors input can only restate its admitted component role. USING and QUERY
VECTOR cannot both supply that expression. An omitted candidate alias is its
final producer-name component; an explicit AS remains authoritative. Omitted
METRIC selects exact cosine. Explicit cosine, dot and negative-distance l2
remain authoritative. Positive safe-integer literal K and the final result AS
are mandatory. K is per query, not a search-work or memory ceiling.

KEY references resolve independently within each side. Named key objects use
the resolved input column names; quoting and case-insensitive lookup do not
replace those names with the spelling of the reference. The shared checker
and execution owner verify non-null typed IDs, dimensions, uniqueness,
quantization, finite components, ordering and resource obligations.

KEEP resolves against both input scopes. Unqualified ambiguous references,
duplicate output names and collisions with the result AS name are rejected.
Wildcards expand known columns in declaration order; `*` expands query columns
then candidate columns and still rejects duplicates. Each explicit item retains
its authored position. The output contains KEEP columns followed by the result
closed object: query_key and candidate_key (named objects), score and rank.
Omitted KEEP retains all visible query columns in their declaration order,
followed by the named hit. Explicit `KEEP (*)` still expands both scopes and is
not the query-only default. Old input aliases cannot recover omitted columns. Query values repeat for each retained candidate match; no
match produces no row. Query-key-only uniqueness is never inferred after KNN.

Lowering retains each source producer once, uses the existing rows-to-Vectors
bridges and nearest operation, then common many-to-one joins for KEEP and
ordinary object projection. If the candidate declares an unambiguously resolved `body` column,
its actual value and type are projected as `hit.body` through that same retained
candidate correspondence. It is neither the query row nor a flattened query
column, and cannot replace query_key, candidate_key, score or rank. Other
candidate payload columns remain available through explicit KEEP. A missing
body is not manufactured; ordinary property checking rejects its reference.
These defaults affect newly compiled text only; saved Programs, identities and
Runs retain their original meaning. Explicit candidate selection cannot be replaced
by the filtered query Relation. Shared sources retain one capture boundary
covering both demands under the ordinary grant and capacity checks. No read
permission, synthetic ID, output key witness, implicit sort, retry or alternate
execution engine is supplied by the frontend. The flat pair key remains common
owner evidence; nesting its values does not declare an arbitrary object key.

Optional role pairs are retained by the parser. The typed continuation resolves
the actual input Carriers and connects all four Relation/Vectors combinations
to the existing nearest owner when NEAREST starts the input Pipe or follows a
supported Carrier prefix. WITH producers retain their original binding owner.
Typed Vectors keep their admitted identity/component roles and may restate them
exactly; only Relation sides use rows-to-Vectors conversion. KEEP uses ordinary
row bridges and does not replace either Vectors identity. Composite Vectors use
the common ordered identity components when constructing named output keys.

Explicit Relation KEY tuples retain all ordered components through the same
`to_vectors` Bridge as typed Vectors. The scalar and singleton-list Bridge forms
retain the existing scalar parameter spelling; wider tuples use the closed
ordered field-list alternative. The frontend constructs no combined scalar ID,
string encoding, CID or uniqueness witness. Ordinary
Relation Pipe operations retain their scopes, predicates and limits
before a typed candidate; the same admitted candidate metadata reaches the
existing Relation lowerer. Typed set heads use the common script dispatcher
with the existing outer set owner, and row bridges are retained only for the actual query default, explicit KEEP,
or candidate body demand. JOIN continuations bind their candidate through the same
WITH input owner and pass its admitted Carrier to the existing Pipe compiler;
qualified query roles continue to resolve through the actual JOIN row scope.
Implicit Relation key completion remains limited to the existing sole eligible
String-key rule. Explicit composite conversion does not widen that inference.
Parser/lowering and checked output contracts do not establish installed Host
execution, capacity or successful publication.

## WITH producers and pure Graph construction

`WITH name AS (body), ... query` is the shared logical producer-binding surface
for SQL and AQL-text. Both selectors lower accepted WITH/SELECT/CREATE input
through the same ordinary frontend; SQL keeps its existing top-level head
selection, while AQL-text also accepts a standalone FROM-headed Pipe. JSON/YAML
remain supported machine Program inputs.

A binding does not acquire, copy, store, normalize or publish its value and does
not request placement or a task boundary. Its body resolves before its name
becomes visible. Earlier and outer bindings are visible; the nearest binding
wins regardless of Carrier. Duplicate names in one scope, recursive and forward
references are rejected. Source View paths, lexical producer names, row aliases,
Graph element definitions and labels retain their different namespaces.

Every authored WITH body and ordinary grouped body is Pure: INFER, RESULT and
terminal Effects are excluded. The whole outer CTAS input wrapper is Compute;
its grouped subqueries remain Pure. The final Statement retains explicit
Results/Effects as demand roots. All bindings receive common static checking,
including unused bindings. A valid unused body is not executed merely because
it is named. Demand uses the original checked producer/import/projection edges;
it does not waive input-required order, type, Catalog or profile obligations.
Normal Host preparation and Result publication remain strict.

The NONE-input `time_series(start: value, end: value, step: value)` primary
produces a Relation through the existing common TEA generator. Use it in
`WITH grid AS (time_series(...)) SELECT time FROM grid ORDER BY time`, or as
an AQL-text primary followed by ordinary Pipe operators. SQL retains its
WITH/SELECT query-head selection. The closed arguments are exactly start,
end and step, using the endpoint and positive-step forms of the common
`time_series` contract. A generator cannot consume a current Pipe input.
The common checker determines the timestamp field, key, ascending generation
order, range/arithmetic validity and resolved bounds; the frontend does not
sample rows or substitute Parameter defaults. Unused bodies remain statically
checked and only demanded generators remain in execution. Relation primaries
are not Graph values or implicit Source reads. Installed public execution
and the optional Calendar profile remain separate acceptance obligations.

WITH can retain Relation, Graph, Vectors or Events according to the admitted
common contract. The installed constructor and Graph consumer connections
are described below. Typed Pipe calls also connect `to_vectors(id: field,
vector: field)`, `normalize_vectors()`, `score_vectors(query: value, metric:
string)`, `pool_vectors(by: [fields], method: string, vector: field,
output_id: name)`, `vectors()`, `to_events(id: field, time: field)`,
`row_window(time: field, kind: string, size: value, step: value?, offset: value?)`,
`window_events(kind: string, size: value, step: value?, offset: value?)`,
`watermark_events(watermark_ms: number, policy: string)`,
`watermark_rows(time: field, late_policy: string, watermark_ms: value?, max_skew: value?)`,
`lag(partition_by: [fields], order_by: [OrderKeys], field: field, output: name, offset: value?)`,
`dedupe_events(by: [fields], order_by: [OrderKeys])`, `session(by:
[fields], gap: string)` and `events()` to their existing common operations.
Relation-input session additionally requires its existing `id` and `time`
roles. Field roles resolve visible columns; they are not String values or
producer aliases. The common checker determines the output Carrier and schema.
Vectors/Events retain their Carrier across bindings; only an explicit common
bridge supplies rows to ordinary Relation operators. Full four-Carrier public
execution remains a separate acceptance obligation. A typed producer is not an
invented external Source alias or a row schema inferred by the frontend.

The named `lag` Pipe call uses the existing relational navigation contract;
it is distinct from scalar `LAG(...) OVER (...)`. `partition_by` and `field`
resolve current visible FieldRefs. Partition fields retain authored order and
repetitions, including an empty list. `order_by` accepts the shared shorthand
or closed field/dir/nulls OrderKeys and must be nonempty. `output` is an
OutputName: bare reserved words are rejected, quoted names remain available.
The optional positive safe-integer `offset` or whole Parameter is passed
unchanged; omission retains the common default of one. The common checker
requires candidate-key completion of calculation order independently of the
input or published sequence. It rejects collisions, invalid counts and invalid
order. Navigation adds a nullable column with the input field's value type;
missing predecessors and NULL field values remain NULL. No frontend key proof,
order evidence or execution owner is synthesized. These source connections do
not by themselves establish public Host execution.

The named `window_group(by: [fields], aggregates: {output: AggregateCall, ...})`
Pipe call uses the existing [window grouping contract](language.md#relational-temporal).
Its Relation input must carry checked window boundary roles from `row_window`
or a declared windowed contract. Ordinary columns named `window_start` and
`window_end` do not provide that evidence. `by` uses current FieldRefs; the
common owner prepends both boundary keys once and preserves repeated other keys.

Aggregate output keys are OutputNames: bare reserved words are rejected and
backtick names remain available. Each aggregate is the existing closed record
with `fn`, `field` or `expr`, `filter`, `distinct`, `order_by`, `max_items`,
`max_bytes`, `delimiter` and `fraction` as permitted by its function. `fn` is
an exact decoded String enum; `count_if` is distinct from scalar SQL spelling
`COUNTIF`. `field` and shared shorthand or closed OrderKeys resolve current
FieldRefs. `expr` and `filter` retain the original bounded query Expression
owner, authored spans, work and input/Parameter scope. They are not reparsed
from a String or structured JSON. Filter Boolean typing, NULL contributions,
DISTINCT, function-specific options, calculation order and collection guards
remain common-checker obligations. No frontend window or key evidence is added.

For example, after an existing `row_window`:

```aql
FROM windowed AS r
  |> window_group(by: [r.cohort], aggregates: {
       n: {fn: 'count'},
       total: {fn: 'sum', expr: COALESCE(r.amount, 0) + 1,
               filter: r.amount IS NOT NULL, distinct: true}
     })
  |> SELECT window_start, window_end, cohort, n, total
  |> ORDER BY window_start, window_end, cohort
```

This source connection is an ActQL operation profile. Checker and lowering
coverage is separate from installed Local/HTTPS execution evidence.

The `watermark_rows` call preserves Relation input and the existing
[relational watermark contract](language.md#relational-temporal). Its `time`
is a FieldRef in the current row scope; policy is the exact `'mark'` or `'drop'`
String. Exactly one of `watermark_ms` and `max_skew` is required by the common
checker. The frontend preserves fractional/negative fixed thresholds, positive
skew numbers/durations and permitted whole Parameters without evaluating them,
choosing precedence, or inventing input order. Prefix skew retains its proven
logical input-order obligation. Common generated-field collision, non-null clock,
threshold arithmetic, type and resource checks remain unchanged. Text checking
and lowering do not establish public Host execution.

The `pool_vectors` call retains the existing [pooling contract](language.md#pool-vectors).
`by` is an ordered nonempty FieldRef list and `method` is an exact String value
(`'sum'`, `'mean'` or `'max'`), never an identifier lookup. Relation input requires
`vector` and retained candidate-key evidence, for example from an authored
`ASSERT UNIQUE BY (item_id)`; the assertion's ordinary owner validates actual
uniqueness. Vectors input already owns member identity: `vector` may be omitted
or restate its existing component role, but cannot override it. There is no
separate member `id` option. Optional `output_id` is an OutputName, uses the
ordinary reserved-word/backtick rule, and is allowed only with one grouping
field. It adds the common identity alias without dropping the grouping field.
The shared checker owns nullable/key eligibility, repeated grouping fields,
output collisions, dimensions, profile and execution-resource obligations.
The frontend does not duplicate grouping, numeric folds or identity encoding.
An explicit `vectors()` bridge is required before Relation projection.

All authored clock FieldRefs in `to_events`, `sequence`, `row_window`,
`watermark_rows`, `asof_join` and `interval_join` accept the shared
[timestamp or integer-millisecond domain](language.md#event-clock-domain).
The original column is retained; only internal arithmetic converts timestamps.
No numeric-only exception applies to an Events input.

`row_window` and `window_events` retain the existing [window contract](language.md#event-windows),
respectively Relation-to-Relation and Events-to-Events. `time` is a FieldRef,
not a String or producer name. `kind` is the exact String `'fixed'` or
`'sliding'`. Positive millisecond sizes/steps and signed offsets retain their
authored numeric, duration String or whole Parameter representation; the
shared owner checks the declarations and values. Sliding requires `step`.
Fixed also admits and validates an explicit `step` without using it for
membership. The lowerer never drops that argument or inserts an omitted step
or offset. The common owner supplies default offset zero and retains the
closed-open membership, clock, occurrence order, arithmetic and capacity rules.

`watermark_events` preserves Events and the existing [watermark contract](language.md#event-bridges).
Its closed arguments are a finite numeric `watermark_ms` literal or whole
declared numeric Parameter, including admitted negative/fractional values,
and required exact policy String `'mark'` or `'drop'`.
The common owner validates the Parameter declaration and bound value against
the literal's domain and retains that value for the Run. Row expressions,
implicit NOW() and recomputation on resume are refused. The shared owner checks the Carrier,
fresh output names and values: late means time strictly below the threshold;
equality is not late. Both policies preserve retained identity, payload and
relative order. Use `events()` before ordinary Relation projection. These
source connections do not establish full TEA profile or public execution.

`dedupe_events` preserves Events and the existing [dedupe contract](language.md#dedupe_events).
`by` is an authored list of visible FieldRefs: an empty list selects globally,
and repeated references remain repeated in their original order. `order_by`
is nonempty and preserves the common OrderKey alternatives: `{score: 'desc'}`
uses a FieldRef as its single key and the common implicit NULLS LAST;
`{field: score, dir: 'desc', nulls: 'first'}` preserves explicit NULL placement.
Quoted names and receiver paths use ordinary retained-column scope; Strings
cannot replace FieldRefs. The explicit record keys are case insensitive, while
direction and NULL-placement Strings retain exact values. An omitted argument
is not filled in by the lowerer. The common owner checks KeyComparable grouping,
AuthorOrderable order fields, actual identity/payload/clock retention and
`FailOnTopTie`; input arrival order never supplies a hidden tie breaker.
Use `events()` before Relation operations. These source/checker connections
alone do not establish public Host execution.

`FROM p` preserves the resolved Carrier. `FROM GRAPH p` adds a Graph expectation;
it does not search past a nearer Relation binding. MATCH accepts Graph with or
without that marker. A scalar SELECT explicitly ends PatternScope and exports
only its authored columns; pattern aliases and hidden identity/path slots do
not reappear in an outer scope. A table subquery, JOIN or set operand requires
Relation. An authored row alias requires Relation, independently of spelling.
Both explicit/implicit FROM aliases and Pipe AS parse on a Graph input, then
receive the static `RangeAliasRequiresRelation` reason before any execution.
WITH producer aliasing retains the Graph; a Graph-to-Relation bridge or explicit
MATCH SELECT permits the ordinary row alias on the resulting Relation.

~~~aql
WITH selected AS (
  FROM g |> MATCH WALK (a:Node) |> SELECT a.score AS score
)
SELECT score FROM selected
~~~

The pure `GRAPH (...)` constructor is an ActQL value extension using the
[selected GoogleSQL/SQL-PGQ mapping profile](../design/frontend-standard-profiles.md#graph-mapping-and-element-identity).
It creates no Catalog object and claims no ISO GQL constructor syntax.

~~~aql
WITH nodes AS (SELECT 1 AS id, 'one' AS name),
     g AS (GRAPH (
       NODE TABLES (nodes AS N KEY (id) LABEL Node PROPERTIES (id, name))
     ))
FROM g |> node_rows() |> SELECT id, name |> RESULT nodes
~~~

REFERENCES resolves a Graph-local element definition and its ordered KEY
columns. Typed keys, independently keyed parallel edges, Graph-owned label
sets, Graph-wide property types and same-label property sets remain common
Graph contracts. The frontend cannot fabricate those facts, replace static
labels with property comparisons or collapse edge identity. A schema declaration
alone cannot supply the Source View provenance required by the common checker.
The retired declaration, old pure-constructor spelling and LABELS annotation
have no parser, compatibility selector or fallback entry.

An acquired input retains its original declaration, Source View/Catalog ownership
and Host-selected capture boundary. Multiple references reuse that prepared
producer; bindings do not acquire it again. Source construction and static
checking alone establish neither public execution nor snapshot acceptance.
Graph-preserving bodies keep the existing admitted definition domain; a binder
rename does not reconstruct the constructor or add a projection. Actual
constructor-definition changes retain their ordinary identity consequences.

SQL/Pipe INNER/LEFT/CROSS JOIN chains use the existing bounded JOIN operations,
range scopes, ON/USING conditions, evaluated projection slots and alias-priority
ORDER rules. No legacy Graph conversion or alternate execution owner is allowed.
Current profile refusals stay explicit rather than being approximated.

## Named logical SGA calls

The adopted named SGA surface is an ActQL extension, not a SQL scalar-function
or ISO GQL procedure alias. The operation names are reach, traverse,
shortest_path, components, degree, graph_bounds, match_nodes, match_edges,
normalize_graph, subgraph, graft_graph, union_graphs, subtract_graphs,
graphs_equal, graph_diff, apply_graph_delta, mean_graphs, node_rows and
edge_rows. Calls retain their existing logical Carrier transitions; a Graph
is not implicitly converted to a Relation for SQL compatibility.

Arguments are named. Their role comes from the operation contract rather
than from the content of a String: `with: target` names a producer,
`start: "A"` is an ID value and `field: delta` designates a column. Relation
selectors in reach/traverse `start.from`, shortest_path `source.from` and
`target.from`, and subgraph `nodes.from` use producer references. Bare and
backtick producer names follow the nearest WITH resolution rules; String
values cannot name producers. A mean_graphs `with` list is explicit and does
not silently acquire an additional current input. Duplicate input
specification must be rejected rather than merged or ignored.

The signature adapter keeps the following roles separate until ordinary
Program lowering. String literals cannot substitute for reference or output
name positions; they remain decoded data in literal and enum positions.

| Role | Connected examples | Meaning |
|---|---|---|
| ProducerRef | `with: target`, `start: {from: seeds, ...}` | Nearest lexical WITH producer identity, without acquiring or placing data |
| FieldRef | `start: {from: seeds, id: seeds.element}`, `field: changes.delta`, `weight: cost`, `fields: [id, payload]` | Column of the declared operand; a selector qualifier must resolve to that operand |
| OutputName | `bindings: {identity: element, source: src, target: dst}` | Authored output identifier, without looking up an existing column |
| Expression | `where: {gt: [{field: payload.score}, {literal: 10}]}` | Existing common field/property expression nodes, with common type and NULL checking |
| Enum/Literal | `direction: 'out'`, `start: 'A'`, `definition: 'N'`, `label: 'Person'` | Exact decoded data, never an inferred reference |
| ClosedRecord/List | Selector, bindings and expression records; explicit operand lists | Signature-selected leaf roles, preserving list order and repetition |
| WholeParameter | Existing parameter-enabled operation positions | Existing common parameter contract, without a frontend replacement value |

Relation selector columns in `start.id`, `source.id`, `target.id` and
`nodes.id`, and Delta `field`, resolve against their declared Relation operand.
`id: element` and `id: seeds.element` select the same column when `from: seeds`;
the qualifier follows the same lexical binding as `from`, including inside a
nested WITH. A qualifier for another producer or a missing column is rejected.
A single column containing a dot must be one backtick-quoted name, such as
`id: \`node.key\``. Expression `payload.score` instead lowers to a field plus
property projection; its receiver is not searched as a global producer.
Graph field, identity, presence, label, selector and parameter obligations
remain with the existing common checker and execution Owner.

Operation and selector vocabulary is case-insensitive. Object-valued data
retains its own field names and decoded values. Numeric tokens retain their
exact spelling until normal numeric admission. A single numeric token can have
a unary `+` or `-`; a sign cannot apply to a parameter, parenthesized expression
or calculation. The installed common numeric decoder retains precision,
finite-value, hexadecimal and negative-zero admission. The same lexical, syntax,
work and depth budgets apply to calls inside a query and a WITH body.

A Graph-preserving query can bind its producer through WITH or precede a
Graph MATCH. For example:

```aql
WITH normalized AS (FROM g |> normalize_graph())
FROM GRAPH normalized |> MATCH WALK (a:Node) |> SELECT a.id
```

This lowers to the existing normalize_graph step on g and the existing
definition-selected MATCH on its output. WITH does not copy the Graph,
reacquire its inputs, add a Result or request materialization/physical
placement. The normalization has no named options; extra arguments are not
discarded. Unconsumed Graph calls cannot pass through relational compilation.

The Frontend also connects the existing `node_rows()` and `edge_rows()`
Bridge operations to ordinary Relation processing. Use a constructor-bound
WITH producer, for example:

```aql
WITH rows AS (FROM g |> node_rows() |> SELECT node_key, labels)
FROM rows |> ORDER BY node_key |> RESULT nodes
```

Each call accepts either no arguments, `definition: "N"`, or `label: "Person"`.
Exactly one string-valued selector is permitted; these names are Graph element
names, not producer references or property predicates. Resolution uses the
common Graph name identity and retains declared spelling. Definition selection
chooses one same-kind definition; label selection chooses all same-kind
definitions declaring that label, including properties exposed by their other
labels. Unknown names, wrong element kinds, mixed selectors and non-string
selectors are explicit pre-admission refusals. The selector is lowered to the
existing closed `node_rows` / `edge_rows` object, without inferred filtering.
The common Bridge owns the finite schema, typed element identities, retained
key columns, label sets and property presence. Conditional presence is not
nullable: an ordinary reference to a Conditional field is rejected by the
common checker, even after `IS NOT NULL`. Project guaranteed columns before
ordinary filtering if the selected schema still contains Conditional fields.
The remaining Relation operations
use normal scope, expression, order and Result lowering. WITH adds no copy,
acquisition or execution owner. A Graph-preserving normalize call still needs
an adapted common consumer; source lowering alone does not authorize it.

The existing Graph diagnostic operations also enter ordinary Relation processing:

```aql
WITH stats AS (FROM g |> degree(direction: "out"))
FROM stats |> WHERE degree > 0 |> SELECT node_id, degree |> RESULT active
FROM g |> graph_bounds(max_nodes: 10, max_edges: @edge_limit)
  |> SELECT kind, node_id, actual, max |> RESULT violations
FROM g |> components(kind: "strong", max_output_rows: 100)
  |> SELECT node_id, component_id, component_size |> RESULT groups
```

Each line terminating in RESULT is a separate query example. The Pipe's left
Graph supplies the existing operation input. Bodies, typed parameter references
and authored guards are preserved for the common checker and owner; omitted
required arguments and invalid values are not replaced with defaults. Diagnostic
thresholds select violations, rather than raising execution-resource ceilings.
The Relation scopes are exactly `node_id, degree`, `kind, node_id, actual, max`, and
`node_id, component_id, component_size`, respectively. Graph identity types,
nullable bounds `node_id`, component identity/order, selected capacity and
atomic guard failures follow the existing machine contracts. WITH reuses the
producer; old Graph columns do not reappear after the Relation transition.
These source connections do not establish support for other Graph operations
or waive the common admission and execution obligations.

Both emissions of `traverse` enter ordinary Relation processing:

```aql
WITH seeds AS (FROM g |> node_rows() |> SELECT id AS element)
FROM g
  |> traverse(start: {from: seeds, id: element}, direction: 'out',
              min_hops: 0, max_hops: 2, path_mode: 'trail',
              emit: 'nodes', max_output_rows: 10)
  |> SELECT start_id, node_id, depth |> ORDER BY depth |> RESULT visited
```

`start.from` resolves an earlier WITH-bound Relation producer, including a
backtick-quoted WITH name. Its `id` names a column containing the common
typed Graph identity, not a raw key. The Frontend retains every authored
argument, including an empty `edge_types` list and explicit output/hop bounds.
Numeric arguments use the same literal admission as query expressions.
The common checker owns selector membership, identity/type checks, path mode,
predicates, finite hop bounds, fixed non-NULL output contracts and capacity.
For `emit: 'nodes'`, the output names are `start_id`, `node_id`, `depth`.
For `emit: 'paths'`, they are `start_id`, `end_id`, `hop_count`, `node_ids`,
`edge_ids`. Path identity arrays retain complete definition-scoped typed
identities, including distinct parallel-edge keys. Path eligibility, exact-path
deduplication and canonical enumeration remain common traversal contracts;
the Frontend neither converts paths to minimum-depth nodes nor sorts them
implicitly. No uniqueness or presence
proof is manufactured by the Frontend. A WITH binding of that output can
continue through ordinary Relation operations without expanding its producer.

This connection requires explicit literal `emit: 'nodes'` or `emit: 'paths'`.
Omitted, unknown and parameter-valued emission cannot supply a static column
scope and are rejected. Direct installed selector Sources remain unconnected and are rejected
before Run admission. Installed selectors need the existing checked
acquisition/share boundary; the Frontend cannot replace it with repeated reads.
These are current implementation gaps, not new limits on the common traversal
contract. Typed literal/list and predicate selectors are passed unchanged for
ordinary checking; source acceptance alone is not their execution evidence.

`match_nodes(...)` and `match_edges(...)` also produce ordinary Relations.
Their required `fields` list declares the visible output names in order; it
must be a nonempty list of STRING values. The common match checker resolves
`definition`, optional `label`, identity/source/target `bindings`, property
presence, field contracts and predicate types. No identity or presence proof
is inferred by the Frontend. The authored operation body is retained,
including structured Expression predicates, parameters, empty edge `types`
and invalid options for the ordinary checker to refuse. Arguments are values
in the adopted named SGA surface, not query aliases or SQL expression text.
The Frontend does not reparse STRING contents as query expressions. A matched
Relation can bind WITH and continue through normal WHERE, SELECT, ORDER and
LIMIT; omitted Graph fields and further Graph calls are unavailable.

`graphs_equal` also enters ordinary Relation processing:

```aql
WITH same AS (FROM g |> graphs_equal(with: g))
FROM same |> SELECT equal |> RESULT comparison
```

The required `with:` argument resolves an earlier WITH-bound Graph producer using
the nearest WITH naming rule, including backtick-quoted names and bindings
that retain a producer. A string is not a producer reference. The left input
is the current Graph, including a preceding `normalize_graph()` output;
resolving the right input does not reconstruct, acquire or copy either Graph.
Unknown/forward references, Relation inputs, missing or extra arguments and
a second Graph call after the Relation transition are explicit preparation
refusals. A WITH binding of the comparison can continue through the ordinary
Relation scope, expression, order and Result paths.

The existing common checker owns compatible closed definitions and key/type
contracts; the common comparison owner evaluates admitted Graph values,
including complete identity, labels, properties and retained provenance.
The output is one row with the non-NULL Boolean column `equal`. Subsequent
Relation filtering may produce an empty result while retaining that column's
contract. The Frontend exposes only `equal`, not the original Graph's keys,
properties or internal slots, and does not derive new Graph equality semantics.
Authored ORDER/LIMIT is lowered unchanged, but the current common order owner
does not derive total-order evidence for this output and rejects that path with
`UnresolvedOrder` before Run admission. This is a common implementation gap,
not a language restriction or permission to discard the authored order.

`graph_diff(with: target)` uses the same earlier WITH-bound Graph producer resolution
and transitions to an ordinary Relation with the single non-NULL JSON column
`delta`. The left input is the current Graph; `target` is an explicit producer
reference, not a STRING value. Only `delta` enters the new output scope. WITH
reuse does not reconstruct either Graph, and ordinary Relation projection and
filtering keep their existing meaning. The common Delta checker requires the
same complete Graph contract for both operands; the Frontend does not infer
compatible identity domains or implement a difference algorithm.

The checked `graph_diff` operation completes exactly one Delta row. The common
order owner derives logical order from that producer contract and preserves
it through admitted projection, filtering and take operations. A row-count
ceiling alone does not establish order for an arbitrary JSON Relation.
Graph Delta application produces a Graph and establishes no Relation order.
The Frontend does not synthesize a sort, key, scalar encoding or fallback to
publish the JSON value.

`union_graphs` preserves the Graph Carrier and admits the existing scalar or
nonempty-list `with:` form. Each bare/backtick name resolves an earlier WITH-bound
Graph producer; STRING values never resolve Graph names. The current Graph is
the primary operand, followed by each peer in authored list order. Repeated
peer references remain repeated fold occurrences; lowering does not deduplicate
them, reorder them or reacquire their producers.

```aql
WITH combined AS (FROM g |> union_graphs(
  with: [peer, g], merge: {node_properties: {score: 'number_sum'}}))
FROM combined |> node_rows() |> SELECT node_key, score |> RESULT nodes
```

The common union checker owns identity-domain/definition/key/label compatibility
and recursive property contracts. Authored merge strategies are passed unchanged;
no policy is inferred to make a conflict succeed. Sequential fold arithmetic,
parallel-edge identity, atomic failures and operation-wide capacity remain common
owner obligations. The output retains the checked compatible definition names
and can continue into WITH, Graph calls and normal Relation processing after
node_rows/edge_rows. No legacy Graph conversion, implicit Relation conversion,
sort, storage boundary or separate union evaluator is introduced. Empty lists,
undeclared/forward/Relation references, extra arguments and invalid common
policies are preparation refusals. Other Graph-algebra connections and wider
common compatibility are independent coverage obligations.

`subtract_graphs(with: peer, merge: {...})` also preserves the Graph Carrier.
Unlike union, the common subtraction contract is binary: `with:` is one earlier
bare/backtick WITH-bound Graph producer, not a list. The left operand and explicit
merge arguments are retained unchanged. Missing/STRING/Relation/forward peers,
list operands and extra arguments are preparation refusals, not implicit casts.
Without a nonempty strategy map for an entity kind, equal shared payloads remove
that entity; conflicts fail. An explicit strategy such as `exact_equal` instead
retains its transformed entity, including an unchanged or zero property value.
Node and edge policies remain separate. Edges whose endpoints are absent after
node subtraction are removed by the common induced-closure owner; the Frontend
does not implement this rule, infer a non-NULL value from a strategy, or revive
removed nodes. Actual NULL numeric operands fail, rather than becoming zero.
The common checker/owner retains identity, labels, recursive contracts, empty
output types, capacity, cancellation and atomic publication responsibilities.

Other named calls parse but their output Carrier/schema is not yet connected
to subsequent source operations; they return UnsupportedGraph before Run
admission. Calls following a MATCH Relation are also explicitly unsupported
by this first connection. These are implementation gaps, not permanent
language restrictions. Common new-Graph consumer support is an independent
requirement: successful source lowering does not override a common checker
refusal, authorize execution or establish snapshot/replay acceptance. No
legacy Graph conversion or alternate SGA executor is provided.

## Graph pattern source

`FROM GRAPH name` selects an existing Graph value. `MATCH` yields a binding
Relation. Omitting its path mode selects `WALK`, as in the selected GoogleSQL
path-mode profile; explicit `WALK`, `TRAIL`, and `ACYCLIC` retain their meanings.
Default mode changes neither traversal bounds nor supported pattern shapes. It cannot
silently construct a Graph from a Relation, attach to an ambient Graph, or
introduce a second implicit Graph input. One Graph source admits one MATCH;
another pattern needs a separate source and an explicit Relation join.

Labels belong to the admitted Graph definition, separately from
properties. A node label such as `(a:Account)` tests membership in that label
set; it is not equality on an `entity_type` property. Edge labels likewise
come from their definition's label set. The retired `LABELS` property
annotation does not establish a current Graph definition or grant authority.

Full edge patterns `-[]->`, `<-[]-`, and `-[]-` select outgoing, incoming,
and either-direction traversal respectively. Fillers and finite quantifiers
retain the same scope and bounds in each direction. An any-direction pattern
uses the existing logical `traverse` direction `both`; it does not construct
reverse edges or change definition-scoped edge identities. Exact duplicate
paths follow the common traversal contract, including a single self-loop
occurrence rather than two synthetic directional edges. Abbreviated `->`,
`<-`, and `-` have the same meaning as the corresponding full empty edges,
with no variable, label, or local constraint. They use the same finite bounds
and path modes. Use a full edge when a filler is needed. `--` remains a SQL
line-comment introducer, not an alternative any-direction edge spelling.
This selected spelling follows the [GoogleSQL element-pattern reference](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/graph-patterns#element_pattern)
(consulted 2026-10-07); it adds no new Graph execution contract.

A fixed path retains each authored node and edge occurrence. Its
local predicates are evaluated at their demanded prefix: the starting node
over the initial node scope, then each reached edge and node after the
corresponding hop. WALK permits revisits, TRAIL excludes reuse of the same
definition-scoped typed edge key, and ACYCLIC excludes node revisits. Separate paths with
the same endpoints remain separate rows unless the query requests DISTINCT.
The Script frontend passes a fixed pattern's reached-node `WHERE`
or property-map to the corresponding `traverse.hops[i].node_where`. A
qualified receiver names that hop's node variable; it does not capture another
pattern variable. Static candidates follow the edge label and direction and
its declared endpoint definitions. Any-direction hops include both endpoint
definitions as static candidates; the initial selector does not prove a
narrower reached schema. Ordinary checking validates property
presence, types and nullable object access across every reached candidate.
A reached-node label is admitted only when every static candidate carries it;
otherwise the missing per-hop label filter is explicitly unsupported.

A quantified pattern's terminal-node condition remains unsupported: the common
homogeneous `node_where` filters every reached hop, so applying a terminal-only
condition there would incorrectly prune intermediate nodes. Fixed-hop
conditions do not add a new evaluator or implicit node-property projection.

Finite edge quantifiers accept `{n}`, `{m,n}`, and `{,n}`. The fixed form
sets both traversal bounds to `n`; an omitted lower bound is zero. A finite
upper bound must be positive, and an explicit lower bound must be non-negative
and no greater than the upper bound. Bounds must be safe integers and remain
subject to common admission and resource ceilings without clamping. These
spellings follow the selected [GoogleSQL quantified-path syntax](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/graph-patterns#quantified_path_pattern)
(consulted 2026-10-07), within the existing homogeneous edge profile. They do
not add subpath/group-variable support or remove unsupported terminal
conditions. Open upper bounds and named quantified edges remain unsupported.

Graph variables are compile-time binding names. They do not create new
runtime Node, Edge, or Path value types.

Finite traversal bounds, selector ownership and definition-scoped identities
are checked by the common MATCH/TRAIL owner. Graph and Relation resource
ceilings remain separate and partial path output is never published as a
Result. A missing property-selected start gives an empty match, while an
explicit typed identity selector retains its membership-failure rule.

Implementation boundary: the query-only `query_program.Context` carries
Relation inputs, not a constructor definition. It therefore returns
`UnsupportedGraph` for `FROM GRAPH`; the former `GeneratedGraph` /
`CapturedGraph`, `graph_inputs`, and tuple `node_rows` / `edge_rows` generator
are removed. The common current path is an ordinary Program containing the
admitted `graph` constructor and definition-scoped MATCH/TRAIL. The
Script frontend's connection to that path is reviewed separately; syntax
admission alone does not establish that a pattern is executable. Unsupported
pattern bindings or consumers must be refused, not lowered through the
retired representation.

## Bounds, source positions and identity

The lexer bounds input bytes, token count and literal decoding. Parsing bounds
syntax nodes, nesting, CTE count and deterministic work before constructing a
Program. The source builder rechecks total nodes, depth, strings, encoded bytes
and origins. Diagnostics point into the original UTF-8 source; generated
helper names carry generated origins. A failed parse or admission returns no
partial Program. Formatter output may normalize case and spacing but must
preserve the checked Program meaning and explicit query structure.

The Grammar Manifest binds the raw UTF-8 bytes of this document and the query
EBNF separately from the retained expression-text dialect and the structural
text withdrawal policy. There is no structural text fallback or public
Program-to-STEP formatter.
These identities describe the source form. They do not certify that a specific
Run succeeded or that all r1 acceptance cases have been implemented. Changing
either input changes the manifest CID and dependent compiled identities; the
Program contract version remains 0.1.


## Composition assertions, capture predicates and terminal updates

`|> ASSERT UNIQUE BY (path, ...)` is an ActQL spelling of the existing
`assert_rows.unique_by` operation. Paths resolve in the current Relation scope;
ITEM KEY selects an INFER key and does not establish uniqueness. The ordinary
checker and physical assertion owner validate non-null, present, unique tuples
before a consumer can use their key evidence. Assertion success preserves every
row and its order; it never deduplicates. An empty key tuple is rejected.

In the supported equality-key JOIN profile, grouping parentheses around either
key reference preserve the same resolved column or scalar value-table receiver.
`ON (l.id) = ((r.id))` uses the same key mapping as `ON l.id = r.id`, including
conjunctions of keys. Grouping alone does not make arithmetic, a cast, an object
or a whole ordinary row into a supported JOIN key; existing key comparability,
NULL matching, range precedence and output ceilings remain unchanged.

An optional `MAX_OUTPUT_ROWS positive_integer` suffix on each JOIN retains its
existing `max_output_rows` author guard. The integer must be exactly representable
in the safe integer range. Lowering rejects a guard above its admitted frontend
ceiling; it does not clamp it or replace it with a Host resource limit. Omitting
this suffix retains the existing frontend default. Each JOIN occurrence keeps
its own guard, including a JOIN chain and a JOIN inside a WITH body.

A leading ordinary WHERE on a single-use acquired WITH input is retained at the
Host-selected capture boundary and removed from the downstream pipeline so that
it runs once. This uses the same filter expression owner as standalone queries.
If any other consumer refers to the installed input, its complete capture is
shared and each WHERE remains downstream. Analysis is conservative across WITH,
CTE, set, constructor and query references; it cannot narrow another consumer's
capture or silently reacquire a shared Source. Projection remains downstream.
There is no separate scan-predicate language.

The terminal update spelling is:

```aql
|> EFFECT save UPDATE
   TARGET 'connector://crm-main/Test_Record__c'
   MAPPING `mapping:published-reference.v1`
   FROM RESULT updates ID target_id SET (Name = next_name)
```

EFFECT is a declaration after the query's row operations, not another row
operation. It must be terminal and is not admitted in WITH bodies. Its
name may be omitted for this single terminal UPDATE: `EFFECT UPDATE`
lowers with the fixed Program-local name `aql_update_effect`. An explicit name
is preserved exactly and remains identity-bearing; an invalid empty name is
not omission. The omitted form and explicit `aql_update_effect` form normalize
identically under the same bindings and output contract, independently of
whitespace or source offsets. A second terminal Effect is rejected. Command
postludes may follow the query terminator; their names remain explicit and
unique across the complete Effect Set, including the completed terminal name.

`FROM RESULT name` may be omitted. Omission consumes the current checked
Relation, after its authored row operations, through a closed stage-local private
Result. The explicit form selects its actual retained producer, even when a
later filter, rename, projection or Stage continuation has changed the current
Relation. A step alias or undeclared Result is not an explicit Result selection.
No Source or Model is acquired again to prepare either input.

SET requires one nonempty assignment list. Its values may use the existing pure
typed SQL expressions. All assignments see the same selected input snapshot;
a target assignment is not a binding for another assignment. Computed values
lower through the ordinary Relation derive/select owners before the private
Result is captured. The Effect receives only evaluated fields or literals,
never an expression to evaluate at dispatch. Nested property access, successful
INFER refinement, NULL and absence, CASE demand, numeric admission and work and
capacity limits retain their existing meaning. Duplicate target fields,
unresolved or ambiguous references and unavailable functions are rejected.
Literal strings retain their original Unicode and CR/LF values through the
ordinary string decoder. The existing explicit FROM RESULT form containing only
direct fields or scalar literals keeps its original lowering and identity.

A generated UPDATE Result contains only its selector and SET fields. It is not
an exported Named Result, and its private helper columns do not widen an
authored public Result. With no authored public RESULT, the Program-root
`results` map is empty and no unused full-row default Stage Result is created.
An authored terminal RESULT remains public without an additional default
export. An authored nonterminal RESULT retains the existing public primary tail
export as well as the authored Result, including across an INFER continuation.
Public inventory, describe, read and inspect do not grant access to private
capture payloads or helper columns. Plan/Debug projections keep their separate
capabilities and current-authority rules. Effect-only completion is Run status
and receipts with zero Named Results; no read result is fabricated.

The private capture uses the existing Stage Result and `effect.update.from.result`
contracts, never Table `table_inputs`. Its expanded private-output Program has
the same identity as this normalized spelling; an explicitly public RESULT has
different observables and identity. Existing checker, Mapping, planner, preview,
approval, durable capture and cleanup owners remain authoritative. Preparation
failure produces no partial Preview or write. Approval and restart consume the
same sealed values without reevaluation or repeated acquisition, Model work or
confirmed Effects. Syntax admission does not establish those runtime outcomes
or authorize execution. The long TARGET/MAPPING form remains available;
the short forms below resolve to the same existing owners.

### Short Effect forms and SQL statements

The checker MUST resolve each short `conn.resource` or `conn.operation` form
against the selected connection's published contracts, refusing unknown,
ambiguous, type-incompatible or unauthorized bindings before acquisition.
The author does not name a Mapping in the short form; a published logical
UPDATE target may carry an explicit `MAPPING` as described below. Explicit long
forms select among multiple published contracts without broadening their
authority.
Normalization records the resolved target, contract and installation identity.

The admitted terminal forms are:

```text
|> EFFECT [name] UPDATE conn.resource ID key SET (field = expr, …)
|> EFFECT [name] INSERT conn.resource (field, …) [VALUES (expr, …)]
|> EFFECT [name] UPSERT conn.resource ID key SET (field = expr, …)
|> EFFECT [name] DELETE conn.resource ID key
|> EFFECT [name] STORE conn.resource [SET (field = expr, …)]
|> EFFECT [name] COMMAND conn.operation [TARGET expr] ID key [INPUT (field = expr, …)]
```

These forms MUST consume the current checked Relation through existing private
Stage Result capture, evaluating pure expressions before Preview and preserving
explicit public Results without inventing a public Named Result.
INSERT without VALUES maps same-named input columns; with VALUES, its lists
have equal arity. UPDATE and UPSERT use the declared record key; DELETE carries
no SET fields. Omitted single-terminal names are completed deterministically
by Effect kind, with UPDATE retaining `aql_update_effect`; explicit names remain
identity-bearing and unique across terminal and postlude declarations.
INSERT's target-field list is represented by the canonical `create.values`
map over that same captured Result. The original Mapping is retained rather
than trimmed to its default row mapping or replaced by an inferred declaration;
omission, typing and write authority follow the create contract in language.md.

Object, file and stage STORE MUST require a typed `content_ref` for each output
object, with destination and overwrite fields checked by the published write
Mapping; rows without content are refused rather than implicitly serialized.
Content may come from SERIALIZE or an admitted contents Source. A declared
table resource instead accepts its typed rows. SET fields are evaluated inputs,
not codec options: `format` does not turn rows into Content. The sealed Preview
fixes the destination, exact content identity or row scope, and overwrite guard.

A short COMMAND MUST resolve to exactly one versioned Command contract, require
TARGET when that contract needs a per-row ResourceRef, and refuse TARGET when
the contract fixes the target.
ID identifies the input operation row in Preview, status and recovery; it is
not a recipient or a substitute for the Command's target-plus-payload identity.
Optional INPUT is checked against the contract, including an empty input.

SQL UPDATE, INSERT INTO and DELETE FROM MUST lower to the same update, create
and delete Effects as the terminal forms, with the same checks and approval.
For UPDATE and DELETE, key equality addresses the key directly; any other
WHERE selects identities and versions at Preview time. Apply consumes that
fixed set and never re-evaluates WHERE to add newly matching records. A Connector
unable to fix identities and apply-time conditions refuses the form at check.
A changed apply-time condition produces `failed` with `conflict`, not a refreshed
Preview, automatic resend, or a silently omitted row.

### Published logical UPDATE targets

A terminal UPDATE can instead name a Host-published logical target, with an
optional explicit Mapping:

```aql
|> EFFECT save UPDATE crm.records
   FROM RESULT updates ID target_id SET (Name = next_name)
```

```aql
|> EFFECT save UPDATE crm.records
   MAPPING `mapping:published-reference.v1`
   FROM RESULT updates ID target_id SET (Name = next_name)
```

The logical path contains at least two identifier components. It uses the
published Relation-name rules: each unquoted component matches without ASCII
case, while a quoted component requires exact spelling. It is not inferred
from a Source alias, a query input, a Connector name or a Mapping's spelling.
The explicit `TARGET 'uri' MAPPING identifier` form keeps its existing meaning
and still requires MAPPING. The optional Effect name, selection of an explicit retained Result or the
current Relation, ID field and nonempty pure typed SET list reuse the preceding
UPDATE rules. Target resolution does not change input selection, expression
preparation, the existing direct-field/literal identity guarantee, or the
distinction between public Results and private capture.

The trusted installed Effect profile publishes
`queryUpdateTargets: [{name, targetRef}]`. Loading that profile produces an
owned publication bound to its `installationBindingCid` and exact
CheckEnvironment owner, together with `installationOwnerCid`, the canonical
CID of the existing installed row-effect owner's `installationFacts` snapshot.
The physical binding and complete owner identity remain distinct. A
caller-authored object or an equal-CID foreign
environment cannot replace that publication. This is a connection to the
existing installation and Mapping owners, not a second target registry or a
new static write Capability. A missing, duplicate or ambiguous logical binding
is refused before a Program is issued.

After resolving the target, omitted MAPPING requires exactly one installed,
structurally valid Mapping for that exact target whose existing operation and
identity contract supports UPDATE by ID. Candidate discovery considers the
complete installed Mapping collection independently of the current grants and
authored SET fields. It does not select the first candidate, rank names, use
field compatibility to break a tie, or remove an unauthorized candidate to make
another one unique. No candidate, multiple candidates, or an incomplete or
invalid target Mapping declaration causes refusal. An explicit MAPPING retains
its exact reference and must be installed, valid, UPDATE/ID-compatible and bound
to the resolved target; it cannot redirect that target.

Resolution emits the same concrete target and MappingRef in the ordinary Stage
update Effect. Equivalent explicit-target and logical-target forms normalize
to the same Program under the same environment, installation publication,
Effect name, input-selection form, SET expressions and output contract. This
preserves the identity distinction between an authored public Result and an
omitted FROM RESULT using private capture. Target spelling is not extra Program
meaning.
The ordinary capability, type, ID, SET, current authority, preview, approval,
read-denial and Effect checks still apply after selection. A logical publication
does not make a write-only Resource readable or authorize acquisition or dispatch.

Execution and recovery retain the original Stage/Effect occurrence, concrete
target, Mapping reference and CID, Check Environment, physical installation
binding and complete installed-owner CID in the existing compilation material.
Equivalent full and short forms in the same selected context have equal
selection bytes; alias spelling is excluded. Restoring a saved concrete Program
and Check Environment uses those originals even if an alias was subsequently
removed or changed. Current exact installed-owner, grants, approval, lease and
dispatch fences still apply. Restore does not re-resolve aliases, reselect
another candidate or resend an unknown outcome. Source
admission and identity fixtures alone do not establish those public execution
or recovery connections, which require separate acceptance evidence.

Implementation boundary: installed alias metadata and pure frontend completion
are separate from durable Run custody. Until coordinated activation of the
existing Run owner's original-selection retention and rechecks, normal Host source preparation
withholds the logical UPDATE publication. Logical UPDATE is therefore refused
before Provider work on that path; the explicit TARGET/MAPPING path remains
available under its existing checks. This fail-closed boundary is an outstanding
implementation obligation, not a permanent restriction of the adopted syntax.

### COMMAND postludes

An explicit COMMAND declaration follows a semicolon-terminated query:

```aql
FROM files.transfers |> SELECT destination, name, content |> RESULT transfers;
EFFECT upload COMMAND
  FROM RESULT transfers AS t
  TARGET t.destination
  CONTRACT `command:files.upload.v1`
  INPUT (name = t.name, content = t.content);
```

SQL uses the same postlude after its SELECT or WITH query; WITH and FROM-first
Pipe statements use the public `aql-text` format (the frontend's `Text` form).
The postlude refers to an explicit retained Result, not a Source alias or a
pipeline step. Qualified
fields use that declaration's Result alias. TARGET and INPUT use existing
EffectValue fields or scalar literals; computed expressions are refused and
belong in the preceding Relation pipeline. Unknown Result names, foreign
aliases, unknown fields, duplicate Effect names and duplicate INPUT fields are
rejected. An empty INPUT list remains subject to the declared Command schema.
Command postludes may accompany one terminal record, store or Table Effect.
All declarations in the text are checked as one Stage and one Effect Set,
with one Checkpoint when approval is required. They do not imply execution
ordering between members; dependent work uses separate Stages. Both the query
separator and each postlude terminator are required.

Lowering emits the existing `command` Effect with its original Result port,
ResourceRef target, CommandContractRef and typed input. The common checker
validates the target kind and input schema; parser success does not issue a
ResourceRef, grant write permission or approve a Command. Preview, current
authority, approval, durable send entry, saved outcome, unknown non-resend and
cleanup remain with their existing owners. ContentRefs are references to owned
bytes, not arbitrary bytes authored in the postlude. Retained Model Results
cross an ordinary Stage Result edge before a downstream COMMAND continuation;
the continuation does not re-acquire or re-evaluate that Model producer.

## Table create and whole-table replace

The initial Table write surface is:

```sql
CREATE TABLE analytics.report AS SELECT id, p FROM source;
CREATE OR REPLACE TABLE analytics.report AS (SELECT id, p FROM source);
FROM source |> SELECT id, p |> CREATE TABLE analytics.report;
FROM source |> SELECT id, p |> EFFECT save CREATE OR REPLACE TABLE analytics.report;
```

A Table path resolves against an explicit Host-published write binding to the
existing Connector Resource, Mapping and Capability. It is not a Source alias
and confers no authority by itself. Unknown, ambiguous and action-incompatible
targets are rejected by checking before acquisition or dispatch. Table writes
are terminal and cannot occur in WITH bodies or another Table write's input.

CREATE selects only a fixed create binding. CREATE OR REPLACE selects the
single published create or replace operation; it does not observe the Catalog
to choose one. A create conflict remains a conflict under OR REPLACE and does
not switch to replace. Authored intent, selected operation, target, Mapping,
Capability, installation binding and expected Table identity/generation form
checked meaning and approval. Execution and recovery recheck that binding;
conflicts do not refresh the expected generation, change candidates or resend
unknown operations. Catalog commit checks absence for create and exact approved
identity/generation for replace.

Lowering uses the existing store Effect and private Table capture. It preserves
absence, explicit NULL and actual values without creating an implicit public
Relation. A save-only checked Effect Program has `results: {}` under the common
Effect-only Program contract; ordinary Named Results remain all-Required.
When an earlier `RESULT name` precedes further row operations, that Result keeps
its original rows and schema, while the private Table input consumes the final
Relation. CREATE and REPLACE export exactly the authored public Results; they do
not add the configured primary export for that private consumer. A terminal
authored Result still names its retained Relation. Ordinary SQL and UPDATE keep
their existing primary-tail behavior.
Initial support is Relation create and same-schema whole-table replace using
the installed writer's admitted types. Syntax does not authorize a write.
Append/upsert, schema evolution, automatic Catalog observation and other Carrier
writers are separate implementation units.


### Named finite event sequences

The adopted ActQL Pipe call `sequence` lowers through the existing common
[sequence contract](language.md#sequence). `pattern` is a finite list of
`{as: OutputName, where: Expression}` records. The predicate is parsed once from
the original query tokens, retaining its opaque source Expression owner, spans
and charged work. String-valued predicates are String expressions, not reparsed
SQL; structured JSON is not a second source-expression language here.

```aql
WITH records AS (
  SELECT 1 AS id, 0 AS occurred_ms, 1 AS kind
  UNION ALL SELECT 2, 10, 2
)
FROM records AS e
  |> sequence(by: [], id: e.id, time: e.occurred_ms,
       pattern: [{as: first, where: e.kind = 1},
                 {as: second, where: e.kind = 2}],
       within: 20, overlap: 'disallow', contiguity: 'adjacent',
       max_matches_per_key: 2, max_output_rows: 2)
  |> SELECT first_id, second_id |> ORDER BY first_id;
```

Closed keys are `by`, `id`, `time`, `pattern`, `within`, `overlap`, `contiguity`,
with `by`, `overlap`, `contiguity`, `max_matches_per_key` and `max_output_rows`
optional in the authored form. Omitted grouping and modes complete to `[]`,
`'disallow'` and `'adjacent'` at check time; the closed canonical body stores
them explicitly. `within` remains required. Required membership,
pattern length, generated-name collisions and clock/identity validity remain
with the common checker. `by`/`id`/`time` are ordinary current-row FieldRefs;
label names use ordinary OutputName reserved/quoted-name rules. The original
scope and Parameters are available to every predicate. Earlier labels never
introduce input fields into a later predicate. CASE, property access, NULL and
other ordinary expressions keep their existing typing/evaluation contracts;
only Boolean true matches. Whole Parameters for within and guards retain
existing binding and validation obligations, with no substituted defaults.

Relation and Events inputs return a Relation through the existing sequence
owner. On Events the explicitly named clock must be a non-null number payload
field; the common event carrier does not synthesize `event_time_ms` inside its
record schema. An explicit events() bridge has its own output fields and does
not justify rewriting an authored sequence clock. Empty outputs retain the
complete match schema. No evaluator, capture owner, identity or resource
quantity is created by this syntax connection.

### Named temporal correlations

The adopted ActQL Pipe calls `asof_join` and `interval_join` lower to the
existing two-input TEA operations. Their `with:` value is a bare or backtick
lexical producer reference, never a String containing a producer name. The
current producer is the left operand. It is resolved and retained through the
ordinary binding/capture Owner; a shared input is not acquired again.

```aql
WITH ticks AS (SELECT 1 AS id, 10 AS at),
  spans AS (SELECT 7 AS id, 5 AS begin, 15 AS finish)
FROM ticks AS t
  |> interval_join(with: spans, kind: 'left', mode: 'point_in_interval',
       on: [], left: {time: t.at},
       right: {start: spans.begin, end: spans.finish},
       select: {id: left.id, value: right.id}, max_output_rows: 3)
  |> SELECT id, value |> ORDER BY id;
```

`asof_join` accepts exactly `with`, `kind`, `by`, `left_time`, `right_time`,
`direction`, `tolerance`, `select`, and optional `left_id`, `right_tie_break`.
`interval_join` accepts exactly `with`, `kind`, `mode`, `on`, `left`, `right`,
and optional `select`, `max_output_rows`. Required/optional membership follows
[the common as-of contract](language.md#asof-join) and
[the interval contract](language.md#interval-join), including kind restrictions.
No default tolerance, identity, pair or output guard is inserted by this surface.

The pair-list `left` and `right` fields, temporal-record fields, `left_id`,
`left_time`, `right_time` and `right_tie_break` retain typed FieldRef roles.
Unqualified references use the signature's operand. The corresponding fixed
`left.field`/`right.field` qualifier is allowed; left fields may use the current
row alias and right fields the resolved `with` producer qualifier. A current
row alias takes priority over a same-name WITH producer. A qualifier for the
other operand is rejected instead of looking up a coincidentally named column.
`select` uses ordinary OutputNames, including the existing reserved/quoted-name
rules, mapped to explicit `left.field` or `right.field` selectors.
Repeated pairs and tie-break fields retain their authored order and occurrence.

Whole Parameters for tolerance and output guards retain their existing common
binding obligations. As-of admits Relation or Events on the left and Relation
on the right, returning a Relation; interval joins require two Relations.
The common checker owns Carrier/type/NULL contracts, identity/tie completion,
endpoint validation, logical order, bounds and pending value/resource evidence.
Text lowering does not establish backend execution or external coverage.

### Named ranking fusion

`merge_rankings` is the adopted ActQL logical Pipe call for the existing
[common ranking-fusion contract](language.md#merge-rankings). It consumes the
current Relation and names earlier lexical peers with `with:`. A bare/backtick
name is a ProducerRef; a String containing that name is not a reference.

```aql
WITH first AS (SELECT 1 AS id, 1 AS position),
  other AS (SELECT 2 AS id, 1 AS position)
FROM first AS current
  |> merge_rankings(with: [other, other], by: [], candidate: current.id,
       rank: current.position, k: 3,
       score_policy: {rrf: {rank_constant: 1, weights: [1, 2, 3], rank_window: 2}})
  |> SELECT id, score, rank |> ORDER BY rank;
```

The closed argument keys are `with`, `by`, `candidate`, `score`, `rank`,
`score_policy`, `score_contract`, `k` and `tie_break`. Common policy checking
selects required/forbidden members. `by`, `candidate`, `score`, `rank` and
`tie_break` use ordinary current-row FieldRefs, including the existing explicit
row-alias and quoted-field rules. Closed policy/score-contract keys are signature
vocabulary; their authored String values, numeric values and list order are data.
Repeated group/tie fields are retained until common checking.

Max and weighted_sum use one peer. RRF may use a nonempty flat list. The current
input occurs first, followed by every authored peer occurrence in list order.
Binding/capture storage is shared by the existing owner, while repeated
references remain separate weighted inputs in the ordinary Program and Plan.
The frontend never deduplicates the RRF list, reweights it, substitutes k for a
rank window, or changes the floating-point fold. An empty list is not a default.
The common owner checks complete ranks, keys, domains, weights and all work,
value, ordering and retained-state bounds before publication.

For max/weighted_sum, `score_contract` does not authenticate arbitrary raw
number columns. The common retained score-declaration evidence is still
required. Literal Values with only number fields are rejected with the existing
MissingScoreContract condition. Score snapshot reconciliation and the frontend
check-only Context must preserve that evidence before a positive public
score-fusion claim is made. This is a remaining connection requirement, not a
new language restriction or permission to invent a declaration. Pure RRF does
not require score-scale comparability; its own complete-input obligations remain.

### Optional named Calendar operations

`calendar_bucket(time: field, unit: string, timezone: string, into: name,
week_start: string?)` is an adopted Relation Pipe call. `calendar_series(start:
value, end: value, unit: string, timezone: string, week_start: string?)` is a
NONE-input Relation generator, using the existing producer-primary/WITH path.
Both retain the optional [Calendar profile](language.md#calendar). No default
profile, host locale, ambient timezone database or fixed-duration approximation
is supplied by the frontend.

```aql
WITH days AS (
  calendar_series(start: '2000-01-01T00:00:00.000Z',
                  end: '2000-01-03T00:00:00.000Z',
                  unit: 'day', timezone: 'UTC')
)
FROM days AS d
  |> calendar_bucket(time: d.start, into: month,
                     unit: 'month', timezone: 'UTC')
  |> SELECT start, `end`, month
  |> ORDER BY start
```

`time` uses the ordinary current FieldRef resolver and `into` the reserved/
quoted OutputName rule. `unit`, `timezone` and `week_start` are exact decoded
literal strings. `week_start` is required for week and forbidden for other
units, including explicit NULL. Series endpoints retain literal timestamp or
whole non-null timestamp Parameter roles; year/range/bound checks belong to the
existing common owner. A generator cannot consume a Pipe input. Fixed signature
key `end` remains available; the ordinary leading column name `end` must be
quoted. Public Result fields retain authored projection order separately from
canonical object-schema order.

Trusted source Contexts carry the exact optional SelectedCalendarProfile from
the existing CheckEnvironment. Actual Catalog and ModelTask owners must agree
with that environment. The frontend neither reacquires TZDB bytes nor asserts
physical execution capability. Missing profile remains a common refusal;
foreign same-CID profile owners are not accepted through a published Catalog.
Source/checker connection does not establish an installed Calendar runtime:
current physical lowering and normal Host profile installation must be verified
separately.

## Refused GoogleSQL Pipe forms

The closed set of specifically refused GoogleSQL Pipe forms in this profile
is `|> CALL`, standalone `|> WINDOW`, `|> TABLESAMPLE` and
`|> ASSERT condition`. Each is rejected with `query_syntax_invalid` from the
public check Reason catalog, with an original source location when available.
The WINDOW clause inside SELECT or EXTEND remains admitted. ActQL's
`ASSERT UNIQUE BY` and JOIN `MAX_OUTPUT_ROWS` retain their separate contracts;
they are not aliases for the refused general ASSERT form.
