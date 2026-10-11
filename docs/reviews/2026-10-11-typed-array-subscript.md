# Typed array subscript execution

## Scope and contract

Issue [#1195](https://github.com/actql/actql/issues/1195) identifies a checked,
complete JSON Program that the Relation lowerer refused with
`ExpressionNotImplemented("subscript")`. This change connects the existing
typed-access contract in `docs/spec/language.md` and existing machine node in
`spec/contracts/actql-expressions.json` to the ordinary expression frame.
It adds no Frontend evaluator, fallback, schema change or new identity domain.

The receiver is evaluated before the index, once each. The index must be a
nonnegative safe integer; NULL, negative, fractional and unsafe indexes fail
even when the receiver is NULL. A valid index into a NULL/empty array or outside
its extent produces NULL. The result retains the item contract and is nullable.
No safe-integer index is narrowed before the extent comparison.

`SubscriptValue` and `SubscriptIndex` use the existing continuation and root
owners. The receiver's retained root survives bounded measurement and root
registration of the selected value. Only then is it released. Closing a frame
closes pending measurement and owned roots once; caller roots remain borrowed.
Ordered-reference evidence visits `/body/value` before `/body/index`, although
canonical serialization writes the `index` key first.

## Independent evidence

The complete Issue Program and empty-array control are retained in
`src/query_program/typed_subscript_program_test.mbt` and
`scripts/fixtures/typed-subscript-input.mjs`. Their expected `answer` values are
`[{"v":1}]` and `[{"v":null}]`, with one nullable Number column named `v`.
The fixtures retain the Values input, checked Stage and Named Result roots.
They do not manufacture runtime frames to bypass public preparation.

The pre-change focused JS run `run-dTGhMW` failed the independent checked
Program's lowering assertion. After connection, `run-0AwQ1t` passed 37/37
selected JS tests, including existing array, property, expression-frame and
ordered-reference regressions. `run-lLW3VQ` passed 2/2 independent Node fixture
and narrow-profile tests. These editing runs used uncommitted source; their
receipts are not a claim of clean-HEAD packed acceptance.

Resource expectations are derived independently of successful measurements:

- `[2,1][1]` requires logical work 18: array work 10, two new entries,
  index production/consumption 2, array consumption 3 and selection production 1.
  Work 17 fails with typed `LogicalWorkLimit`; quantum 1/7/256 and draining
  preserve the result, work and final reclamation.
- The same expression needs nine unretained workspace slots. With retained
  measurement, eight cursor handles, two traversal frames, a speculative
  successor and the subscript continuation require twelve slots. One-short
  fails with `WorkspaceLimit`. Array construction needs seven live bytes;
  six fails with `LiveValueLimit`.
- Selecting a 1792-byte decomposed-Unicode/astral Text requires work 8973 and
  a 3590-byte peak. A cancellation fixture closes during selected-value
  measurement while the receiver still owns 1796 bytes. No work is refunded,
  no borrowed root is released, and repeated close leaves zero owned workspace.

## Public acceptance command

After a clean commit, use the normal bounded heavy guard to run:

```sh
node scripts/test-packed-public-query.mjs --typed-subscript-only --keep-artifacts
```

The normal five-package producer runs prepack and installs outside the checkout.
The selection contains six successes, two runtime failures with denied Results
and two check-time refusals through both Local and HTTPS. Success assertions
read Named Result rows and declared columns, then attach, resubmit the same
request and verify no additional acquisition. The existing retained-cohort
restart reads the original Result in fresh processes without new dispatch or
Compute. Unrelated Planner, Effect, INFER, Graph and String campaigns are not
part of this selection.

Public acceptance is not established by the editing tests above. The handoff
must identify its clean source SHA, all five package digests, actual completion
inventories, process-stop receipts and released locks. CI, Preview and full-Core
coverage remain separate and must not be inferred from this local selection.
