# Typed Relation pipeline pilot

This is a retrospective test/review-cost comparison for existing operations,
not delivery of a new product operation. Existing failure, capacity, backend,
Store and historical regression tests remain in place. No test is retired.
`baseline.json` was committed before generator implementation.

## Contract and domain

The initial registry contains `filter`, `select` and `sort`. Its checked root is
an authored `Values` producer, imported with its exact `ProducedInput` ownership
and occurrence-order evidence. The historical `duckdb_fixed_values` helper uses
the ActQL pipeline/lowering/execution APIs; it invokes no SQL or DuckDB evaluator.
Rows contain three numeric fields (`k` nullable), bounded integer values, at most
six rows, NULL, duplicates, empty input/output and distinguishable ties. Generated
sequences have two to four steps. Shrunk sequences may have one step.

The generator tracks schema/nullability, exact prior producer and the admitted
total occurrence order. Each descriptor must satisfy its precondition before
construction. Removing a step rebuilds exact producer references; reductions
which lose a required field or order premise are excluded before execution.
Each actual case goes through the checker, registered Local module provider and
selected Relation execution. A rejected or unexecuted case is not counted.

The [adopted order contract](../../docs/spec/language.md) supplies sort tie
behavior: eligible checked candidate keys take precedence; this pilot asserts
none, so an admitted total input occurrence witness supplies the tie order.
Unique-looking data is not a candidate-key proof. Arbitrary physical Relation
enumeration does not supply that witness. `take` requires the tracked admitted
total order. Select's authored public projection order and canonical internal
schema order are observed separately.

The independent JS oracle implements the restricted specification using numeric
comparison, NULL-aware predicates, projection and strict insertion sorting.
It imports no product evaluator/comparator. Neither product output nor its
accounting reference supplies expected semantic rows.

## Reuse versus new obligations

| Obligation | Evidence and limits |
| --- | --- |
| Delta work and terminal/cleanup behavior | Existing conditional Session theorem; new finite real selected-adapter/kernel comparisons. This adapter is not the generic adapter used by the nest pilot. |
| Child work plus handoff, preserved consumed budget, cleanup responsibility | Existing conditional arbitrary-finite serial chain model; actual per-case registered chain accounting and exact child input bindings. |
| Filter NULL/true-only behavior, projection, numeric/NULL sort and ties | Descriptor contract and independent oracle, with actual checked public/internal observations. |
| Exact schema/producer/order connections | Construction metadata plus independently logged checked source/sequence/order origin and registered execution. |
| Capacity | Existing reservations/tests retained. Child/runtime upper bounds and the 256-byte allowance remain unproved. |
| Store, backend and ownership boundaries | Existing acceptance/regression tests retained; no substitution with this numeric pipeline model. |

The harness runs each child through its actual selected adapter and its direct
cumulative kernel, comparing progress/work on every poll. It checks sealing,
cleanup retry and cancellation at that actual child/adapter boundary. Empty
children which finish on the first poll are recorded separately rather than
inventing a cancellation observation. Parent work is compared with summed child
work and attempted handoff charges. These are finite implementation correspondence
tests, not a proof of MoonBit/compiler/FFI refinement for arbitrary sequences.
The delayed-stop callback counterexample is a separate residual obligation.

Common Lean propositions, audits and shared state-machine histories are frozen
by `baseline.json`. No new common theorem, owner, product operation or lifetime
optimization is introduced. Old fixed-scope evidence gates are not widened.

## Generation, shrinking and mutations

Seed `105106` constructs valid directed adjacent pairs and 48 additional seeded
sequences. Initial three-operation corpus: 57 cases, nine adjacent contracts.
Four-operation corpus after `take` registration: 64 cases, 16 adjacent contracts.
Case counts do not measure tests removed or developer hours saved.

Actual production-site mutants exercise wrong checked handoff port and reversed
stable ties. Source is restored byte-for-byte after each mutant, including on
failure. Only JS explores and shrinks. Exact shrunk counterexamples are then run
under mutated and restored source on JS/Wasm/native. These are finite reproductions
on each target, not backend-wide mutation coverage.

Connection shrinking must retain the same operation-occurrence producer/consumer
edge and the traced wrong port. Order shrinking must retain the same sort
occurrence/field, the same distinguishable input occurrence pair with equal keys,
the expected pair order, the actual inversion and the same output multiset.
Thus another error with the same broad classification does not qualify.
Reductions cover operation subsequences, rows, individual numeric/null values,
equal-key value classes and descriptor arguments. The final certificate checks
every admissible one-step reduction. Minimality is local to these reductions.

## Marginal registration comparison

`extension.json` freezes the three-operation engine, execution/observation harness,
gate and orchestration before registering `take`. Adding take changes its own
descriptor and registry registration. The descriptor supplies order/count/offset
preconditions, postcondition, independent skip/limit oracle, syntax, argument
generation and reductions. Review additionally covers that local contract and
the existing bounded take route.

The same generator then covers `filter/take`, `select/take`, `sort/take`,
`take/filter`, `take/select`, `take/sort` and `take/take` without adding a handwritten
sequence fixture, generator branch or common theorem. These are seven new
adjacent contract obligations; they are not seven deleted or saved test cases.
The remaining per-operation boundary/resource/Store review is still necessary.
This establishes the supported registration mechanism, not universal elimination
of combination-specific semantic review.

## Reproduction and receipt audit

Use the repository's pinned MoonBit and existing audited Lean pins:

```sh
node --test proofs/relation-pipeline/engine.test.mjs proofs/relation-pipeline/evidence.test.mjs
node proofs/relation-pipeline/run.mjs js base
node proofs/relation-pipeline/mutations.mjs
node proofs/relation-pipeline/run.mjs all
node proofs/relation-pipeline/audit.mjs
```

CI runs this beside the existing gates. `.artifacts/relation-pipeline/` retains
exact requested cases/programs, source snapshots, compiler pin, generated fixtures,
successful execution logs, at-run artifact hashes, model audit logs and shrunk
counterexamples. The audit independently checks fixture/log/receipt/request
agreement, target, source, profile, order, conditional premises, local minimality
and the take extension hashes. Hashes identify evidence; they do not prove scope.
Execution fixture programs and checked origin are matched independently of the
requested/derived metadata, including a negative test that relabels both sides.

Earlier batches overwrite the temporary compiled observation driver. Their
artifact hashes identify the binary at execution time, not the final current
binary. Final normal-corpus binaries are archived and checked separately. Receipt
auditing does not execute downloaded Linux binaries on the local macOS machine.
The trusted runner, compiler and environment remain explicit assumptions.
