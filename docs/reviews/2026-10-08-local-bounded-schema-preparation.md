# Bounded checked schema emission

## Completion unit and dependency

This continues the existing retained Result preparation owner from #904,
`7735f90755085640fefc370dc1344319698d7928`. The starting main was fetched and
confirmed as `2664bcf3203c42eafe0ca5919763dbe8ad081b40`. Parent #904 remains
unmerged at publication preparation; the final merge destination is main.
Do not merge this child into the dependency branch to claim completion.

Previously `identify_relation_schema` synchronously emitted the entire resolved
schema to hash and wire writers, then copied all field names. The contract
emitter also scheduled all object children in one loop and synchronously
processed long names/reference parameters. The outer preparation poll did not
make those internal traversals interruptible.

The checked contract emitter now owns a bounded cursor. `emit_checked` drains
that same cursor for existing synchronous callers; no alternative serializer
or compatibility fallback was added. The Relation schema owner polls the
emitter and the existing ordered-key writer cursor, and publication metadata
polls the schema owner before issuing its stream.

Implementation boundaries:

- `src/value_contract/encode.mbt`: `start_checked_emission`,
  `advance_checked_emission`, `cancel_checked_emission`. Object children are
  borrowed in canonical order one at a time. Only the fixed vocabulary's at
  most five members are locally sorted. Keys and Text advance through the
  existing writer cursors, with at most 64 UTF-16 units per poll.
- `src/execution_relation/relation_schema_identity.mbt`:
  `start_relation_schema_identity`, `advance_relation_schema_identity`,
  `finish_relation_schema_identity`, `cancel_relation_schema_identity`.
  Hash emission still precedes wire emission. Canonical reference spelling
  is borrowed from the admitted schema rather than reconstructed/concatenated.
  Field names transfer once after incremental collection.
- `src/execution_relation/completed_export_preparation.mbt`: pending schema
  custody is cancelled with metadata custody, before any stream transfer.

Checked configuration/type contracts, not Model/Effect data values, are the
domain of this emitter. No string normalization, language, wire, CID or
stored-data meaning changes. Generated MoonBit interfaces reflect the real
new implementation APIs and preparation errors.

## Resource and identity evidence

All byte, node and depth accounting remains in the existing writer. Poll count
is not a replacement logical resource quantity. Pending continuation admission
checks the explicit frame limit before append; schema preparation derives a
finite bound of `min(IntMax, 2 * max_nodes + 8)` from its existing output-node
ceiling. A wide object does not create an object-width-sized continuation array.
This frame count is not a claim about total process heap or all serializer roots.

Independent tests cover:

- A 129-field object: exactly 392 emitted nodes and depth 3, using an authored
  literal wire assembled independently from the emitter. Pending continuations
  peak at 8, not proportional to width; a limit of 7 fails with `OutputLimit`
  and clears incomplete custody. Quanta 1/7/64 preserve the same output/usage.
- Exact byte/node/depth and one-short refusals for checked contract emission,
  plus cancellation inside long object keys and reference Text. Cancelling a
  successfully transferred child does not revoke the enclosing writer.
- The existing supplementary/BMP schema vector retains its fixed CID
  `sha256:e13e51f472cae3497095edf7f88922ebd7bf0b1c48f2bc31480b47406728c2e6`:
  exactly 217 UTF-8 bytes, 16 nodes, two fields and depth 3. Limits of 216 bytes,
  15 nodes or depth 2 fail with `Encoding(OutputLimit)`.
- Empty schema retains its independent `{}` CID and exact 2-byte/1-node limits.
- Conditional presence retains its independent literal wire/CID, distinct from
  nullability. No field absence is converted to NULL.
- Cancellation during both hash and wire name emission exposes no partial
  identity, retires writers/cursors/private names, and preserves the source.
- A 65-child schema reaches the actual completed metadata owner; cancellation
  before stream transfer clears its existing workspace reservation. Successful
  transfer clears preparation references without destroying the output schema.

## Actual retained Host route

Two new cases in `retained-values-chain.test.mjs` use ordinary Program
preparation, Values/Filter/Select, real retained/publication Stores, and two
consumer tasks. Each authored payload has 65 distinct numeric properties;
the rows use different independently specified property values. Results order
by `id DESC`, with expected rows `[id=2, id=1]` and exact payloads. All three
committed names are independently read, not just a product-reported count.

