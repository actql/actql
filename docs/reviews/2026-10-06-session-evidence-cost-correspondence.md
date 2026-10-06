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
- Existing read-only timing evidence remains the source of completed job spans.
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

The regressions include negative acquisition/collection bindings, isolated
owner substitutions, omitted measurements, historical/current relabeling,
invalid costs under a resealed outer certificate and forged savings/residuals
through the actual `checkAcceptance()` consumer, as well as independent ZIP/API
fixtures for push/main and workflow_dispatch/main.

Completion of the overall goal still requires real image acceptance, compatible
successful main originals, ordinary PR reuse, relevant-input fresh execution
and positive net runner savings including producer/final job spans and transfers.
Controlled cost fixtures are not physical execution or economic evidence.
