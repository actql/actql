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

The first clean-source packed run (`8c3ed5b2ec4659216f893e74f4d8b98c0aee3b87`,
`run-3sNaUH`) failed in both transports at the Unicode fixture's column
assertion. Five preceding successes completed per transport; this is not a
completed inventory or fresh-process reread. The expected Text column omitted
its independently derived `max_utf8_bytes: 9` (decomposed `e` = 3 bytes,
CR/LF = 2, astral character = 4). The existing literal/item contract retains
that bound. The fixture now checks it explicitly without weakening equality.
Both workers exited with failure and zero live children; the normal guard
verified its owned group stopped and released both locks. The failed receipt
and five-package artifacts remain retained.

The corrected clean-source run (`a8be6a553dc8407a86ecd0eed85cd0ccd1af0e77`,
`run-fpDmJi`) completed all ten cases per transport and one retained root per
transport in new processes. All four workers and the normal guard exited
successfully, with zero live children and released locks. The five normal
package digests match the earlier runtime artifacts. However, the generic
restart fixture's `physicalDispatches: 0` was not instrumented for this narrow
selection. It proves rereading and preservation of the original Run, not the
stronger physical non-reexecution claim. That earlier claim is withdrawn.

The narrow selection now installs the existing observed fixture authority in
both initial transports, proves the dispatch hook is live during initial
execution, and retains its authority and exact boundary sample inventory for
fresh-process restoration. The same existing observer then checks that attach,
original-submission replay and lookup do not dispatch or advance Compute.
This is acceptance instrumentation, not a product authorization bypass.

Public acceptance is not established by the editing tests above. The handoff
must identify its clean source SHA, all five package digests, actual completion
inventories, process-stop receipts and released locks. CI, Preview and full-Core
coverage remain separate and must not be inferred from this local selection.
