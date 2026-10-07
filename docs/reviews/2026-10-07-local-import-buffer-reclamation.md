# Incremental private import buffer reclamation

## Source and scope

Implementation: `d3dcaa495f405d2f14ac5012c01bd763fcb6e15b`.
Integrated source: `7e6565aa132bd129cfcc7ccb216b712f023de030`.
Adopted main: `32870dd0812a809955917ef924d859ade2f51967`.
The normal merge preserved the implementation and incorporated the merged
managed scratch/input-stop owners from #830 and #832. No unmerged parent remains.

The preceding input-stop cursor bounded collection traversal, but one input
could still synchronously discard all private row containers. The common
bridge/import owners now expose incremental close/cancel operations which reuse
`advance_admitted_buffer_reclamation`; there is no second reclamation algorithm.

- `advance_close_managed_producer_bridge` immediately revokes the use scope.
  Unfinished or unaccepted sealed storage is reclaimed incrementally. Successful
  handoff is tracked separately from a finish attempt: adopted rows are immutable
  and must not be reclaimed by the bridge.
- `advance_cancel_completed_output_import` separately tracks completed conversion.
  Failed or unfinished admission and encoder buffers resume through their existing
  owner. Active readers block mutation; cancellation does not re-read the source.
- The managed driver prepares deferred buffers and keeps the same input cursor
  entry until its callback reports completion. Each callback uses quantum one;
  the cursor performs at most 64 entries, buffer polls or phase boundaries.
- A snapshot reload importer is registered with the same retained-input cursor.
  Its cancellation closure no longer drops its only pending cleanup root.

One import callback can remove an admitted reference and an encoder reference;
the 64-step cursor is not a claim of 64 total inner operations, a wall-clock bound
or a GC/destructor bound. Default non-deferred convenience callers retain their
existing synchronous cancellation behavior.

The existing common reservation retirement body, provider stop/cleanup gates,
cumulative logical work, exact input/content/CID checks and accepted output
custody are unchanged. Three existing preparation APIs gain an optional deferred
reclamation flag; two incremental common APIs are added. The public MoonBit
interface was regenerated with `moon info src/execution_relation`. No public
wire, stored identity, policy ceiling or reservation formula changed.

## Independent evidence

Seven common-owner fixtures use 24 rows with two cells each: the independently
derived amount is `24 * (2 + 1) = 72` row/cell references. They cover immediate
logical revocation, zero quantum, 64-plus-8 reclamation, quantum-one termination,
append/identity/completion failures, active readers, idempotence, unchanged work
and intact source storage. Successful bridge handoff and completed conversion
remain unchanged after cleanup polls. A sealed-but-unaccepted bridge must still
reclaim its private rows.

The input cursor fixture adds a 100-poll first owner. The first 64 calls cannot
skip that owner or start later port cleanup. Existing absent/repeated entry and
reentrancy cases remain.

The new managed-driver fixture prepares a checked normal Values Program and two
consumer tasks through the existing installation/dispatch helpers. Its 100-row
producer is compared against all independently constructed expected rows. The
consumer imports 99 rows without sealing, then cancels before its provider starts.
Reservation custody remains through pending buffer cleanup; bounded later polls
release it without provider work, late writes or consumer completion. The producer
remains available until its own release, and final held/retention/execution amounts
are zero. This is real common-driver ownership evidence, not public Host input-I/O
cancellation or a snapshot-reload failure fixture.

The source guards reject skipped pending inputs, oversized buffer polls, dropped
snapshot custody, active-reader bypass, mutation of adopted rows and premature
scratch/reservation release. These are source mutation checks, not executable
Native mutations or a whole-physical-lifetime proof.

## Executed checks

