# Resumed retained capture inventories and Result lookup

## Completion unit and dependency

This unit connects captured Artifact equality, Result-name inventories and
Result lookup to the existing retained publication validation driver. It does
not complete all retained Local or publication processing.

The prerequisite is unmerged Draft #951 at
`3f179ac3df3d40100c2c48a2dcab785186f115a6`, which depends on #948.
The branch normally adopts main
`ce6d529d43292733eaa1b6967fc4571627a4ea5c` without conflicts. Incoming
changes concern independent cancellation fixtures and numeric derive evidence,
not overlapping production implementation. The child retains its parent base
until that dependency reaches main; the final merge destination is main.

All verification below used clean source
`9160c1c3666e443b2dc1906d27e2eb872e0fbc56`. Before first publication, a
commit-body wrapping correction recreated the two unpublished commits.
The corresponding trees and mapped parent relationship are unchanged.
Receipts retain their actual tested SHA, not the later record-only HEAD.

## Existing owner connection

`CaptureInventoryPreparation` borrows the canonical captured context and
manifest inventory. Its Artifact comparison polls the existing exact paired
canonical stream; matching CIDs alone do not establish value equality.
The remaining two inventories require the same nonempty names, not just the
same count. Their admitted canonical object keys are unique and UTF-16 sorted,
so indexed comparison needs neither a copied name array nor another sort.
Each name comparison retains an offset and consumes at most 64 UTF-16 units.

`ComputationEvidenceCheck` polls this child before Result-row validation. A
separate `ResultLookup` phase searches admitted keys with the same fragment
cursor. After equality, the paired field inventory uses the validated index;
it does not repeat synchronous name lookup. Row/field shape, exact definition
binding, snapshot validation and later evidence checks remain required.

The original dependency and Effect-preview preflight stays before these checks,
with unchanged failure precedence. It remains a separate synchronous boundary.
Missing fields, mismatched Artifact content, name/shape mismatches and missing
Results retain existing typed causes. No wire, identity, public authority,
execution scheduler, ledger or compatibility fallback is added.

Private parent and child workspace is reserved before child installation.
Peak capacity propagates to the existing driver. Cancellation retires emission
state and borrowed references, not caller-owned contracts or physical Store
custody. Existing capture issuance reaches this driver for final validation;
blocking convenience callers still drain it synchronously.

## Independent boundary evidence

The isolated inventory fixture uses literal canonical bodies, not a complete
admitted Artifact contract:

```json
{"alpha":null,"beta":null}
{"alpha":[],"beta":[]}
```

Its independent control total is 30:

- The paired stream has two six-transition emitters, six comparisons and
  Begin/Done: 20 transitions.
- Inventory Begin, two sections of Names/two comparisons/end, and final
  Names completion: 10 transitions.

Quantum 1, 7 and 64 agree. Private peak is 2077 slots: parent 12, stream 12,
two 1024-unit buffer reservations, four pending frames and one provisional
emitter slot. Exactly 2077 succeeds; 2076 retains the typed captured-Artifact
refusal and retires private state. These are private validation control and
workspace quantities, not a new Compute work contract or heap latency bound.

A 259-unit Unicode name needs five fragments in each name inventory. Eight
positive retained offsets demonstrate internal progress rather than only
yielding between names. Changed Artifact content, count, field inventory,
same-count foreign names, non-object values and missing values retain specific
typed failures and precedence. Partial Artifact emission and both name scans
can be cancelled; private state reaches zero and borrowed context is unchanged.

## Actual retained Host acceptance

The ordinary Values/filter/select Program uses real retained and publication
Stores. Success reads exactly the producer and two consumer Named Results,
with independently authored Unicode/NULL rows in exact DESC order.

Two new cancellation cases poll publication validation with quantum one.
Capture-inventory cancellation requires three observed child-phase polls,
including actual Artifact emission after installation and Begin. Result-lookup
cancellation requires repeated lookup observations after actual progress.
Neither case uses a fixed sleep or manually assembled execution state.

Existing assertions preserve the original abort cause, forbid contract writes,
attempt creation and committed index publication, and require all three
Compute dispatches to remain completed without additional execution. Harness
cleanup retains existing owners and finally reclaims retained resources.
Earlier capture issuance, root/Receipt/context/row/suffix cancellation and
durable nested cleanup remain covered by the selected consuming tests.

## Executed verification and artifacts

Commands used the repository-pinned Node and MoonBit environment:

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
moon info --target js src/run_publication
node scripts/connector-node-bundles.mjs
node scripts/workers-fixtures.mjs
node scripts/node-host-fixtures.mjs
node --check adapters/connectors/duckdb/node/test/retained-values-chain.test.mjs
git diff --check
```

At clean source `9160c1c3666e443b2dc1906d27e2eb872e0fbc56`:

- Common JS: 276/276; `run-IndC01`, `focused-test-ajN3yt`.
- Selected release runtime build: 38 incremental tasks; `run-09OE8w`.
- Selected Node: 13/13, including eleven real retained Host cases, portable
  control and nested durable cleanup; `run-ZO4c1c`, `focused-test-wSX2tv`.
- API generation and Node/RelA, Node Host and Workers generator freshness
  passed without tracked generated changes. Changed MoonBit formatting and
  Node syntax passed. Before publication, all new commit lines were checked
  against the 72-character limit.

Consuming artifacts are matching checkout release runtimes, not pristine
packed tarballs. Receipts and output remain under `_build/local-checks/attempts`
and `_build/focused-evidence`. Earlier dirty-tree diagnostic `run-EtemhK`
passed 276/276 but is not substituted for clean-source acceptance. The first
diagnostic failed on a fixture's unused non-Unit return; that fixture was fixed
before these clean checks. Documentation-only changes do not relabel receipts.
Local success does not establish hosted required CI success.

## Remaining boundaries

Dependency/Effect-preview preflight, capture issuance inventories, scalar
schema/unique-array checks, field-name normalization and contiguous allocation
latency remain distinct boundaries. The new Result inventory cursor does not
make those paths bounded. Blocking APIs remain blocking.

Effectful asynchronous publication, Native/direct execution, all-target,
packed/HTTPS and hosted required CI are not established by this unit. Whole
publication and whole retained Local completion remain separate goals.
