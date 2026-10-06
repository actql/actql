# Selected aggregate expressions through the existing Group owner

Owner: B. Base: parent #509 (`fix/frontend-having-aggregates`) at
`9679a37fadf16ac676e16b62b1a99f46ec9aa9a9`, containing main
`64046e37a1cadb2148edeab7cbf85b96d125b518`. Final target is main; retain this
parent base until its merge. The separate grouped single-JOIN repair is #512;
this unit does not depend on or include it.

## Contract and first failure

```sql
SELECT COUNT(*) + 1 AS next FROM t
```

The adopted SQL select-list expression and ordinary Group/derive contracts can
express this query. An independently authored complete Values Program passes
the common checker before source parsing fails on the base (0/1,
`run-eGPQxK`). The same full Program becomes the positive exact-canonical
comparison. Expectations are not obtained from the compiler or Result.

The [GoogleSQL SELECT expression reference](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#select_list)
and [aggregate call contract](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/aggregate-function-calls)
separate evaluation of aggregates from selection of their scalar expressions.
This connects the already adopted expression/aggregate subset; it is not a
claim of every aggregate modifier, nested aggregate or analytic expression.

## Implementation and scopes

The existing aggregate-primary parser used by HAVING also recognizes calls
inside SQL SELECT scalar trees. The parsed tree references private evaluated
Group outputs, retaining original source spans and bounded parser accounting.
Whole-call aggregate and analytic projections retain their existing shape and
producer identities. Pipe AGGREGATE/EXTEND and WHERE placement restrictions are
unchanged; this does not introduce aggregates into those scalar scopes.

Group carries the additional private aggregate projections; ordinary SELECT
retains only the user's projection list. Call reuse requires the same function,
arguments, DISTINCT/order/delimiter and resolved input slots. Qualified input
references and unqualified input references are equal only when they resolve to
the same value. Calls inside SELECT always use its input snapshot, not a newly
introduced SELECT alias. A selected aggregate can supply an equivalent embedded
call without making its authored alias visible to SELECT siblings.

Only parser-generated references enter the grouped SELECT expression scope.
The parser excludes their names from every authored token. A star can still
retain an implicit input column with that private-looking name: the existing
physical allocator separates the aggregate output and the star preserves the
original column. An independently authored full Program fixes this case too.
The allocator starts at the supplied physical entry count; two input entries
plus two retained keys produce suffix 4, not an assumed first free suffix 1.
An intermediate exact comparison differing only in that suffix is recorded as
expectation allocation bookkeeping, not a wrong Result or changed semantic
expectation.

HAVING can consume the completed scalar alias through its existing evaluated
projection, and subsequent SQL/Pipe ORDER/SELECT use the ordinary output scope.
Ungrouped inputs and same-SELECT sibling aliases remain unknown references.
Private aggregate/expression columns are removed by the ordinary projection.
NULL, numeric profiles, key/order evidence, evaluation failures and capacities
remain the common checker's and execution owners' responsibility.

No common Owner, execution strategy, capacity increase, fallback, schema/law
pin or public AST interface is added. The expression production is already
closed by query-text.md, so its grammar text and manifest preimage are unchanged.
D's CTE/predicate/assert/Effect and cancellation/Model-wire implementation,
H's Effect/Ledger work, A's progress/retention and C's Graph are not edited.

## Independent public cases and evidence scope

The existing packed acceptance corpus includes an independent captured-Source
JSON control and authored source cases. They retain WHERE, duplicate and NULL
input, DISTINCT cardinality, HAVING alias filtering, explicit LIMIT/OFFSET,
input/alias collisions, typed parameters, CTE/Pipe composition, empty global
input and source-free COUNT. Ordered column contracts include nullable SUM and
nonnullable COUNT/COALESCE. A demanded division failure must publish no readable
or describable Result. Invalid siblings, ungrouped input, COUNTIF type,
undeclared parameter and aggregate placement must fail before admission/I/O.

Public acceptance compares Named Result rows/order and Result.describe contracts,
column order and hidden-column absence, shared acquisition counts and same-Run
read/attach/resend behavior. Cases are registered in the ordinary packed corpus;
`--select-aggregate-expression-only` is a focused local selection, not a different
Host or post-lowering Program correction.

Executed checks and final clean-SHA package digests are recorded in the PR body
and external evidence. Pre-fix failure, working-tree regressions and pristine
package execution remain separate. `run-FL5N7C` only loaded a module and executed
zero tests; it is not evidence. Corrected bounded runner `run-72nKWY` executed
93 syntax, 30 grouped-scope and 26 aggregate caller tests. Later collision
regressions are recorded separately. This unit does not claim full Core,
all-target, full packed, proof, performance, Cloud or required CI completion.
