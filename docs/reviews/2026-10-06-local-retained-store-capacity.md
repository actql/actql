# Retained Local Store inventory admission

## Boundary and correction

The ordinary nested Set Program prepared and completed five tasks before the
last Sort could reserve its capacity. Candidate identity and exact ordered input
binding passed. The actual refusal was `Execution(Physical(RetentionLimit))`:
188,434,240 held bytes plus 37,686,848 required bytes exceeded the default
200,000,000-byte floor. The earlier task-zero/ForeignCandidate attribution is
corrected, not retained as a confirmed cause. Diagnostic evidence is
`run-HipDXL` / `focused-test-pfTJCO`; logging hooks did not change decisions.

`client_local_sequence_capacity` summed provider output allowances, but not
Store import/export allowances. Dispatch correctly included them later. The
fix derives the retained inventory before Run creation from the checked data
edges and the same installed import/export limits dispatch uses. It counts
receiving ports, including repeated references to one producer, not unique
producers. The export limits have one shared constructor. The transfer allowance
also covers all counted receiving ports, retaining its existing minimum.

The per-task allowance is provider ceiling + export ceiling + imported ports *
import ceiling. For the independent eight-task fixture the constants are:

- Provider: 14,240,000 bytes per task.
- Export: 1,541,184 bytes per task.
- Import: 21,905,664 bytes per receiving port.
- Ports: `[0, 1, 2, 1, 1, 1, 1, 1]`.
- Total: `8 * 15,781,184 + 8 * 21,905,664 = 301,494,784` bytes.

These are authored from declared representation ceilings, not sampled from a
successful execution. The existing 536,870,912-byte admission ceiling, per-task
limits, work, output order, completion identity and publication checks are
unchanged. The 200 MB number is the existing minimum Run allowance, not the
finite admission ceiling. Overflow and excess inventories refuse before opening
the Run. No parent is released early, no allocation is reported as zero, and no
Ledger, lifecycle or cancellation state machine is replaced.

## Executed evidence

Focused JS capacity checks passed **4/4**, `run-GhEEmM` /
`focused-test-tqWnxJ`:

```sh
node scripts/local-checks.mjs test moon -- --target js \
  src/client_local_host/retained_capacity_wbtest.mbt
```

They fix literal exact/one-short totals, zero-input output cost, repeated ports,
installed import/export constants, unchanged ceiling rejection, invalid numbers
and overflowing multiplication. They are capacity-inventory evidence, not a
sampled whole-operation work/workspace measurement.

Only `local-node` and `run-host-core` were rebuilt from the changed source.
The ordinary public boundary and adjacent interval caller passed **2/2**,
`run-Mr69z9` / `focused-test-CAVmMo`:

```sh
npm run build:runtime-packages -- local-node run-host-core
node scripts/local-checks.mjs test node -- \
  adapters/host-node/public-set-value-retention.test.mjs \
  adapters/host-node/public-interval-retention.test.mjs
```

The Set case submits ordinary JSON through `connectEmbeddedLocal`, with the
real retained Store and existing publication owner. EXCEPT/INTERSECT ALL and
DISTINCT compare Array values containing 256-character common-prefix Text and
NULL, then Unnest, project and sort. Each producer and both independently named
consumers are read against hand-authored ordered rows. Positive bounded advances
are observed. Reusing the same request produces no extra Compute and preserves
the Result. Snapshot directories are empty after publication. The case is
imported by `embedded-installation.test.mjs`, not only registered in a manifest.

The existing zero-input retained Values caller also passed **1/1**,
`run-ymQGSi` / `focused-test-tvPc5P`, selecting
`public source-free Program uses installed retained Relation output` from that
suite through the same Node wrapper. The rest of the installation suite was not
run. Changed MoonBit formatting, Node syntax and `git diff --check` passed.

The implementation tree tested here is committed unchanged; the PR records its
full source SHA. Ignored runtime bundles are generated, never committed. This is
checkout public-Host evidence, not clean packed distribution evidence.

## Scope and remaining work

This is the source-free retained Store inventory/publication follow-up to #510.
It preserves that unmerged dependency; final merge target is main. Memory output
capacity, Effect ledger preparation and externally supplied multi-acquisition
ledgers are unchanged. No new public API, wire, schema, pins or value semantics.

### Public cancellation inside comparison scanning

The follow-up uses the same ordinary Program, authorization and real Store.
A matching kernel fixture certifies that eight 256-work advances reach a live
`TextUnits` frame in `SortLeft`, phase 3, with an offset strictly inside the
257-code-unit operand. This is UTF-16 comparison scanning after input admission,
not value measurement or a sampled wall-clock delay. The session reports
cumulative work, while the provider reports each advance's delta.

The public test awaits the existing `local_compute_advanced` hook at cumulative
Set work 2048. Before releasing that barrier it requests cancellation through
the public execution handle. Both input snapshots remain present, cancellation
is requested but physical stop is not confirmed, and no Result is completed.
After release, the same owner reports confirmed physical stop and `cancelled`;
all three named Results remain unavailable. Both input snapshots are reclaimed.
There is no further positive Compute advance, output seal or dispatch, including
when the cancelled request is submitted again. The test releases its barrier
before closing the owner; it does not delete Store custody if owner close fails.

The matching focused kernel case passed **1/1**, `run-VlT0B9` /
`focused-test-HGTkXe`. The public success and cancellation cases passed **2/2**,
`run-SWsWqY` / `focused-test-8Q2W1g`:

```sh
node scripts/local-checks.mjs test moon -- --target js \
  src/execution_relation/bounded_set_nested_comparison_wbtest.mbt \
  --filter '*public Set fixture*'
node scripts/local-checks.mjs test node -- \
  adapters/host-node/public-set-value-retention.test.mjs
```

The entire changed nested-comparison test file then passed **7/7**,
`run-IGmeG1` / `focused-test-zioDjw`, without the name filter. Its existing
quantum-invariant work, exact/one-short limits and cleanup cases remain intact.

No production source or runtime package changed in this follow-up. The reused
runtime was generated from the unchanged production tree at
`71c55c55058c2ee745bc0878ff32fe3b78dd0f9f`. This checkout public-Host evidence
does not establish a new packed artifact or D's Model cancellation recovery.
The kernel fixture separately verifies one cleanup, zero comparison workspace
and live borrowed inputs; empty snapshot directories are not represented as a
public whole-Ledger reservation census.

Wasm/native, packed/HTTP, full Core, integrated CI, new Store fault campaigns and
a complete retained-route closure are not claimed. D's Run cancellation
finalization and H's Ledger-close/value fixes remain their own owners and
adoption units. This test-only follow-up does not implement either boundary.
