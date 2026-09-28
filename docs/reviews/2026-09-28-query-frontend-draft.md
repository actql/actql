# Query Frontend B2 draft scope

This draft uses the bounded multi-task Host merged through PR #34. Its
current integrated main base is
`83274c3e2990d2926e8ebd44109d9470aa1df225`; PR #34's changes are
absent from the current branch diff against main. The original PR-3/PR-4
requirements remain in the Frontend work order. This draft records the
implemented combinations; it does not claim completion of all PR-3/PR-4
forms or GoogleSQL compatibility as a whole.

SQL and Pipe use the same bounded lexer, expression representation, query
lowering, source builder, Program admission, checker, planner, and ordinary
Host. The packed test compiles SQL/Pipe into Program JSON before calling
`client.aql(..., {format: 'json'})`. The SDK does not accept raw SQL/Pipe text.

| Adopted area | Implemented and exercised in this draft | Remaining or explicitly rejected |
| --- | --- | --- |
| Expressions and names | Closed scalar expression tree, precedence, NULL, strict query `CONCAT`, legacy AQL `concat`, alias priority in GROUP BY/HAVING/final ORDER BY, case-insensitive column/field/alias lookup even when quoted, non-output ORDER BY expressions with a private slot | Full scalar typing/failure matrix; WHERE and peer SELECT aliases remain rejected; analytic OVER scope is distinct from final ORDER BY |
| SELECT and source | Values and one captured source through SELECT/WHERE/projection; named noncorrelated FROM subqueries and source maps; typed declared `@parameter` references pass through the ordinary checker and value binding | Correlated subqueries and broader source compositions |
| JOIN | Direct Values INNER/LEFT and bounded CROSS; FULL/USING via an identity-bearing DISTINCT CTE; one Pipe JOIN with an optional preceding WHERE; NULL extension, output projection and duplicate rows in packed cases | General JOIN chains, post-projection Pipe JOIN, unkeyed FULL JOIN and multiple independent physical acquisitions |
| Aggregation | COUNT/COUNTIF/MIN/MAX, supported SUM/AVG numeric profiles, bounded STRING_AGG and nonnullable keyed ARRAY_AGG; group/HAVING aliases and empty global COUNT | Nullable ordered ARRAY_AGG, collection composition and the remaining aggregate failure matrix |
| Order, distinct and limit | Selected-expression DISTINCT correspondence, hidden sort slots, NULL direction, OFFSET and final ORDER/LIMIT after a three-term UNION ALL; r1's explicit `LIMIT 0` rejection | Wider tie and limit matrix remains |
| CTE and sets | Nonrecursive used CTEs, two references to one producer, sequential/branched CTEs; UNION ALL/DISTINCT, INTERSECT/EXCEPT DISTINCT and exact BY NAME in supported two-operand forms; three-term UNION ALL | Unused CTE and broader set/subquery composition; a different captured source or filter per operand; Remote physical acquisition count is not established |
| Pipe | SELECT/WHERE, simultaneous EXTEND/SET, DROP/RENAME/AS, supported AGGREGATE, ORDER/LIMIT, one JOIN shape and a parenthesized SQL right set operand | Other Pipe JOIN scope forms and collection aggregation after SET |
| Analytic | Limited inline OVER ranking/navigation and framed COUNT/SUM/AVG; updated and previous Pipe alias snapshots | Remaining frame/signature/scope matrix |

The exact Program comparison uses
`spec/frontend/fixtures/query-pair.expected-program.json`; expected rows
are independently authored in `query-pair.expected-rows.json`. The packed
Local and HTTP test reads Named Results for Values, captured input, alias
collision, LEFT/FULL joins, CTE reuse, set multiplicity, strict/legacy
concatenation, aggregates, Pipe snapshots and limited OVER. It also checks
that the three-term SQL and Pipe UNION ALL forms preserve duplicate rows and
apply final ORDER/LIMIT to the entire set. Local acquisition counting supports
one physical read for reused CTE input; HTTP Result success alone does not
establish the remote physical count.

