# Session evidence cost correspondence

Baseline: `c558da09dff69e1d84fed3741b86ca228b3a03a9`.
This unit connects existing cost observations to immutable final evidence.
It does not qualify origins or broaden evidence reuse.

## Implemented boundary

- `proofs/ci-evidence/collect.mjs`: bind the existing collection-cost bytes in
  the executed certificate, without rewriting original receipts.
- `proofs/ci-evidence/final.mjs`, `acceptance.mjs` and affected consumer tests:
  reconstruct that cost binding and preserve fresh/reused execution identity.
- A small `proofs/ci-evidence/costs.mjs` and focused tests: distinguish nested
  cost boundaries, avoid counting isolated preparation twice, and retain
  missing/unmeasured costs instead of reporting zero-cost reuse.
- `proofs/ci-evidence/inputs.mjs`: bind the new production consumer's bytes as
  reviewed policy inputs; no source selection or runtime closure changes.
- `scripts/ci-timing.mjs`, its existing evidence/artifact consumers and focused
  tooling regressions: retain distinct job-duration totals per run/attempt,
  separately from overlapping wall spans, partial/unknown execution and outcomes.
  Phase sums do not establish total runner savings or parallel wall time.

#412 source selection/image/guards and #568 Bridge admission are separate.
No product, Owner, workflow, job selector, action descriptor, toolchain, Ready
transition, manual CI dispatch/retry or merge is included.

## Acceptance

Current fresh action durations/counts retain their current owner and original
receipt identity. Reused observations keep null current units/duration; origin
elapsed time is a baseline observation, not newly executed work. Preparation
appears both in the collection and isolated-action envelope, so the latter's
exclusive part must be separated before any phase sum. Comparison subphases and
consumer verification likewise must not be added to their enclosing intervals.

The executed certificate binds the exact collection-cost bytes. Final admission
reconstructs costs from those bytes, parsed receipts, independent acquisition,
actual checker duration and isolated execution when fresh. Tampered bindings,
wrong owners, negative/invalid values and missing cost records reject. The
optional main comparison still remains independent of fresh acceptance.

`checked.json.collectionCostsDigest` fixes `collection-costs.json`; the existing
acquisition digest still fixes `acquisition-plan.json`. `costObservation` is
reconstructed, not accepted from a carried report. It includes the following:

- Current fresh units/duration and exact original receipt digest/run/attempt.
- The authenticated current producer job owner, separately from the final
  report owner, for selecting their enclosing API job intervals.
- Null current units/duration for reused work, with historical origin values
  in separate fields. No current isolated-execution record may accompany reuse.
- Runtime collection, preparation, comparison total, acquisition and checker
  durations, plus the exclusive action duration after subtracting preparation
  from the isolated action's already-inclusive envelope.
- Nested comparison subphases kept separately, a partial
  `knownProducerMilliseconds`, mandatory unmeasured-cost residuals and
  `netRunnerSavingsMilliseconds: null`.

The source archive size comes from actual ZIP bytes, compared against API
metadata at final collection and reconstructed again at main acceptance.
Enclosing producer/check job spans remain the independent measurement of total
runner time. Do not add this partial phase sum or nested comparison/consumer
durations to those spans. No action scheduling or concurrency changed here.

Missing cost records are not accepted through an old-format compatibility
path. Changed consumer policy bytes participate in action inputs, so earlier
originals cannot silently qualify under this new policy. Neither the cost
checker nor its controlled fixtures authenticates an origin by itself; the
existing provenance, receipt, runtime and executed Lean checks remain required.

After ordinary integration with main `0e810449cc1a5d330fb244d7651617366ef135f3`,
the complete catalog contains 30 required actions, including the Events model
and JS/Wasm/Native connections. The cost and final main-applicability consumers
are exercised with all 30 receipts and unchanged dependency declarations. Each
Events cost/receipt omission rejects; the optional reused mutation remains the
only row with null current execution. These are controlled source/receipt
fixtures, not execution of the 30 physical actions or the Lean kernel.

The regressions include negative acquisition/collection bindings, isolated
owner substitutions, omitted measurements, historical/current relabeling,
invalid costs under a resealed outer certificate and forged savings/residuals
through the actual `checkAcceptance()` consumer, as well as independent ZIP/API
fixtures for push/main and workflow_dispatch/main.

Local real-image mutation acceptance is submitted separately in Draft #605;
that diagnostic does not authorize hosted reuse or replace authenticated final
admission. Completion of the overall goal still requires compatible successful
main originals, ordinary PR reuse, relevant-input fresh execution and positive
net runner savings including producer/final job spans and transfers.
Controlled cost fixtures are not physical execution or economic evidence.

## Enclosing runner observations

The existing live `scripts/ci-evidence.mjs` and offline artifact timing paths
consume `ci-timing.mjs` without a new dispatcher or framework. Each attempt now
retains its independently observed job intervals and `runnerConsumption`:
distinct completed job seconds, known partial seconds, unknown/skipped counts,
successful-sample status and a separate job wall span. Parallel intervals are
summed only as runner consumption, never as wall time. No step or phase sum is
added to its enclosing job duration.

An incomplete/mismatched API inventory, running job, invalid timestamp, missing
runner or no observed step execution leaves the total unknown. This includes
billing failures reported with synthetic job timestamps and zero steps.
Failed/cancelled jobs retain actual measured consumption when available but
cannot be successful samples. Retries remain separate run/attempt observations.
The projection adds no API calls and does not alter outcomes or reuse readiness.

For a real fresh/reused comparison, select the source/applicability owners from
authenticated archives, retain their job spans and the complete attempt total,
and use the Session cost record only to explain subphases. Equal obligations and
inputs plus comparable execution conditions remain required independently of
timing. No economic result is inferred from controlled examples or failed runs.

## Connecting original costs to completed attempt observations

The existing offline `--artifacts` consumer now reads Session source ZIPs through
`scripts/ci-session-costs.mjs`, using the existing cost checker and independent
30-action catalog. This closes the missing measurement connection: certificate
and receipt costs are bound to the actual producer ID, then joined to the
observed same-attempt producer/check jobs and complete runner total. Transfer,
setup and final verification inside those intervals are included once. Parallel
wall time remains separate; no historical or nested phase is added to the jobs.

The existing cost fixture and stored-ZIP fixture are shared with the new consumer
regressions. The real CLI executes against original stored ZIP bytes, with both
complete timing and unavailable timing. Wrong owner, attempt, catalog, receipt,
cost binding, current reused execution, duplicate final owner, zero-step job and
incomplete execution are covered. No network call or heavy campaign is added.
The read-only projection neither authenticates offline provenance declarations
nor qualifies any new origin. Net savings still requires actual comparable
production fresh/reused samples and remains null here.
