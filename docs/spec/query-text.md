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
Relation paths use their separate rule: an unquoted component matches without
ASCII case, while a quoted relation component requires exact spelling.
Unquoted names match `[A-Za-z_][A-Za-z0-9_]*`. Backticks quote names and do
not switch column lookup to exact-case mode. Single quotes delimit strings;
only escaped quote, backslash, `n`, `r`, `t`, four-hex-digit `u`, and
eight-hex-digit `U` are decoded. Escapes must denote valid Unicode scalars.
Double-quoted tokens are reserved for the explicit Graph `LABELS` annotation;
they are not query expression strings or quoted identifiers.
Comments are line `--` and non-nested block `/* ... */` comments. Query
parameters use `@name`; interpolation, raw/triple/byte literals and multiple
statements are rejected. The legacy JSON/YAML expression-text dialect is
unchanged.

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

Nonrecursive CTEs and named, noncorrelated FROM subqueries become checked Stage
Result references, so reusing a source does not imply another physical read.
JOIN, grouping, sets, analytic and Pipe operations lower to existing Program
operations and AoA meaning. No connector receives the original SQL as a raw
query. Finite bounds, stable-order evidence, identity requirements, captured
source grants and current authorization remain ordinary admission obligations.
Unsupported shapes must be rejected instead of approximated by a second
checker or evaluator.

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
EBNF separately from the legacy expression text and structural text grammar.
These identities describe the source form. They do not certify that a specific
Run succeeded or that all r1 acceptance cases have been implemented. Changing
either input changes the manifest CID and dependent compiled identities; the
Program contract version remains 0.1.
