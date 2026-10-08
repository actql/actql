# Resumed retained authoring and Model evidence checks

## Completion unit and dependency

This unit connects the computation evidence suffix to the existing retained
Effect-free publication and Captured Run validation owners. It does not
complete all retained Local processing.

PR #948 at `8e342713a9b578b1472ab50c4c28cf9ab22f3d43` is now included
in main. The branch initially adopted main
`5f8937a511da19648f63b99cf406390019966de0` without conflicts.
Incoming changes are independent public Effect cancellation and packed Read
acceptance material, not overlapping production implementation. The child PR
kept its parent dependency until main contained it. PR #951 now targets main.

The subsequent normal merge adopted main
`0ed193460b2c220e78dc840b3fde23661fc926b9` without conflicts, producing
`f25d61d9bc0ac358751fde9a3a65ec346bfec1f8`. The suffix implementation,
all `src/run_publication` inputs and the retained Host fixture are unchanged
from the previously submitted `3f179ac3df3d40100c2c48a2dcab785186f115a6`.
Existing source-specific receipts are not relabeled as new Host acceptance.
The later capture units remain separate dependent PRs, #953 and #959.

Common JS and release runtime checks used clean source
`88e5751b81aba21b29e170679a735cf29c1bd2e5`.
The strengthened Host cancellation fixture was separately verified at
`a89c992774229434d7e988cb62c71db4dcab1a36`; compiled inputs are unchanged.
A later unpublished message-only correction produced
`fc741389a2dd901fe8a0fa5ce80060ca117c9313`.
Each corrected commit's tree and mapped parent relationship was checked;
final tree equality was also verified. Original receipts retain their tested
SHA. No published history or code changed for this formatting correction.

## Existing owner connection

`ComputationSuffixPreparation` replaces the synchronous suffix algorithm.
It validates authoring identity through the existing canonical stream cursor,
preserves its Program/preview binding, then checks every embedded Model
identity against the listed CID at the same position. Missing fields,
identity changes and listed-order mismatches retain their existing typed
causes. No CID equality substitutes for canonical identity recomputation.

External observation comparison remains an exact multiset comparison.
Multiplicity matters; the same distinct members alone are insufficient.
Singleton CID tuples are collected one per transition and reconciled with
the existing `bounded_tuple_sort` deferred owner, not another sorter.
Each tuple reserves its reference, component and two deferred index slots
before append. Sorting and final 64-unit UTF-16 comparisons advance within
the parent's quantum. Caller-owned external references are not sorted or
mutated in place.

The common computation driver polls the child after Result-row validation.
Peak private capacity is propagated. Cancellation retires active canonical
emission and both sorter owners, drops private arrays and references, and
leaves borrowed contracts and physical Store custody with existing owners.
Capture issuance reaches the same final validation driver.

The unused synchronous embedded-identity array helper is removed. Blocking
public callers already drain this driver: they share the new algorithm but
remain explicitly blocking. No fallback validator, new executor, ledger,
wire shape, CID rule or public execution authority is added. Fixture phase
labels describe progress only.

## Independent boundary evidence

The isolated fixture uses literal canonical bodies and independently authored
SHA-256 values; it is not an admitted complete Model invocation:

```json
{"payload":"alpha","version":"model-fixture"}
{"payload":"beta","version":"model-fixture"}
```

Their independent identities are respectively
`sha256:663a7bcd81810cce90ee6aade5989160b356062a4a1e3dbf71756fc6d0224448`
and
`sha256:d712ef7ae4cfd6383b426e2cba7626ea598eefc785a24eb8874930c0d60b9ab4`.
The authoring body uses a fixed Program CID of 64 digit-eight hex units and
`"version":"authoring-fixture"`; its independent identity is
`sha256:6f968b232c060e5abe84eaaa82911066aa277465fb82de735c76f9d7d46a68b7`.
These constants are not derived from product output.

Embedded alpha/beta/alpha/beta entries match external beta/alpha/beta/alpha
observations. The independent control total is 98:

- Begin, nine authoring polls and Model inventory admission.
- Four Model visits with seven identity transitions each, and Model end.
- Five external collection/setup transitions.
- Twenty polls for each existing four-entry bounded sort.
- Four two-fragment equality checks and final completion.

Quantum 1, 7 and 64 agree. Logical private peak is 48: sixteen frame slots
plus four slots per embedded and external entry. Exactly 48 succeeds;
47 refuses before the last external tuple and retires private state.
These are private control/workspace accounting quantities, not physical heap
latency guarantees or changes to Compute's contractual logical work.

