# Query text profile

The [query grammar](../../spec/grammar/actql-query-0.1.ebnf) describes the
GoogleSQL-derived SQL and Pipe surface of ActQL 0.1. It is a source form for an
ordinary Program, not a separate execution model. Parsing and lowering do not
authorize an input, certify a Plan, or bypass ordinary Program admission and
the common checker. The grammar alone does not promise every form is
currently executable. The [frontend design mapping](../design/frontend-r1.md)
records implemented boundaries and intentional differences.

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

Double quotes do not quote identifiers: `"id"` is a value, while `` `id` `` is
a name. The explicit Graph `LABELS` annotation retains its separate historical
double-quoted annotation profile; accepting double-quoted query literals does
not expand that profile's escapes or admit raw control characters in it.
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
its final order. CTE and DATA relations use their current declared columns.
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
parameter. Names lower to the ordinary `take.count` and `take.offset` Parameter
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
accept an integer literal or a whole named parameter, for example
`ROWS BETWEEN @before PRECEDING AND @after FOLLOWING`. Direction remains
syntax; the parameter is lowered to the common `preceding`/`following`
Parameter slot. Declarations and bound values use ordinary Program checking,
including safe-integer and interval-order validation; no default replaces a
missing or invalid binding. This connection retains the current common
contract's positive distances. GoogleSQL also permits zero numeric boundaries;
that difference remains a common-contract coverage gap, not a restriction of
GoogleSQL. Row-dependent and arithmetic boundary expressions, RANGE and GROUPS
are not implemented in this profile.

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
a Relation or DATA producer. CTEs, derived tables and set operands each have
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
the common checker and operations. DATA and CTE sets use the same rules without
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
DATA queries. This applies to standalone SQL/Pipe, nested set operands and
CTE bodies. JOIN predicates, key mappings and declared output ceilings remain
with the existing JOIN lowerer; final ORDER BY/LIMIT sees only the combined
output. Input binding does not add another source read or materialization.

WITH may precede either a SELECT query or a FROM-starting Pipe query. A CTE
body, FROM/JOIN table subquery and parenthesized query operand use the same
relational query composition: SELECT or FROM-starting Pipe, set expressions,
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
inside a DATA query body may instead reference an existing pipeline step;
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
Those forms remain unsupported by the current membership expression profile,
not invalid GoogleSQL. An ordinary SELECT ARRAY remains an `array` expression.

`[expression, ...]` and `ARRAY[expression, ...]` preserve the authored element
order and duplicates through the ordinary finite `array` expression. Elements
use the common checker for compatible types, NULL context, parameters and
constructor capability checks; the Frontend does not stringify values or
infer a second type system. The parser's existing work, node and depth limits
also cover array children. An empty list needs unique type context.

The explicit annotation subset is `ARRAY<BOOL>`, `ARRAY<BOOLEAN>`,
`ARRAY<STRING>`, `ARRAY<FLOAT64>`, `ARRAY<DOUBLE>`, `ARRAY<TIMESTAMP>` and `ARRAY<JSON>`.
Annotations use the existing typed `empty_array.items` evidence. A nonempty
annotated array uses an ordinary constant-true lazy `if` with that empty-array
peer, so the common checker checks the declared item type and evaluates the
actual elements once. It does not add an element CAST. NULL elements retain
their nullable contract even when the annotation provides a nonnullable peer.

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
`ARRAY<INT64>`. Those are coverage gaps here: the common constructor capability
contract currently rejects JSON item types, and the selected finite Number
profile does not establish exact INT64 semantics. Additional type annotations
remain explicitly unsupported; an unresolved `[]` is not silently assigned
Number or JSON. The source and independently authored Program rejection of
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

The adopted INFER Pipe form has mandatory `ITEM KEY`, `INPUT`, and result
`AS` clauses, with optional `KEEP`. The contract name is carried unchanged
to ordinary `infer.contract` resolution in the same Check Environment;
backticks can delimit a complete existing reference such as
`model-task:risk-score.v1`. Parsing a name does not resolve a ModelTask, select
a newer version, or authorize model egress. An empty INPUT is checked against
the resolved closed input contract, not treated as permission to omit fields.

