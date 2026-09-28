# Frontend query milestone: PR-3 and PR-4

## Baseline and scope

BASE_SHA: `02c279a39567febbc11fb75a463bd6fbe92fb284` (fetched origin/main).
Branch: `feat/frontend-query-sql-pipe`.
The branch was rebased onto fetched `origin/main`
`c1ed3f526e2e5576e3cdd172b4b6a66c893fdd4f`. The pre-rebase
`686965b916e3dbb43f1f1756393593aa85fb8b46` is retained at
`backup/frontend-query-before-c1ed3f5`. The generated Run Host interfaces and
the combined normative import hash were regenerated from the merged sources;
`git range-diff` found no dropped change. The current source-free task Host
path issues its Invocation through the compiled Run owner instead of calling
the removed standalone Run bridge. The Host unit test covers issuance and a
foreign Definition rejection; `check-moonbit-api` and the independent query
Program test pass at `07c96ecf4`. The packed Local run reached source-free
CTE, SQL/Pipe, JOIN, and acquired-input setup, but its full Local/Remote run
was interrupted during slow captured-input cases. It is not a passing final
product gate at this SHA.
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
| Closed scalar expressions, precedence, NULL and CONCAT | Structured Expression admission/typing | Independent trees, demand/failure and legacy regression | Partial: shared AST and direct tree lowering; strict and legacy CONCAT execute through packed Local/Remote; full typing/failure matrix pending |
| SELECT, FROM-only, subqueries, WHERE | Existing Program derive/select/filter | SQL/Pipe expected Program and rows | Partial: base SELECT/FROM/WHERE and named noncorrelated FROM subqueries, including nesting, execute through captured Host; one JOIN-right subquery from an earlier CTE executes through packed Local/Remote; broader joins, set operands and additional source forms remain |
| INNER/LEFT/FULL equijoin, USING, finite CROSS JOIN | Existing join and checked bounds | NULL extension, aliases, shape and multiplicity | Partial: direct Values joins support INNER/LEFT, bounded CROSS, DISTINCT and output/non-output ORDER with LIMIT; a DISTINCT CTE supplies identity for packed source-free and captured-input FULL/USING; general join scope remains |
| GROUP BY, aggregates, HAVING | Existing group | Alias collisions, empty/NULL input, aggregate failure order | Partial: COUNT, MIN/MAX and pinned-profile SUM/AVG execute through packed Local/Remote, including empty input; bounded STRING_AGG and nonnullable keyed ARRAY_AGG over Values execute; nullable ordered ARRAY_AGG and the collection failure matrix remain |
| DISTINCT, ORDER BY, LIMIT/OFFSET | Existing distinct/sort/take | Output-only equality, hidden fields, ties, limits | Partial: alias priority, private selected-expression slots and non-output ordering, including JOIN output and hidden input order through packed Local/Remote; captured DISTINCT→ORDER runtime passes, broader ties/limits pending |
| Nonrecursive CTE | Shared Stage input and dataflow | Multiple references with one physical acquisition | Partial: each used declaration lowers to one checked Stage Result; packed Local/Remote execute Values, acquired SELECT, a two-reference equijoin with hidden ORDER/LIMIT, a sequential chain, two branches from one predecessor and a join inside a declaration body; packed Local physical statement counts match a single-reference acquisition, while broader joins and Remote physical counting remain |
| UNION ALL/DISTINCT, INTERSECT/EXCEPT DISTINCT, exact BY NAME | Existing append/row-set | Positional alignment, type mismatch, duplicate rows | Partial: two source-free Values operands and two terms sharing one captured source execute through packed Local/HTTP Clients; different captured sources, different physical source filters, CTE reuse and broader type/order cases remain |
| Pipe SELECT/WHERE/EXTEND/SET/DROP/RENAME/AS/AGGREGATE/JOIN/order/limit/set | Shared query scope and Relation lowering | Snapshot RHS, old range slots, SQL/Pipe pairs | Partial: SELECT/WHERE/AGGREGATE/ORDER/LIMIT, EXTEND, scoped SET/DROP/RENAME/AS, one JOIN with an optional preceding WHERE, and a parenthesized SQL right operand for Pipe set; post-projection JOIN and other scope forms remain |
| Adopted analytic/OVER | Existing analytic | Closed signatures, inline scope, frame/order rejection | Partial: inline OVER, bounded checker and packed ranking, navigation, framed COUNT, SUM and AVG Results; Pipe EXTEND/SET before OVER preserves updated and prior alias snapshots; full negative and frame matrix pending |
| Bounds, origin maps and Grammar Manifest | Existing owners | Before-allocation bounds, source diagnostics, pins/vectors | Partial: query grammar/rules now bind the 0.1 Grammar Manifest with schema, generated pin and independent vector; exact-limit and origin diagnostics matrix remains |
| Ordinary execution and Named Result | Packed Local and HTTP Host test connection | Values and acquired input; CTE acquisition counter | Partial: source-free and captured query, analytic, set and CTE examples run through packed Local and HTTP Remote Host; independent acquisition count remains |
| Core isolation and SDK dependency boundary | Existing gates | No frontend production dependency or tracked runtime bundles | Partial: connector-free Core isolation passes; final SDK closure gate remains |

