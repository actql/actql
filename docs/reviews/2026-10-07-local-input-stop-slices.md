# Managed input stop collection slices

## Source and scope

Implementation source: `94b7d15250e11a874f46b885f816ad139fcdfc04`.
Before the first push, its message was shortened to the 72-character limit;
the identical tree is `fdd060390d4126e6ea870e2245ffaa9dcfc2113c`.
The executed receipts remain tied to their original SHA, not relabeled.
Parent: `45ff12f18ba30d062728c8ca3c3089dd7e5f8066` (#830).
Adopted main: `735ac73c5519753f77de31c26d6233ffc015c088`.
This follow-up depends on #830 and does not replace its scratch-retirement work.

The existing managed driver cancelled/disposed every bridge and retained importer
in synchronous collection loops. A private cursor now advances at most 64 input
entries or phase boundaries per invocation. Request liveness, finalization
cancellation and provider cancellation still happen before the first slice.
The same driver continues pending revocation from its cleanup callback; no new
scheduler, execution owner, ledger or logical work counter is introduced.

Revocation does not clear the original optional input roots. Retirement and its
release witness reject pending revocation, and common reservation retirement
is unchanged. Provider cleanup still requires its actual stop observation and
successful cleanup. Its cumulative work is cached before its root is dropped.
Active callbacks prevent cleanup polling from retiring scratch.

The cursor prevents reentrant advancement while an input callback is active.
Completed scratch retirement can finish input-stop bookkeeping immediately:
the preceding owner already detached every input root, and settled/disposed
handles cannot repopulate it. Accepted result storage is not revoked.

## Independent collection fixtures

Four private fixtures cover:

- Seventy bridge entries and three imports: the first slice closes exactly the
  first 64 bridges; all original roots remain. Later slices finish once.
- Sixty-two/sixty-three absent bridge entries: both phase boundaries count, so
  exact 64 steps completes and one more step remains pending.
- Repeated owner references and absent entries preserve physical port order.
- Reentrant cancellation cannot repeat, skip or retire the active input.

These are private cursor cases, not a claim of a 70-port public Program or a
measured public stop-delay counterexample. Existing source mutations reject
early scratch release, skipped import cancellation, dropped bridge roots,
unbounded collection walks and bypassed reentrancy/provider cleanup guards.
The common reservation body remains checked exactly.

## Executed checks

The focused JS command passed 35/35 during preparation at dirty parent
`45ff12f18ba30d062728c8ca3c3089dd7e5f8066`. The implementation was committed
unchanged as `94b7d15250e11a874f46b885f816ad139fcdfc04`; this is source
correspondence, not a relabeled clean-SHA execution.

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 120 -- \
  --target js --jobs 2 \
  src/connectors/local/driver/input_stop_wbtest.mbt \
  src/connectors/local/driver/scratch_retirement_wbtest.mbt \
  src/query_integration/managed_import_release_wbtest.mbt \
  src/query_integration/local_managed_values_wbtest.mbt
```

Receipts: `run-6IBI6c`, `focused-test-CgkIUA`. This includes the preceding
cursor and real managed-import ownership cases, not 35 new fixtures.

At the clean implementation SHA, only the two consuming JS runtime roots were
built (9 incremental tasks, `run-unzuPd`). Existing asset generators and their
checks passed; ignored bundles were not committed.

```sh
node scripts/local-checks.mjs build moon --timeout-seconds 120 -- \
  --target js --release --jobs 2 \
  src/client_values_host_abi src/connectors_builtin_node
node scripts/build-local-node-assets.mjs
node scripts/build-local-node-assets.mjs --check
node scripts/build-run-host-core-package.mjs --runtime-only
node scripts/build-run-host-core-package.mjs --check
node scripts/local-checks.mjs test node --timeout-seconds 120 -- \
  --test-name-pattern 'public retained Values completion names|public retained Append completion names|public retained Cross Join completion names|source rejects|current driver/common' \
  adapters/host-node/public-property-name-retention.test.mjs \
  proofs/relation-pipeline/capacity/parent-control/driver-retirement.test.mjs
```

The Node selection passed 27/27 at the clean implementation SHA: three real-Store
public Host cases and 24 exact-source/overlay guards (`run-KkqkLV`,
`focused-test-O2T56r`). Host cases compare all three Named Results and schema
against independent expectations, verify request reuse without extra dispatch,
deliver cancellation after positive progress, keep snapshots before physical
stop and observe final release without additional dispatch/completion.

This uses the parent's private source-local client-wire installations, not a
new packed distribution campaign. Local provider asset SHA-256:
`6b8495e4ec4385439a4d6812d08feb4e040442ca8cc9e0ea4f6d560491a3efed`.
Run Host ABI SHA-256:
`226557953b53c84cbf9076f090075d02ecd02199b42dd1307eaf22f90ee85aba`.
Other runtime roots were not rebuilt or declared fresh for this source.

## Remaining work

This bounds collection traversal, not all work inside one close callback.
`close_managed_producer_bridge` and `cancel_completed_output_import` still use
the synchronous `cancel_admitted_buffer` convenience API for unfinished private
rows. Its row containers must be connected to the existing incremental buffer
reclamation owner in a subsequent unit; successful transferred rows must not
be mutated. GC/destructor latency is also outside this collection bound.

Installed availability callbacks, retired Carrier walks, other scratch and
Native physical allocation/reclamation correspondence remain. No public API,
CID, logical work, operation limit or reservation formula changed. Wasm/Native,
full Core, full proof campaigns, packed/HTTPS, performance and CI were not run.
The complete retained Local goal remains open.
