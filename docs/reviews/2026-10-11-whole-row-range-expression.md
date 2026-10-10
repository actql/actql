# Ordinary row ranges use common object expressions

## Fixed requirement and counterexample

The adopted [GoogleSQL range-variable rule](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#range_variables)
distinguishes a value table's original row value from an ordinary table's
STRUCT of all declared columns. The fixed analyzer reference remains
GoogleSQL d82db99a923a46571f543a13899dc791a7b6f743.

At parent #1354, 3e90979771832b4b3330c733e01f83a624b05f99:

```sql
SELECT chosen AS row, chosen.element AS value, chosen.position
FROM (FROM UNNEST(@items) element WITH OFFSET position) chosen
ORDER BY position
```

With the declared nullable numeric array [2, null, 2], independent rows are:

```json
[{"row":{"element":2,"position":0},"value":2,"position":0},
 {"row":{"element":null,"position":1},"value":null,"position":1},
 {"row":{"element":2,"position":2},"value":2,"position":2}]
```

The row object is nonnullable and closed. Its element field is nullable and
position is nonnullable. Baseline run-ZitVaN executes 1/2: the independent
ordinary object Program checks, while the source rejects Expression.UnknownReference.
No incorrect public rows are claimed from this compiler-only baseline.
Original source/control and baseline are preserved at
/private/tmp/actql-b-whole-row-range-independent-control.json and
/private/tmp/actql-b-whole-row-range-3e9097977-baseline.mbt.

## Implementation boundary

The existing expression append API accepts an optional scope callback yielding
public field names and evaluated slots for a bare row reference. Normal field
resolution wins first. Only a unique surviving ordinary range becomes the
existing object/field expression; no Frontend type, evaluator or storage form
is added. Object construction is charged to the compile work limit and retains
the reference origin. AS remains a logical binding, without eager object derivation.

SQL single-input projection, Pipe expression scope and available ORDER scope
use this connection. SET preserves the captured original row slots; AS after
SET captures the new values. DROP/RENAME retain surviving ranges, while a new
AS captures only current columns. ORDER uses the existing alias-first resolver
and refuses any range whose slots are unavailable after materialization. A
single value table retains its scalar or original whole-object behavior.

A missing member of a valid row now reaches the existing common property
checker, which reports UnknownField("missing"). A removed receiver still
fails name resolution. The corresponding caller regression distinguishes these
boundaries instead of accepting any generic failure. Public preparation must
reject both before Run admission and provider I/O.

Specialized grouped, analytic and JOIN whole-row expressions are follow-up
coverage, not newly imposed language restrictions or claimed completed support.
No Graph, CTE owner, inference, physical strategy or Host implementation changes
are included. Shared-source acquisition remains an existing owner responsibility.

## Independent fixtures and focused evidence

- The complete single-input object Program is authored independently and
  compared to source lowering, including producer, derive and Result bindings.
- Focused run-4ZVPH6 executes 47/47 MoonBit JS tests covering the changed API,
  property callers, value-table controls, scope/order and the consuming Run CID.
  Node policy/vector checks there execute 72/73; the remaining old grammar
  expectation is subsequently derived from the frozen preimage and new document
  bytes, then run-d739gC passes its 5/5 selected tests. The other 68 Node tests
  passed without subsequent changes to their relevant inputs.
- run-d739gC passes read-only compilation-manifest, spec-family, canonical JSON,
  Workers and Node fixture freshness checks. Selected query_expression API
  generation compiles its supported JS/Wasm/native interfaces; this is not
  three-target runtime execution or a repository-wide API campaign.
- The existing public composition cohort gains nine normal cases and four
  typed refusals, including a standalone JSON control, empty input, implicit
  output naming, SET snapshots/rebinding, DROP/RENAME, column priority and
  computed ORDER. Rows and describe contracts are independent authored data.
  The ordinary packed registration also includes them; no source/Program is
  patched after lowering. Whole-row objects have checked additional_properties
  false; parameter declarations retain their separate authored contract.

The entire authored inventory is 3,746 cases (2,363 normal, 1,333 refusal,
50 execution-failure cases). Its registration digest is
1333d16fb3085bbfa3475fd8e2ac0c39d7a715f2fa69557cec85fed1b93acfd9.
This count is not a claim that the complete inventory was executed.

## Identity and delivery

Syntax bytes and common expression/Program contracts remain unchanged. The
query rules document changes the grammar manifest from
683c36d56e7d45ac12cb3cd72f361b6ebe2656ce4b2d05b3ddc4be3270d4f0fd to
594cac2184f658e9e07993e1846fd0f8177295affaf213a498413757c180fa56.
The complete prior Values preimages are retained in
scripts/fixtures/pre-whole-row-range-values-identities.json. Independent sorted
JSON hashing yields the new containing Run definition
980299c966ef566cf2b399e1f4181218586aaa72b0bce8d57b39056e2dc7aff2;
Unit, Program, ResultPlan and value identities are unchanged. Historical Runs
retain their original pins rather than being relabeled.

Submit as a Draft child of #1354 until that parent reaches main. The PR records
the exact normal-pack source revision, five tarball digests, original receipt,
Local/HTTPS outcomes and exact-SHA CI state after execution. Compiler/policy
success does not establish public execution or complete Frontend coverage.
No merge or manual CI rerun is part of this unit.