The [architecture correspondence](../design/frontend-r1.md#shared-query-vocabulary-and-scope)
uses reference terms and existing IR names. In this status table, an intentional
profile difference is distinct from an unimplemented adopted feature. The
former includes eager ActQL boolean/failure rules, explicit new-query NULL
sort directions, no implicit set-column type promotion or padding, and the
specified exclusion of recursive/correlated CTEs. The latter includes
the remaining Pipe JOIN scope forms. No
unimplemented item is reclassified as an intentional incompatibility.

The common expression lowering and Local evaluator now retain distinct
`concat_strict` and `concat` operators. The former propagates NULL after
evaluating its operands; the latter skips NULL and returns an empty string
when all operands are NULL. Both use the existing bounded expression frame.
Packed Local and HTTP Remote Clients read two Result rows with
`{strict:NULL,legacy:"a",joined:"é😀"}` from a source-free Values query.
The evaluator regression also covers all-NULL legacy concatenation. This
does not establish the full scalar typing and failure matrix.

For a sole global `ARRAY_AGG(DISTINCT a IGNORE NULLS ORDER BY a DESC)` on a
nonnullable Values field, the frontend first projects `a` and applies the
existing row DISTINCT. This yields an actual candidate key without choosing a
representative for any other column. Both packed Local and HTTP Remote return
`{ids:[2,1]}` from input values `1,1,2`. A nullable `a` still fails the
common ordered-aggregate checker; the frontend does not invent a nonnull key
from `IGNORE NULLS`. Other aggregates and grouped keys do not use this
transformation because pre-deduplication could change their input.
The corresponding Pipe `AGGREGATE` runs through both packed Clients with the
same rows. The final lowering leaves a preceding Pipe `SET` outside this
special case; the common checker rejects that unkeyed composition. An
experimental pre-deduplication after `SET` passed the checker but failed
before publication in packed Local, so that Host-path composition remains
unimplemented rather than being reported as executable.
An independent source-free Values query with `a=0,1` also verifies the
ActQL-specific eager `AND` rule through both packed Clients:
`WHERE a <> 0 AND 10 / a > 1` fails the Run on division by zero. The
frontend does not present SQL boolean conjunction as a short-circuit guard.

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
The computed alias `amount + 1 AS bucket` is also grouped through both packed
Hosts, yielding `(bucket,n)=(31,2),(NULL,1),(21,1)` from the acquired rows.
This checks one evaluated key slot and NULL grouping without a representative
row choice.
Source-free Values `(NULL,1,2)` also execute through packed Local and HTTP
Remote: ascending ORDER returns `NULL,1,2` and descending ORDER returns
`2,1,NULL`. These are the query profile's explicit NULL directions, not a
change to the legacy AQL sort default.
The same source-free ordered rows with `LIMIT 2 OFFSET 1` publish `1,2`
through both packed Clients, after the NULL row is skipped.
Global COUNT over source-free Values now runs in both packed modes:
`[1,NULL,2]` yields `COUNT(x)=2` and `COUNT(*)=3`, while an empty typed
Relation yields one aggregate row with `COUNT(*)=0`. SUM/AVG remain separate
numeric-profile work; these COUNT results do not establish their execution.
On `[1,NULL,2,2]`, both packed modes also return `COUNTIF(x>1)=2`,
`COUNT(DISTINCT x)=2`, `MIN(x)=1` and `MAX(x)=2` from one global aggregation.
Pipe column edits also retain the input snapshot in both packed modes.
`SET x=y,y=x` on `(2,1),(1,2)` publishes old and new values
`(2,1,1,2),(1,2,2,1)`, and `DROP x` still permits `before.x` while omitting
top-level `x` from the named output.
Pipe `WHERE` immediately before a `LEFT JOIN` filters the left input before
null extension. The packed Local and HTTP Clients return `{a:2,d:NULL}`
from `FROM set_left AS l |> WHERE l.a > 1 |> LEFT JOIN set_right AS r ON
l.a = r.c |> SELECT l.a AS a, r.d AS d`. A pre-join predicate cannot refer
to the right relation. Other Pipe edits before JOIN still fail closed because
their range snapshot has not yet been connected to JOIN lowering.
The same pre-join filter over two named `FROM (SELECT ...)` sources now runs
through packed Local and HTTP Remote. Both publish `{a:2,d:NULL}` as a Named
Result. The checked Stage expands into internal tasks; the shared Plan issuer
emits each selected task pipeline and binds producer/consumer ports using the
checked operation-input coordinate. The Local dispatcher selects each task's
own prefix, so its completed output matches the exact checked target. A
dedicated Plan test checks the internal edge and selected pipelines; the packed
test checks the full Client-to-Result path. The input fixtures and expected
rows were written independently of the generated Plan.

The full packed Node/browser Client smoke passes locally after the selected
task fix. Fixed-SHA CI and the remaining accepted SQL/Pipe matrix have not
passed at this revision; this is not yet a review-ready PR.

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
The packed Local and HTTP Remote paths also execute MIN and MAX in one
explicit ROWS frame over acquired rows with NULL and duplicate order keys.
They retain the original row order, with the first NULL producing NULL bounds
and later numeric rows producing running minimum and maximum values.
The source-free packed Local and HTTP Hosts also evaluate RANK and DENSE_RANK
against the same peer window: input rows with sort keys `2,1,1` retain their
input order and yield ranks `3,1,1` versus dense ranks `2,1,1`. The peer rows
are specified independently of the generated Program. The installed Host now
selects the repository-pinned numeric reduction profile by its exact CID when
admitting the check environment. The Host ABI rejects an unknown CID, and the
old no-profile entry retains its `NeedsInputs` behavior for SUM/AVG. Packed
Local and HTTP Remote both publish SUM=5 and AVG=5/3 over `(1,NULL,2,2)`;
empty input yields NULL for both. An explicit ROWS-frame OVER query publishes
running SUM `(1,1,3,5)` and AVG `(1,1,1.5,5/3)` in input order. This selects
the existing numeric reduction owner; it does not infer an algorithm from SQL
syntax or silently fall back after execution failure.
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
open; the packed embedded Local test observes the same number of physical
DuckDB source statements for one and two CTE references. The HTTP Remote
Host runs in a separate process, so its physical statement count remains
unobserved by that counter.
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
branch does not divide by zero. General post-join grouping and multiple
joins remain open. JOIN DISTINCT now removes duplicate matched rows using only
the named output columns; packed Local and HTTP Remote reduce two equal
matches to one `{a:1}` Result. CTE JOIN DISTINCT also selects the deduplicated
Stage Result in checker tests. A prior JOIN sort attempt failed task
compilation before the common Plan issuer preserved exact segmented task
outputs. With that boundary corrected, direct Values JOIN now sorts by
selected aliases and non-output input expressions, takes a bounded prefix,
then removes private sort columns. SQL and Pipe emit the same Program; packed
Local and HTTP Remote Clients return the independently expected rows and do
not expose private fields. DISTINCT rejects a non-output sort expression.
The same resolution and private-slot implementation now serves CTE JOINs;
a source-free CTE reused as both JOIN inputs sorts and limits correctly
through packed Local and HTTP Remote Clients. Broader sort/failure cases
remain open. No
candidate key or total-order witness is fabricated here. FULL JOIN is parsed
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
`(3,3)` matches. The Program has one acquisition Stage. The packed Local
test observes DuckDB's prepared SQL for the physical source and checks that
the two-reference CTE issues exactly as many source statements as the
single-reference CTE over the same filter. Result delivery adds no source
statement. The HTTP Remote Result path passes, but that Host's SQL runs in
the parent test process and is outside this counter. A CTE declaration body can now join two prior checked CTE
Results through the same bounded join operation; a packed Local and HTTP
Remote example returns `{id:2}` from one source-free base CTE and two
consumers. An acquired DuckDB input runs the same shape and publishes four
`{id:3,amount:30}` rows from two duplicate left rows and two duplicate right
rows. The generated Programs retain one Values seed or one acquisition stage,
respectively. The Local physical comparison covers the CTE self-join;
separate Remote physical counting remains. JOIN projection and post-JOIN filtering now
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
The packed Local physical comparison also covers the two-reference CTE
self-join; it does not establish a count for every declaration topology.
ARRAY_AGG requires the adopted `IGNORE NULLS` and explicit order spelling;
STRING_AGG requires a literal delimiter and explicit order. Both lower to the
existing group call with caller-supplied item and byte ceilings. The
independent checker accepts the bounded ARRAY_AGG example on a keyed captured
input. It refuses ordered ARRAY_AGG over unkeyed duplicate Values rather than
inventing a candidate key. Bounded STRING_AGG over the Values input passes
the checker and publishes `y|x|x|n` through packed Local and HTTP Remote
Clients. Ordered ARRAY_AGG Result delivery still needs a keyed physical input
fixture; the source-free Values example cannot establish its required key.
LIMIT and OFFSET now parse the full exact safe-integer range, rejecting zero
LIMIT, fractions, and values above `2^53-1` before Program construction.
