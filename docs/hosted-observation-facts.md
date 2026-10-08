# Restored observation fact custody

## Boundary

The common MoonBit observation Owner suppresses repeated diagnostic facts before
charging the cumulative request budget. Polling task A, task B, and then task A
must not create another measurement for A. This remains true after restoration
and after the record or byte budget is exhausted.

This is observation custody only. It never skips execution, Source acquisition,
capture, publication, cancellation, or cleanup. It does not decide Run state,
authorize dispatch, or constitute Evidence capture.

## Finite representation

`ObservationBudgetSnapshot.fact_hashes` retains the SHA-256 hexadecimal digest
of each charged, named fact, in first-observed order. The existing fact admission
still requires 1 to 512 printable ASCII characters. Unnamed records are charged
individually. Raw fact text is not persisted in the snapshot.

The existing maximum of 2,048 charged records bounds the history to 2,048
64-character digests. Digest text therefore occupies at most 131,072 ASCII
bytes, before serialization and container overhead. No history eviction or
budget replenishment occurs. Duplicate or malformed saved digests and a history
longer than the charged record count are refused. Snapshots and restoration
copy the array; external mutation cannot change live Owner custody.

The public `/observation` export uses the closed `factHashes` array instead of
`lastFact`. A last-only snapshot cannot prove interleaved fact custody and is
refused, not converted to a fresh zero balance. An adapter encountering such
custody must suppress further optional observation while execution continues.
There is no legacy fallback.

## Evidence and adoption

The regression `interleaved task polling stays repeated after restoration`
failed against the parent implementation: task A was rejected with
`ObservationRunLimit` instead of `ObservationRepeated`. The retained failing
focused-test receipt is `focused-test-rTlDnm` under the worktree's ignored
`_build/focused-evidence` directory.

Additional common Owner tests cover the finite maximum, cumulative exact and
one-short limits, foreign scope/request refusal, malformed and duplicate
digests, and snapshot isolation. The public package test serializes custody,
restores it, repeats an earlier interleaved fact, and verifies unchanged counts.
Its expected digest is computed independently with Node's SHA-256 API.

This change depends on the portable observation Owner in OSS PR #993. Cloud
adoption requires freshly produced formal packages and an explicitly finite
physical journal record limit large enough for the admitted history. The old
4 KiB Cloud observation record limit does not cover 512 digests. Component
tests do not establish Cloud adoption, Worker/Native completion, two-tenant
isolation, or the complete Hosted fault campaign.