KEEP accepts column references, optional output aliases, and known-schema
`*` or range `.*`. Expansion retains visible declaration order, and explicit
items retain authored order. Calculations belong in SELECT or EXTEND.
Duplicate output names, a collision with the result AS name, unresolved
references, and repeated ITEM KEY value slots are rejected. The common checker
still proves the complete non-null scalar candidate key; specifying ITEM KEY
never supplies that proof. Only INPUT mappings are sent to the model.

The new visible scope consists of KEEP columns followed by one result object:
`input_key` (named fields in the authored key tuple), `outcome`, and `value`.
Omitted KEEP produces only that object. Prior range aliases cannot recover
omitted input fields. KEEP is a checked one-to-one correspondence with the
same retained input producer, not a new read or a row-position join. The common
infer output remains flat keys, outcome and value. Ordinary join and object
projection construct the surface shape without changing its capture format.

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

NEAREST consumes the current Relation as queries and an explicitly named
candidate Relation. The candidate range alias, QUERY KEY and VECTOR, CANDIDATE
KEY and VECTOR, METRIC, positive safe-integer literal K, and result AS are
mandatory. Metrics are the existing exact cosine, dot and negative-distance
l2 contracts. K is per query, not a search-work or memory ceiling.

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
Omitted KEEP yields only that result object. Old input aliases cannot recover
omitted columns. Query values repeat for each retained candidate match; no
match produces no row. Query-key-only uniqueness is never inferred after KNN.

Lowering retains each source producer once, uses the existing rows-to-Vectors
bridges and nearest operation, then common many-to-one joins for KEEP and
ordinary object projection. Explicit candidate selection cannot be replaced
by the filtered query Relation. Shared sources retain one capture boundary
covering both demands under the ordinary grant and capacity checks. No read
permission, synthetic ID, output key witness, implicit sort, retry or alternate
execution engine is supplied by the frontend. The flat pair key remains common
owner evidence; nesting its values does not declare an arbitrary object key.

Implementation support is currently source construction for a linear Relation
Pipe with singleton keys. Composite-key syntax is adopted, but its lowering
reports UnsupportedNearest until the common Program bridge can express that
identity tuple. Combining NEAREST with CTE/set/JOIN query assembly is also
pending and explicitly rejected. These are implementation gaps, not permanent
language restrictions. Object/property execution is a separate common-owner
dependency; source construction and type checking do not claim packed Host
execution or successful publication.

## Logical DATA and pure Graph construction

The AQL-text source grammar admits logical `DATA name = expression;`
bindings followed by a query; SQL format retains its query-only entry.
DATA names reference producers and do not create acquisition, storage,
placement or physical task boundaries. Bodies resolve before the declared
name becomes visible. Duplicate, recursive and forward references are
rejected. A Graph producer is not a Relation alias. RESULT, INFER and EFFECT are
not permitted in a DATA query body; final queries retain explicit Results.

A DATA body can bind an explicitly projected Graph MATCH Relation, for example:

~~~aql
DATA selected = FROM GRAPH g |> MATCH WALK (a:Node) |> SELECT a.score AS score;
~~~

The projection defines its public columns; Graph pattern variables and internal
identity/path slots are not visible through the DATA name. Normal Relation
processing can then reuse that producer. The existing keyed MATCH/TRAIL checker
and execution owner retain identity, label, predicate, path and capacity rules.
This DATA connection does not expand Graph CTE or derived-table support.

