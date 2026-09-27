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
| UTF-8, tokens, escaping, numeric domain, original spans | Original source owner and bounded query lexer | Positive, negative and exact-limit cases | Pending |
| Closed scalar expressions, precedence, NULL and CONCAT | Structured Expression admission/typing | Independent trees, demand/failure and legacy regression | Partial: shared AST and direct tree lowering; full typing/failure matrix pending |
| SELECT, FROM-only, subqueries, WHERE | Existing Program derive/select/filter | SQL/Pipe expected Program and rows | Partial: base SELECT/FROM/WHERE equivalence and captured Host Result; subqueries pending |
| INNER/LEFT/FULL equijoin, USING, finite CROSS JOIN | Existing join and checked bounds | NULL extension, aliases, shape and multiplicity | Pending |
| GROUP BY, aggregates, HAVING | Existing group | Alias collisions, empty/NULL input, aggregate failure order | Pending |
| DISTINCT, ORDER BY, LIMIT/OFFSET | Existing distinct/sort/take | Output-only equality, hidden fields, ties, limits | Partial: alias priority, private selected-expression slots and non-output ordering; captured DISTINCT→ORDER runtime passes, ties/limits pending |
| Nonrecursive CTE | Shared Stage input and dataflow | Multiple references with one physical acquisition | Pending |
| UNION ALL/DISTINCT, INTERSECT/EXCEPT DISTINCT, exact BY NAME | Existing append/row-set | Positional alignment, type mismatch, duplicate rows | Pending |
| Pipe SELECT/WHERE/EXTEND/SET/DROP/RENAME/AS/AGGREGATE/JOIN/order/limit/set | Shared query scope and Relation lowering | Snapshot RHS, old range slots, SQL/Pipe pairs | Pending |
| Adopted analytic/OVER | Existing analytic | Closed signatures, inline scope, frame/order rejection | Pending |
| Bounds, origin maps and Grammar Manifest | Existing owners | Before-allocation bounds, source diagnostics, pins/vectors | Pending |
| Ordinary execution and Named Result | Packed Local and HTTP Host test connection | Values and acquired input; CTE acquisition counter | Partial: source-free `SELECT *` and captured filter/query run through packed Local and HTTP Remote Host; multi-step Values and CTE pending |
| Core isolation and SDK dependency boundary | Existing gates | No frontend production dependency or tracked runtime bundles | Pending |

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
or arbitrary physical acquisition shape is complete. Source-free queries with
more than one Values task step still hit the installed Host's direct-Values
compilation boundary; the ordinary Values-only packed route remains intact.
The same captured route also executes `SELECT DISTINCT id FROM records WHERE
id > 1 ORDER BY id`, returning `2, 3` in order. The source includes duplicate
`id=3` rows; DISTINCT supplies a proven key before sorting. Arbitrary source
ORDER BY still requires the existing total-order evidence and is not inferred
from the SQL spelling alone.
