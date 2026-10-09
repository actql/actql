# Pipe EXTEND window inputs

## Selected contract and counterexample

Adopted main: `ffe46cdae6d064a60da517dec2937eeaee4a1c30`, normally merged
without conflicts. This branch retains the unmerged INNER correlated UNNEST
parent #1111 (`b96374bacb8a7f0465f3a3e3d63a25ec7932ead3`); final target is main.

The official [GoogleSQL Pipe EXTEND reference](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/pipe-syntax#extend)
allows window calls and operator-local WINDOW declarations while propagating
the input columns. The independent common Analytic Program was already checked;
both equivalent source forms failed at the parser before this connection:

```sql
FROM orders
|> EXTEND ROW_NUMBER() OVER (ORDER BY id) AS pos
|> ORDER BY id

FROM orders
|> EXTEND ROW_NUMBER() OVER w AS pos WINDOW w AS (ORDER BY id)
|> ORDER BY id
```

`src/query_program/pipe_extend_window_test.mbt` authors the entire expected
Program independently. Its final projection retains the full declared input
row followed by pos. Baseline evidence `run-7NxQHo` / `focused-test-sdqJkF`
has one successful checked JSON control and two source parsing failures.

## Connection and scope

The existing projection parser extracts direct and scalar-contained windows.
An EXTEND resolves only its own WINDOW declarations, using existing inheritance,
case-insensitive lookup and duplicate/forward-reference checks. It introduces
an ordinary Analytic/AnalyticExpressions operation, followed by Extend.

The lowerer adds already evaluated window slots to the public current row and
uses the existing expression lowerer for scalar operands. Every sibling sees
one immutable input snapshot; another sibling output is not a window input or
scalar alias. Existing range aliases keep their original slots across SET.
Authored names resembling private slots remain ordinary columns; generated
private slots cannot be named by users and are removed before publication.
No runtime owner, execution path, implicit acquisition, Result, budget or
analytic signature/frame extension is introduced.

Pipe SELECT's local named WINDOW and windows inside Pipe WHERE remain separate
Frontend coverage gaps. This connection does not claim full GoogleSQL analytic
support or implicit aggregate/default frames.

## Independent public fixtures

The existing normal/focused window-scalar cohort includes eight new positives:
independent JSON, inline and named EXTEND, a typed parameter operand, empty
input, WHERE/SELECT/ORDER/LIMIT continuation, immutable versus current LAG
values after SET, and distinct local WINDOW declarations in consecutive EXTENDs.
Five new exact ClientProgramInvalidInput refusals cover an existing column
collision, a sibling alias, an authored private-slot reference, a leaked WINDOW
name and a dropped range alias. Public refusal checks require zero Run admission
and Source I/O.

For input (id,amount) `(4,20),(1,NULL),(3,10),(2,20),(5,NULL),(0,999)`,
WHERE id > 0 and descending amount/id ranking followed by ORDER BY id produces
n values `[4,1,3,2,5]`. Full rows publish columns amount,id,n; amount remains
nullable, including empty input. Input enumeration differs from both analytic
and final order. The immutable-range control independently expects original
LAG values `NULL,NULL,20,10,20` and changed values `NULL,NULL,-20,-10,-20`.
Existing helpers check Named Result, rows, stream completion, describe column
contracts, hidden-field absence, acquisition once and same-Run replay/reread.
No generated Program is patched after lowering.

One newly authored compiler test originally omitted the Pipe separator before
LIMIT (`ORDER BY pos LIMIT 1`). Its source was corrected to `ORDER BY pos |>
LIMIT 1`, retaining the intended limit and expected results. The intermediate
24/25 failure (`run-YxEg7Z`) and diagnostic 5/6 (`run-mImWpm`) are fixture
syntax failures, not successful product evidence. Corrected callers pass 25/25
(`run-K3aI9V`).

## Grammar and identities

The grammar changes from `6c736875bc97084060934856c845f467405e231cdd8971494e8d0934c043b18b`
to `2d24701e5ceee0f06400e197124eb7d9c05b74b88de7bd76500820b04fe692ed`
(SHA-256 CIDs). Complete preceding grammar and independent Run preimages are
retained in `scripts/fixtures/pre-pipe-extend-window-grammar.json`.
The independent canonical oracle derives current Values Run
`436bf4c3edf01dc70bb6b1258516807ad35c4d9f9fd5485a9876c704c2aba9ec`,
while preserving preceding `4dcc3bab...` and earlier historical vectors.
Unit/proof/ResultPlan and Program/value contracts are unchanged; grammar-bound
invocation, executable/compiled Plan and Run identities change. Saved old Runs
are not relabeled. Generated manifests, metadata, imports and canonical vectors
are refreshed using the existing generators, never by editing generated bodies.

## Executed checks and remaining acceptance

- Pinned JS compiler, analytic/scope callers and Values publication identity:
  26/26, `run-oBCsOy`, `focused-test-I3xb2y`. Exact UnknownReference and
  DuplicateOutput reasons are checked for the new lowering refusals.
- Fixture, independent grammar/Run preimage and compilation-manifest tests:
  20/20, `run-PS69Pg`, `focused-test-qZCkr8`; executed before adding the fifth
  public refusal, whose matching MoonBit counterexample already passes.
- Final public fixture/document/import checks: 19/19, `run-8dc6jI`,
  `focused-test-rSzQHg`, including all five public refusal fixtures.
- Existing compilation-manifest, metadata, spec-family and canonical-vector
  read-only checks pass; no metadata writes remain and 382 vectors match.
- Fresh five-package Local/HTTPS acceptance, submitted-HEAD CI and three-target
  runtime execution are not yet established by these compiler/fixture checks.
  Full Core, full packed and performance campaigns were not run.
