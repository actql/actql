# Anonymous evaluated windows in positional set operands

This is a frontend connection repair based on window parent #1265 at
`6015995f1de5d836323b1617bb8d7778eabf9b46`, containing main
`5f07afe9a21daaea46d420e7eb1b6567aa062d93`. Parents #1254 and #1265 are
now merged into main. Integration commit
`1a7c99650e45a5fdf75fd9e16f8121568850f64b` normally merges main
`8e1d4277cae568f498ab3b90543bbaff86bdb857`; no unmerged parent dependency
remains. Final destination is main, never a dependency branch.

## Existing meaning and fixed counterexample

```sql
DATA r = SELECT 1 AS x UNION ALL SELECT 2 AS x;
SELECT 0 AS a, 0 AS b
UNION ALL
SELECT ROW_NUMBER() OVER (ORDER BY x),
       ROW_NUMBER() OVER (ORDER BY x DESC)
FROM r ORDER BY a, b
```

Independent expected rows are `(0,0), (1,2), (2,1)`, a/b in declaration
order, both nonnullable numbers. The first operand supplies output names.
The existing query EBNF already makes the SELECT alias optional. GoogleSQL's
[SELECT aliases](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#implicit_aliases)
and [positional set rules](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#set_operators)
permit anonymous expressions and match values by ordinal. These selected
rules do not require automatic renaming of top-level ActQL Named Results.
No live Google-service execution or full standard conformance is claimed.

At the parent plus only the new regression, JS failed at parser unwrap while
the hand-authored ordinary JSON control passed: `run-jOPzqh`,
`focused-test-gAiCYR`, 1/2. Source inspection identifies the exact parser
refusal, `Function output requires a name`. This was not executed wrong rows.

## Minimal repair and independent expectations

The parser retains no authored name for an anonymous whole window, as it
already does for an anonymous aggregate. Program lowering admits the window
only at a terminal positional operand, allocates a collision-safe private
evaluated slot, and looks up its full call in the original SELECT snapshot.
Existing ordinal projection replaces private names with the left output names.
No window evaluator, Owner, grammar, wire, identity, numeric law or ceiling
changes. The clause alias helper skips anonymous values rather than attempting
to invent a name or expose their private slots. Named QUALIFY remains valid.

A complete hand-authored DATA Program matches semantic lowering exactly and
passes the usual checker. A separate ordinary JSON Values/analytic/append/sort
control defines the same independent row and type expectation. This repair
never rewrites a generated Program in its acceptance consumer.

Focused checks include opposing windows, a Pipe SET whose current x is the
negative of the immutable original.x, mixed anonymous/named QUALIFY, typed
empty output, and exact private UnknownReference failures. Public/BY NAME and
nonterminal anonymous output remains explicit UnsupportedProjection coverage;
this is a current connection limit, not a permanent GoogleSQL language rule.
EXTEND still requires an authored name at its existing parser boundary.

Five normal and two refusal cases enter the existing ordinary and scoped
public registration. One Source session, same-request reuse, Result reread,
rows/describe types/nullability/column order, hidden-field absence and refusal
before admission/Source I/O retain the existing consumer assertions. The
independent JSON window control from #1265 stays in the same unchanged cohort.
The scoped consumer now has 73 cases per transport: 48 normal, 25 refusals.

Authored registration: 3,356 occurrences; 2,126 normal, 1,183 refusal and 47
execution failures. Historical baseline ce027a937 is preserved. Digest:
`4d0101acad893b43f8c1926a763314a1075fafdc75b01e59ceeda41d0c05af84`.
This is enumeration of authored fixtures, not an oracle from product results.

The targeted counterexample/parser checks passed 9/9 at the pending patch:
`run-sdvgrf` / `focused-test-X3bwCa`. Complete final caller checks and
exact-SHA five-package/public receipts are recorded in the PR after execution.
They are not established by these lowering tests. Exploratory diagnostic test
compilation errors are retained and are not passing test evidence.

## Separate unresolved CTE boundary

The [saved SQL-parenthesized counterexample](fixtures/anonymous-window-parenthesized-set.sql)
still refuses UnsupportedProjection. It has the same independent expected
rows and columns as the ordinary JSON control above. `run-5ohrNR` /
`focused-test-Xps7Ee` fixed the refusal; the temporary cause-only trace in
`run-cgy3hw` confirmed the inner analytic sees positional_terminal=false.
The temporary trace was removed before final checks and is not product code.

`QueryParser::sql_operand` binds a parenthesized query through bind_query.
That creates an internal CtePart with carry_ranges=false. The existing
lower_script_relation CTE loop lowers that producer without the enclosing
positional_set_output, so the anonymous output refuses before outer alignment.
The direct Pipe set operand uses the existing parenthesized query directly
and retains its positional context; that public path is part of this repair.

This is a distinct CTE/export-scope connection gap, not capacity, common
window execution or a wrong expected result. The source, independent expected
Program and failure evidence are a concrete handoff for D's CTE boundary.
This PR does not blindly pass positional permission to all CTEs, guess
internal producer names or change CTE ownership in parallel. The issue remains
open; changing the new scoped control to the existing Pipe set form does not
claim the saved SQL-parenthesized form is supported.
