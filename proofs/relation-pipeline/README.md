# Common acceptance for typed Relation pipelines

This foundation accepts existing operations on the registered serial Relation
route. It extends the #128 pilot; it does not deliver a new product operation,
retire the four Host tests kept by #131, or prove the whole implementation.

## Development procedure

1. Add an operation descriptor: admitted input conditions, schema and order
   postconditions, syntax, bounded arguments, independent semantic oracle and
   argument reductions. Do not import product checking, lowering or comparators
   to produce expected contracts or rows.
2. Register its precise variant and actual selected kernel route in
   `obligations.mjs`. Add predicates for concrete semantic boundaries over
   independent intermediate inputs/outputs. Labels and adjacent pairs are not
   evidence. `corpus.mjs` completes missing witnesses deterministically using
   the same typed generator and rejects any remaining missing obligation.
3. Register small production-site mutants, their admitted search domains and
   same-defect anchors in `mutation-registry.mjs`. Keep fixed reproductions in
   `regressions.json`; include primitive-specific and connection defects.
4. Run `node --test proofs/relation-pipeline/*.test.mjs`, then the existing
   `node scripts/local-checks.mjs run pipeline-evidence` job with the pinned
   MoonBit and audited Lean tools. Submit the marginal operation rules, actual
   connection evidence, mutation/shrink receipts and remaining obligations.

Each campaign validates its current source snapshot, tested commit, pinned toolchain,
independent semantic observations and exact artifact/receipt identities. Changes do
not require declarations about earlier commits. Historical comparison experiments
are available in Git history, not part of current acceptance.

## Supported route and independent observations

The root is checked authored Values with exact ProducedInput ownership and total
occurrence order. Three numeric fields (`k` nullable), bounded integers, at most
six rows, NULL, duplicates, empty input/output and distinguishable ties are
admitted. Sequences have one to five steps; generated sequences have two to four.
Filter, select, sort, take, simultaneous rename, whole-row distinct and the
numeric snapshot-map `derive` instance are registered. Derive adds one fresh
field equal to an admitted numeric field plus an integer in -2..2; NULL remains
NULL and its declared nullability is retained. Other expressions, sequential
shadowing, demanded failures and arbitrary numeric ranges remain outside this
successful domain. Unsupported
variants, strings, arbitrary schemas and candidate-key assertions remain outside
this domain. Their existing tests stay in place.

Every case is checked and executed through `prepare_local_compute_module`, the
registered Local provider and the selected Relation chain. Each selected child
uses `selected_binding_rows_execution` and the bounded binding-rows Session.
This is a different adapter from the nest pilot: its own cumulative/delta,
terminal, cancellation, exact-input and cleanup correspondence is exercised.
The historical `duckdb_fixed_values` helper invokes no SQL or DuckDB evaluator.

Three observations are kept separate:

| Observation | Expectation and actual binding |
| --- | --- |
| Independent expected contract | Descriptor postconditions derive full field type/nullability; compared with the checked schema for every step. Empty/all-NULL cases validate that contract, not a type inferred from cells. |
| Connection to execution | The same GeneratedSequence passed to the registered provider supplies selected kernels, checked/kernel output schemas and Select input/output references. No second unrelated checker plan is used. |
| Executed values | Public columns and their order, canonical completed-table columns, wire projection, cell values, duplicates and row order are compared with the independent oracle. Each selected child output is also compared with its independent intermediate result, so a later empty output cannot hide an intermediate defect. |

Completed tables do not expose independent runtime field contracts. This adds
no runtime metadata or public API. The selected kernel schema is an associated
checked contract, not independently inferred runtime schema. Existing completed
wire projection is observed separately from canonical cell storage.

Sort ties use the adopted specification's admitted input occurrence witness,
not physical enumeration or an assumed stable library sort. Take requires total
order. Rename preserves contracts and occurrence order, rewrites sort key names,
and expands in canonical INPUT-name order; public output-name order can differ
from canonical schema order. Downstream operations actually reference new names.
A swap reads both original fields simultaneously. Rename lowers to Select and
is not evidence for a new physical algorithm.

## Reused guarantees and residual obligations

Existing conditional Session/chain Lean propositions and axiom audits remain
unchanged. Finite actual child/adapter/kernel comparisons check delta accounting,
sealing, cancel-next-advance stop without Compute, cleanup retry and exact input
bindings. Parent work is compared with child work plus attempted handoff charges.
Empty children already terminal on the first poll are counted separately.

The general theorems are model proofs under stated premises. The real sequence
observations are finite tested correspondence. Neither is a proof of the MoonBit
compiler, runtime, FFI, all providers, arbitrary DAGs or all Algebra operations.
Child/runtime capacity bounds, the 256-byte allowance and delayed-stop work remain
unproved/separate. Reservation, resource-boundary, cancellation, retained Host,
fan-out, Store and physical backend tests are maintained.

## Fixed verification, fresh exploration and audit

CI always executes fixed corpus, concrete obligation checks, known-site mutant
and restored-success reproductions on JS/Wasm/native, and whole-report target
substitution rejection. Fresh JS exploration and shrinking are additionally
required by `exploration-impact.mjs` for kernel, adapter, Session/chain, typing,
specification, build dependency, CI and unknown-path changes. Invalid/missing
base, empty diff or diff failure also require exploration. Only a small reviewed
presentation-only allowlist can skip it. The required check prints and retains
its source-bound decision; the audit independently recomputes it.

Exploration retains source SHA, toolchain, seed, reviewed domain, same-defect
anchor, each shrink attempt and every final one-step reduction. Minimality is
local to those reductions. Fixed replay never claims fresh search or minimality.
Exact minima are replayed under mutated/restored source on all targets; a JS
search result is not a backend-wide detection guarantee. Source restoration is
byte-for-byte, including failure paths. Timings separate search, shrink, mutated
and restored target replays, and normal fixed target verification.

