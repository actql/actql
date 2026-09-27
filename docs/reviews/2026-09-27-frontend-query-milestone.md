# Frontend query milestone: PR-3 and PR-4

## Baseline and scope

BASE_SHA: `02c279a39567febbc11fb75a463bd6fbe92fb284` (fetched origin/main).
Branch: `feat/frontend-query-sql-pipe`.
PR-0 through PR-2 are already merged; this milestone reuses their source builder,
origin mapping, structural envelope, checker boundary and Grammar Manifest.
One PR covers shared query expressions, SQL/Pipe and the adopted analytic subset.
No implementation or runtime pass is implied by this initial inventory.

The immutable imported work order and specification sections 6-8, 13-14 and
appendices B/C remain the scope source. Source assets are not edited. The
[design mapping](../design/frontend-r1.md#shared-query-vocabulary-and-scope)
records reference terms, frontend and existing IR meanings, and differences.

## Requirement correspondence

| Requirement | Existing target | Required evidence | Current status |
| --- | --- | --- | --- |
| UTF-8, tokens, escaping, numeric domain, original spans | Original source owner and bounded query lexer | Positive, negative and exact-limit cases | Partial: exact lexer and query syntax/work limits, original Unicode error span and unadopted OVER rejection pass; full diagnostic matrix pending |
| Closed scalar expressions, precedence, NULL and CONCAT | Structured Expression admission/typing | Independent trees, demand/failure and legacy regression | Partial: shared AST and direct tree lowering; full typing/failure matrix pending |
| SELECT, FROM-only, subqueries, WHERE | Existing Program derive/select/filter | SQL/Pipe expected Program and rows | Partial: base SELECT/FROM/WHERE and named noncorrelated FROM subqueries, including nesting, execute through captured Host; one JOIN-right subquery from an earlier CTE executes through packed Local/Remote; broader joins, set operands and additional source forms remain |
| INNER/LEFT/FULL equijoin, USING, finite CROSS JOIN | Existing join and checked bounds | NULL extension, aliases, shape and multiplicity | Partial: direct Values joins support INNER/LEFT, bounded CROSS and output-only DISTINCT; a DISTINCT CTE supplies identity for packed source-free and captured-input FULL/USING; general join scope remains |
| GROUP BY, aggregates, HAVING | Existing group | Alias collisions, empty/NULL input, aggregate failure order | Partial: scalar reductions and ordered ARRAY_AGG/STRING_AGG lower through group; captured COUNT/GROUP/HAVING runtime passes, ordered collection runtime and failure matrix pending |
| DISTINCT, ORDER BY, LIMIT/OFFSET | Existing distinct/sort/take | Output-only equality, hidden fields, ties, limits | Partial: alias priority, private selected-expression slots and non-output ordering; captured DISTINCT→ORDER runtime passes, ties/limits pending |
| Nonrecursive CTE | Shared Stage input and dataflow | Multiple references with one physical acquisition | Partial: each used declaration lowers to one checked Stage Result; packed Local/Remote execute Values, acquired SELECT, a two-reference equijoin, a sequential chain, two branches from one predecessor and a join inside a declaration body; physical provider read counter and broader joins remain |
| UNION ALL/DISTINCT, INTERSECT/EXCEPT DISTINCT, exact BY NAME | Existing append/row-set | Positional alignment, type mismatch, duplicate rows | Partial: two source-free Values operands and two terms sharing one captured source execute through packed Local/HTTP Clients; different captured sources, different physical source filters, CTE reuse and broader type/order cases remain |
| Pipe SELECT/WHERE/EXTEND/SET/DROP/RENAME/AS/AGGREGATE/JOIN/order/limit/set | Shared query scope and Relation lowering | Snapshot RHS, old range slots, SQL/Pipe pairs | Partial: SELECT/WHERE/AGGREGATE/ORDER/LIMIT, EXTEND, scoped SET/DROP/RENAME/AS, one JOIN before other Pipe operators, and a parenthesized SQL right operand for Pipe set; post-projection JOIN and other scope forms remain |
| Adopted analytic/OVER | Existing analytic | Closed signatures, inline scope, frame/order rejection | Partial: inline OVER, bounded checker and packed RANK, ROW_NUMBER, LAG and framed COUNT Results; Pipe EXTEND/SET before OVER preserves updated and prior alias snapshots; full negative and frame matrix pending |
| Bounds, origin maps and Grammar Manifest | Existing owners | Before-allocation bounds, source diagnostics, pins/vectors | Partial: query grammar/rules now bind the 0.1 Grammar Manifest with schema, generated pin and independent vector; exact-limit and origin diagnostics matrix remains |
| Ordinary execution and Named Result | Packed Local and HTTP Host test connection | Values and acquired input; CTE acquisition counter | Partial: source-free and captured query, analytic, set and CTE examples run through packed Local and HTTP Remote Host; independent acquisition count remains |
| Core isolation and SDK dependency boundary | Existing gates | No frontend production dependency or tracked runtime bundles | Pending |

The current Local expression IR rejects `concat_strict` and `concat` during
`lowering_relation.lower_expression_measured`: `ExpressionNotImplemented`
is the concrete boundary. The query compiler emits the adopted distinct
expression trees and the common checker accepts them, but the packed Host
rejects a Values query before Run creation with
`RunHostCompilationRejected`. The packed embedded Local test records that
explicit refusal; the public HTTP Client correctly reports an uncertain
submission when the server fails before returning a Run reference, so this
known compiler gap is not asserted as a remote Run failure.
The Local Compute owner must extend the existing lowering and evaluation
of these two operators, preserving strict NULL propagation versus legacy
null skipping and bounded output accounting. The frontend must then change
this expected refusal into independent Local and HTTP Remote Result rows.
It must not rewrite strict CONCAT as legacy concat or invent a parallel
expression evaluator.

Named noncorrelated SQL and Pipe `FROM (SELECT ...) AS source` now use the
same checked Stage Result binding as a CTE. The bounded parser preserves
the source alias and accumulates nested source stages without reparsing
expressions or copying acquisition. A two-level captured-input subquery
applies DISTINCT, ORDER BY and LIMIT after acquisition and returns `id=2,3`
through packed Local and HTTP Remote Named Results.
Missing aliases and source-count overruns are rejected. A named noncorrelated
JOIN-right subquery also becomes a checked Stage Result when its input is an
earlier CTE, with the same global CTE count bound. A packed source-free case
reuses one base CTE in the outer join and the right subquery; Local and HTTP
Remote both publish `{left_id:2,right_id:2}`. Correlation, arbitrary join
chains and set operands containing subqueries remain outside the implemented
path.
Generated source bindings avoid names already present in the input tokens;
a user CTE named `aql_query_source_0` retains its own binding while the
subquery uses the next available internal name. The name search is charged
to the existing query work budget.

## Reference evidence

GoogleSQL reference revision: `d82db99a923a46571f543a13899dc791a7b6f743`.
The reference analyzer tests are inspected as external evidence, not counted as
ActQL runtime tests. Relevant upstream suites: `alias_ambiguity.test`,
`orderby.test`, `aggregation.test`, `analytic_function_partitionby_orderby.test`
and `pipe_set.test` under `googlesql/analyzer/testdata`.

The adopted alias precedence and non-output ORDER BY decisions are not new SQL
semantics. Duplicate names, grouped visibility and OVER scopes still require
individual validation. DISTINCT ordering must recognize selected expressions,
not merely compare column spelling. No hidden representative is chosen.
The packed Local and HTTP Clients now distinguish both scopes on independent
Values rows `(x,y)=(2,1),(1,2)`: `SELECT x AS y ... ORDER BY y` returns
`y=1,2`, while `SELECT x ... ORDER BY y` returns `x=2,1`. The source has an
input column named `y` in the first case, so the output tests alias precedence
at runtime rather than only checking a generated sort field.
The separately authored `query-pair.expected-program.json` remains the
SQL/Pipe Program comparison, and its independent expected rows are now read
through both packed Client modes: the open orders sort to `o1,o3`.
An acquired-input case also separates the two ORDER scopes:
`SELECT amount AS id, ROW_NUMBER() OVER (ORDER BY id) AS pos ... ORDER BY id
DESC` ranks original input `id` values and finally sorts by the projected
`id` alias. Packed Local and HTTP Remote both return `(20,2),(NULL,1)`.
For DISTINCT, both packed Clients execute `SELECT DISTINCT id + 1 AS next
... ORDER BY id + 1` over a duplicate acquired input and return `2,3,4`.
This checks selected-expression correspondence; the source field `id` does
not leak into the Result or enter the DISTINCT equality row.
The acquired-input alias collision `SELECT amount AS id, COUNT(*) AS n ...
GROUP BY id HAVING n > 1` returns only `{id:30,n:2}` through packed Local and
HTTP Remote. The source has an input `id` column, so this verifies SELECT
alias precedence in grouping and HAVING through the ordinary Host.
Source-free Values `(NULL,1,2)` also execute through packed Local and HTTP
Remote: ascending ORDER returns `NULL,1,2` and descending ORDER returns
`2,1,NULL`. These are the query profile's explicit NULL directions, not a
change to the legacy AQL sort default.
The same source-free ordered rows with `LIMIT 2 OFFSET 1` publish `1,2`
through both packed Clients, after the NULL row is skipped.

GQL patterns, VecA/TEA-specific surfaces, INFER/Artifact spelling, INSERT,
installed raw-text routing, deployment and other owners' runtime redesigns
remain later work. Existing engine gaps are recorded as dependencies rather
than redefined as language restrictions.

## Reference cases inspected

At the reference revision above, `alias_ambiguity.test` explicitly tests
SELECT alias override and ambiguous duplicate aliases in ORDER BY/GROUP BY/
HAVING. `orderby.test` includes an unselected-column sort at line 750 and
post-DISTINCT inaccessible input-column errors at lines 1563-1578. These
support separate post-projection scope and selected-expression correspondence,
not a blanket spelling-based field allowlist. The official window-function
rules separately constrain SELECT-list aliases inside analytic arguments/OVER.
No upstream analyzer binary or hosted BigQuery query has been executed here.

The official operator precedence places concatenation alongside multiplication
and division. The new source AST follows that grouping; the legacy AQL text
parser and its existing precedence are unchanged. The adopted profile limits
concatenation to strings even though GoogleSQL has additional overloads.

## Implementation in progress

The shared query lexer and explicit-stack expression AST now cover scalar
operators, function calls, named paths, parameters, predicates, searched CASE
and adopted CAST type spelling. Direct source-builder lowering reaches existing
Expression admission without reparsing legacy expression text. Independent
expected trees cover strict versus explicit legacy CONCAT, precedence, parameter
identity, IN values, source-resolution refusal and integer admission.

This is not a PR-3/PR-4 completion claim. Relational SQL/Pipe elaboration,
aggregate/analytic source calls, typed scope integration, complete function
mapping, unified work accounting, normative grammar/manifest updates and full
packed Host acceptance remain. Unary plus over a nonliteral currently fails closed;
its final handling must preserve numeric typing rather than erase the operator
and accidentally accept strings. Raw-text routing is not installed in the
standard Client; that is a later delivery unit.

The test-only query adapter now uses the same structured Program admission as
the Host. The independent SQL/Pipe fixture yields the same Program; the normal
checker accepts its declared relation. A physical acquisition needs a separate
capture Stage: the installed Host's existing acquisition owner requires an
exclusive filter→select chain, then a downstream task for direct Result
publication. The frontend emits this chain only for a context explicitly
selecting a captured Stage, moves the original WHERE into that capture once,
and preserves the downstream query. A packed installation then executes
`SELECT * FROM rows` over source-free Values and
`SELECT id FROM records WHERE id > 1` over a captured DuckDB source via both
embedded Local and HTTP Remote. Named `answer` Results contain `1, 2` and
`3, 2, 3`, respectively. This is a concrete
product route for that query shape, not a claim that the full SQL/Pipe profile
or arbitrary physical acquisition shape is complete. The same packed Clients
also run source-free `SELECT id FROM rows WHERE id > 1` through the existing
multi-step Values pipeline, returning `{id:2}`. This replaces the earlier
assumption that the installed Values compiler only accepted a direct root.
The same captured route also executes `SELECT DISTINCT id FROM records WHERE
id > 1 ORDER BY id`, returning `2, 3` in order. The source includes duplicate
`id=3` rows; DISTINCT supplies a proven key before sorting. Arbitrary source
ORDER BY still requires the existing total-order evidence and is not inferred
from the SQL spelling alone.
The captured route also executes `SELECT id, COUNT(*) AS n FROM records WHERE
id > 0 GROUP BY id HAVING n > 1 ORDER BY id`, returning `{id:3,n:2}` in Local
and HTTP Remote. This exercises the existing `group` operation and post-group
filter through the normal Host, with the SELECT alias `n` resolved after
aggregation. The corresponding Pipe `AGGREGATE` and post-group `WHERE` emit
the same canonical Program under the same compile context. The broader
aggregate signature, empty/NULL and failure-order matrix remains pending.

Inline `OVER` now lowers the r1 ranking, navigation, value, and selected frame
aggregate spellings to the existing `analytic` operation. `PARTITION BY` and
the window's `ORDER BY` resolve against the input snapshot, independently of
the query's final `ORDER BY` alias scope. Matching windows combine their calls
in one analytic operation. The ordinary checker accepts row-number/navigation
and framed COUNT over bounded Values with explicit Host analytic ceilings;
missing ceilings are not inferred. Physical Result verification for this
surface is partial; the broader SQL/Pipe scope remains pending. The packed Local and
HTTP Remote Host route also executes `RANK() OVER (ORDER BY id)` on captured
rows with a duplicated sort key and returns ranks `3, 1, 2, 3` in input order.
The test Host explicitly supplies analytic resource ceilings.
The same packed route reads independently specified rows for ROW_NUMBER, LAG
and an explicit ROWS-frame COUNT over a two-row acquired input. The Pipe
ROW_NUMBER spelling emits the same admitted Program as SQL and returns the same
rows through both Clients. This covers those signatures and frame; the full
adopted analytic matrix remains unverified. Pipe EXTEND followed by ROW_NUMBER
reads the updated input snapshot and returns NULL-preserving adjusted values.
The packed path now also reads independent DENSE_RANK, LEAD, FIRST_VALUE and
LAST_VALUE rows. FIRST_VALUE retains the initial NULL within its explicit
ROWS frame; LAST_VALUE advances to the later non-NULL row.
The source-free packed Local and HTTP Hosts also evaluate RANK and DENSE_RANK
against the same peer window: input rows with sort keys `2,1,1` retain their
input order and yield ranks `3,1,1` versus dense ranks `2,1,1`. The peer rows
are specified independently of the generated Program. SUM and AVG lower to
the existing analytic operator, but standard installed Host preparation
cannot yet supply the numeric reduction profile: the
`clientProgramCheckEnvironment` bridge in
`src/connectors_builtin_node/client_program_bridge.mbt` has no numeric-profile
selection input. The shared checker returns `NeedsInputs` for either call
without the profile and accepts both when the existing pinned numeric profile
is supplied in the MoonBit test. The installed Local/HTTP Result path for
these two signatures remains unverified; it must not silently choose a
reduction algorithm.
Pipe SET retains an earlier range alias inside OVER: after replacing `id` with
`amount`, `ORDER BY before.id` ranks the original input values. Packed Local
and HTTP Remote both return `(old_id,id,pos)=(1,NULL,1),(2,20,2)`.
Pipe `EXTEND` lowers a batch of expressions against one input snapshot, so
sibling aliases are not visible. A packed captured-source query with
`EXTEND amount + 1 AS adjusted` returns the expected NULL-preserving values
from both Local and HTTP Remote Hosts. Its Result fields are `id, adjusted`;
the direct Result-root admission now compares checked projection fields in
canonical schema order while retaining authored Result order. Previously it
rejected non-lexical field order as requiring an extra transformation.
An unfiltered captured DuckDB query passes Source Evidence context selection
but cannot select the installed native acquisition candidate. Its physical
compiler currently accepts a bound field comparison, not the checked true
filter used for a FROM-only capture. This is a physical capability gap, not a
grant or evidence failure; the frontend does not insert a value-changing
predicate to hide it.
Pipe SET now derives all replacement values against the pre-SET snapshot and
rebinds top-level names to new physical slots. DROP and RENAME change visible
names while older range aliases retain their prior slots; AS captures a new
range snapshot and is not an ActQL step alias. The packed Local and HTTP
Remote Hosts both execute `SET id = amount, amount = id` followed by a SELECT
of original and new values. Both return the independently expected swap,
including a NULL source value. For a Pipe SELECT followed by ORDER BY, the
projection is deferred so the old range alias remains available to sorting;
the SELECT output alias takes precedence over the input column of the same
name. The checker accepts both distinct sort targets. Pipe AGGREGATE after a
column edit materializes the current visible names before grouping and closes
the old range scope. Both packed Hosts return `id=20,n=1` and `id=30,n=2`
after replacing `id` with `amount` and grouping. Analytic after a scope
mutation and additional operators after a Pipe SELECT still need the next
scope pass before this milestone closes.
Two source-free Values operands now lower through checked Stage Results and
the existing `append`, `distinct`, `intersect` and `except` operations. An
alignment projection occupies its own Stage so each physical task retains the
correct input and output contract. The packed Local and HTTP Remote Clients
read independently expected Named Results for UNION ALL, UNION DISTINCT,
INTERSECT DISTINCT and EXCEPT DISTINCT, including duplicate and NULL rows.
The packed Clients also execute `UNION DISTINCT BY NAME` with the right
SELECT columns reversed. The visible Result order follows the left operand;
the checker rejects the same names when their typed columns are swapped.
The common Result-plan issuer maps physical task indices back to checked Unit
indices when a Stage splits. Two captured set terms using the same checked
DuckDB source and identical `id > 1` predicate now share one acquisition
Stage. Packed Local and HTTP Remote each return six `id` rows for the three
matching source rows repeated by UNION ALL. The same packed path returns two
distinct typed rows after `UNION DISTINCT BY NAME` with reversed right
columns, two distinct IDs after `INTERSECT DISTINCT`, and an empty Named
Result after `EXCEPT DISTINCT`. The common predicate is moved to
the acquisition Stage once; term predicates are retained when they differ.
The installed physical candidate does not yet admit a broad unfiltered
capture for differing predicates, so this latter shape has only Program and
checker evidence. Distinct captured sources and CTE acquisition reuse remain
open; no physical provider read counter has yet established once-only I/O.
The first Pipe set form, `FROM set_left |> SELECT a, b |> UNION ALL
(SELECT c, d FROM set_right)`, now emits the same admitted Program as its SQL
counterpart. Packed Local and HTTP Remote Clients read the same independently
specified rows. An acquired `FROM records |> WHERE id > 1 |> SELECT id |>
UNION ALL (...)` emits the same Program as its SQL counterpart and produces
the six expected duplicate-preserving rows through both packed Clients.
Further Pipe chaining and multiple right operands remain unverified.
SQL and Pipe INNER equijoins, SQL LEFT equijoins, and SQL finite CROSS JOINs
over two source-free Values relations now execute
through packed Local and HTTP Remote Clients, preserving duplicate rows and
NULL-key nonmatches. A bounded CROSS JOIN uses the existing product operation.
The Pipe INNER JOIN emits the same Program as SQL. This lowering currently
permits one join. When a SELECT contains a computed scalar expression, the
join retains only its referenced inputs in private slots, then uses the
ordinary Expression derive once after matching and projects only the named
outputs. Packed Local and HTTP Remote execute an arithmetic expression over
INNER and LEFT JOINs; unmatched right rows produce NULL, and SQL/Pipe compile
to the same Program. A post-join WHERE uses the same private input slots and
runs after NULL extension: `LEFT JOIN ... WHERE r.c IS NULL` publishes only
unmatched left rows in packed Local and HTTP Remote. The Pipe spelling emits
the same Program. Two packed zero-input cases preserve demand: the post-join
WHERE excludes a division by zero before projection, and an unselected CASE
branch does not divide by zero. General post-join grouping, order and multiple
joins remain open. JOIN DISTINCT now removes duplicate matched rows using only
the named output columns; packed Local and HTTP Remote reduce two equal
matches to one `{a:1}` Result. CTE JOIN DISTINCT also selects the deduplicated
Stage Result in checker tests. An attempted `ORDER BY` after a checked JOIN
also reached
the standard Host but `run-host-core.compileTasks` rejected it with
`RunHostTaskCompilationRejected`. This reproduced with source-free CROSS JOIN
and with two DISTINCT CTE inputs and DISTINCT joined output; both Programs
passed frontend admission and query checker. The tentative frontend lowering
was removed, so this branch does not claim executable JOIN ordering. The
Compute/Host owners need to identify the sort-order or task-compilation
obligation on the joined result before the frontend can publish this surface.
No candidate key or total-order witness is fabricated here. FULL JOIN is parsed
but the
Values compiler refuses it before issuing a Program: the checked FULL JOIN
requires stable identity on both inputs, which the generated Values Stage
Results do not carry. No representative row or synthetic key is inferred.
A keyed captured-input CTE FULL JOIN passes the common checker. For
`FULL JOIN ... USING`, the frontend now emits distinct left and right private
key slots, derives the unqualified key with the existing typed `coalesce`
expression, and selects only requested fields into the Result. The common
checker accepts this shape. Packed Local and HTTP Remote Clients execute
source-free FULL/USING self-joins and a captured-input FULL/USING join of
two different CTE Results. The latter branches from one deduplicated CTE
into `id=2` and `id=3` inputs. The left-only row is published as
`{id:2,left_id:2,right_id:null}` and the right-only row as
`{id:3,left_id:null,right_id:3}`. Private key slots do not enter the Named
Result. The captured Program uses a simple acquisition CTE, then a DISTINCT
CTE to supply stable identity before the FULL JOIN. Placing
DISTINCT in the acquisition CTE itself fails before Run acceptance with
`QuerySequenceIssue::UnsupportedExecutionShape`; the successful Program
keeps acquisition and later computation in their existing roles.
SQL source aliases with and without `AS` emit the same checked Program.
The keyed FULL acceptance is paired with an unkeyed Values CTE rejection
by the common checker; the frontend does not claim an identity witness from
duplicated literal rows.

One nonrecursive CTE now lowers its body into a single Stage Result and the
outer SELECT refers to that result. A second form uses the same CTE Result
twice as left and right equijoin inputs, with an explicit requested output-row
ceiling that the common capacity owner checks again. Packed Local and HTTP
Remote Clients execute both source-free and acquired CTEs. The acquired
self-join of filtered `id` rows `3,2,3` returns five rows, including four
`(3,3)` matches. The Program has one acquisition Stage; a physical provider
read counter has not yet been added, so the once-only read acceptance case
remains open. A CTE declaration body can now join two prior checked CTE
Results through the same bounded join operation; a packed Local and HTTP
Remote example returns `{id:2}` from one source-free base CTE and two
consumers. An acquired DuckDB input runs the same shape and publishes four
`{id:3,amount:30}` rows from two duplicate left rows and two duplicate right
rows. The generated Programs retain one Values seed or one acquisition stage,
respectively. A physical provider read counter is still needed to establish
the once-only acquisition claim. JOIN projection and post-JOIN filtering now
share one lowering path between source-free queries and CTE bodies. Packed
Local and HTTP Remote runs compute `{total:4}` from source-free rows after
filtering, and four `{total:6}` rows from one acquired input with duplicate
`id=3` rows. The latter retains one acquisition Stage and does not turn the
post-JOIN predicate into a source filter. Direct captured
JOIN inputs, longer join chains and correlated subqueries still fail closed
rather than being textually substituted.
The same packed path accepts `JOIN ... USING(id)` and exposes one unqualified
`id` Result column while retaining qualified left and right key bindings.
FULL JOIN uses the coalesced-key lowering described above instead of taking
only the left key. Packed source-free and captured-input paths include an
independent right-only key case. General multi-relation join chains remain
open.
Two sequential CTE declarations also execute with each later body referring
to its immediate predecessor. A packed acquired-input example produces
`3,2,3` after the second filter. Two branches may refer to one prior Stage
Result without copying its acquisition. Unused declarations currently fail
closed: admitting them without checking their fields and types would skip
semantic validation, while materializing them could perform extra acquisition.
A physical provider read counter is still pending.
ARRAY_AGG requires the adopted `IGNORE NULLS` and explicit order spelling;
STRING_AGG requires a literal delimiter and explicit order. Both lower to the
existing group call. The independent checker accepts the bounded ARRAY_AGG
example; STRING_AGG reports the missing Host string-byte limit instead of
inventing one.
LIMIT and OFFSET now parse the full exact safe-integer range, rejecting zero
LIMIT, fractions, and values above `2^53-1` before Program construction.
