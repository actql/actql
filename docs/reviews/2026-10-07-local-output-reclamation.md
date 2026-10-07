# Bounded provisional Relation output reclamation

Implementation commit: `a9edb078d801d547fbf19aae56c39c4233f32d00`.
Verified integrated source: `a34d8d49c92c2eddce1f68049f6da3f535d9078f`.
Adopted main: `148723200139ced6605223cc703275c0fa71f3a0`.
The Sequence parent (#800) is merged; this unit targets main.

## Counterexample and ownership

The normal checked/lowered 32-row Values fixture stops after 24 committed
provisional rows. Its 24 row containers and 48 cells need 72 reclamation entries.
Before the change, the first cleanup returned complete and dropped the output
owner. The regression failed at that completion assertion (`run-QNY91g`,
`focused-test-4Cl2ck`). This is an owner/custody counterexample, not a measured
public stop-delay claim.

The existing admitted-row buffer now owns deferred reclamation for bounded
kernels. Cleanup removes at most 64 private cell/container references per
callback, retaining the output and outstanding workspace custody until done.
Dense and presence-bearing cells are overwritten before pop: the pinned
Native/Wasm array implementation retains references in unused slots. Empty
backing arrays are detached after their original references are removed.
Shared immutable payloads and source presence containers are never mutated.

Append failure revokes a bounded buffer without draining it synchronously.
Explicit synchronous admission cancellation keeps its existing convenience
contract; it is not promoted to bounded execution by this unit. No new
scheduler, ledger, evaluator, storage engine or compatibility path is added.

Values, Append, Set, Cross Join, Join, binding rows, COUNT, Group, row window,
Unpivot, Unnest, Nest, interval join, as-of join and Sequence use this owner.
They keep sealed material until the common session accepts it. Failed completion
and cancellation racing a kernel's completion reclaim unaccepted material;
accepted output survives kernel cleanup for its existing consumers.

Installed providers use explicit cleanup-pending observations. The common
cleanup Bool still reports a state change: disposal can return true while
buffer reclamation remains pending. Eleven additive pending readers were
generated through the normal MoonBit interface generator. No wire, canonical
identity, logical work or operation-limit contract changes.

## Independent boundary evidence

The five new core regressions cover:

- 72 entries: the first 64-entry slice leaves exactly eight entries, pending
  output and workspace custody; the second finishes once. Work is unchanged.
- Row limit 24: the next append fails with typed `CaptureLimit`, cannot seal,
  and retains its 24 rows until sliced reclamation.
- Sealed accepted output remains readable. Copied conditional-presence rows
  reclaim in slices without changing their original ID or omitted cell.
- Revoking the completion port rejects with typed `Completion(Unverified)`;
  the sealed but unaccepted output remains owned until reclamation finishes.
- A common-session observation-boundary injection cancels after the real
  Values kernel completes. The first cleanup reports change but remains pending,
  and the second finishes. This fixture does not assert a public Run race.

The resource checker rejects missing kernel/provider custody connections,
reference-slot overwrite primitives, accepted-output protection or any of these
fixtures. Its mutation regression establishes guard behavior, not a heap theorem
or operation-wide acceptance for every variant.

## Executed verification

On the clean integrated source, affected auto-merged callers and the new
counterexamples passed **55/55** (`run-JP6kc1`, `focused-test-eMKUtl`):

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 120 -- \
  --target js --jobs 2 \
  src/execution_relation/admitted_output_reclamation_wbtest.mbt \
  src/execution_relation/bounded_asof_child_cleanup_wbtest.mbt \
  src/execution_relation/bounded_asof_join_wbtest.mbt \
  src/execution_relation/bounded_group_wbtest.mbt \
  src/execution_relation/bounded_row_window_wbtest.mbt \
  src/execution_relation/bounded_unpivot_wbtest.mbt \
  src/execution_relation/bounded_unnest_wbtest.mbt
```

The shared interface regeneration/comparison
`moon info --target js,wasm,native src/execution_relation` succeeded without
interface divergence or a remaining generated-file diff. This is interface
checking, not Wasm/Native test execution.

The two consuming runtime roots built at the clean integrated source
(`run-iUrxlK`), followed by both existing runtime asset generators and their
read-only checks:

```sh
node scripts/local-checks.mjs build moon --timeout-seconds 120 -- \
  --target js --release --jobs 2 src/client_values_host_abi src/connectors_builtin_node
node scripts/build-local-node-assets.mjs
node scripts/build-local-node-assets.mjs --check
node scripts/build-run-host-core-package.mjs --runtime-only
node scripts/build-run-host-core-package.mjs --check
```

The clean-source retained Host/gate/index selection passed **5/5**
(`run-g4Bcv4`, `focused-test-levXwR`; receipt dirty flag is false):

```sh
node scripts/local-checks.mjs test node --timeout-seconds 120 -- \
  --test-name-pattern 'shared output reclamation|acceptance evidence index|evidence paths exist|public retained Values completion names|public retained sequence disallow position copies' \
  scripts/check-local-resource-accounting.test.mjs \
  scripts/pure-operation-inventory.test.mjs \
  adapters/host-node/public-property-name-retention.test.mjs
```

The actual public Host uses a real retained Store, reads exactly the producer
and two consumer Named Results with independent ordered rows/schema, reuses
the same request without extra dispatch and confirms physical stop and final
reclamation after delivered cancellation. Its positive-progress barrier is
not evidence of a specific private reclamation phase.

The freshly built consuming asset SHA-256 digests are:

- Local provider: `6db9b25f3eb910feeefbddf6fd02f6ecd51f33d3045d9f3754518381d42b839c`.
- Run Host ABI: `226557953b53c84cbf9076f090075d02ecd02199b42dd1307eaf22f90ee85aba`.

Other runtime roots reuse retained artifacts. This is selected checkout-runtime
acceptance, not a pristine packed/HTTPS campaign or full-root freshness proof.

Before the implementation commit, affected JS kernel/provider regressions
passed **118/118** (`run-9ugwmY`, `focused-test-5uDa2t`) and selected resource
gate mutations passed **4/4** (`run-Xwvdhg`, `focused-test-vcn555`). Those
receipts record the parent HEAD with a dirty tree, not the integrated SHA.

An earlier three-case Native buffer diagnostic passed **3/3**
(`run-SnIXzc`, `focused-test-3VZi8C`). A later Native selection timed out at
120 seconds (`run-ps2sXJ`, exit 124), with no passing-test summary. Neither
establishes final integrated Native acceptance. Fixture compilation mistakes
and corrected phase-barrier attempts remain separate failed receipts; no
product limit or expected logical work was inflated to repair them.

Receipts remain under `_build/local-checks/attempts/` and
`_build/focused-evidence/`. Runtime bundles remain ignored. Formatting,
Node syntax and whitespace checks passed.

## Remaining work

This closes provisional-output custody and explicit row/cell reference walks,
not all Local retained execution. Installed availability callbacks, other
algorithm scratch collections and Native allocation/callback correspondence
remain separate boundaries. Array capacity zero is not a GC/destructor latency
or complete physical-heap theorem.

Wasm execution, final Native execution, full Core, packed/HTTPS, proof,
performance and a complete Store-fault matrix were not rerun. No CI success
is claimed; Draft preparation is not merge verification.