```sh
node --test proofs/relation-pipeline/*.test.mjs
node proofs/relation-pipeline/run.mjs js base
node proofs/relation-pipeline/mutations.mjs fixed
node proofs/relation-pipeline/mutations.mjs auto
node proofs/relation-pipeline/run.mjs all
node proofs/relation-pipeline/audit.mjs
node proofs/relation-pipeline/audit-target-regression.mjs
```

`.artifacts/relation-pipeline/` retains actual inputs, programs, source snapshots,
fixture/log/receipt hashes, compiler, model logs, normal binaries and mutation
receipts. Audit binds the requested target to report, receipt, command, artifact
path and archived normal binary. Unchanged native reports in JS, Wasm or baseline
slots are rejected. Hashes fix evidence identity; scope is checked independently.
The runner, compiler and environment remain trusted assumptions.

## Current source and retained model baseline

Current evidence must match the tracked tested commit, including proof inputs
that Git ignore rules would otherwise hide. No per-commit historical declaration
or declaration archive is required.

The separate bounded-model baseline remains: it checks reviewed model/checker
bytes against fixed Git revisions and verifies the current model inputs. These
specific historical Git objects are still required by the full proof audit;
shallow-checkout support for the current-source guard does not imply that the
entire proof suite runs without those objects.

### Eight-part hosted evidence

The full workflow uses the source-bound `proof-parts.mjs` plan with exactly eight
fresh producers. `L-C2` keeps the entire 28-case normal/boundary tuple on all
three targets and the final 114-case corpus in the same checkout after boundary
restoration. `L-C3` owns backing/model evidence and custody followed by
native-parent evidence. Its actual independent support receipts do not become
generic pipeline executions. `L-C4` and `L-C5` own the first three and final two
capacity mutations, respectively, with unchanged fresh search, shrinking,
mutated minima and independent instrumented healthy replays. `L-M2` through
`L-M5` each own two registry mutations; fixed and required fresh modes remain
together in each independent mutable/pristine pair. Local logical `L-M0` and
`L-M1` aliases retain their original complete four-variant groups.

Each mutated root is restored byte-for-byte. Its old executor closes before a
new owner executes its assigned recovered minima on the same restored root, on
all three targets. These fresh recovery observations remain separate from the
original pristine/instrumented healthy replays and are not another execution of
the 114-case corpus. The new owner closes before the part is sealed. Existing
local consistency and custody checks remain mandatory before sealing.

`ci-parts.mjs` seals a PART envelope, never a full scientific success. Receipts
and observation IDs receive their part namespace at production. The aggregate
requires all eight successful exact artifact IDs from one workflow/run/attempt,
identical tested source, toolchain and plan, and successful same-source
synthetic validation (executed once in parallel). Missing or duplicate parts,
observations, changed receipts, foreign owners and incomplete local obligations
fail admission. Original part reports and receipts are retained unchanged; a
new derived union binds them by digest and retains their actual owner maps.
Only that complete union undergoes the full scientific and whole-report negative
audits and can satisfy `pipeline-evidence`. No build tree or completed proof
result is cached or shared between producers.

### Numeric derive extension

The original six-descriptor corpus remains the exact first 86 inputs, including
their identities. The existing typed generator adds only sequences containing
the new descriptor: 28 inputs, including all 13 new directed adjacent pairs.
When generated identities collide with retained inputs, only the new input
gets an `extension:` prefix. No original input or execution receipt is changed.
The same shrinker retains schema validity when a downstream step reads the
derived field. Five concrete predicates require NULL propagation, nonzero
arithmetic with the source retained, downstream use, duplicate/order retention
and the empty output contract. A missing predicate fails corpus admission.

The real observation harness admits `SnapshotMap` as an additional selected
kernel route; it contains no derive oracle. Checked/kernel schemas, every
intermediate output, parent/child work and stopped/cleanup correspondence are
checked by the existing execution and evidence consumer. No Session/chain law,
generator or shrink coordinator is copied or extended. Preserving the original
corpus does require a generic corpus-union change, and it is reported as a
common change rather than a zero-common-change experiment.

The eight existing mutation campaigns and physical/Host fixtures remain. Their
past results are not new derive mutation evidence. The arithmetic-expression
kernel, all unadmitted expression/failure forms, physical capacity and Host
custody still need their own obligations. This extension does not retire tests,
authorize another cached action, or establish CI savings.

### Subsequent registry additions

`registry.mjs` keeps accepted descriptor stages in `corpusFoundations`: the
original six-descriptor foundation and the seven-descriptor numeric derive
stage. `fixedCorpus` completes them in order and appends only inputs containing
descriptors new to the next stage. It preserves every earlier input and identity,
deduplicates equal input bodies, and resolves new identity collisions without
renaming original cases. Each accumulated stage must discharge its concrete
obligations. Reversed, repeated or nonprefix stages are rejected.

For another operation, retain those explicit arrays, register the operation's
local premises/independent oracle/contract/argument reductions and connection
obligations, then append its descriptor stage and select that stage as the
current registry. Update the independently reviewed final corpus count in
`proof-parts.mjs` to the actual complete union; preserve its three targets and
all unrelated campaigns. Do not replace an old stage with a regenerated latest
registry or retire inputs solely because the new random stream has coverage.
Any changed generator, oracle, contract or descriptor still invalidates its
source-bound evidence; stage retention is not a receipt-reuse permission.

The current 114 inputs and corpus digest remain unchanged. Future additions in
the corpus regression use generator-only fixtures to demonstrate two successive
extensions; they are not registered product operations, runtime acceptance or
new semantic guarantees.
