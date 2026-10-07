# Bounded retained export metadata

## Product boundary

Completed export preparation previously sorted all column names, including whole
Text comparisons, and allocated six full-width summary arrays synchronously.
Within-row polling from #886 did not cover this earlier boundary. This finding
comes from the production source, not a measured cancellation-delay benchmark.

The existing common export owner now prepares canonical name order and column
metadata incrementally. Name comparisons reuse the existing charged Text and
UTF-16 comparison cursors; insertion shifts also consume traversal steps. The
Local Node output adapter polls this preparation and yields to the Host before
acquiring its physical Store. It requires the new hook, with no blocking or old
argument fallback. The current MoonBit tuple representation is checked at the
Node boundary; malformed or zero-progress pending polls refuse before acquisition.

Publication completion separately transfers its six privately owned summary
arrays and field names once instead of copying them at finish. Public readers
still return independent snapshots. Receipt identity, row content, field order
and canonical content CIDs are unchanged. No scheduler, ledger, retry owner,
language rule or stored-data contract was added.

This branch began from #886's published source
`26882cf6357bb84e7fdc88fb9626276bdcf49b39`. After #886 merged, it normally
adopted main `7ea97f7f835f219d6c4ddf4187c2712b3874b4be` without source
conflicts. Its generated execution interface merged automatically and was
checked against `moon info`. There is no unmerged parent dependency; the PR
destination is main.

## Custody and independent accounting

- Preparation borrows the checked immutable completed source. It owns canonical
  entries, copied names and zero summaries, not an execution/publication receipt.
  Source availability is checked on each poll and before stream transfer.
- Sixteen fixed slots and order-entry capacity are reserved before allocation;
  each column reserves seven further slots before appending its copied name and
  six summary counters. Cancellation clears the private roots once and does not
  invalidate the producer. A finished stream receives custody once.
- Successful canonical-order work is unchanged: column count plus one and both
  UTF-8 name lengths per comparison. Traversal quantum is separate from that
  logical charge. Work is neither clamped nor reset between polls.
- Names `b,a` independently require work 5, not 4, and sixteen traversal steps.
  Two columns require twenty preparation steps and 32 workspace slots:
  sixteen fixed plus two times eight. Slot 31 refuses with
  `Admission(CaptureLimit)`; work 4 refuses with `Wire(OrderLimit)`.
- A 1024-ASCII common prefix followed by a supplementary Unicode character and
  one suffix has 1029 UTF-8 bytes per name. Its independent work is
  `2 + 1 + 2*1029 = 2061`; 2060 refuses. Quanta 1/7/64 preserve order and work,
  with a finite poll bound and cancellation inside Text charging/comparison.
- Empty rows retain the declared schema and the fixed canonical `[]` CID.
  Revocation after preparation but before transfer refuses and retires its
  private state without revoking the original producer.
- The modeled export envelope changes from eight to sixteen fixed 64-byte
  preparation roots. Preparation does not overlap the row cursor after transfer.
  This adds 512 bytes per output, changing the independent eight-task capacity
  from 301498880 to 301502976, with one-short 301502975. The 512 MiB policy
  ceiling is unchanged. This structural model is not a measured RSS or GC bound.

## Ordinary Program and physical Store evidence

The standard Host prepares the ordinary producer
`Values -> filter true -> select id,s`, including long Unicode Text and NULL.
Two distinct consumer tasks reuse the retained output. Real retained and
publication Stores expose all three required Named Results, compared with
handwritten expected rows and names. The observation wrapper calls the actual
preparation/row cursor at quantum one and rejects blocking `next()` calls.

The new cancellation case schedules abort after ten actual incomplete metadata
transitions. No Store lease is acquired and no row cursor runs. It checks the
original abort object, physical stop, no completed producer/consumer, no committed
publication, final zero retained/reserved resources and dispatch count one.
Existing within-row cancellation, scalar exact/one-short, arithmetic failure,
Store append/finalize failure and cleanup retry cases remain selected. They
exercise the existing execution, Site and Store cleanup owners without Compute
redispatch. This is checkout Host evidence, not external packed/HTTPS acceptance.