## Selected imported acceptance cases

The imported `spec/frontend/acceptance-index.json` remains a frozen
requirements index. This table records only evidence exercised by this draft;
it does not turn all 140 imported cases into passes. `compile_test.mbt` and
`query_test.mbt` exercise the semantic and rejection edges, while
`scripts/test-node-client-package.mjs` reads the listed successful Results
through installed Local and HTTP Clients.

The PR #37 review corrections are exercised separately: declared parameters
survive ordinary, CTE and set Program generation and reach the existing
checker; absent, supplied, undeclared and wrong-type bindings stay distinct.
Quoted column and alias spelling resolves without changing the authored
spelling, while quoted relation paths retain their separate rule. A hidden
ORDER BY expression is derived once before sorting and removed before Named
Result publication; DISTINCT reuses the selected slot. Packed Local and HTTP
Results verify the resulting order and a failing hidden expression prevents
publication.

| Cases | Evidence in this draft | Boundary |
| --- | --- | --- |
| SQL-01 | `scripts/query-program.test.mjs`; independent expected Program and rows; packed pair Result | Exact Program under one context, then installed Host Results |
| SQL-02–06 | `src/query_program/compile_test.mbt` Pipe snapshot tests; packed SET/EXTEND/DROP/RENAME Results | Current names and prior range slots remain separate; invalid peer references reject |
| SQL-07, SQL-29 | Typed `AmbiguousColumn`/`UnknownColumn`/`AmbiguousRelation` and `UnsupportedJoin` regressions in `compile_test.mbt` | Non-equality outer ON is rejected before any Program is issued |
| SQL-08–12 | JOIN/USING and set compilation in `compile_test.mbt`; packed Local/HTTP rows | Includes NULL extension, duplicate multiplicity, positional and exact BY NAME alignment in exercised forms |
| SQL-13–19 | Group, NULL ordering, missing total-order witness and pagination tests in `compile_test.mbt`; packed Local/HTTP rows for supported forms | Tied sort keys without a candidate key are rejected by the ordinary checker; no arbitrary representative is selected |
| SQL-20–22 | `query_test.mbt` rejects zero, parameterized and out-of-range LIMIT; `lower_test.mbt` checks integer range | Rejection occurs during frontend parsing/lowering; explicit provider read/write counters for SQL-20 remain unverified |
| SQL-23–26 | Strict and legacy CONCAT plus eager failure and CASE in `lower_test.mbt` and packed Results | Existing legacy behavior remains distinct from query CONCAT |
| SQL-27–28 | CTE compilation and packed Local read counter; recursive CTE parser rejection | One Local acquisition for reused CTE; HTTP physical read count remains unverified |
| SQL-30–32 | Limited ranking/navigation and frame tests in `compile_test.mbt`/`query_test.mbt`; packed Results | Adopted ROWS forms and RANGE rejection; remaining frame/signature matrix is pending |
| SQL-33–34 | `SELECT *` nested array/vector check in `compile_test.mbt`; packed Local/HTTP typed rows; checker rejection without a captured schema | No helper field egress or provider sampling to invent unknown schema |

The imported diagnostic catalog's exact code mapping is still pending;
current MoonBit
issues and source spans must not be reported as those registered codes.

The PR Validation section records the fixed SHA, current target results, and
remaining checks. The initial pre-merge implementation parent
`04ca66778b341a62c871298190ae9f9234110896` passed the three focused
query packages and packed Local/HTTP smoke. After integrating main, the
focused query packages and packed smoke were rerun; they are not substitutes
for final affected gates and same-SHA Linux CI.

Before Ready, close the missing high-risk rejection/diagnostic cases in the work order,
verify the affected spec and three-target Core gates, and confirm the final
packed artifact on the submitted SHA.

The r1 source specification, profile, and acceptance case SQL-20 explicitly
reject `LIMIT 0` because the existing `take` contract requires a positive
count. This is an adopted profile restriction, not an implementation gap.
