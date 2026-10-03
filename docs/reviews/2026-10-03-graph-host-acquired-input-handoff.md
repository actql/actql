# A handoff: acquired consumer completion after producer port close

## Reproduction boundary

Base source: `79107ff2a1f89265149757d69bfa8e85d8f7cabc`, based on main
`b36d7864b57dc654cc03f583d8391e9ba2a506b3`. The handoff commit adds the
counterexample to the two existing MATCH pilot cases in
`src/query_integration/property_graph_host_custody_wbtest.mbt`. Its exact SHA
is recorded in #270's handoff comment. No product source is changed.

The existing Host fixture has seven tasks: captured source 0, VALUES 1,
Graph construction 2, MATCH 3, Relation producer 4, and consumers 5 and 6.
Independent node identity and node/edge projection expectations remain.
The first quantum-1 iteration reproduces the issue for both MATCH nodes
and MATCH edges; later quantum values are not claimed as executed after failure.

## Operation order and observed state

1. Run VALUES, Graph construction, MATCH and producer 4. MATCH alone receives
   cleanup false, error and retry injection. Its scratch reservation remains.
2. Complete consumer 5. Start consumer 6 through the real installed dispatch
   path, with the exact managed input from producer 4. Advance by one quantum.
   Assert incomplete execution, zero output rows, no material and no committed
   consumer result.
3. Close consumer 5 and verify its exact holding credit and idempotent close.
4. Close producer 4's Host public port and dispose/refresh its execution.
   Do **not** revoke the acquired material: its availability callback stays true.
   The Host port matcher is false, the acquired material is available, and
   held bytes are unchanged. The active consumer still retains its input.
5. Execute consumer 6. Independent expected rows pass: nodes produce
   `{"node_name":"first"}` and `{"node_name":"second"}`; edges produce
   `{"weight":10}` and `{"weight":20}`. Finalization and settlement succeed.
6. Register consumer 6 completion. Actual result:
   **`Err(Execution(ForeignCandidate))`**. Expected: successful completion
   bound to that consumer's already-acquired input and original Run/occurrence.

The new test preserves the success expectation and fails explicitly at step 6.
It does not turn this refusal into a passing expected-failure acceptance test.
An earlier diagnostic also revoked the fixture's material callback and correctly
failed during computation; that diagnostic is separate and is not the handoff
counterexample or evidence of a product failure.

## Actual correspondence path

`LocalManagedDispatchOperations.complete` in
`src/connectors/local/driver/managed_dispatch.mbt` passes the exact
`setup.completion_inputs` to
`complete_managed_task_execution_with_inputs` in
`src/physical_strategy/task_completion.mbt`.

The latter calls `captured_mixed_managed_inputs_match` in
`src/physical_strategy/captured_dag.mbt`. That function's `relation_matches`
branch looks up `managed_task_output_reference(run, edge.producer)` from the
producer's current public `run.outputs` slot. `close_captured_task_output` in
`src/physical_strategy/retention.mbt` has cleared that slot. The already-started
consumer still owns its acquired binding, but the public-slot lookup returns
None and completion rejects the candidate. This explains the observed refusal;
G has not changed that check or its required ownership conditions.

## Minimal selected command and evidence

Use the pinned repository toolchain environment and the existing bounded,
nonzero-test wrapper:

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 120 -- --target js src/query_integration/property_graph_host_custody_wbtest.mbt --filter 'Host MATCH *'
```

Actual diagnostic result: 2 executed, 0 passed, 2 failed, exit 2. Both fail at
the explicit `Execution(ForeignCandidate)` completion assertion, after the
holding, revoked-public-port, execution-row and finalization observations above.
This is neither a compile failure nor a final-zero-only assertion.

Preserve `_build/focused-evidence/focused-test-y2Z30W` and
`_build/local-checks/attempts/run-g0i6sQ`. Their source is the counterexample
test bytes committed with this document; subsequent document-only changes do
not change those bytes. Earlier diagnostic logs remain separate.

## Ownership of the follow-up

A owns a separate product-fix PR. Bind completion to the existing acquired-input
and ownership evidence; retain rejection of foreign Run/occurrence and released
inputs. Do not remove the check, reopen the closed public slot, add another
owner or introduce a fallback. G will not duplicate that product fix.

## Follow-up at A's fixed revision

A implemented the acquired-binding check in #272 at
`d5c1e949cec0064a8898554a6bf87f4e59fff235`, directly based on the fixed
counterexample commit `7f5c7c8353c8058c5710a6cd29f7ba3af3b53215`.
G reran the same two cases in an isolated checkout: **2/2 pass on JS**,
including quantum 1, 7 and 1024, completion, last-consumer holding and exact-once
cascade return. No success expectation was relaxed.

Three independent product mutations in that checkout were each detected by
the intended intermediate reservation/holding assertion. Each exact-byte/mode
restoration then passed the same two cases. See the
[fixture acceptance record](2026-10-03-graph-host-owner-fixtures.md#fixed-source-normal-and-mutation-acceptance)
for source recipes, invocation evidence and limits. This is finite JS
implementation evidence, not a formal implementation proof or cross-target
mutation claim.

The isolated fixed revision is not #270's submitted HEAD. #272 has been
retargeted from #270 to main without changing its SHA. Its diff against main
includes the published G tests/review records and existing declaration, in
addition to A's product fix; those inherited changes need to remain explicit
in its review scope. No dependency-branch PR merge is authorized. #270 stays
Draft until the final revision is adopted through main and exact-head CI
succeeds. The original red CI and the earlier green `79107ff2...` CI retain
their distinct meanings.
