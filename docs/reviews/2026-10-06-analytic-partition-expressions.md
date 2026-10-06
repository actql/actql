# Analytic partition expressions through public source

## Existing boundary and reference

Fixed integration baseline `54db8b2292d39987f99b8ec85970729bd14f56c9` normally
merges Graph subtraction source HEAD `8aa30284d8d7d06eb04e0ddcdbb492e6617202e2`
with main `c94f4a83f543a0f04bf86040e144686966bc2112`. Main's numeric public
checking ingress and Effect cleanup-custody changes are adopted unchanged.
Graph graft, mean, Reach and shortest-path remain unconnected common consumers
at this baseline; Frontend does not approximate them through old Graphs.

The ordinary expression/analytic checker can consume a privately derived
Boolean partition key. Its equivalent source fails because `QueryParser::over`
reads only a path. Pre-repair `run-mZoPbU` is 0/1: the independently authored
complete Program passes the ordinary checker first, then parsing source fails.

The selected [GoogleSQL window specification](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/window-function-calls)
allows partition expressions over the input scope, excludes constants and
sibling SELECT aliases, and has its own key-type restrictions. This unit
connects row-dependent expressions to the existing ActQL common key types.
It does not claim the complete GoogleSQL type profile: common finite binary64
number keys differ from Google's floating-point exclusion. Named windows,
optional ordering, frame defaults and nested windows remain coverage gaps.

## Repair and preserved meaning

`QueryParser::over` now uses the ordinary bounded expression parser, retaining
real source origins, precedence and argument structure. The AST interface was
already an expression list and does not change. `analytic_partition_field`
rejects literal/parameter-only expressions rather than reinterpreting an ordinal;
otherwise it reuses `analytic_order_field`. There is no constant folding.

The existing lowerer supplies immutable SELECT input slots, including qualified
names and Pipe range snapshots. Repeated expressions share a private evaluated
slot across partition keys, OVER order and different windows. Authored partition
lists retain repeats/order. The common checker owns member, operand, nullability
and equality-key contracts, while the existing expression execution preserves
conditional demand. Final projection removes helpers before publication.

No expression evaluator, sort, checker, planner, capacity, execution owner,
Model, Effect, CTE, storage or replay changes. No type/equality evidence is
fabricated by Frontend. Unknown or removed names retain their existing refusal
boundary; expression failures do not become NULL or partial successful Results.

## Independent obligations and local evidence

The complete expected Program in `analytic_partition_expression_test.mbt` is
authored independently. Both SQL and Pipe lowering compare the whole Program
with it after normal checker admission. Additional tests distinguish input
receivers from colliding aliases, immutable/current Pipe slots, shared and
repeated keys, constants, parameter-only keys, unknown members and invalid
operand/equality-key types.

Public Source arrival order is ids 4,1,3,2,5,6,0; `WHERE id > 0` removes id 0.
For `amount > 25`, FALSE ids 1,2, TRUE ids 4,5 and NULL ids 3,6 form separate
partitions. Final id-ordered positions are `[1,2,1,1,2,2]`. CASE ELSE or
COALESCE moves NULL to the FALSE bucket and yields `[1,2,3,1,2,4]`. Changing
current amount to its negative yields positions `[1,2,1,3,4,2]`, while an
original range still gives the original partition result. These expectations
are designed from the selected rules, not emitted compiler output.

The existing packed driver registers 11 normal cases (one independent JSON
control), 8 preparation refusals and 1 demanded execution failure per transport.
They include SQL/Pipe, Boolean/CASE/COALESCE keys, alias collision, shared
partition/order slots, lazy conditional demand, empty typed Result, existing
direct columns and Pipe snapshots. Existing row/type/column order, private
column exclusion, stream completion, same-request Run identity, single acquired
Source, attach/reread and pre-admission/provider-I/O assertions are retained.
No generated Program is supplemented or corrected in the driver.

The initial repaired selection is 22/23 (`run-kX4aMQ`); the only failure is
an incorrect hand-counted origin (37 instead of 39), not product behavior.
The actual source substring was independently counted to offset 39..49.
The corrected origin tests and affected Values Run vector passed 3/3 JS;
independent fixtures/profile consumers/identity vectors passed 20/20 Node
(`run-bb9EdD`). The 22 passing initial cases include the new complete Program,
partition/ORDER slot sharing and existing property/order callers. Both failures
are retained, not represented as successful invocations.

Manifest, metadata, spec-family and canonical-vector freshness checks passed;
changed-file formatting and diff checks are retained. Full Core, Wasm/native,
proof, performance, complete packed corpus and Cloud are not run locally.
The submitted PR body records the actual final SHA, ordinary pack/digests,
public acceptance receipt and exact automatic CI outcome separately. Public
acceptance remains unproven until that final receipt passes.

## Identity and delivery

Existing opaque query expression grammar bytes are unchanged. Normative query
rules update grammar CID from
`f6691d7e84028f06cef976870509421ba61d6f6310f7f32171f8ad5cf6ad422e` to
`76c09e292bf9def41ddb0d40fe5bf59b60483e1a6c2ebde654a54bb3153c4ead`.
The independent canonical preimage yields Values Run CID
`7c37b6c976ba6501b6f942b50543ec3894c1b5ab723c7201478d87ea9e165aa4`.
Historical grammar/Run vectors are retained. Registry, value contracts, common
expression/analytic laws, Unit and Result Plan are unchanged. Generated pins
and metadata follow their owners; independent expectations are not regenerated
from product values.

This delivery is stacked on #596 and retains its unresolved #593/#586 ancestry;
the eventual target is main. It does not establish overall migration completion.
Helpers, prior failures, package manifest, receipt and CI readout are archived in
`review-artifacts/b-analytic-partition-expressions-2026-10-06/` in the author
worktree. No PR merge, force push or manual CI rerun is performed.
