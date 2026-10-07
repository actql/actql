# Resumed retained Result publication validation

## Completion unit and dependency

This connects the existing context-hash and captured-row continuations to
Effect-free publication validation. It is not whole publication or whole
Local completion. The development prerequisite was PR #931, source
`a3dca321a2d0865c2c434f6994fc482fe9843968`, on main
`c54e157b5caa1ad981eb9393f64fd0815fb5a434`.
That prerequisite has now merged. Its source is an ancestor of fetched
origin/main `c28c05d941f4a3dadaa98a287015fd46721e79f0`; the PR targets main
without an unmerged parent dependency. The tests below remain evidence of
this branch's fixed source, not independent verification of every newer
main change.

The verified implementation/test source is
`5f963c44bf51753928942faf71239aca7697725b`. Later record-only changes do not
relabel previous CI or packed evidence as checks of the new HEAD.

## Existing owners and ordering

`start_effect_free_run_evidence_check` exposes the existing opaque
`ComputationEvidenceCheck`. It recomputes the context identity and verifies
each captured Result's fields, row shape, count and logical CID through the
same snapshot checker used by issuance. Contracts and canonical rows are
borrowed, not copied wholesale or released by private validation cleanup.

`PublicationCommitPreparation` preserves the existing check order: Result
dependencies, durable bindings, computation evidence, and commit references.
The explicit blocking complete validator drains this same continuation.
No evidence check is deleted and no alternate ledger or validator is added.

The Node control awaits both owners. Its bridge encodes pending, complete
and refusal as 0, 1 and -1, rather than depending on optional-Boolean layout.
Unknown progress is rejected, and every exit retires private state.
These are internal bridge values, not a new wire protocol or identity domain.

Fresh publication checks the actual abort signal before and between polls
and before proceeding to contract persistence or attempt creation. Existing
commits are still reconciled first, even when the request is already aborted.
Their complete validation is awaited without treating request cancellation
as authority to discard a durable committed outcome.

The Store awaits the same commit checker within its existing semantic commit
owner. Existing record checks, durability reconciliation, cleanup custody
and prepared-object adoption remain unchanged. Effectful commit validation
is not converted by this unit.

## Independent acceptance

The common fixtures require identical control transition totals at quantum
1, 7 and 64, finite polling, one-time finish, cancellation during context and
row phases, and preserved borrowed inputs. A substituted captured value
still produces `EvidenceReferenceMismatch("captured_result_values")`.
Missing Result dependencies still fail before invalid binding/index
arguments can mask the typed inventory cause. Private control underflow
is rejected; this is not a new universal aggregate resource formula.

The normal retained Host Program uses Values, filter and select, followed
by two consumer Stages. Real retained/publication Stores provide three
required Named Results: `published`, `consumed_a`, `consumed_b`. All three
are read with fixed descending expected rows containing long composed and
decomposed Unicode, CRLF, supplementary characters and explicit NULL.
The fixture forbids the blocking chain/commit bridge exports.

Cancellation is delivered after at least two actual polls in context or row
validation, after all three Compute tasks complete. Contract persistence,
attempt creation and commit validation remain at zero. No Result is
published. Existing final cleanup checks require zero retained holdings,
read buffers, execution reservations and publication reservations, with
exactly three dispatches before and after cleanup.

The portable control/real Store case also verifies reference substitutions,
commit replay with an already-aborted request, and concurrent cleanup.
The replay returns the same committed index without another export.

## Executed verification

At the clean implementation/test source above:

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- \
  --target js --jobs 1 src/run_publication
node scripts/local-checks.mjs test node --timeout-seconds 180 -- \
  --test-name-pattern 'portable control validates Receipt and Captured Run references|retained publication validation yields before commit|retained Captured Run issuance yields through final evidence checking' \
  adapters/host-common/publication-contract-control.test.mjs \
  adapters/connectors/duckdb/node/test/retained-values-chain.test.mjs
```

- Common JS: 250/250; bounded receipt `run-sQSRDV`, focused receipt
  `focused-test-tkJpqM`.
- Selected Node: 8/8 (seven top-level cases, one nested cleanup case);
  bounded receipt `run-Dzx2nS`, focused receipt `focused-test-We9968`.
- Matching release runtimes: 11 incremental tasks in `run-9cnI9d`, using
  `build moon --timeout-seconds 180 -- --release --target js --jobs 1
  src/connectors_builtin_node src/connectors/duckdb/conformance`.
  They were built at `ad2ce70bd7c66b1bc138b20303ef307fc409bcc1`; the only
  subsequent implementation/test change was the fixture's cancellation
  synchronization. Compiled source inputs are identical to the verified
  source. The Host evidence uses these checkout artifacts, not tarballs.
- Read-only Node/RelA generation and Node Host/Workers fixture checks passed.
  Selected public interfaces were regenerated with `moon info`; Node syntax
  and patch whitespace checks passed. Existing RelA unused-import warnings
  remain separate from errors.

Receipts are retained under `_build/local-checks/attempts` and
`_build/focused-evidence`. They are local evidence, not hosted CI results.

Earlier unsuccessful attempts remain separate evidence: `run-Zp1UrC` found
a missing terminating loop expression; `run-XuAst9` timed out while building
the unused debug configuration; `run-qfh9O4` exposed optional-Boolean refusal
polling; and `run-2MPpPM` passed 7/8 with the first-poll synchronization
assertion failing. Those are not reported as passing acceptance.

## Remaining boundaries

Result dependency/inventory/reference metadata leaf validators, uniqueness
comparisons, field-name normalization and some scalar schema predicates
still execute synchronously. Splitting payload context/row traversal is not
proof that arbitrary metadata has a bounded maximum resume duration.
Effectful commit validation, explicit blocking Native/direct consumers and
physical allocation latency remain separate work.

Full Core, Wasm/native execution, pristine packed/HTTPS acceptance, proof
campaigns and performance measurements were not run. Draft CI preparation
and required Ready/integration coverage must be distinguished. No hosted CI
success is claimed by this record.