Empty Model evidence needs sixteen transitions and peak 31, including the
authoring emitter. Exactly 31 succeeds; 30 retains the typed authoring
identity refusal. Missing listed evidence, changed payload, listed-order
changes, wrong Program binding and changed external multiplicity are rejected.
Partial authoring, Model hashing, both sorts and fragment-comparison
cancellation leave zero private slots and unchanged borrowed context bytes.

Existing black-box capture validation reaches this owner with admitted Model
evidence. The same canonical cursor's long Unicode, nested value and byte/node
limits are covered by the retained prelude tests. This reuse is valid because
the suffix polls that exact cursor with its own remaining workspace and
original canonical limits; no alternate emitter is selected.
This is not a packed Model-provider/capture-replay campaign.

## Actual retained Host acceptance

The ordinary Values/filter/select Program has a producer and two consumer
Stages. Real retained and publication Stores are used. Success reads all
three independently named Results and compares hand-authored Unicode/NULL
rows in exact DESC order.

The new cancellation case polls the common owner with quantum one and
delivers abort after at least three observed suffix polls, including actual
authoring hash progress after child installation. It keeps the typed abort
cause, refuses public index creation, finishes existing cleanup with zero
retained resources and never dispatches Compute again. Existing capture
issuance and publication success remain on the normal Host entry, without
manually constructed execution state.

## Executed verification and artifacts

Commands use the repository-pinned Node and MoonBit environment:

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- \
  --target js --jobs 1 src/run_publication
node scripts/local-checks.mjs build moon --timeout-seconds 180 -- \
  --release --target js --jobs 1 src/connectors_builtin_node \
  src/connectors/duckdb/conformance
node scripts/local-checks.mjs test node --timeout-seconds 180 -- \
  --test-name-pattern 'portable control validates Receipt and Captured Run references|retained publication validation yields before commit|retained Captured Run issuance yields through final evidence checking' \
  adapters/host-common/publication-contract-control.test.mjs \
  adapters/connectors/duckdb/node/test/retained-values-chain.test.mjs
node scripts/local-checks.mjs test node --timeout-seconds 180 -- \
  --test-name-pattern 'retained publication validation yields before commit: suffix-check$' \
  adapters/connectors/duckdb/node/test/retained-values-chain.test.mjs
```

At `88e5751b81aba21b29e170679a735cf29c1bd2e5`:

- Common JS: 274/274; `run-pclFm6`, `focused-test-GYZBW3`.
- Release runtime build: 38 incremental tasks; `run-JMM5Qe`.
- Selected Node: 11/11, including nine real retained Host cases, portable
  control and nested cleanup; `run-xyFsla`, `focused-test-z7lM8u`.

At `a89c992774229434d7e988cb62c71db4dcab1a36`:

- Strengthened suffix cancellation: 1/1; `run-6HFi95`,
  `focused-test-aHDLiu`. Only fixture synchronization changed; a Git diff
  confirms unchanged MoonBit, generator and build inputs.
- API generation, Node/RelA, Node Host and Workers fixture freshness and
  Node syntax passed without tracked generated changes.

Consuming artifacts are matching checkout release runtimes, not pristine
packed tarballs. Receipts remain under `_build/local-checks/attempts` and
`_build/focused-evidence`. The earlier 273/273 diagnostic `run-aS4CvL`
preceded empty/negative additions and removal of an unused synchronous helper;
it is not final-source acceptance. The build process handle was absent on
continuation, but its authoritative completed receipt records exit zero,
complete output and released locks; no replacement build was launched.

Changed MoonBit sources are checked against complete pinned formatter output;
commit subjects and all body lines follow Conventional Commits and the
72-character limit. Documentation-only commits do not relabel earlier test
receipts. Hosted required CI is not claimed by local success.

At integration source `f25d61d9bc0ac358751fde9a3a65ec346bfec1f8`, the
focused JS command above passed 274/274 again. Evidence is `run-Q2qB5l`
and `focused-test-Z5SgHy`. The initial sandbox attempt could not start the
wrapper's process supervision; it did not execute tests. The completed
supervised attempt is the execution evidence. This integration did not run
a new runtime build, Host/packed campaign, all-target tests or hosted CI.
The following record-only update does not change compiled or fixture inputs.

## Remaining boundaries

Capture snapshot/dependency preflight and issuance inventories, computation
capture-inventory equality/name checks, scalar schema/unique-array checks,
field-name normalization and contiguous allocation latency remain distinct
synchronous boundaries. Fixed-field removal still handles closed admitted
contracts; generic large object normalization is not closed here.

Effectful asynchronous commit connection, explicit blocking Native/direct
callers, all-target, packed/HTTPS and required hosted CI are unverified by this
unit. Whole publication and whole retained Local completion remain separate
goals.
