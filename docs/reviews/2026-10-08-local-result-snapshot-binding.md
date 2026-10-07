# Exact export ownership for captured Result snapshots

## Scope and source

The implementation source is
`817905b09a422e905a3f6d9ea06d0593decae6d7`. The work branch normally merged
main `465a501b6ccf1a7b57943d11d5d3614e3a53e511`, without conflicts, on top of
#911 at `a1b1fd54ea1b0eea67d6567a6efab8786416b8e0`. #904 is now adopted by
main; #907 and #911 remain dependencies until their adoption.

`completed_relation_export_snapshot` previously checked receipt liveness and
stream completion but did not match the receipt's export identity. A receipt
from a second export, including another export of the same completion, could
authorize traversal of the first export's view. Equal logical content does
not establish this exact ownership. The counterexample is at the common API;
it does not demonstrate an incorrectly published public Run.

The existing owner now compares `export_identity` before writer allocation or
row traversal and returns `ForeignMaterial` on substitution. Receipt liveness,
source availability, finished-stream checks and encoding limits remain in
place. Refusal does not close either valid receipt or revoke the producer.
There is no new API, serializer, scheduler, ledger, wire or CID contract.

## Independent regression and production reachability

Two new cases failed before the guard in `run-TpoUox` /
`focused-test-eOefsY`. They substitute a second receipt from the same completion
and a receipt from an equal independently completed source. After refusal, the
correct receipt still yields the independently fixed Unicode rows and permits
ordinary cleanup. The fixture selects `s, n`: field inventory retains that
projection while canonical JSON keys remain `n, s`.

An intermediate run, `run-2HV6Lz`, passed 19/20 but exposed an incorrect new
fixture expectation for that authored field order. It is not success evidence.
The expectation was corrected from the fixture's explicit `select`, not by
copying a measured identity or changing production ordering.

The actual connection remains:

`storeCompletedResultPublicationPayload` -> publication control snapshot
admission -> `PublicationOutputExport.admit_captured_snapshot` -> the exact
finished export owner -> captured Result admission.

The focused real-Store Host case prepares a normal Program, executes the Local
producer and two consumers, captures their snapshots and publishes all three
Named Results. Each committed name and exact payload/order is checked against
independent expectations; final Store reservations return to zero. The test
uses checkout runtimes, not a pristine packed distribution.

## Verification at the implementation source

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- \
  --target js --jobs 1 \
  src/execution_relation/completed_output_export_wbtest.mbt \
  src/query_integration/captured_publication_preparation_wbtest.mbt \
  src/query_integration/client_result_transformation_wbtest.mbt
node scripts/local-checks.mjs build moon --timeout-seconds 180 -- \
  --target js --release --jobs 1 \
  src/connectors_builtin_node src/connectors/duckdb/conformance
node scripts/local-checks.mjs test node --timeout-seconds 180 -- \
  --test-concurrency=1 \
  --test-name-pattern '^retained Named Result schema yields within recursive contracts: success$' \
  adapters/connectors/duckdb/node/test/retained-values-chain.test.mjs
```

Common JS: 20/20 in `run-MXA34d` / `focused-test-PXVuIe`. The two consumed
runtime roots built in `run-MNoA88` (76 tasks); generated runtime bundles remain
ignored. Actual Host: 1/1 in `run-Z8LgFg` / `focused-test-Aqe2h7`. These checks
ran with the pinned Node/MoonBit tools and a clean implementation source.
Formatting and `git diff --check` passed. A sandbox-only wrapper attempt failed
before test execution because it could not inspect its owned process group;
the normal wrapper invocation retained the actual counterexample evidence.

## Remaining bounded snapshot work

This closes receipt substitution, not interruptible snapshot materialization.
`completed_relation_export_snapshot` still drains row/cell wire emission;
`admit_captured_result_snapshot` still parses, validates fields, canonicalizes
and hashes the complete payload synchronously. The future connection must
poll the existing value/wire and canonical admission owners through both
stages; bounded emission followed by blocking admission is insufficient.
Field-list copies/validation and allocation latency remain separate boundaries.

No full Core, Wasm/Native execution, packed/HTTPS, proof or performance campaign
ran. Hosted verification belongs to the submitted SHA and is not established
by these local results. No CI rerun, main merge or branch-history rewrite was
performed. This is not whole Local Compute completion.