The affected common owners and direct callers passed 32/32 during dirty-source
preparation at parent `233fc9e36679da530c719a99d5502f83d7b5fe6b`:

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 120 -- \
  --target js --jobs 2 \
  src/execution_relation/import_reclamation_wbtest.mbt \
  src/execution_relation/managed_producer_bridge_wbtest.mbt \
  src/execution_relation/completed_output_import_wbtest.mbt \
  src/execution_relation/admitted_output_reclamation_wbtest.mbt \
  src/connectors/local/driver/input_stop_wbtest.mbt \
  src/query_integration/managed_import_release_wbtest.mbt \
  src/query_integration/retained_execution_cleanup_wbtest.mbt
```

Receipts: `run-j6JxOM`, `focused-test-gApSWZ`. Later edits add the integration
fixture and its optional preparation helper; common production code is unchanged.
The receipts are not relabeled as clean-source execution.

After the final integration expectation was made independent, the following
passed 3/3 at clean implementation `d3dcaa495f405d2f14ac5012c01bd763fcb6e15b`:

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 120 -- \
  --target js --jobs 2 \
  src/query_integration/managed_import_reclamation_wbtest.mbt \
  src/query_integration/managed_import_release_wbtest.mbt
```

Receipts: `run-nffXMS`, `focused-test-u875Gu`. The preceding dirty attempt also
passed 3/3 (`run-dZvdMM`, `focused-test-03XOOA`) before the expectation refinement;
it is not the final test-source evidence.

At integrated `7e6565aa132bd129cfcc7ccb216b712f023de030`, the two-root JS runtime
build timed out at 120 seconds (`run-175Qth`, not a pass). After its process group
terminated and released its locks, the roots were diagnosed separately with the
same budget: ABI was up to date (`run-KGrJP5`), and Local completed its remaining
one incremental task (`run-VsbuB9`). No timeout increase or full rebuild was used.

```sh
node scripts/local-checks.mjs build moon --timeout-seconds 120 -- \
  --target js --release --jobs 1 src/client_values_host_abi
node scripts/local-checks.mjs build moon --timeout-seconds 120 -- \
  --target js --release --jobs 1 src/connectors_builtin_node
node scripts/build-local-node-assets.mjs
node scripts/build-local-node-assets.mjs --check
node scripts/build-run-host-core-package.mjs --runtime-only
node scripts/build-run-host-core-package.mjs --check
node scripts/local-checks.mjs test node --timeout-seconds 120 -- \
  --test-name-pattern 'public retained Values completion names|public retained Append completion names|public retained Cross Join completion names|source rejects|current driver/common' \
  adapters/host-node/public-property-name-retention.test.mjs \
  proofs/relation-pipeline/capacity/parent-control/driver-retirement.test.mjs
```

The generators and consistency checks passed. The Node selection passed 34/34
at that clean integrated SHA: three real-Store public Host cases and 31 source/
overlay guards (`run-1F9u5q`, `focused-test-CrwvhK`). The public cases retain
independent Named Results for producer/two consumers, schema, request reuse,
post-progress cancellation custody and final release. Only the two consumed
runtime roots were prepared; other roots are not declared fresh at this source.

The Host test uses private source-local client-wire installations, not a pristine
packed campaign. Ignored runtime assets were not committed. SHA-256 digests:

- Local provider:
  `434cd3c1d593a7f2f3f46a353d0dac41f22222addc803deacc5b8f9fe7f025be`.
- Run Host ABI:
  `938588f3b9626ecb1eda2730ab5855a99c2b1572f0bb92b93f22b801deb9c050`.

## Remaining work

The managed-input path is connected; this does not close every retained Local
path. `close_local_materializing_attempt` still loops over imports and cancels
non-deferred buffers synchronously. Its import/copy roots and scratch witness
need the same existing reclamation discipline, retaining stopped-provider custody
and successful output retention. Managed publication buffers are a separate
remaining boundary.

Snapshot cancellation custody is checked by the source guard; cancellation during
an actual Graph-derived snapshot reload has not been added to the public acceptance
selection. Installed availability callbacks, retired Carrier walks, other scratch
and Native physical-byte correspondence remain unproven.

Wasm/Native execution, full Core, full proof campaigns, packed/HTTPS, performance
and CI were not run. Draft preparation does not establish shipping readiness.
The complete retained Local goal remains open.
