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
| GROUP BY, aggregates, HAVING | Existing group | Alias collisions, empty/NULL input, aggregate failure order | Partial: scalar reductions and ordered ARRAY_AGG/STRING_AGG lower through group; captured COUNT/GROUP/HAVING runtime passes, ordered collection runtime and failure matrix pending |
| DISTINCT, ORDER BY, LIMIT/OFFSET | Existing distinct/sort/take | Output-only equality, hidden fields, ties, limits | Partial: alias priority, private selected-expression slots and non-output ordering; captured DISTINCT→ORDER runtime passes, ties/limits pending |
| Nonrecursive CTE | Shared Stage input and dataflow | Multiple references with one physical acquisition | Pending |
| UNION ALL/DISTINCT, INTERSECT/EXCEPT DISTINCT, exact BY NAME | Existing append/row-set | Positional alignment, type mismatch, duplicate rows | Partial: two source-free Values operands execute through packed Local/HTTP Clients; captured operands, Pipe set, CTE reuse and broader type/order cases remain |
| Pipe SELECT/WHERE/EXTEND/SET/DROP/RENAME/AS/AGGREGATE/JOIN/order/limit/set | Shared query scope and Relation lowering | Snapshot RHS, old range slots, SQL/Pipe pairs | Partial: SELECT/WHERE/AGGREGATE/ORDER/LIMIT, EXTEND and scoped SET/DROP/RENAME/AS; JOIN/set and some post-projection scope remain |
| Adopted analytic/OVER | Existing analytic | Closed signatures, inline scope, frame/order rejection | Partial: inline OVER, bounded checker and packed RANK Result; full negative and frame matrix pending |
| Bounds, origin maps and Grammar Manifest | Existing owners | Before-allocation bounds, source diagnostics, pins/vectors | Pending |
| Ordinary execution and Named Result | Packed Local and HTTP Host test connection | Values and acquired input; CTE acquisition counter | Partial: source-free direct and filtered Values plus captured filter/query run through packed Local and HTTP Remote Host; CTE reuse pending |
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
surface and the broader SQL/Pipe scope remain pending. The packed Local and
HTTP Remote Host route also executes `RANK() OVER (ORDER BY id)` on captured
rows with a duplicated sort key and returns ranks `3, 1, 2, 3` in input order.
The test Host explicitly supplies analytic resource ceilings.
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
The common Result-plan issuer maps physical task indices back to checked Unit
indices when a Stage splits. These fixtures do not establish captured set
operands, Pipe set syntax, mixed operator grouping or CTE acquisition reuse.
ARRAY_AGG requires the adopted `IGNORE NULLS` and explicit order spelling;
STRING_AGG requires a literal delimiter and explicit order. Both lower to the
existing group call. The independent checker accepts the bounded ARRAY_AGG
example; STRING_AGG reports the missing Host string-byte limit instead of
inventing one.
LIMIT and OFFSET now parse the full exact safe-integer range, rejecting zero
LIMIT, fractions, and values above `2^53-1` before Program construction.
