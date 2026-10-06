# Session evidence cost correspondence

Baseline: `c558da09dff69e1d84fed3741b86ca228b3a03a9`.
This unit connects existing cost observations to immutable final evidence.
It does not qualify origins or broaden evidence reuse.

## Planned edit boundary

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

Completion of the overall goal still requires real image acceptance, compatible
successful main originals, ordinary PR reuse, relevant-input fresh execution
and positive net runner savings including producer/final job spans and transfers.
Controlled cost fixtures are not physical execution or economic evidence.
