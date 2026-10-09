# Literal membership expression reuse

This unit starts from main `584b3a6144d4a8053ca4a541ef042a6e17c674e9`.
It repairs Frontend reuse of two spellings already lowered to the same common
operation; it does not change membership evaluation, admission or resource limits.

## Requirement and counterexamples

The selected profile in `docs/spec/query-text.md`, ARRAY constructors, lowers
unannotated `[NOT] IN UNNEST` arrays of scalar literals and immediate parameter
references to the existing `in`/`not_in` literal-list contract. It retains atom
order, duplicates, NULLs and parameter holes. General and annotated arrays retain
their separate admission and are not silently literalized.

The reference is GoogleSQL `d82db99a923a46571f543a13899dc791a7b6f743`,
`docs/operators.md`, IN operator, lines 2748–2808. That section specifies list
and UNNEST membership and the equal-match-before-NULL rule. This repair concerns
the already selected literal subset, not support for all reference forms.

Both of these queries were rejected before the repair:

```sql
SELECT x IN (1,2,2,NULL) AS included, COUNT(*) AS n
FROM t GROUP BY x IN UNNEST([1,2,2,NULL]);

SELECT DISTINCT x NOT IN (1,2,2,NULL) AS included
FROM t ORDER BY x NOT IN UNNEST([1,2,2,NULL]) NULLS LAST;
```

The ordinary lowerer produces identical common membership operands, but
`same_expression` compared different Predicate names and list/array child shapes.
GROUP and DISTINCT had already removed the original input column, so attempting
to lower the unreused expression rejected a valid reference to the evaluated value.
The independently authored complete expected Programs passed the ordinary checker.
The two pre-repair regression tests failed (0/2), retained at
`_build/local-checks/attempts/run-GR5VXf` and
`_build/focused-evidence/focused-test-D4unV9`.

## Repair and boundaries

`query_membership_expression.mbt` identifies only the literal membership shapes
already accepted by `query_expression/lower.mbt`. `same_expression` compares
their common operation, needle and ordered atom trees using its existing scope
callbacks and value comparison. No expression is evaluated to establish reuse.

- IN and NOT IN are distinct. Atom order and duplicate count must match.
- Parentheses and ARRAY keyword spelling do not change the admitted literal list.
- Computed/annotated arrays, array parameters and signed scalar parameters do not
  obtain new literal-list equivalence. Shared numeric admission rejects invalid
  literals; it does not create an alternative numeric law.
- A changed output alias receiver cannot reuse a membership of the old input.
  Qualified input references continue to resolve to the input where visible.
- Common parameter/type checks remain authoritative. No execution Owner,
  fallback, inferred evidence or frontend evaluator was added.

An initial additional test incorrectly expected UnsupportedOrdering for
`SELECT DISTINCT x IN (1,2) AS x ... ORDER BY x IN UNNEST([1,2])`.
The actual correct boundary is a fresh ORDER expression over the Boolean output
alias x, rejected by the ordinary checker as
`TypeMismatch("membership element domain")`. Its complete expected Program and
exact cause are now asserted. The old failing diagnostic probe is retained at
`_build/local-checks/attempts/run-Py6DpX`; it is not evidence of a product defect.

## Independent public corpus

`scripts/fixtures/membership-expression-reuse-source-input.mjs` contains 14
positive cases and 10 pre-admission refusals, registered in both normal packed
acceptance and the focused `--membership-expression-reuse-only` selector.
The complete JSON controls are hand-authored without source compilation.

Positive cases cover both GROUP spelling directions, both DISTINCT ORDER
directions, Pipe, nullable parameters, duplicate rows, empty input, WHERE,
LIMIT/OFFSET, column contracts/order and receiver collisions. Alias and qualified
input membership deliberately sort IDs differently: `2,3,4,1,5` versus
`1,4,2,3,5`. NULL and duplicate atoms are preserved in the control Programs.
The ordinary acceptance harness checks Named Result rows and describe columns,
one Source acquisition session, same-Run resubmission, attach/re-read without
additional acquisition/admission, and no leaked internal columns.

Refusals cover changed operation/atom order/multiplicity, annotation, computed
atoms, a different needle, undeclared/missing/wrong-type parameters, and the
Boolean-alias/numeric-list mismatch. The harness checks typed rejection with no
Run admission or Source I/O.

The existing literal-array corpus's registration test assumed its selector was
first in both selection expressions. Main already has earlier selectors.
That test now checks membership and exact corpus registration without imposing
unrelated priority. Its existing 10 positive/7 refusal expectations are unchanged.

## Focused evidence and remaining verification

- JS: `node scripts/local-checks.mjs test moon -- --target js
  src/query_program/membership_expression_reuse_test.mbt
  src/query_program/in_unnest_literal_array_test.mbt
  src/query_program/grouped_in_atoms_test.mbt
  src/query_program/group_numeric_literal_test.mbt
  src/query_program/distinct_order_output_test.mbt
  src/query_program/join_order_test.mbt`: 22/22. Evidence:
  `_build/local-checks/attempts/run-kjSgPK`, focused `focused-test-txaRPM`.
- Node: `node scripts/local-checks.mjs test node --
  scripts/membership-expression-reuse-source-input.test.mjs
  scripts/in-unnest-literal-array-source.test.mjs
  scripts/compilation-manifests.test.mjs`: 11/11. Evidence:
  `_build/local-checks/attempts/run-j8pg3p`, focused `focused-test-Glvl8J`.
- Read-only `node scripts/compilation-manifests.mjs` is fresh. No grammar,
  normative rules or contract preimages changed, so no pins were rewritten.
- Changed MoonBit files were formatted and `git diff --check` passed.

These tests used the eventual source diff on a dirty baseline checkout. Packed
Local/HTTPS must use normal five-package production from its clean committed SHA;
its exact source, tarball digests, receipt and outcome will be recorded in the PR.
They had not yet run at the time of the first source commit. Full Core,
Wasm/native, performance campaigns and hosted required CI are not claimed here.


## Public refusal fixture correction

The normal clean `81a19f01f378edc2c377feb3fd4b754183c83177` five-package
campaign passed all 14 Local positive cases and the six explicit ordering
refusals (the parameter refusals also completed). It then stopped because the
last Boolean-alias/numeric-list case expected ClientProgramRejected instead of
ClientProgramInvalidInput. HTTPS was not reached. Failed evidence is retained at
`worktrees/.codex-scratch/public-query-evidence-WphN3O` (010 stderr/stdout and
summary), with bounded wrapper evidence `run-NNQW9T`. Temporary installations
were removed by the existing evidence cleanup; logs and tarball digests remain.

The correction follows the existing contracts rather than copying an observed
product value: the regression asserts the common membership element-domain
TypeMismatch, the checker classifies ordinary expression type errors as
InvalidInput, and `adapters/host-node/client-program-preparation.mjs` maps
check_invalid_input to ClientProgramInvalidInput. Only that refusal fixture and
its registration test change; no product classification is changed. A new clean
source SHA must be packed and the complete Local/HTTPS corpus rerun.
