# Negated IS predicate expression reuse

Baseline: main `584b3a6144d4a8053ca4a541ef042a6e17c674e9`.
This independent Frontend unit repairs reuse of already supported expressions.
It does not depend on the separate literal-membership or concatenation PRs.

## Existing requirements and observed defect

`docs/spec/language.md`, common-expression-contract.canonical-nodes and
boolean-tests, specifies IS NOT TRUE/FALSE/UNKNOWN and IS NOT DISTINCT FROM
as common NOT around their corresponding tests. `query_expression/lower.mbt`
also lowers IS NOT NULL to NOT(IS NULL). Explicit unary NOT uses that same
common NOT node. No evaluation or new algebra is needed to connect the spellings.

The selected GoogleSQL operator reference is
`d82db99a923a46571f543a13899dc791a7b6f743`, `docs/operators.md`, IS operators
and IS DISTINCT FROM (lines 3020–3140). IS tests always return Boolean without
SQL NULL; IS UNKNOWN requires Boolean input. IS DISTINCT FROM is null-safe and
must not be replaced by ordinary equality/inequality.

Minimal counterexamples:

```sql
SELECT x IS NOT NULL AS value, COUNT(*) AS n
FROM t GROUP BY NOT (t.x IS NULL);

SELECT DISTINCT x IS NOT NULL AS value
FROM t ORDER BY NOT (t.x IS NULL);
```

Both were rejected on the baseline after GROUP/DISTINCT removed input x.
The source comparator matched different Predicate/Unary node kinds, despite
ordinary lowering producing the same common value. The complete independently
authored expected Programs passed the normal checker before source compilation.
The two initial regression tests failed (0/2), retained at
`_build/local-checks/attempts/run-PAyCd4` and
`_build/focused-evidence/focused-test-awzznD`.

## Repair and preserved distinctions

`query_negated_predicate_expression.mbt` recognizes only the exact common shape
shared by direct IS NOT and explicit NOT around the corresponding positive IS
predicate. `same_expression` then compares each original operand tree through
its existing scope callbacks. It does not evaluate an operand or reconstruct
its value. Reuse remains of an already evaluated slot.

- NULL, TRUE, FALSE, UNKNOWN and DISTINCT FROM are separate tests.
- NOT is retained, not removed or distributed; nested/double NOT is not folded.
- DISTINCT FROM is not ordinary equality. Different second operands do not match.
- Operand order, parameters and their declared contracts remain unchanged.
- Output aliases and qualified input references retain different receiver meanings.
  A fresh ORDER expression over an output alias is not replaced by the old input test.
- Common Boolean test typing is not weakened. Numeric IS TRUE input still receives
  an InvalidInput rejection, including when the two source spellings can reuse.

No public grammar, common contract, execution Owner, admission, numeric law,
order evidence, resource ceiling or pin preimage changes. BETWEEN/LIKE owner
dependencies are separate and were not added to this repair or implemented here.

## Independent acceptance

The complete MoonBit expected Programs cover both spelling directions for all
five IS predicates, GROUP, DISTINCT ORDER, nullable scalar parameters and the
fresh alias ORDER expression. Seven exact UnsupportedOrdering controls preserve
test kind, operand changes, different receivers, ordinary equality and extra NOT.

`scripts/fixtures/negated-predicate-reuse-source-input.mjs` contains 19 positives
and 8 pre-admission refusals in both normal packed acceptance and the focused
`--negated-predicate-reuse-only` selector. Common JSON controls are hand-authored.
Nullable amount rows distinguish TRUE/FALSE/UNKNOWN; the resulting IS values
have nonnullable Boolean contracts. The corpus also covers duplicates, WHERE,
empty input, LIMIT/OFFSET, nullable parameters and Pipe. Receiver collisions
deliberately sort IDs as `1,2,3,4,5` for the output alias versus `5,1,2,3,4` for
the qualified input. The rows and schemas are independent expectations.

The existing public harness compares Named Result rows and describe columns in
declaration order; exact rows exclude internal slots. It checks one acquisition
session and same-Run resubmission/attach/re-read without more Source I/O or
admission. Refusals preserve typed codes and unchanged admission/I/O counters.
No fixture modifies a compiled Program or supplies a replacement evaluator.

## Focused verification and limitations

Using pinned Node 22.22.0 and MoonBit 0.10.12+1634b282e:

```sh
node scripts/local-checks.mjs test moon -- --target js \
  src/query_program/negated_predicate_reuse_test.mbt \
  src/query_program/aggregate_membership_order_test.mbt \
  src/query_program/distinct_order_output_test.mbt \
  src/query_program/join_order_test.mbt \
  src/query_program/grouped_in_atoms_test.mbt
node scripts/local-checks.mjs test node -- \
  scripts/negated-predicate-reuse-source-input.test.mjs \
  scripts/compilation-manifests.test.mjs
node scripts/compilation-manifests.mjs
```

JS: 23/23 (`run-CCOPuK`, focused `focused-test-Cy3o8S`). Node: 9/9
(`run-pVG2C0`, focused `focused-test-cQCV5L`). Read-only manifests are fresh;
changed MoonBit files were formatted and `git diff --check` passed. These checks
used the final source diff before commit, not a clean published-SHA campaign.

Normal five-package production and focused packed Local/HTTPS must next use
the clean committed SHA. Its receipt, exact source and independent digest check
will be recorded in the PR. No packed success is claimed at this document's
initial commit. Full Core, Wasm/native, performance and hosted required CI have
not been run by this focused selection. Overall Frontend completion is not claimed.
