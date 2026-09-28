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
| Expressions and names | Closed scalar expression tree, precedence, NULL, strict query `CONCAT`, legacy AQL `concat`, alias priority in GROUP BY/HAVING/final ORDER BY, non-output ORDER BY with a private slot | Full scalar typing/failure matrix; WHERE and peer SELECT aliases remain rejected; analytic OVER scope is distinct from final ORDER BY |
| SELECT and source | Values and one captured source through SELECT/WHERE/projection; named noncorrelated FROM subqueries and source maps | Correlated subqueries and broader source compositions |
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

At implementation parent `04ca66778b341a62c871298190ae9f9234110896`,
`query_program` passed 51/51, `query_syntax` 27/27, and
`query_expression` 6/6 on JS. The packed Node/browser Client smoke passed
with installed Local and HTTP Hosts. Tests after the latest main merge and
B2's final gate and same-SHA Linux CI remain pending at this draft stage.

Before Ready, close the missing high-risk rejection/diagnostic cases in the work order,
verify the affected spec and three-target Core gates, and confirm the final
packed artifact on the submitted SHA.

The r1 source specification, profile, and acceptance case SQL-20 explicitly
reject `LIMIT 0` because the existing `take` contract requires a positive
count. This is an adopted profile restriction, not an implementation gap.
