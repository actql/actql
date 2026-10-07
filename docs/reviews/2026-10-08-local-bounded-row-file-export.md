# Bounded retained row-file export

## Product boundary

The former completed-row export measured every column, traversed every nested
value, and emitted the whole row before returning. Yielding between rows did
not expose cancellation while processing one large Text or nested cell. This
is a source-level boundary finding, not a measured stop-delay benchmark.

The existing export owner now resumes column-name measurement, nested value
measurement, wire measurement, and payload/logical emission. It uses the
existing stepped value, Text/key and admitted-wire cursors. All column
admission still precedes row emission. There is no separate encoder,
scheduler, ledger or retry progression.

The Local row-file driver exposes this poll through its existing output
transfer. The Node Store adapter requires it, yields to the Host between
polls, and never uses a blocking `next()` fallback. Partial row bytes stay
private; only complete rows reach the existing Store writer. The blocking
convenience API drains this same cursor for its remaining callers.

The branch starts from merged #877 at
`7819dd7d721501ce3e9e1a5cde873072c4360ac2`. Adopted main is
`c85a5b4612e11b74579510a6a73fe474c0bd8331`, normally merged without
conflicts. There is no unmerged dependency; the destination is main.

## Custody and accounting

- Logical nodes, UTF-8 text bytes and work accumulate in the original budget
  across polls. Traversal steps are a separate quantum, not replacement work
  or duplicated logical charges. Existing row ordering and fixed CIDs remain.
- Private continuation slots are reserved before cursor/frame allocation.
  A changing workspace allowance is rejected during a pending row. Cancellation
  clears private measurement, wire and key state once, not the borrowed source.
- Each poll verifies source availability. Reentrant polls cannot take cursor
  custody. Revocation inside a callback unwinds after that transition returns.
- A cancelled partial row cannot finish or publish a receipt. Physical stop,
  execution close, retained capacity release and cleanup confirmation remain
  separate facts owned by the existing task, Site and Store owners.
- Store append/seal waits retain their existing custody. Failure cleanup retries
  do not re-enter Compute. The Host cancellation test checks the original abort
  object inside the cleanup-owned error, not just its outer error name.
- The modeled export envelope adds eight fixed 64-byte owner/continuation
  slots: 512 bytes per output. Existing nested-depth allowance remains.
  The eight-task independent inventory changes from 301494784 to 301498880
  bytes, exactly eight times 512. Its one-short is 301498879. The 512 MiB
  policy ceiling is unchanged. Structural slots and this model are not RSS
  measurements or an allocator/collector latency guarantee.

## Independent boundaries and ordinary Programs

Two authored scalar rows (`n=1,s="é"` and `n=2,s="😀"`) require six value
nodes, ten text bytes and sixteen logical work. Their row export needs 32
traversal steps and three private workspace slots at quanta 1/7/64.
Work 15 or two slots fails with typed `Admission(CaptureLimit)`.
The independent existing content CID is unchanged.

A 500-element zero array requires 502 nodes, seven key bytes and 509 logical
work. Seven slots admit its existing wire continuation plus the row owner;
work 508 or six slots refuses. Cancellation during its measurement leaves no
private workspace. Additional fixtures cover long supplementary-Unicode Text,
a 256-unit key, explicit NULL and cancellation during key emission. They use
finite poll limits and check the original source remains available.

The actual standard Host prepares a normal three-step producer:
Values (long Text and NULL) -> filter true -> select id,s.
Two separate consumer tasks select id,s from that retained output. The real
retained/publication Stores expose all three Named Results, compared with
handwritten expected rows and independently required result names.
The output wrapper observes the real export cursor at quantum one and rejects
any call to blocking `next()`.

The cancellation variant schedules abort after ten actual export transitions,
before a row is available. It observes physical stop, no completed producer or
consumer, no committed Result index, and final zero retained/reserved resources.
Dispatch remains one; cleanup does not redispatch. Existing arithmetic,
append/finalize failure, cleanup retry and scalar exact/one-short cases remain.

## Fixed-source verification

Verified clean source:
`440bb2566331700b6785914a50c77b9bf54eb052`.

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- \
  --target js --jobs 1 \
  src/execution_relation/completed_export_row_progress_wbtest.mbt \
  src/execution_relation/completed_output_export_wbtest.mbt \
  src/query_integration/local_materializing_wbtest.mbt \
  src/client_local_host/retained_capacity_wbtest.mbt
node scripts/local-checks.mjs build moon --timeout-seconds 180 -- \
  --target js --release src/connectors_builtin_node
node scripts/local-checks.mjs build moon --timeout-seconds 180 -- \
  --target js --release src/connectors/duckdb/conformance
node scripts/local-checks.mjs test node --timeout-seconds 180 -- \
  --test-concurrency=1 \
  --test-name-pattern 'successful retained output|Local output |physical Local output|retained Store configuration|cancel during|reasonless Store|abort between|retained row-file export|retained source-free Values chain retains responsibility|retained Values honors exact scalar' \
  adapters/local-node/retained-output.test.mjs \
  adapters/connectors/duckdb/node/test/retained-values-chain.test.mjs
```

- JS: 27/27, `run-plRyab` / `focused-test-YHMmSP`.
- Consumed checkout runtime builds: `run-GIrjIW` and `run-kprtvK`.
  These use integrated source, not an old tarball or adapter overlay.
- Node: 16/16 (seven standard Host and nine output-adapter cases),
  `run-7YTkvK` / `focused-test-NdpIvR`.
- Six affected MoonBit files match the pinned formatter. Generated interfaces
  for execution_relation, Local and its driver were produced by `moon info`.
  Runtime bundles remain ignored. `git diff --check` passed.

Earlier dirty-source attempts are not relabeled as fixed-source evidence.
Initial compile failures (`run-uJ3Vre`, `run-vvxCfO`) exposed pinned-toolchain
closure inference and loop syntax requirements. Initial Node attempts
(`run-UnoLF6`, `run-eVIzkB`) exposed incorrect test assumptions about the
cleanup error envelope and capacity release, not lost abort causes. Corrected
dirty-source checks passed JS 27/27 (`run-4SJMxT`) and Node 16/16
(`run-EjDNJ0`). Their evidence remains separate.

Attempt IDs resolve beneath `_build/local-checks/attempts`; focused receipt IDs
resolve beneath `_build/focused-evidence`. The subsequent evidence-only commit
changes this report and the remaining-boundaries document, not verified code.

## Remaining scope

Export preparation and publication-receipt finalization still contain column
metadata setup/copies. Native and other blocking convenience consumers do not
become interruptible merely because they drain the same new cursor. Physical
chunk admission, View-plan construction and trusted source/verifier callbacks
remain separate boundaries. Allocations, collector pauses and complete Host
stop latency have not been wall-clock proven.

This is checkout Host/real-Store acceptance, not a pristine packed/HTTPS
campaign. Full Core, Wasm/Native execution, performance and proof campaigns
were not run. Hosted verification for the submitted HEAD is recorded in the
PR; no CI success is inferred from local results or parent runs.
The whole retained Local goal remains incomplete.