The existing driver is polled with quantum 1. A read-only observation of the
real contract continuation schedules cancellation after at least four object
children have been processed. It creates no replacement execution state and
does not wait for a fixed sleep before deciding that the target phase started.

At this boundary all three Compute tasks are already physically complete;
this is Result schema cancellation, not evidence of Compute stop delivery.
The test checks exact original abort-cause identity through the existing
durable publication envelope, no committed index, cancellation of the pending
Result borrow, and final zero retained holdings/read buffers/execution and
publication reservations. Cleanup cannot increment the Compute dispatch count.

The fixture's default nested-value ceiling of 1000 bytes rejects the two
authored payloads during normal preparation. Only these success/cancellation
cases therefore install an explicit 4096-byte fixture ceiling and reissue its
canonical environment identity before checking. This does not change product
capacity or replace an exact boundary test with a larger budget. Existing
typed policy refusal remains intact; the failed attempt is retained separately.

## Fixed-source verification

Implementation source: `3f7bf9ea1eeb4c218400236d5d679a82f1d4df67`.
Host fixture source: `757c3e2830815919496ca0d53b6f8d6e3632b6e9`.
The latter changes only the Node fixture policy setup; all compiled runtime
inputs are identical to the implementation build SHA. The following record
commit is documentation-only, not a new execution or packaged artifact.

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- \
  --target js --jobs 1 \
  src/value_contract/emission_progress_wbtest.mbt \
  src/value_contract/contract_test.mbt \
  src/execution_relation/relation_schema_progress_wbtest.mbt \
  src/execution_relation/relation_schema_identity_wbtest.mbt \
  src/execution_relation/completed_schema_preparation_wbtest.mbt \
  src/execution_relation/completed_export_preparation_wbtest.mbt \
  src/execution_relation/completed_result_rows_progress_wbtest.mbt

node scripts/local-checks.mjs build moon --timeout-seconds 180 -- \
  --target js --release src/connectors_builtin_node \
  src/connectors/duckdb/conformance

node scripts/local-checks.mjs test node --timeout-seconds 180 -- \
  --test-concurrency=1 \
  --test-name-pattern 'retained Named Result schema|retained Named Result ordering' \
  adapters/connectors/duckdb/node/test/retained-values-chain.test.mjs
```

- Clean implementation JS **32/32**: `run-8rqS3W`,
  `focused-test-mSBE6t`.
- Both consumed checkout runtime roots built at that same SHA:
  `run-488yMs`. Generated bundles remain ignored.
- Clean fixture Host **4/4**: `run-PEDC85`, `focused-test-gbPxJ2`.
  This includes the two new recursive-schema cases and the two existing long
  Text Result-ordering cases from the parent. It is not an all-Host campaign.
- `moon info --target js src/value_contract src/execution_relation` generated
  both changed interfaces. Each changed MoonBit file was formatted separately.
  Node Host fixture freshness, Node syntax and `git diff --check` passed.

Retained local diagnostic evidence is under `_build/local-checks/attempts` and
`_build/focused-evidence`. Failed attempts are not overwritten: `run-IrCss2`
exposed an independently incorrect fixture depth of 4 (the structure has
three containers); `run-cNp2eH` rejected a fixture using checked-only
`additional_properties` in authored Values syntax; `run-BbZzuC` passed the
existing ordering cases but rejected the new payloads at the 1000-byte policy.
None is counted as successful public schema acceptance.

## Remaining boundaries

Blocking convenience publication callers still drain the shared owner; their
public start/advance/finish connection is separate work. Snapshot getters and
physical chunk admission remain separate, as does the parent's narrower
inter-task Result projection limitation. Trusted callbacks and runtime
allocation/GC/contiguous String materialization are not wall-clock bounded by
this change. In particular Native/Wasm StringBuilder finalization is not
established as interruptible by these JS tests.

No full Core, all-target, pristine packed/HTTPS, proof or performance campaign
was executed. CI status belongs to the exact submitted HEAD and is reported
separately; Draft preparation is not merge verification. This completes the
checked schema traversal connection for the retained asynchronous Result
transformation route, not the whole Local Compute goal.
