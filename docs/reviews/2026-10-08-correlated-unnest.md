# Correlated UNNEST: existing common expansion from public text

Base: main `4ceb8b6f97674b9b9d0edbc2dbae4541187d5d22`. Independent branch:
`feat/frontend-correlated-unnest`. This unit does not depend on the pending
literal membership or Graph quantifier PRs and adds no execution owner.
Current integration adopts main
`c6a1a8e7ab3726cccbf1fddc897bde15a5927e5a` by normal merge, retaining its adopted
literal-membership, finite Graph grammar, input refusals and bounded cleanup.
The adopted commit also contains manifest-derived Local package payloads; its
normal package producer is used without a compatibility overlay.

## Fixed counterexample and reference

```sql
SELECT p.id, element, position
FROM parents AS p
CROSS JOIN UNNEST(p.items) AS element WITH OFFSET position
ORDER BY p.id, position
```

The independent Values input has `(id, items)` rows `(2, [2,NULL,2])`,
`(1, [1])`, `(3, [])`, `(4, NULL)`. The ordered output is:

```json
[{"id":1,"element":1,"position":0},
 {"id":2,"element":2,"position":0},
 {"id":2,"element":null,"position":1},
 {"id":2,"element":2,"position":2}]
```

The [GoogleSQL array expansion reference](https://docs.cloud.google.com/bigquery/docs/arrays#converting_elements_in_an_array_to_rows_in_a_table)
defines per-row correlation, parent-column retention and OFFSET. These are
selected semantic obligations, not a claim of full correlated JOIN support or
a live differential run against BigQuery.

Before implementation, the hand-authored complete JSON Program passed the
ordinary checker, but the equivalent SQL failed parsing. The retained failing
selection is `run-O9crpo`, `focused-test-fwknhe`: 0/1 passed. No public Run
failure was demonstrated by this compile-boundary regression.

## Connection and scope

SQL and Pipe CROSS JOIN UNNEST dispatch to the existing `UnnestSource` operation.
Lowering resolves the expression in the current preceding row scope, copies its
evaluated value to a private array slot, and emits common `unnest` with optional
`with_index`. Parent columns/ranges survive; nothing is silently removed from
the source or re-evaluated by a second executor. Ordinary JOINs preceding
correlation use the existing general joined-row scope.

Successive closed object expansions retain every original value receiver.
SET changes the current column while a preceding range still names its original
slot. SELECT/AS replace that scope under the existing rules. Unknown child
contracts do not prevent an unrelated qualified parent star. Common checking
owns ARRAY admission, NULL propagation, key transfer and expansion capacity.
The Frontend does not declare a parent key unique after one-to-many expansion.

The public corpus contains fourteen positive cases and eight pre-admission
refusals. It includes independent JSON controls, row-dependent ARRAYs,
duplicates/NULL elements, NULL/empty ARRAYs, parent stars, original versus current
SET values, explicit filtering/LIMIT, DATA, and one-acquisition ordinary and
joined parents. The normal corpus and focused Local/HTTPS consumer both register
the same fixtures. No test patches the generated Program.

## Identity and evidence

Existing generators update grammar, complete normative import metadata and
canonical vectors. The pre-integration grammar CID was:
`sha256:669a907108617a89e253dcf5d5f5ef88fe14ec46fe84df18bb6e4d22638347f5`.
The complete hand-assembled Values Run preimage independently yields
`sha256:4ca80c7d99dd7834c8fc281ce2aff63833e52711eb52702c2cc628c361a01af4`.
Its predecessor grammar/Run pair is retained; no saved Run is relabeled. Values
Unit, cardinality proof, Result Plan and common operation meanings are unchanged.
The combined grammar CID is
`sha256:39ed3dd3cca9b11c128c369308bdbd340ee69a5b82c43bc5408b9b66b8e6f0ac`;
the same complete independent preimage yields Run CID
`sha256:d48070d700e2e74ce504796caefec6fc0255d8b998f8f570e02723580949f5b3`.
Both parent grammar/Run pairs remain independent vectors. No product issuer is
used to obtain the expectation. Normal packed registration includes each
correlated case once; the duplicate registration detected during integration
is removed and its count is checked.

Focused JS regressions, including existing UNNEST callers, passed 13/13:
`run-1iH1Vc`, `focused-test-dRTqHI`. Earlier additional assertions exposed two
test-fragment mistakes (`run-ZZp92Y`) and an overly broad parent-star guard
(`run-oa4JSr`); both failures remain separate evidence. The latter was fixed by
using the parser's actual star receiver expression, without rejecting parent
projections. A Node manifest check exposed incomplete generated metadata
(`run-fR4vJJ`, 15/16); the normal metadata/canonical generators repair that
closure, rather than suppressing the check. The repaired focused Node selection
passed 16/16 (`run-wLlAIM`, `focused-test-j9YRL0`). The affected Values Run
material boundary passed JS 1/1 (`run-RNPlV6`, `focused-test-h9NElK`).
Read-only manifest, metadata and canonical-vector checks pass (375 vectors);
formatting is checked only for the changed MoonBit files.
After the normal main merge, the same focused UNNEST family plus the complete
predicate/LIMIT Program regression passed JS 14/14 (`run-gQPPk5`,
`focused-test-i6QZoA`). The selected Node fixture/vector/manifest and affected
literal-membership/Graph staging checks passed 26/26 (`run-OjEEFY`,
`focused-test-Vu8cFC`). A first integration selection (`run-w5GO8o`, 24/26)
detected two test-integration mistakes, a missing formatted fixture and a
selector-prefix assertion; restoring the test bodies and retaining main's
selector composition repaired them. The capacity refusal is not counted as
fixed by those preparation checks.
The integrated Values Run-material identity boundary passed JS 1/1
(`run-wah2BM`, `focused-test-VIS8X9`).

## Fixed-source public execution and common capacity boundary

Normal five-package production at
`58f39b8b29240f9257a0d534a9ff57d12d363bcc` passed (`run-4yanmF`). The manifest is
`/private/tmp/actql-b-correlated-unnest-58f39b8b2-pack/packed-client-packages.json`.
The external consumer (`run-LX1Ab1`) retained its receipt at
`worktrees/.codex-scratch/public-query-evidence-TlNLmC/summary.json`.
Its Embedded Local JSON control, SQL, Pipe, quoted aliases, DATA, empty parents
and empty/NULL arrays reached Named Result with the independent rows, ordered
columns and complete contracts. The next filter/LIMIT source failed after
admission; later cases, refusals and the HTTPS corpus were not reached. These
are evidence for that source SHA, not later integration or complete acceptance.

The independent filter/LIMIT JSON control and source both also failed on the
same packed HTTPS Host (`run-Di2na4`, `focused-test-yXPF0t`). A direct diagnostic
of that JSON control through the installed common execution entry
(`run-9RS6jf`, `focused-test-awONLf`) identified
`LocalManagedStart(Execution(Physical(ExecutionLimit)))`, before any completion.
`ACTQL_E_UNPUBLISHED_RUN` and `CapturedRunPublicationFailed` are later symptoms.
An independent candidate-preparation probe (`run-tgaExh`,
`focused-test-FC59ZR`) recorded retained capacity 14,240,000 bytes and execution
capacity 601,097,472 bytes with every ledger usage counter zero. It did not run
the prepared candidate: that probe's second entry call was refused because
preparation had already sealed its managed identity policy. Keep that diagnostic
limitation separate from the preceding verified execution failure.

The common Host execution budget stays 536,870,912 bytes. No overestimate has
been established. A must distinguish correct capacity refusal from incorrect
derivation or an admission/dispatch mismatch before changing a common boundary.
Relevant owners are `client_local_host/captured_ledger.mbt`,
`connectors/local/driver/managed_dispatch.mbt` and
`physical_strategy/task_execution.mbt::start_captured_managed_execution`.
The Frontend neither raises this budget nor duplicates that capacity owner.

The unchanged source is `correlated-unnest-filter-limit` in
`scripts/fixtures/correlated-unnest-source-input.mjs`. The separate,
hand-authored `correlatedUnnestFilterLimitProgram` fixes the same filter, ordered
keys and `take: {count: 2, offset: 0}` for reproduction without Frontend lowering.
Submit it normally as JSON with that fixture's `parameters`; the expected rows
remain `[{"id":1,"element":1,"position":0},{"id":2,"element":2,"position":0}]`.
Both controls remain positive obligations in the normal corpus. Excluding the
failing case or converting it into an expected failure cannot close this unit.

Fresh integrated packages and complete Local/HTTPS acceptance remain pending.
Use `node scripts/test-packed-public-query.mjs --correlated-unnest-only
--keep-artifacts` when the common boundary is resolved. Retain the failed Store,
logs and package digests for the owner handoff. Local checks do not certify all
backends or full integration.

## Remaining coverage

Ordinary Relation JOIN after expansion, INNER/LEFT correlation, implicit comma
expansion, Pipe-set tails and stars requiring an unknown ARRAY element schema
remain explicit coverage gaps. These are not restrictions of GoogleSQL and are
not implementation completion. Unsupported placement is rejected instead of
reordering consumers or changing multiplicity. The common declared ARRAY bound
and Host capacity policy remain in force; no capacity ceiling is raised.
