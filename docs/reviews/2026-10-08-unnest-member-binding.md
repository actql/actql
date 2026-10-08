# UNNEST parameter member binding

Date: 2026-10-08. Status: implementation and independent fixtures; final-source
public execution remains unverified until the normal packed consumer completes.
This is a follow-up to #988, not overall Frontend completion.

## Preserved requirement and counterexample

`docs/spec/query-text.md` selects ASCII case-insensitive field lookup, including
backtick names. Machine Program declarations and JSON data remain case-exact.
The existing nullable parameter contract has `payload.nested.items`, bounded to
three nullable closed objects with non-NULL numeric `id` and nullable `label`.

```sql
SELECT element.*, position
FROM UNNEST(@payload.NESTED.ItEmS) element WITH OFFSET position
ORDER BY position
```

This must produce the same complete Program as the already authored independent
`unnest_parameter_path_test.mbt` expectation using `nested.items`. Before this
fix, the selected two-test file passed only 1/2: the new member-spelling case
was rejected before complete query member binding. Evidence: `run-q5QD63`,
`focused-test-F85Pmu`. This establishes a Frontend compilation defect; it is not
an executed public Run counterexample.

## Change and boundaries

The early UNNEST element-type probe now calls the existing `MemberResolution`
expression binder. It uses declared receiver contracts and rewrites only authored
property selectors to their exact declared spelling. There is no second name
resolver, row sampling, lowercasing of parameter values, guessed schema, or new
checker/executor. The final Program still uses ordinary full-query binding and
checking. The full real query limits are threaded through `compile_steps`;
callers retain their existing numeric limits and arguments.

The binder can report its existing typed receiver refusal to the early probe.
A failed probe retains its reservation; it does not restart with a fresh budget.
Successful binding, receiver checking, copying, readmission and final typing use
the remaining probe allowance. Untyped empty/NULL arrays and correlated row
resolution retain their existing scope. No new expression work contract is
introduced or common execution-owner code changed.

`query_script_program.mbt::lower_script_relation_term` changes only the argument
that supplies those existing limits to `compile_steps`. CTE predicates, assert,
Effect, capture, acquisition and recovery logic are unchanged. The analogous
JOIN, Graph rows and keyed Graph calls receive the same limits record. This is
an internal Frontend calling-boundary adjustment, not a new composition owner.

## Independent obligations

- Unquoted `NESTED.ItEmS` and quoted `NESTED`/`ITEMS` selectors resolve to the
  existing exact `nested`/`items` contract; the complete expected Program is
  unchanged.
- A contract and values authored with `Nested`/`Items` retain that exact spelling
  in the JSON control. Lowercase SQL selectors choose those declared fields.
- `nested` plus `NESTED` in one receiver contract is ambiguous and rejected;
  no arbitrary field is chosen. The public refusal requires
  `ClientProgramInvalidInput`, Run admission zero and Source I/O zero.
- Existing typed causes and authored locations from #988, nullable propagation,
  three-element bounds, NULL containers/elements, duplicates, offsets, full
  Result.describe contracts and column order remain required.
- The ordinary public corpus includes all new cases. The existing narrow
  parameter-UNNEST consumer executes 14 success fixtures and six refusals through
  Embedded Local and real HTTPS, including independently authored JSON controls.
  No fixture patches the generated Program after compilation.

Initial corrected sources passed 33/33 selected JS cases (`run-tQBCfY`,
`focused-test-IU9m9n`): independent UNNEST Programs, #988 diagnostics, correlated
input, ordinary object member binding and existing probe-budget ownership.
The expanded fixture/refusal-control Node selection passed 9/9 (`run-PSG12N`,
`focused-test-WpfsgX`). These are working-tree evidence, not final-HEAD CI or
packed execution evidence. Final-HEAD results belong in the PR and retained
command receipts.

## Dependency and remaining verification

Parent #988 is fixed at `50696221a77b23a017448bbf09181a4d601423fb`; its unchanged
10-success/five-refusal corpus passed normal five-package Embedded Local/HTTPS
acceptance (`run-maUNyb`, `public-query-evidence-p7Hcww`). That earlier execution
cannot prove this follow-up's new cases. Keep the dependency until main contains
#988, use normal merges, preserve original tarballs/manifests/receipts, and do not
reinterpret past CI or runtime evidence as verification of this change.

Still required: exact final-source selected tests and normal packages, complete
14-success/six-refusal public cohort, review and required CI. Wasm/Native and full
Core are not locally certified. No merge or manual CI rerun is performed.
