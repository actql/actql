# Retained record field binding

## Scope and owners

This component starts from #566 at
`35cd17419c928d62b9c47b4bd92967d30bd1535e`. The reviewed #563 and #566
parents are adopted on main; the merge target is main.

The existing stepped append owner now retains field-name hashing, exact
collision comparison, sorted Carrier Knowledge lookup, required-field checks,
identity lookup and prior-record identity-name comparison across advances.
The Knowledge and admitted contracts remain authoritative. Short-name fixtures
retain their poll counts; long names add cumulative charged polls independent
of the driver's quantum. Wire construction work, value bytes, raw UTF-16
ordering, typed qualification, row order and uniqueness meanings are unchanged.

The name cursor borrows prefix and spelling without assembling qualified names
during lookup. Each hash/comparison fragment examines at most 64 UTF-16 units;
each bucket/search poll also limits transitions to eight. Hashing selects only
a bucket: complete spelling comparison is required before accepting equality.
Schema lookup additionally checks the typed qualification role. Field/value
references are captured before yielding so caller mutation cannot substitute
another field after its hash or contract was selected.

For nonempty records the reservation is
`16 + 3*fields + identities + 3*depth`: original fixed
append custody (eight), fixed name cursor custody (eight), snapshots, numeric
fingerprint buckets and collision links. Collision comparison retains its
existing second-emitter reservation and reuses existing name custody; the
legacy synchronous comparison is not silently charged for a new unused name
cursor. Empty records keep the original fixed eight-slot reservation, with
constant-time missing-field/identity refusal rather than allocating a name
cursor. Name scans do not alter canonical construction work.

No new provider, scheduler, ledger, stop rule or storage engine is introduced.
The production connection remains Pool -> managed_record_runtime RecordAppend
-> managed_record_storage AppendCursor. Cancellation requests do not release
inputs or provisional output before the existing execution owner confirms stop.
Cleanup clears the new bindings/links once and keeps earlier committed rows
under the builder until its separate cancellation cleanup.

## Independent boundaries

- Before the change, a 130-unit declared field was accepted in the first poll.
  The new first-poll regression failed 0/1 (`run-uJl5r0`,
  `focused-test-TzyrqJ`). It now yields before retaining the field.
- `[["<130 a>",1]]` independently needs 138/137 bytes and 6/5 construction
  work. The 25-slot append cursor and three-slot row coexist at 28/27 workspace.
- `ab` and `bA` have the same djb2 fingerprint but remain separate fields.
  Duplicate, missing and absent long names retain typed InvalidRecord refusal.
  Raw UTF-16 comparison covers a surrogate boundary and qualification roles.
  Caller mutation and cancellation during prior identity lookup preserve custody.
- The one-record scalar Pool baseline is 61 control units. An 8,096-unit field
  has 127 fragments. Field hash/schema, required hash/bucket and identity
  hash/bucket each add `2*(127-1)`; name wire emission adds `127-1`.
  Exact control is `61+7*126=943/942`, logical construction remains 18, and
  workspace is `15+16+9+1+30=71/70`. Quanta 1, 7 and 256 agree.
- The public counterpart uses a 513-unit field and an unused 90-item Array.
  Starting from the independent Array-257 Relation baseline (592), removing
  167 items removes 334 polls; nine name fragments add 56. Exact control is
  `592-334+56=314/313`, workspace `31+16+9+1+9=66/65`. At work 256 the
  required-name scan is unfinished and no record is committed. Reduction
  progress is already one; it is not completion or publication evidence.

Existing exact Pool expectations increase by eight fixed name slots plus one
collision-link slot per output field. Their expected work is not replaced by
measurements from successful runs. Earlier document values remain historical
evidence for their original source revisions.

## Executed evidence

The final candidate focused JS selection passed 88/88 (`run-wT75Gw`,
`focused-test-GsIa8U`), covering record storage/runtime, VecA and affected Pool
input/member/Object/public-barrier fixtures. Earlier 74/74 and 87/87 receipts
precede the explicit fixed-name reservation and are not final evidence.
The final common/consumer selection with typed qualification, a sixteen-name
collision bucket and the unchanged empty-record limit passed 42/42
(`run-RAHUBR`, `focused-test-mcE8ZO`). This later selection executes the changed
storage and runtime packages plus both Pool field-binding counterparts; it
does not reexecute the complete VecA corpus from the earlier 88/88 receipt.

The initial public 8,096-unit author fixture failed before dispatch with
InvalidClientRequest (`run-vkQ8lt`); six existing public cases and the gate
mutation passed, but that attempt was 7/8, not acceptance. The within-request
public fixture and evidence-removal case passed 2/2 (`run-uEWvkG`,
`focused-test-MPbJzg`). It reads all three explicit Named Results from a real
retained Store, checks request reuse without another dispatch/advance, and
holds cancellation at work 256 until stop confirmation. Pending cancellation
keeps snapshots and does not claim a terminal state; confirmed stop makes all
three Results unavailable and reclaims snapshots. After the final empty-record
reservation and required bucket/qualification evidence were added, the focused
public field-binding, existing Object-name and evidence-removal cases passed
3/3 (`run-rMTN1J`, `focused-test-1mLv4q`). The actual resource checker passed;
its full-boundary-completion flag remains deliberately unasserted. Node Host
and Workers freshness checks passed without generated changes. Final
committed-SHA evidence is reported separately.

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js \
  src/managed_record_storage src/managed_record_runtime src/local_veca \
  src/query_integration/pool_field_binding_wbtest.mbt \
  src/query_integration/pool_member_encoding_wbtest.mbt \
  src/query_integration/pool_object_name_recheck_wbtest.mbt \
  src/query_integration/vector_input_recheck_wbtest.mbt
npm run build:runtime-packages -- local-node run-host-core
node scripts/local-checks.mjs test node --timeout-seconds 90 -- \
  --test-name-pattern 'retained field binding|typed Object name admission|Pool output' \
  adapters/host-node/public-pool-key-retention.test.mjs \
  scripts/check-local-resource-accounting.test.mjs
```

## Residual boundaries

This closes the stepped append name-binding scans, not every schema/name scan
in preparation or Pool input matching. Qualified-name wire spelling still
assembles a reference String at emission setup. Legacy synchronous drains,
runtime String buffer assembly,
aggregate intermediate-byte custody and whole-Run physical Ledger remain
separate obligations. Full fault/retry, packed Local/HTTP, Wasm/native execution
and final CI are not established by a focused JS/checkout boundary selection.

The evidence gate requires the common exact limits/collision/prior-cleanup,
Pool quantum/stop, public barrier and public Store fixtures. Removing each
required role fails the gate; registration alone does not prove execution or
full retained-path completion.