## Fixed-source verification

Common core and consumed runtime build source:
`ea2a1cb22ed027c07abad545fcc6b6ac0c359c4b`.

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- \
  --target js --jobs 1 \
  src/execution_relation/row_wire_order_wbtest.mbt \
  src/execution_relation/completed_export_preparation_wbtest.mbt \
  src/execution_relation/completed_export_row_progress_wbtest.mbt \
  src/execution_relation/completed_output_export_wbtest.mbt \
  src/query_integration/local_materializing_wbtest.mbt \
  src/client_local_host/retained_capacity_wbtest.mbt \
  src/execution_relation/table_input_export_wbtest.mbt
node scripts/local-checks.mjs build moon --timeout-seconds 180 -- \
  --target js --release src/connectors_builtin_node
node scripts/local-checks.mjs build moon --timeout-seconds 180 -- \
  --target js --release src/connectors/duckdb/conformance
```

JS passed 42/42 (`run-i3XpCZ` / `focused-test-6XdnHf`), including the current
Table-input callers introduced by main. Consuming build attempts `run-xFKFDN`
and `run-66wsqt` succeeded. Runtime bundles remain ignored, not committed.
All nine changed MoonBit files match the pinned formatter. The three affected
generated interfaces were produced by `moon info`; `git diff --check` passed.

Node adapter and Host test source:
`37268a22ad81015c5c35bd7b2d19cf76dede586f`.

```sh
node scripts/local-checks.mjs test node --timeout-seconds 180 -- \
  --test-concurrency=1 \
  --test-name-pattern 'successful retained output|Local output |physical Local output|retained Store configuration|cancel during|reasonless Store|abort between|retained row-file export|retained source-free Values chain retains responsibility|retained Values honors exact scalar' \
  adapters/local-node/retained-output.test.mjs \
  adapters/connectors/duckdb/node/test/retained-values-chain.test.mjs
```

Node passed 19/19: eight actual Host cases and eleven output-adapter cases
(`run-KE0fHY` / `focused-test-eSDMTB`). The three-file change after the runtime
build only fixes the JS tuple reader, matching observation fixture and malformed
progress regression; all MoonBit/runtime source inputs are identical to the
build SHA. This is disclosed source reuse, not a new-SHA packed artifact claim.

The first actual Host attempt at the earlier source failed six cases with
`InvalidLocalOutputPreparation` (`run-bk4Flm` / `focused-test-fcjCgg`): the
adapter and observation fixture assumed a JS Array, while generated MoonBit
tuples use `_0` and `_1` fields. It failed before the intended Store/abort
boundaries. Correcting that binding, not weakening expected errors or cleanup,
produced the passing selection above. Earlier dirty-source JS preparation
passed 35/35 (`run-1NuWII`); that is not relabeled as final-source evidence.

Attempt IDs resolve beneath `_build/local-checks/attempts`; focused receipt IDs
resolve beneath `_build/focused-evidence`. The evidence-only final commit
changes this report and the remaining-boundaries document, not tested code.

## Remaining scope

Publication schema identity calculation and Result-view setup remain atomic;
only bare Local row-file metadata preparation is exposed as an interruptible
public poll here. Blocking convenience and Native callers drain the same common
preparation but do not thereby become interruptible. Public snapshot getters
still copy metadata; physical chunk admission and trusted availability/verifier
callback durations are separate boundaries. Allocation, array growth and GC
latency are not wall-clock bounded by the cursor accounting.

Full Core, Wasm/Native execution, pristine packed/HTTPS, proofs and performance
campaigns were not run. Hosted results belong to the exact submitted HEAD and
are recorded in the PR, not inferred from local checks or parent CI. Draft
preparation is not merge verification. The whole retained Local goal remains
incomplete.
