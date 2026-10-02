# Public SDK write-response loss: current boundary

Audit basis: `actql/actql` main
`bcbf77049fe4991c9b0f1a18541ac7a7952b01ad`, for
[issue #200](https://github.com/actql/actql/issues/200). This is bounded
acceptance of the existing public contract, not a new outcome protocol.

## Existing coverage and owners

- `aql` / `start`: [SDK submission](../../packages/sdk/README.md) retains the
  request ID and connection lookup context in `SubmissionUnknown`. The Host
  owns atomic request deduplication. SDK/Host submission tests and
  `scripts/test-node-client-package.mjs` already cover lookup and exact-request
  resubmission. This increment does not repeat submission coverage.
- `cancelRequest`: the SDK documents `CancellationUnknown` with the original
  request ID and an explicit same-ID resend. The real ingress parity tests in
  `adapters/host-node/in-process-client.test.mjs` cover internal failure and
  malformed post-record replies, and unchanged known refusals.
  `scripts/test-packed-client-checkpoint.mjs` additionally drops a real
  cancellation reply and verifies retained request recovery. These are the
  existing [#154](https://github.com/actql/actql/issues/154) contract and
  checkpoint coverage, not new Run-cancel operation semantics.
- `resolveCheckpoints`: the same ingress tests and packed Checkpoint acceptance
  retain the exact signed items after uncertainty and resend them unchanged;
  the Host reports duplicate resolution without re-signing or resuming a new
  Run. This increment does not add another Checkpoint matrix.
- `Execution.cancel`: the
  [current protocol](../spec/protocols/run.md#client-cancellation-observations)
  binds acceptance to the exact Run reference and control revision. The real
  journal tests already cover durable cancellation/start exclusion, repeat
  cancellation and terminal outcomes. Existing packed Client tests cover
  pre-start cancellation, status and same-request Run reuse. The missing
  bounded public test was transport loss around the cancellation commit.
- `Execution.reconcile`: the
  [Run reconciliation owner](../spec/execution.md#run-states) observes the same
  retained execution and cannot retransmit it. The SDK returns that Run state;
  this is not an operation-specific cancellation lookup. No additional
  reconcile-write acceptance or operation identity is claimed here.

## Added acceptance

`adapters/host-node/client-cancel-response-loss.test.mjs` uses the public SDK,
installed in-process and HTTP ingress, actual SQLite request journal, common
MoonBit cancellation/state/control owners, and the installed attach/lookup
owners. A pre-existing retained Run is seeded through the journal's admitted
Run Definition boundary; Program submission and physical provider execution
are outside this narrow fixture.

For each transport it covers:

1. Drop the cancellation request before ingress dispatch. No cancellation is
   committed. The SDK reports `ClientTransportUnknown`, retains its original
   `Execution.ref`, and sends no automatic retry.
2. Drop the successful reply after the real journal commits. The SDK reports
   the same transport uncertainty. An independent read-only SQLite connection
   observes one original request/Run row, one revision increment and the
   cancellation bit. The Run has not physically started.
3. Refuse cancellation through the current common-owner authorization check.
   `ClientRunCancellationDenied` remains a definitive 403 refusal and changes
   no stored state.

Both loss cases revoke authorization before recovery: the original handle,
attach, request lookup and a further explicit cancel are denied without
reaching the cancellation owner. Restoring authorization permits read-only
lookup/attach/status of the same Run. The post-commit case observes cancelled
with confirmed pre-start stop; the pre-dispatch loss observes running with no
cancellation and unknown stop. Neither is an inference from the failed reply.

Independent SQLite row count, identities, revision and dispatch/start/stop
flags stay fixed during recovery. Recorded ingress operations and owner calls
reject automatic duplicate cancellation, implicit submit or Run reconciliation.
There is no mocked successful cancellation response and no test-only outcome
variant. The before/after drop points are controlled; no sleeps or race timing
select the failure boundary.

## Exact unresolved contract gap

Current `Execution.cancel()` has only the Run reference as its request target.
Neither its wire request nor its SDK result/error exposes an immutable
cancellation-operation reference, and there is no operation-scoped cancellation
lookup. The SDK's generic transport/Host errors do not carry a cancel-specific
recovery context. A subsequent Run `control.cancellation_requested` observation
can establish that cancellation was requested, but cannot attribute that state
to one caller's lost cancellation when other callers may also cancel. Optional
or unavailable `control` cannot resolve even that Run-level question.

This acceptance preserves and observes the existing Run identity; it does not
claim cancellation-operation identity, a new idempotency rule, or complete
operation reconciliation. A public cancellation reference/lookup/unknown-outcome
contract, including the protocol/schema/pin/SDK changes and concurrent-caller
meaning, remains with the common lifecycle owner in
[#182](https://github.com/actql/actql/issues/182). It must be implemented and
accepted there before this test can assert such semantics. #200's stronger
operation-identity requirement remains open to that extent.
