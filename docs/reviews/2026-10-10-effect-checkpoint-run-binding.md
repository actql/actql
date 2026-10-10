# Effect Checkpoint binding to the original checked Run

A Cloud Checkpoint slot currently confirms sealed bytes and checks the Run ID
and Run Definition CID. It does not establish that the subject is the original
Effect computation unit. Reading the compiled plan in the Cloud adapter would
create another interpretation of a checked execution boundary.

The common Run publication Host now admits the exact Checkpoint through the
existing Checkpoint Owner, binds the original allowed Effect Run and definition,
and checks its original computation unit. The first resident Effect review
requires Commit / EffectSet / EffectScopeApproved; partial-application approval
and other deferred decisions remain separate contracts. Its created/expiry
window cannot extend the original Run or policy lifetime.

`effectReviewCheckpointBinding(allowed, definition, checkpointWire)` exposes
those facts through the existing portable run-host-core facade. It performs no
physical I/O and grants no permission. Native review preparation consumes the
same admission after authenticating its actual original capture and Preview.
There is no new identity domain, scheduler, ledger, serializer or wire profile.

The Cloud caller must still authenticate the reporting Site, bind the original
consumer dispatch/attempt and current generation, confirm Native custody,
recheck current authorization/lifetime, persist exact metadata, and CAS the Run
transition. The API neither proves Provider completion nor manufactures any of
these missing observations. Expired metadata remains inspectable for evidence
and cleanup; the current protected-operation check is separate.

## Dependency and validation

This change is stacked on the published Native continuation/Checkpoint custody
PR #1202, whose parent is #1201. Its final merge destination is OSS main, after
those parents. Cloud must formally adopt a merged cohort; local source builds
are diagnostics and do not change the current Cloud vendor pin.

Focused validation selects two common Owner tests, the portable binding tests
and existing Effect Run facade tests, consuming Native/JS/Wasm checks and strict
TypeScript. The metadata unit tests intentionally use synthetic artifact CIDs;
they are not physical Effect acceptance. The existing actual Native Provider
Checkpoint case separately exercises this new common admission in its caller.
Receipt commands and counts are recorded in the PR after exact-HEAD execution.
Hosted CI, deployment, approval, write, Host restart, public SDK waiting and
formal release are not claimed by this change.
