# Qualified Relation star connection

Owner: B. Base: `b98a50ff763d1367e344fdfa8aea380ec8749132`.

## Counterexample and selected semantics

The independently authored ordinary Program in
`src/query_program/qualified_star_test.mbt` projects `id,amount` from Values
and orders by `id`. The corresponding source:

```sql
SELECT o.* EXCEPT (customer_id, status)
FROM orders AS o
ORDER BY id
```

failed in the parser on the base (0/1, `run-08m07n` /
`focused-test-xk9zs4`). No public pre-fix execution was attempted.

The selected [GoogleSQL SELECT expression.* clause](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#select_expression)
permits a table alias and preserves its field order. This unit connects that
Relation-range case, including EXCEPT, through SQL/Pipe/CTE/JOIN/GROUP to the
existing Program. STRUCT-valued/arbitrary expression receivers, unqualified
JOIN star and direct Graph star retain explicit coverage gaps; they are not
redefined as Relation ranges or a complete-language restriction.

## Implementation boundary

The parser retains a named receiver as an ordinary Reference AST in the star
projection's expression field. Quotation and exact token positions are retained;
there is no rendered expression text, JSON selector injection or reparsing.
Lookahead and AST creation obey existing query work/expression-node bounds.

Expansion uses the existing named range and physical-slot scope. EXCEPT applies
to that range only. A missing receiver is refused even when the projection could
otherwise look like an identity star. Single JOINs requiring range expansion
use the existing shared-scope assembler; its ceilings, ports and joined NULL
contracts still come from the common Program/checker. GROUP ordinals count the
expanded list and validate every selected input value as a grouped value.

SELECT materialization ends its input range scope. A deferred query ORDER keeps
the required SELECT input snapshot until its physical projection is emitted;
afterward the old range is unavailable. SET/DROP/RENAME still retain an earlier
range's original value slots, and AS still replaces ranges with the current row.
There is no Graph compatibility layer, execution owner or invented type/order
evidence in this connection.

## Independent acceptance and identity

The fixed public fixture contains ten successes and seven preparation refusals.
It includes an authored JSON control, a complete range, hidden-input ordering,
quoted dot-containing aliases, the original positive values after SET negates
the current columns, replacement AS, nullable LEFT JOIN output, GROUP ordinal,
CTE scope and typed empty output. Independent rows include NULL and duplicate
Source rows. The ordinary harness verifies rows, complete schema/column order,
stream completion, one acquisition session and same-request/re-read identity.
Refusals require zero Run admission/provider I/O and cover missing/displaced
ranges, post-projection access, ungrouped columns, unknown exclusions and
currently unsupported multi-part field receivers.

The grammar and query rules update the grammar-manifest self CID from
`sha256:3fe450061e6884fc773ecda7492de02dd27a15219a6832e8e490a096e29b1c9a`
to `sha256:1e69c47a6aba9a6bc728c10d4edbeeb1e72964e0504d82d7f54fde65293de06a`.
The independent normative-preimage test retains the predecessor. Current complete
document imports, normative document references and canonical vectors were
updated by the existing metadata generators. Old pins/Runs are not relabeled.
The Program schema, expression contract and execution algebra are unchanged.

## Verification checkpoint

After implementation: focused JS passed 25/25 (`run-mxu8J0`), including parser,
star exclusions, GROUP ordinals, single-JOIN grouping and alias ORDER callers.
Public fixture/selector Node checks passed 11/11 (`run-64KKvS`). Independent
manifest checks passed 7/7 (`run-j4nxdZ`) after their metadata update.
Workers and Node fixture generators passed their read-only freshness checks;
they required no fixture source change for this parser/lowerer update.

Normal five-package Local/HTTPS acceptance and submitted-SHA CI are pending at
this checkpoint. Syntax/checker success is not counted as executed acceptance.
Full Core, all targets, complete packed/Planner, performance and Cloud suites
are not part of the local checkpoint.
