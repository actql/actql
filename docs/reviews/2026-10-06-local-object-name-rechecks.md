# Retained typed Object name admission

## Scope and ownership

This component starts from #563 at
`cc3255411d5882163cecb3bac710c3c1578d2e26`. The parent is now adopted in
main; this component incorporates that main baseline by a normal merge.

The common runtime recheck previously compared and measured a whole declared
Object name inside one field poll. It now retains an ObjectName continuation
and checks at most 64 UTF-16 units plus a surrogate partner. Exact equality to
the opaque admitted Fields name reuses its NFC/LF evidence; no new normalizer
or metadata certificate is added. Child and sibling frames are scheduled only
after the name completes, so the original depth-stack reservation suffices.
Short names keep their original poll count. Value node/depth/byte meaning,
field order, raw data Strings, wire/CID contracts and installed limits do not
change. Long names add charged continuation polls, independent of quantum.

The production connection is the existing Relation Pool input recheck owner:
load_pool_field -> relation_cell_recheck -> advance_recheck_runtime_value ->
bind_pool_field. No new provider, scheduler, ledger or cleanup state is added.

The integration preserves the current opaque JSON domain. Declared Object
constructors reject noncanonical identifiers, and an unwrapped Object is not
a typed JSON value. Inside JsonData, exact member names are data: the shared
synchronous and stepped rechecks both preserve decomposed Unicode, CR and CRLF.
An identifier normalization check must not be applied to those JSON keys.
Long opaque JSON name scanning remains a separate interruptibility obligation.

The existing complete-order fixture now accounts for the new declared-name
phases independently: root, two field visits, six 64-unit name fragments,
Number and terminal give 11 recheck polls; the unchanged emitter costs 13.
The total is 24 for quantum 1, 7 and 256. Node/byte limits remain unchanged.

## Independent boundaries and public path

- Common typed Object: 130 ASCII units require eight polls (root, field setup,
  three name chunks, child, exhausted fields, finish). Nodes 2/1 and bytes
  130/129 retain exact refusal. Cancellation after the first chunk leaves the
  child unvisited. A surrogate-boundary fixture fixes 197/196 UTF-8 bytes;
  a late name mismatch fails before an independently invalid child.
- Relation Pool: replace the existing 517-poll Array in the independently
  derived 592-poll fixture by a 112-item Array (227), a 130-unit Object name
  (eight recheck polls), and one extra field/group/identity lookup (three).
  Total control is 313/312; workspace remains 55/54 because unused field count
  does not change record/role storage or continuation depth. Quanta 1, 7 and
  256 use the same cumulative allowance and typed PoolWorkLimit failure.
- The exact producer read uses five declarations plus 1+2+3+4+5 column
  comparisons = 20 metadata entries. This is distinct from kernel workspace.
- Pool cancellation: begin/groups/identity (three), Array field (1+227+2),
  Vector field (1+5+2), two scalar fields (2*(1+2+2)) total 251. Object
  load/root/setup adds three. Poll 255 checks the first name fragment. Early
  cleanup refuses NotStopped, then confirmed stop permits exactly one cleanup;
  the borrowed input remains live.
- The ordinary public Program uses the same five columns, a 112-item unused
  Array and one unused Object with a 513-unit name. Its nine name fragments
  occupy polls 255 through 263; the Host's 256 boundary is inside that name,
  before its child and record collection. Nested wire content remains below
  the unchanged installed 1,000-byte policy. Actual Local selection and the
  real retained Store publish `published`, `consumed_a`, `consumed_b`, each
  equal to the literal row `{group:1, embedding:[1,2], member_count:1}`.
  Request reuse adds no dispatch/advance. Cancellation at the held advance
  does not release snapshots or claim stop early; subsequent confirmed stop
  leaves all three Results unavailable and reclaims snapshots.

## Executed candidate evidence

Before the implementation change, the two common regressions failed 0/2
(`run-KZOw6d`, `focused-test-IlOgmy`). After the change the shared name and
nested recheck selection passed 5/5 (`run-EfdFAJ`, `focused-test-qVIKcB`).
An expanded selection passed 166/167: the new source fixture incorrectly used
the checked-contract-only additional_properties field. After fixing the author
schema, its read still omitted two of the five-column lookup entries. Those
attempts are failures, not acceptance evidence. The corrected initial fixture
and existing input tests passed 3/3 (`run-3ut9cz`, `focused-test-C8sETp`),
before the final Array/name placement described above.
The final candidate's shared package and affected Pool/nearest input selection
passed 167/167 (`run-hV827g`, `focused-test-NhOnFw`), including the 313/312
control and 55/54 workspace boundary and poll-255 cancellation.

Selected runtime preparation (`local-node run-host-core`) passed; bundles
remain ignored. Initial public input with 8,096-unit Object names correctly
failed at preparation with ValuesRecursiveIssue.BytesExceeded. A temporary
diagnostic adapter overlay identified that cause (`run-5kJHls`); it was removed
before acceptance. The within-policy input passed the public Store case and
required-evidence removal test, 2/2 (`run-pZE3BB`, `focused-test-7zSywz`).
Final committed-SHA verification is recorded in the PR separately from these
candidate receipts. Only the checks actually executed establish evidence.

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js \
  src/value_admission \
  src/query_integration/pool_object_name_recheck_wbtest.mbt \
  src/query_integration/vector_input_recheck_wbtest.mbt
npm run build:runtime-packages -- local-node run-host-core
node scripts/local-checks.mjs test node --timeout-seconds 90 -- \
  --test-name-pattern 'public retained Pool|Pool output' \
  adapters/host-node/public-pool-key-retention.test.mjs \
  scripts/check-local-resource-accounting.test.mjs
```

## Remaining obligations

Long runtime JSON identifier normalization, Carrier field/schema lookup and Map
hashing, legacy synchronous drains, runtime buffer assembly and aggregate
intermediate-byte custody remain separate boundaries. This unit is not a
whole-Run physical Ledger/latency proof or full retained-path completion.
Full Store fault/cleanup retry campaigns, packed Local/HTTP, Wasm/native
execution and final CI are not established by these focused JS/checkout cases.