`DATA g = PROPERTY GRAPH (...)` is an ActQL pure-value extension using the
[selected GoogleSQL/SQL-PGQ mapping profile](../design/frontend-standard-profiles.md#graph-mapping-and-element-identity).
It does not create a Catalog object or claim ISO GQL constructor syntax.
Relation producers, element-definition names and labels are separate.
REFERENCES resolves the element definition and its ordered KEY columns.
Typed keys, independently keyed parallel edges, Graph-owned label sets,
Graph-wide property types and same-label property sets belong to the
common Graph contract. The Frontend cannot issue those checked facts,
replace static labels with property predicates or discard edge identity.

DATA query bodies use existing query-expression lowering, including supported
CTE and set forms. An acquired Relation retains its original input declaration
and the Host-selected capture boundary. Multiple references to that input use
the same prepared producer; a DATA or CTE binding does not acquire it again.
Constructor input paths follow the published source name rules before being
bound to those producers. A schema declaration alone does not supply the
admitted Source View provenance required by the common Graph checker.

Frontend preparation passes the constructed Program to the common checker;
it cannot substitute its own Graph admission or execution. Source construction
and checking alone establish neither execution nor snapshot support. No
conversion to the old simple-Graph contract is permitted. SQL, Pipe, DATA and
CTE INNER/LEFT/CROSS JOIN chains retain each range's column scope while lowering
to ordinary bounded JOIN operations. ON resolves only preceding ranges and
the current right input; USING shares an unqualified key without discarding
either qualified input column. Projection and ORDER BY reuse the normal output
alias and evaluated-slot rules. FULL JOIN chains still require an adapted
stable-row identity/coalescence path; they are explicitly unsupported rather
than approximated. Unused CTE checking without scheduling acquisition and standalone Stage
references without their producer definitions remain explicit implementation
gaps. These are support limits, not permanent restrictions of the target
language.

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
`start: "A"` is a value and `field: "delta"` designates a column. Relation
selectors in reach/traverse `start.from`, shortest_path `source.from` and
`target.from`, and subgraph `nodes.from` use producer references. Bare and
backtick producer names follow the existing DATA resolution rules; String
values cannot name producers. A mean_graphs `with` list is explicit and does
not silently acquire an additional current input. Duplicate input
specification must be rejected rather than merged or ignored.

Operation and selector vocabulary is case-insensitive. Object-valued data
retains its own field names and decoded values. Numeric tokens retain their
exact spelling until normal numeric admission. The same lexical, syntax,
work and depth budgets apply to calls inside a query and a DATA body.

A Graph-preserving query can bind its producer through DATA or precede a
Graph MATCH. For example:

```aql
DATA normalized = FROM g |> normalize_graph();
FROM GRAPH normalized |> MATCH WALK (a:Node) |> SELECT a.id
```

This lowers to the existing normalize_graph step on g and the existing
definition-selected MATCH on its output. DATA does not copy the Graph,
reacquire its inputs, add a Result or request materialization/physical
placement. The normalization has no named options; extra arguments are not
discarded. Unconsumed Graph calls cannot pass through relational compilation.

The Frontend also connects the existing `node_rows()` and `edge_rows()`
Bridge operations to ordinary Relation processing. Use a constructor-bound
DATA producer, for example:

```aql
DATA rows = FROM g |> node_rows() |> SELECT node_key, labels;
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
use normal scope, expression, order and Result lowering. DATA adds no copy,
acquisition or execution owner. A Graph-preserving normalize call still needs
an adapted common consumer; source lowering alone does not authorize it.

The existing Graph diagnostic operations also enter ordinary Relation processing:

```aql
DATA stats = FROM g |> degree(direction: "out");
FROM stats |> WHERE degree > 0 |> SELECT node, degree |> RESULT active
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
The Relation scopes are exactly `node, degree`, `kind, node_id, actual, max`, and
`node_id, component_id, component_size`, respectively. Graph identity types,
nullable bounds `node_id`, component identity/order, selected capacity and
atomic guard failures follow the existing machine contracts. DATA reuses the
producer; old Graph columns do not reappear after the Relation transition.
These source connections do not establish support for other Graph operations
or waive the common admission and execution obligations.

Both emissions of `traverse` enter ordinary Relation processing:

```aql
DATA seeds = FROM g |> node_rows() |> SELECT id AS element;
FROM g
  |> traverse(start: {from: seeds, id: 'element'}, direction: 'out',
              min_hops: 0, max_hops: 2, path_mode: 'trail',
              emit: 'nodes', max_output_rows: 10)
  |> SELECT start_id, node_id, depth |> ORDER BY depth |> RESULT visited
```

`start.from` resolves an earlier DATA Relation producer, including a
backtick-quoted DATA name. Its `id` names a column containing the common
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
proof is manufactured by the Frontend. A DATA binding of that output can
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
Relation can bind DATA and continue through normal WHERE, SELECT, ORDER and
LIMIT; omitted Graph fields and further Graph calls are unavailable.

`graphs_equal` also enters ordinary Relation processing:

```aql
DATA same = FROM g |> graphs_equal(with: g);
FROM same |> SELECT equal |> RESULT comparison
```

The required `with:` argument resolves an earlier DATA Graph producer using
the existing DATA naming rule, including backtick-quoted names and bindings
that retain a producer. A string is not a producer reference. The left input
is the current Graph, including a preceding `normalize_graph()` output;
resolving the right input does not reconstruct, acquire or copy either Graph.
Unknown/forward references, Relation inputs, missing or extra arguments and
a second Graph call after the Relation transition are explicit preparation
refusals. A DATA binding of the comparison can continue through the ordinary
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

`graph_diff(with: target)` uses the same earlier DATA Graph producer resolution
and transitions to an ordinary Relation with the single non-NULL JSON column
`delta`. The left input is the current Graph; `target` is an explicit producer
reference, not a STRING value. Only `delta` enters the new output scope. DATA
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
nonempty-list `with:` form. Each bare/backtick name resolves an earlier DATA
Graph producer; STRING values never resolve Graph names. The current Graph is
the primary operand, followed by each peer in authored list order. Repeated
peer references remain repeated fold occurrences; lowering does not deduplicate
them, reorder them or reacquire their producers.

```aql
DATA combined = FROM g |> union_graphs(
  with: [peer, g], merge: {node_properties: {score: 'number_sum'}});
FROM combined |> node_rows() |> SELECT node_key, score |> RESULT nodes
```

The common union checker owns identity-domain/definition/key/label compatibility
and recursive property contracts. Authored merge strategies are passed unchanged;
no policy is inferred to make a conflict succeed. Sequential fold arithmetic,
parallel-edge identity, atomic failures and operation-wide capacity remain common
owner obligations. The output retains the checked compatible definition names
and can continue into DATA, Graph calls and normal Relation processing after
node_rows/edge_rows. No legacy Graph conversion, implicit Relation conversion,
sort, storage boundary or separate union evaluator is introduced. Empty lists,
undeclared/forward/Relation references, extra arguments and invalid common
policies are preparation refusals. Other Graph-algebra connections and wider
common compatibility are independent coverage obligations.

`subtract_graphs(with: peer, merge: {...})` also preserves the Graph Carrier.
Unlike union, the common subtraction contract is binary: `with:` is one earlier
bare/backtick DATA Graph producer, not a list. The left operand and explicit
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
its own guard, including a JOIN chain and a JOIN inside DATA or a CTE.

A leading ordinary WHERE on a single-use acquired DATA input is retained at the
Host-selected capture boundary and removed from the downstream pipeline so that
it runs once. This uses the same filter expression owner as standalone queries.
If any other consumer refers to the installed input, its complete capture is
shared and each WHERE remains downstream. Analysis is conservative across DATA,
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
operation. It must be terminal and is not admitted in DATA or CTE bodies. The
explicit RESULT name resolves to its actual retained Stage Result port; a step
alias or undeclared Result is rejected. A preceding terminal RESULT stays
terminal and does not gain an implicit default export. This first update surface
requires one nonempty SET list. Values are direct Result fields or scalar
literals; computed values must be produced by an earlier EXTEND or SELECT.
Duplicate target fields are rejected. Literal strings retain their original
Unicode and CR/LF values through the ordinary string decoder.

Lowering emits the existing Stage update Effect with the authored target,
MappingRef, Result, ID field and SET values. Existing checker, Mapping, planner,
preview, approval, capture and cleanup owners remain authoritative. No approval
policy is authored in this surface, and syntax admission does not authorize
execution. Other Effect kinds and complete Effect-language coverage remain
separate implementation obligations.

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
are terminal and cannot occur in DATA, CTE or another Table write's input.

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
Initial support is Relation create and same-schema whole-table replace using
the installed writer's admitted types. Syntax does not authorize a write.
Append/upsert, schema evolution, automatic Catalog observation and other Carrier
writers are separate implementation units.
