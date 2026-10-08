# Resumable capture input inventories

## Completion boundary and dependencies

The existing capture issuer now resumes Source-advance reference scanning,
Result snapshot ordering and membership, and Model evidence inventory
reconciliation before context emission. It reuses `bounded_tuple_sort` and
the existing aggregate preparation driver. No new scheduler, authority,
ledger, canonical preimage or physical Store owner is introduced.

This unit depends on unmerged #953, whose own prerequisites are #951 and #948.
Its temporary base is `feat/local-bounded-capture-inventories`; the eventual
merge destination remains main, not that dependency branch. Main
`f2ceac7e0c673780b053b9a323e76a03c152e09a` was adopted by a normal,
conflict-free merge. Unrelated incoming main changes are not this unit's work.

## Implementation and ownership

The original admission order remains Receipt/advances/authoring, snapshots,
Effect sources, Models, then plans/dependencies. The Effect-specific helpers
retain their existing checks and typed failure precedence; they are not
claimed bounded by this change.

The private snapshot child collects one borrowed name per transition, uses the
existing deferred sorter, compares duplicate names in 64-unit UTF-16
fragments, and visits one admitted definition or Artifact identity per
membership transition. The former existence rule is preserved; this does not
replace root admission with a different uniqueness rule.

The Model child orders evidence identities, checks token kind and duplicates,
visits one borrowed Receipt observation at a time, and sorts the extracted
Model references with the same sorter. Comparison preserves exact count,
position and multiplicity, including repeated external references.

Tuple and index slots are reserved before append. Sorted output arrays detach
from the child and are reserved by the parent while context emission uses
them. They retire only after that child finishes, or after cancellation stops
it. Cancellation clears private state once; caller-owned contracts, payloads,
input arrays and Store custody are not released or mutated. A read-only fixture
inventory accessor exposes accounting and reference presence, not authority
or a completion proof.

## Independent boundary evidence

Whitebox inventory fixtures use literal CIDs and canonical payloads, not
complete admitted Run/Model bodies. Their expected control totals are derived
from the phases, independently of measured successful execution:

- Two snapshots: Begin 1, collects 3, sort polls 7, snapshot visits 3,
  definition visits 2, Artifact visits 2, appends 2: total 20.
- Two Models: Begin 1, collects 3, sort polls 7, Model visits 3,
  external visits 3, sort polls 7, comparisons 5: total 29.
- Frame 12, two four-slot key/index reservations, two output references:
  peak 22. Exactly 22 succeeds; 21 fails with `CaptureIssuanceEncoding`.
- Empty snapshot and Model cases take 4 and 7 transitions respectively.
  Their frame requires 12 slots; 11 is rejected.

Quantum 1, 7 and 64 agree. A 259-unit Unicode prefix exercises retained
comparison offsets. Sorting, long-name comparison, membership, Model append
and external comparison can be cancelled without modifying borrowed inputs.
Count, duplicate name, foreign binding, wrong Model kind, duplicate identity,
missing observations and multiset mismatches retain specific typed failures.

Separate blackbox fixtures use actual admitted contracts, including Model
evidence. They verify quantum-independent final identity/work, aggregate
cancellation and two held references throughout context emission, followed
by zero references/reservations on retirement or repeated cancellation.
These are private preparation-control quantities, not a new Compute work
contract or a generic heap-latency guarantee.

## Actual retained Host acceptance

An ordinary Values/filter/select Program uses real retained and publication
Stores. Success reads the producer and both consumer Named Results with
independently authored Unicode/NULL rows in exact DESC order.

The added cancellation case uses quantum one within snapshot inventory
preparation and requires at least three phase observations before abort.
Inventory progress precedes cancellation; it is not a fixed-sleep or manually
assembled execution fixture. The original abort cause, no committed index,
exactly three completed Compute dispatches and final resource reclamation
remain checked. Existing root/context/row cancellation and portable
publication control, including concurrent durable cleanup, also pass.

This is not a new Model-provider or packed INFER acceptance campaign. Model
inventory admission is exercised by the common blackbox fixtures above.

## Executed verification and artifact correspondence

At clean source `1fce2861a2b6e43717535d862e6aad4297bc22cd`:

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- \
  --target js --jobs 1 src/run_publication
node scripts/local-checks.mjs build moon --timeout-seconds 180 -- \
  --release --target js --jobs 1 src/connectors_builtin_node \
  src/connectors/duckdb/conformance
```

Common JS passed 280/280 (`run-jHwnee`, `focused-test-7woqcQ`). The selected
release runtime build passed 38 incremental tasks (`run-iXjgYS`).

At clean Host-test source `97de89b3166d692cb8884669d38eec0c4fb1009a`:

```sh
node scripts/local-checks.mjs test node --timeout-seconds 180 -- \
  --test-name-pattern 'retained Captured Run issuance yields through final evidence checking: snapshot-inventory' \
  adapters/connectors/duckdb/node/test/retained-values-chain.test.mjs
node scripts/local-checks.mjs test node --timeout-seconds 180 -- \
  --test-name-pattern 'portable control validates Receipt and Captured Run references|retained Captured Run issuance yields through final evidence checking: (success|root-check|context-check|rows-check)$' \
  adapters/host-common/publication-contract-control.test.mjs \
  adapters/connectors/duckdb/node/test/retained-values-chain.test.mjs
```

The new case passed 1/1 (`run-fQzfWM`, `focused-test-mdF6vA`); the remaining
selection passed 6/6 (`run-k6AhYO`, `focused-test-R94OD3`). Together these
cover five actual retained Host cases and two portable control/cleanup cases.
Only the Host fixture's polling scope differs between those two source SHAs.
All compiled inputs are identical, and both selected release runtimes were
built from the common verified source. These are matching checkout artifacts,
not pristine packed tarballs. Receipts remain bound to their actual SHAs.

`moon info --target js src/run_publication`, Node/RelA bundle freshness,
Workers/Node Host fixture freshness, changed-file formatting, Node syntax and
`git diff --check` passed. The generated API includes the fixture reader.
New commit messages were checked for Conventional Commits and 72-column lines.

Earlier diagnostics failed to compile fixture names/access before the clean
source above. The initial 14-case Node selection at that source timed out at
180 seconds (`run-zgkY9r`, incomplete `focused-test-kXZ02P`); it is not a pass.
The fixture had used quantum one throughout capture preparation. Polling was
then scoped to the target inventory, and the smaller relevant selections
above completed. No broad suite, manual CI retry or success from an old SHA
is substituted for these executed checks.

## Remaining work

Effect-source sorting/body/preview validation, plan preparation and dependency
admission remain synchronous boundaries. Source-advance body admission before
this scan, scalar/unique-array checks, field-name normalization and physical
allocation latency remain separate. Blocking convenience APIs still drain
the shared algorithm synchronously.

Effectful asynchronous publication, Native/direct execution, all-target,
packed/HTTPS and hosted required CI are not established here. Draft CI does
not prove required coverage. Whole publication and the full retained Local
goal remain incomplete; documentation-only commits do not relabel receipts.
