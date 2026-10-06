# Retained Pool: resumable output record admission

Parent: `b9234ef69169f6909621edbffb2b559f6cdeff3b` (#547).
This is a dependent component, not a claim that all Local retention is closed.

## Production and custody

Pool previously charged one `CommitOutput` transition around synchronous
`append_record`: identity and record encoding drained complete values before
another stop observation. The existing Pool Session now retains a shared
`RecordAppend` under `AppendOutput` and polls it once per charged transition.
The same path serves Stored, Viewed and Relation inputs.

`managed_record_storage/append_steps.mbt` owns the provisional record. It
validates one supplied field, required field or identity per poll and reuses
the existing wire/Text cursors for encoding. The record uses a measuring writer:
discarded record text is no longer assembled at finalization. Identity wire,
escaping, field order, uniqueness and canonical byte/node charges are unchanged.
Logical construction work and control polls remain distinct, cumulative scopes.

The builder reserves cursor slots before allocating private snapshots and locks
out another append or finish. A premature finish is rejected without destroying
the pending record. Before commit, record/byte/work/retained/workspace limits
are checked by the existing builder. Only commit transfers the field snapshot
to retained storage. Failed or cancelled cursors retain custody until cleanup;
failure closes writing, not ownership of earlier records. Successful cleanup
drops cursor aliases without clearing transferred fields.

Pool checks its existing stop reader before each cursor poll. It does not emit
output-group progress before record commit. Premature session cleanup remains
`NotStopped`; stopped cleanup discards pending cursor/writer/output once and
does not close the caller's producer read. No ledger, scheduler, source binding,
numeric fold, completion authority or synchronous fallback is introduced.

The synchronous append API still serves unconverted callers; Pool does not use
it as a fallback. The opaque cursor APIs and generated MoonBit interfaces are
added together. No schema, wire, CID or SDK public contract is changed.

## Independent resource boundaries

Cursor workspace is `8 + 2*fields + identities + 3*max_depth`: fixed phase
custody, snapshot/map entries, identity values and three bounded depth stacks.
It coexists with retained record slots until commit, using checked arithmetic.
Pool admits this additional scope before output preparation. These are
structural slots, not a physical-heap theorem.

- A one-field, 130-ASCII Text record has wire
  `[["value","<130 ASCII a>"]]`: 144 bytes, four nodes and width+1 overhead
  two. Logical work is **6/5**, bytes **144/143**, workspace **19/18** (cursor
  16 plus retained record three). It takes 15 polls, not six. The byte-short
  trial keeps work abundant to preserve the existing typed error priority.
- A three-field Pool record with scalar group, two-component Vector and member
  count adds 31 polls: supplied/required/identity scans plus ends 10, identity
  array three, record start one, field tuples 7+4+4, finish/commit two.
  Existing Carrier total 30 becomes **61/60**. Cursor 45 at depth ten makes
  one-member workspace **60/59** and four-member workspace **84/83**.
- Relation Pool previously needed 41 control and 38 workspace. These now
  become **72/71** and **83/82**. The unused 257-item Array trial changes
  **561/560 -> 592/591**, workspace **31/30 -> 55/54** at depth three.
  The input admission node boundary **258/257** is unchanged.
- A single 257-dimensional member independently adds `5*255` to the
  two-dimensional Carrier fixture: one input check, three fold transitions
  and one output wire poll per added dimension. Total is **1336/1335** with
  workspace **315/314**. Stored construction work is **273/272**: 267 record
  nodes, two identity nodes and four overhead units. Both ceilings are tested
  independently with typed failures. Quanta 1, 7 and 256 agree on values and
  total control work; every emitted vector component is independently one.

At control work 1280 the shared cursor is inside output Vector emission. The
kernel fixture checks `AppendOutput`, pending custody, rejected premature
cleanup, live caller input, stopped work/progress, and one successful cleanup.
Replacing each output value poll with a synchronous drain fails **1078 !=
1336** (`run-hieele`, `focused-test-MnPfXY`). The mutation was removed.

## Ordinary retained Host

The normal Program is:

```text
Values(id, group=1, vector[257 ones]) -> to_vectors -> pool_vectors(sum)
  -> vectors -> published + consumed_a + consumed_b
```

The installed Host uses a real retained-file Store. All three explicitly named
Results are read and compared as full ordered arrays against literal group,
component and count expectations. The same request returns the original Run
without additional dispatch or advances.

The awaited `local_compute_advanced` hook sums per-call work after the bridge
and suspends at 1280, not on a sleep. Cancel persists the request while physical
stop is unconfirmed and snapshots remain held. Releasing the hook confirms
stop, publishes no Result, adds no Compute/dispatch and reclaims snapshots.
The prior long-key and unused-Array public cases remain in the same suite.
Snapshot observations are not a complete holder/reservation census.

The initial public trial mistook per-call work for cumulative work and never
reached its synchronization point (`run-JMEUMw`). It was a fixture defect, not
a demonstrated product cancellation failure. The final fixture accumulates
work and uses a scalar group to match the independently derived kernel case.

The resource gate requires operator limits/stop, shared record limits/cleanup,
owner exclusion and the suite-connected public boundary. Removing any required
role or substituting a foreign shared suite fails. Declared cross-target suite
connections do not assert that unexecuted targets passed.

## Focused validation

Checks used the edited sources descended from the parent above. The submitted
SHA is recorded in the PR; no test result is attributed to an unrelated SHA.
The pinned toolchain and existing nonzero-test wrappers were used.

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js \
  src/managed_record_storage src/managed_record_runtime \
  src/local_veca/pool_wbtest.mbt src/local_veca/pool_output_steps_wbtest.mbt \
  src/query_integration/vector_input_recheck_wbtest.mbt \
  src/query_integration/local_carrier_vectors_wbtest.mbt
node scripts/local-checks.mjs test node --timeout-seconds 120 -- \
  --test-concurrency=1 adapters/host-node/public-pool-key-retention.test.mjs
node scripts/check-local-resource-accounting.mjs
```

Final focused MoonBit JS: **108/108**, `run-rgPKMk`,
`focused-test-0pdMry`. Public retained Host: **3/3**, `run-qeuZEI`,
`focused-test-4maGpW`. The public cases used the changed local-node and
run-host-core runtimes, not a newly packed distribution. Runtime packages are
prepared from source and remain ignored; generated shared APIs are committed.
`moon info --target js` succeeds with two existing unrelated warnings.
Node/Workers fixture checks and `git diff --check` pass. An initial generator
invocation omitted `MOON_HOME` and failed before checking outputs; the pinned
environment checks passed without changing those fixtures.

The selected gate/inventory tests pass **6/6** (`run-I6mFGf`,
`focused-test-OizLJx`): `Pool output`, `resource gate accepts every normative`,
`acceptance evidence index`, `evidence paths exist`, `formal Program source
gate`, and `source gate audit` name patterns across
`scripts/check-local-resource-accounting.test.mjs` and
`scripts/pure-operation-inventory.test.mjs`. The actual resource CLI passes,
but explicitly does not assert full boundary completion.

## Residual scope

At this recorded source, identity String assembly and String-key Map
hashing/equality remained synchronous. The later
[identity boundary](2026-10-06-local-record-identity-streaming.md) supersedes
that residual without relabelling this unit's historical checks. Each field's
schema lookup/type-equality and name comparisons still remain synchronous.
Group lookup
and other callers of synchronous record append are not closed by this unit.
The cursor's value/Text traversal is not a claim that arbitrary key or metadata
operations have constant cancellation latency.

Wasm/native execution, packed/HTTP or fresh-process campaigns, whole-Run exact
Ledger budgets and new Store append/finalize/cleanup fault campaigns were not
run here. Existing completion, Store and retry owners are reused; their older
evidence is not relabelled as a new-SHA campaign. Local retention and strict
full-boundary completion remain open.
