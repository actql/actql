# Continue an initial dispatch after reconstruction

A checked consumer can have its original Coordinator intent and Run start
claim committed before the outbound transport marks the send unknown. Cloud's
Accepted-only recovery selection then keeps querying a dispatch which has not
been offered to the Site. This is distinct from losing a response after send.

`initialDeliveryEligible` asks the existing Coordinator Owner about that narrow
initial state. It requires matching dispatch identity, revision zero, durable
intent progress, no Site observation, current authority/Site generation,
current authorization and no cancellation. It changes no record or claim.

The transport must guarantee that every send follows durable outcome-unknown
persistence. That invariant is an explicit trusted input; a transport without
it is refused. In particular, an unobserved record alone does not establish
absence of delivery. Existing `redeliveryEligible` remains unchanged: missing
responses are not typed not-seen evidence, and Accepted is never start authority.

## Cloud caller contract

1. Reconstruct the original saved envelope and its checked retained-input
   custody. Reuse the original Run, dispatch, attempt, expiry and materials.
2. Validate current Run authorization/lifetime, cancellation, Site identity and
   generation through their existing owners. Supply the actual transport's
   persistence invariant, not a value inferred from a query response.
3. Ask `initialDeliveryEligible` before the send transition. Do not acquire a
   new start claim or turn an outcome-unknown record into an initial intent.
4. Persist outcome-unknown using the original physical revision. Only the
   successful conditional writer may offer the original bytes. Failed or
   uncertain writes offer nothing.
5. Recheck current authorization, cancellation, generation and retained custody
   after that await. Bind the final check to this invocation's exact successful
   transition; a newly reconstructed unknown record has no such permission.
6. Leave Site admission and its exclusive execution-start claim in control.
   A failed send remains subject to existing query/recovery and cleanup duties.

This OSS API is one dependency of the Cloud connection fix, not evidence that
the original Run has recovered. Required caller regressions cover interruption
after start claim but before unknown persistence, concurrent continuation,
unknown-write failure, cancellation/current-context changes during persistence,
and refusal of an already-unknown unobserved intent. Public Worker/Native
recovery, Result and formal release remain separate acceptance requirements.

## Focused checks

- `node scripts/local-checks.mjs test moon --timeout-seconds 60 -- --target js src/remote_site_protocol --filter '*delivery*'`: 5 passed.
- `moon info --target js src/remote_site_protocol src/remote_coordinator_abi`:
  affected interfaces generated with the existing generator.
- `node scripts/build-runtime-packages.mjs coordinator-core`: actual Coordinator
  ABI prepared, including its normal generated-artifact freshness check.
- `runFocusedTests('node', ['packages/coordinator-core/cancellation.test.mjs'], {cwd, timeout: 60000})` from `scripts/test-execution.mjs`: 12 passed (including the three initial-delivery cases) through the generated package export. The preceding suite-registration attempt failed due to a stale test variable name; that was fixed. A subsequent supervisor attempt stopped before test execution at its process-inspection boundary. Neither is counted as a successful check.

No full Core, packed campaign, Native build, Preview deployment or CI rerun was
performed. These are Owner/package checks, not public two-task acceptance.
