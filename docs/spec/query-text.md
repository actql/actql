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
Backtick identifiers currently retain their existing limited escape profile;
the wider GoogleSQL identifier escape repertoire is a coverage gap.
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

## Scope and lowering

`WHERE` and siblings in one SELECT list see the input snapshot, not aliases
introduced by that list. In `GROUP BY`, `HAVING` and the query's final
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

Nonrecursive CTEs and named, noncorrelated FROM subqueries become checked Stage
Result references, so reusing a source does not imply another physical read.
JOIN, grouping, sets, analytic and Pipe operations lower to existing Program
operations and AoA meaning. No connector receives the original SQL as a raw
query. Finite bounds, stable-order evidence, identity requirements, captured
source grants and current authorization remain ordinary admission obligations.
Unsupported shapes must be rejected instead of approximated by a second
checker or evaluator.

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

## Graph pattern source

`FROM GRAPH name` selects an existing Graph value. `MATCH` requires an explicit
`WALK`, `TRAIL`, or `ACYCLIC` mode and yields a binding Relation. It cannot
silently construct a Graph from a Relation, attach to an ambient Graph, or
introduce a second implicit Graph input. One Graph source admits one MATCH;
another pattern needs a separate source and an explicit Relation join.

`LABELS {"node":{"field":"entity_type"}}` is a query-local annotation. A
node label such as `(a:Account)` expands to equality on that declared string
field; a null field value does not match. A node label without this annotation
is rejected. The annotation neither changes Graph identity nor grants entity
authority. Edge labels use the Graph's semantic edge-label evidence, never an
arbitrary property with a similar name.

A fixed directed path retains each authored node and edge occurrence. Its
local predicates are evaluated at their demanded prefix: the starting node
over the initial node scope, then each reached edge and node after the
corresponding hop. WALK permits revisits, TRAIL excludes reuse of the same
typed edge tuple, and ACYCLIC excludes node revisits. Separate paths with
the same endpoints remain separate rows unless the query requests DISTINCT.
Graph variables are compile-time binding names. They do not create new
runtime Node, Edge, or Path value types.

The only quantified shape is one homogeneous directed ACYCLIC edge with
literal closed `{m,n}` bounds, where `0 <= m <= n` and `n > 0`. An open bound,
internal quantified edge variable, nested pattern, optional match, or
unbounded repetition is rejected. A missing property-selected start gives an
empty match, while an explicit native traversal ID selector retains its
existing membership-failure rule. Graph and Relation resource ceilings remain
separate and partial path output is never published as a Result.

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
