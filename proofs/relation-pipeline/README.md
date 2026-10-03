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

For a second operation, freeze the completed first foundation's source SHA and
common hashes in `reuse-baseline.json`. The audit rejects common changes against
that baseline. A necessary generic correction must be a separate commit and
reported as a failure of the original no-common-change comparison, followed by
its corrected result. Moving large meaning rules into callbacks does not count
as avoiding review work.

## Supported route and independent observations

The root is checked authored Values with exact ProducedInput ownership and total
occurrence order. Three numeric fields (`k` nullable), bounded integers, at most
six rows, NULL, duplicates, empty input/output and distinguishable ties are
admitted. Sequences have one to five steps; generated sequences have two to four.
Filter, select, sort, take and simultaneous rename are registered. Unsupported
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

## Review-cost comparison

The historical take experiment in `extension.json` remains immutable and is
checked against its original Git blobs, including the separately recorded #128
P2 correction. It is not relabelled as using this expanded foundation.

This first increment pays common costs for concrete obligation completion,
checked/kernel observations and separate fixed/exploratory CI auditing. Rename
adds its own contract/oracle/reductions, six concrete predicates, actual Select
projection correspondence and three primitive/connection mutations. No common
Lean theorem or handwritten existing-operation/rename combination fixture is
added. Generic construction supplies those combinations. Its fixed single-step
mutation regressions are additional defect reproductions, not saved tests.

No deletion count, generated-case-to-saved-test conversion or CI speedup is
claimed. Existing operation boundaries and physical-route reviews still apply.
The second distinct increment measures marginal meaning rules and connection
review against the fixed first foundation, separately from these initial costs.

### Four-part hosted evidence

The full workflow uses the source-bound `proof-parts.mjs` plan with exactly four
fresh producers: `L-C0` owns normal/boundary capacity, backing/model evidence,
custody followed by native-parent evidence, and the full final 86-case corpus on
three targets. `L-C1` owns all five capacity mutations with unchanged fresh
search, shrinking, mutated minima and independent instrumented healthy replays.
`L-M0` and `L-M1` own the reviewed static four-variant groups; fixed and required
fresh modes remain together in each independent mutable/pristine pair.

Each mutated root is restored byte-for-byte. Its old executor closes before a
new owner executes its assigned recovered minima on the same restored root, on
all three targets. These fresh recovery observations remain separate from the
original pristine/instrumented healthy replays and are not another execution of
the 86-case corpus. The new owner closes before the part is sealed. Existing
local consistency and custody checks remain mandatory before sealing.

`ci-parts.mjs` seals a PART envelope, never a full scientific success. Receipts
and observation IDs receive their part namespace at production. The aggregate
requires all four successful exact artifact IDs from one workflow/run/attempt,
identical tested source, foundation, toolchain and plan, and successful same-source
synthetic validation (executed once in parallel). Missing or duplicate parts,
observations, changed receipts, foreign owners and incomplete local obligations
fail admission. Original part reports and receipts are retained unchanged; a
new derived union binds them by digest and retains their actual owner maps.
Only that complete union undergoes the full scientific and whole-report negative
audits and can satisfy `pipeline-evidence`. No build tree or completed proof
result is cached or shared between producers.
