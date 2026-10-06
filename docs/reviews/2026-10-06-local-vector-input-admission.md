# Retained Pool and Nearest: resumable Relation input admission

Parent: `d69268f31de1d1f4a1a5a9f542715964ccdc9663` (#542).
The parent is unmerged; this unit preserves that dependency.

## Production boundary

Pool's Relation source and Nearest's Relation operands previously called
`producer_read_checked_cell` inside one charged field-read transition. That
rechecked complete nested values and Text before another stop observation,
including columns unused by the operator. Admitted Carrier views do not have
that path: they borrow existing checked fields of an exact generation.

The existing bounded Sessions now stage Relation fields with a private shared
`relation_cell_recheck` helper and retain one common value-admission cursor.
Only completion of that cursor binds a checked field. Pool owns `RecheckField`;
Nearest owns `RecheckInputField`. Each poll consumes cumulative control work,
and the existing stop reader is consulted before the next poll. Ranking uses
the same helper, without changing its already established poll counts.

No array-to-vector conversion, scheduler, ledger, output identity, provider
binding, input-port mapping, numeric fold or completion authority is added.
Both Relation operands of Nearest share one pending cursor; mixed input cases
retain the existing distinct Relation and Carrier authorities. Already admitted
Carrier input work and structural workspace limits are unchanged.

Before output preparation, Relation paths reserve eight live cursor slots and
`max_depth+2` continuation slots, with checked arithmetic. Workspace denotes
the existing structural slot model, not a new byte-capacity theorem. Cleanup
before confirmed stop remains rejected. Stopped cleanup cancels the pending
cursor and clears borrowed current fields once, without closing caller inputs.

## Independent control and workspace limits

The existing scalar fixtures now include input admission explicitly:

- Relation Pool: two scalar rechecks (4) and a two-component Vector recheck
  (5) add nine to the previous 32: **41/40**. The previous workspace 18
  adds eight cursor and twelve depth-ten frame slots: **38/37**.
- Direct and fused Relation Nearest: each side adds scalar (2) and Vector
  (5) rechecks. Previous 52 + 14 gives **66/65**. Existing workspace 31
  adds the same twenty slots once, not per operand: **51/50**.

The new fixtures independently include a 257-number column not used by either
operator. An Array requires one node poll, 257 child/number poll pairs, one
exhausted continuation and one completion: `2*257+3=517` polls.

- Nearest: existing 52 + two additional field/match pairs (4) +
  `2*(scalar 2 + Vector 5 + Array 517)` = **1104/1103**. Depth two gives
  workspace `31+8+2+2` = **43/42**.
- Pool: existing 32 + extra field/group/identity scans (3) + two scalars
  (4) + Vector (5) + Array (517) = **561/560**. Workspace
  `18+8+3+2` = **31/30**. Depth three is required by the existing output
  wire's outer record array, field tuple and Vector envelope.
- Array node allowance **258/257** distinguishes a complete admitted value
  from a one-short input. The short case fails with existing typed
  `InvalidNearestRecord(false, 0)` or `InvalidPoolRecord(0)`, not completion.

Quanta 1, 7 and 256 agree on literal output values and cumulative control
work. The first 256-work quantum must remain inside the initial unused Array.
Cancellation at that point rejects premature cleanup, confirms stop without
output, permits one cleanup and leaves all caller-owned producer reads alive.

The unchanged Nearest executable failed with **56 != 1104**
(`run-klcOk4`, `focused-test-gtscB7`). Earlier fixture API errors were
compile failures, not product counterexamples. The initial Pool source view
also needed an independent metadata allowance of 14: four selected columns
plus 1+2+3+4 name probes. Its earlier unwrap failure was fixture setup, not
an additional product defect. A later Pool `Storage(ValueLimit)` diagnostic
identified the depth-three stored envelope described above; no production
policy was raised or fallback introduced.

## Ordinary retained Host

The existing public Host harness now includes two additional normal Programs:

```text
Values -> keyed Relation -> pool_vectors -> vectors -> Named Results
candidate/query Values -> Relation nearest roles -> Named Results
```

Both produce a real retained-file representation and feed two consumer tasks.
The tests read `published`, `consumed_a` and `consumed_b` explicitly and compare
each full ordered array with independently authored rows. Resubmitting the same
request returns the same Run and adds no dispatch or Compute advances.

Each source supplies two 129-number unused Arrays: independently 518 canonical
bytes, within the unchanged nested Values policy. Each Array needs 261 recheck
polls; preceding fields leave fewer than 256 polls for it in the first child
quantum. The awaited Host hook therefore suspends inside admission, not before
start or after output. Cancellation is persisted while physical stop remains
unconfirmed and snapshot custody remains unchanged. Releasing the hook confirms
stop, exposes no Result, reclaims snapshots and adds no Compute or dispatch.
Snapshot observations are not a complete holder/reservation census.

## Executed focused evidence

Checks ran on edited sources descended from the parent above, before commit.
The submitted SHA and dependency are recorded in the PR. Commands used the
pinned MoonBit toolchain and existing `local-checks` nonzero-test guard.

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js \
  src/query_integration/vector_input_recheck_wbtest.mbt \
  src/query_integration/local_carrier_vectors_wbtest.mbt
npm run build:runtime-packages -- local-node run-host-core
node scripts/local-checks.mjs test node --timeout-seconds 180 -- \
  --test-concurrency=1 adapters/host-node/public-nearest-key-retention.test.mjs \
  adapters/host-node/public-pool-key-retention.test.mjs
node scripts/check-local-resource-accounting.mjs
```

- Owning and existing VecA callers: **75/75** (`run-nppYeE`,
  `focused-test-9L92OJ`), including ranking reuse, mixed inputs and empty sides.
- Public retained Host: **5/5** (`run-R4w7iB`, `focused-test-fPRJIS`), including
  existing Carrier/key/output cases and both new Relation input cases.
- Selected input-evidence mutations, real manifest acceptance and operation
  inventory: **6/6** (`run-SwOndZ`, `focused-test-ObXEag`). Removing either
  operation's input boundary/shared/public evidence rejects. A foreign suite
  directory also rejects. The real resource checker passed; it does not assert
  full boundary completion. Existing shared Vector evidence is reused from
  #542 rather than claimed as a new independent execution here.

## Residual work

Object field-name scans, authored field-name binding, Pool's scalar member-ID
encoding and output record admission/wire encoding remain separate synchronous
boundaries. This unit does not describe all Pool or Nearest work as bounded.
No maximum wall-clock resume latency was measured. Existing policy-ceiling
diagnostic readers are not latency observations.

Wasm/native, all-Core, packed/HTTP, fresh-process replay, whole-Run exact Ledger
limits and new Store-failure campaigns were not executed. Existing failure and
retention owners are preserved, not independently re-proven by these five Host
cases. No Run/Model/Effect cancellation contract is changed, and all Local
retention is not declared complete.
