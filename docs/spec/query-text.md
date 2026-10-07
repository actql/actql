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
retain the bound range's original values; Pipe AS replaces that range. SELECT
materialization ends its input range scope, while a deferred query ORDER may
still consume the admitted SELECT input snapshot before that materialization.
SQL GROUP ordinals count the expanded and excluded range columns, and every
retained star column must be grouped. LEFT JOIN nullability belongs to the
common joined schema. A missing or displaced range is refused, including a
star that would otherwise appear to be an identity projection. The selected
[GoogleSQL star reference](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#select_expression)
also permits expression/STRUCT receivers. Those broader receivers remain
unconnected coverage; they are not reinterpreted as Relation ranges.
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
profile, including its floating-point partition exclusion. Named windows,
optional ordering, default frames and nested window calls remain outside this
implemented inline profile.

In the implemented inline `OVER` profile, numeric `ROWS BETWEEN` boundaries
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
window does not add RANGE, unbounded frames or default aggregate frames.
Unused declarations are checked for declaration conflicts but do not execute
their expressions. These rules follow
[GoogleSQL named windows](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/window-function-calls#rules_for_using_a_named_window_in_the_window_specification)
and the selected resolver's declaration flattening. Parsed operation snapshots
copy mutable window/aggregate lists and cannot mutate the admitted syntax owner.

QUALIFY resolves SELECT aliases to their evaluated slots before same-name
inputs. Qualified input references retain their input meaning. A scalar alias
needed by the condition is evaluated once against SELECT's input snapshot and
reused by final projection; unrelated scalar projections are evaluated after
the condition. No alias is made visible inside its own or a sibling SELECT
expression, or inside an OVER specification. Ordinary Boolean and aggregate
typing, failure, capacity and parameter rules remain common-owner decisions.

`WHERE` and siblings in one SELECT list see the input snapshot, not aliases
introduced by that list. In `GROUP BY`, `HAVING`, `QUALIFY` and the query's final
`ORDER BY`, a visible SELECT alias takes precedence over an input column of
the same name. Duplicate aliases, qualified references and aggregate
visibility still undergo their own ambiguity and validity checks. Names in
an analytic `OVER` clause resolve against the input snapshot, not the final
ORDER BY scope. These rules follow the adopted GoogleSQL query and window
scopes; they do not confer general GoogleSQL compatibility.

Pipe range variables bind immutable input value slots. `SET` replaces the
current unqualified columns; every assignment sees the same pre-SET row.
`DROP` removes current names, and `RENAME` changes current names. These three
operations retain an existing range variable's original column names and
values. A removed or renamed current column does not become available through
an unqualified reference simply because an older range variable retains it.

Pipe `AS name` replaces all preceding range variables with that name, bound
to the current visible columns and values. Reusing the same name is allowed
and establishes a new binding. References to a displaced initial or
intermediate range variable are rejected, including references inside
expressions, WHERE and ORDER BY. AS does not restore dropped names or expose
compiler helper slots. These are the adopted
[GoogleSQL Pipe scope rules](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/pipe-syntax).

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

WITH may precede either a SELECT query or a FROM-starting Pipe query. A CTE
body, named FROM/JOIN subquery and parenthesized query operand use the same
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
Recursive declarations,
forward references and references to a displaced range variable remain
invalid. Parsing shares the existing syntax-node, CTE-count and work budgets.

Nonrecursive CTEs and named, noncorrelated FROM subqueries use checked producer
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

A fixed directed path retains each authored node and edge occurrence. Its
local predicates are evaluated at their demanded prefix: the starting node
over the initial node scope, then each reached edge and node after the
corresponding hop. WALK permits revisits, TRAIL excludes reuse of the same
definition-scoped typed edge key, and ACYCLIC excludes node revisits. Separate paths with
the same endpoints remain separate rows unless the query requests DISTINCT.
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
