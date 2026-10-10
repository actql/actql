# Pipe PIVOT connection

## Baseline and independent failure

This independent branch starts from main
`0d547e3ec8b6b3dd7d5d5980d048731adccda0f9`. The selected GoogleSQL
reference is `d82db99a923a46571f543a13899dc791a7b6f743`, specifically
`docs/pipe-syntax.md` PIVOT and `docs/query-syntax.md` PIVOT grouping,
arguments, output aliases and column order. This is a selected-profile
connection, not full GoogleSQL conformance.

The existing common `pivot` Program already supports explicit index columns,
a String axis, static buckets and the five ordinary aggregates selected here.
The pre-fix test (`run-1ICdB9` / `focused-test-74NfE7`) passed the independent
closed machine control through the normal checker and failed parsing:

```aql
FROM orders
|> PIVOT(COUNT(amount) FOR status IN ('open' AS opened, 'closed'))
```

The control is authored in `src/query_program/pipe_pivot_test.mbt`. Its whole
Program includes the ordinary Values input, COUNT argument, implicit index
`[id,customer_id]`, raw compared bucket values, alias projection and authored
output field order `[id,customer_id,opened,closed]`. It is not a product-output
snapshot or a hand-edited post-lowering workaround.

## Implementation and boundaries

`query_syntax/pivot.mbt` retains one aggregate column, axis path, prefix and
ordered literal/alias pairs. Existing identifier, lexical and expression owners
decode names and String chunks. `query_program/pipe_pivot.mbt` resolves both
column paths using the current Pipe/range resolver and lowers to common pivot.
Only current columns not consumed by the argument or axis become implicit keys.
SET/RENAME use their already evaluated slots; old input values are not restored.

`compile_steps` installs the fresh Relation scope and the ordinary final
projection exposes implicit keys followed by the authored IN columns. Common
canonical generated-column order does not change public order. Output alias
and aggregate prefix affect projection names only; they do not rewrite bucket
values. The ordinary JOIN-input classifier recognizes the fresh scope. No
checker, evaluator, Result/order owner, provider, resource ceiling or persistence
format was introduced. D's CTE/assert/Effect paths were not changed.

Unimplemented surface coverage remains explicit: FROM-suffix PIVOT, multiple
aggregates, aggregate expressions/modifiers, COUNT(*), non-String axes and NULL
bucket constants. The existing common contract also requires bucket values
to be admitted field names, unique and disjoint from physical index names.
These are recorded gaps, not claims that the selected standard forbids them.
No implicit stringification, DISTINCT, fill, cast or resource relaxation is used.

## Identities and focused evidence

The new grammar/rules change the grammar-bound Run closure. Existing generators
update manifests, normative references and canonical identity tests. Program,
Values Unit, Result Plan, barrier and common pivot semantics are unchanged.
`scripts/fixtures/pre-pipe-pivot-grammar.json` preserves the complete preceding
grammar and independently reconstructed Run preimages. The current Run vector
comes from the independent authored preimage function, not a runtime-returned
CID. Old persisted Runs are not rebound to the new grammar.

Focused pinned Node/MoonBit checks:

- Parser/lowerer plus affected Pipe scope/JOIN callers: 15/15,
  `run-1QCn7i` / `focused-test-R0nPCZ`. An earlier new-test failure used reserved
  CURRENT as a bare range alias; the test now uses the valid name `reshaped`,
  with its complete expected Program unchanged.
- Parser/lowerer and consuming grammar-bound Values Run tests: 9/9,
  `run-YDL8IC` / `focused-test-SsPcpf`.
- Public fixture/registration/profile and independent identity/manifest Node
  selection: 62/62, `run-C7cQAv` / `focused-test-n084DF`. The first selection
  exposed a second stale current-Run assertion and the profile's old
  not-implemented marker. The current assertion now uses the independently
  reconstructed CID; the profile records partial implementation and retains
  empty execution evidence, without changing frozen imported requirements.
- Read-only compilation manifests, document metadata, spec-family and all
  384 canonical identities: clean.

Commands:

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js src/query_syntax/pivot_test.mbt src/query_program/pipe_pivot_test.mbt src/query_program/pipe_scope_test.mbt src/query_syntax/pipe_join_input_test.mbt
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js src/query_syntax/pivot_test.mbt src/query_program/pipe_pivot_test.mbt src/run_publication_host/client_values_run_materials_wbtest.mbt
node scripts/local-checks.mjs test node --timeout-seconds 180 -- scripts/pipe-pivot-source-input.test.mjs scripts/public-query-profiles.test.mjs scripts/client-values-run-materials-vector.test.mjs scripts/compilation-manifests.test.mjs scripts/frontend-profile.test.mjs
```

## Public acceptance obligations

`scripts/fixtures/pipe-pivot-source-input.mjs` contains eight normal cases and
eight preparation refusals. Independently authored rows/schema distinguish
duplicate non-NULL count, empty bucket zero versus typed NULL, missing buckets,
implicit grouping, SET's changed value, prefix/range names, column order and
global versus keyed empty input. These same cases are registered in the normal
packed corpus and `--pipe-pivot-only`; narrow execution is not their only gate.
The data-only authored inventory now enumerates 3,274 cases. Registration is
not execution evidence.

Normal clean-HEAD five-package production, digest verification and public
Embedded Local/authenticated HTTPS source-to-Named-Result execution are still
required. The ordinary runner checks Result.describe/rows type and field order,
repeat requests and rereads, and zero Run/provider I/O for preparation refusals.
No complete packed success, submitted-HEAD CI, full Core or Wasm/Native execution
is claimed by this record. UNPIVOT PR #1230 is now integrated in main; its
previous capacity refusal is historical evidence, not a current dependency wait.
The wider frontend goal remains incomplete; no merge is performed.

## Current-main integration and schema counterexample

Normally merged main `b890a2f259e8ea4fe806ac7f46a9e4a5d8a51ca4`, including
UNPIVOT and its completed-child scratch reclamation. Both Pipe operators,
their ordinary/scoped acceptance registrations and historical independent Run
vectors are retained. Grammar/metadata/canonical outputs were regenerated from
the integrated sources. The new grammar CID is
`sha256:b381518ea64d0adca1f11e3577c7e8fe066539fd6afefa1c44339a436cd1ebd2`.
The independently reconstructed current Values Run CID is
`sha256:0e78ef6f3c7f4932c00b61d4945432738a8dc32350ca3244405c4927c71ad0aa`.
`submitted-pipe-pivot-grammar.json` and
`pre-integrated-pipe-pivot-grammar.json` preserve both parents' complete
grammar and independently checked Run preimages; old Runs are not reinterpreted.

The first normal five-package acceptance used clean submitted SHA
`13ab7fb028a7c88a037a1ea51c62ef2261f9bac2`. Its producer and independent digest
verification succeeded (`run-Q9K5ei`). Both Embedded Local and HTTPS passed
the independent duplicate/NULL JSON control, then stopped at the first source
case's complete `Result.describe()` contract comparison. Evidence remains in
`worktrees/.codex-scratch/public-query-evidence-r0M9oO` (`010.stdout.log`,
`010.stderr.log`, `summary.json`). This is an incomplete failed campaign;
remaining normal and refusal cases did not execute.

The source fixture omitted the checked String extent, not a row/type/order
failure. `language.md` Value contracts defines admitted checked String bounds.
`expression_typing/signatures.mbt` derives a literal's UTF-8 byte length;
`relation_typing/pivot.mbt` retains index-column contracts. Thus `'kale'` has
`max_utf8_bytes: 4`, including on typed empty input and its identical UNION ALL
operands. The five affected source expectations now include that bound. The
authored JSON Values control intentionally remains unbounded: its explicit
author schema supplies no String extent. Row expectations, column order,
nullability, limits and all cases remain unchanged. The data-only registration
inventory is recomputed from authored fixtures, not runtime results.

Integration checks: focused JS parser/lowerer/scope/JOIN-input and consuming
Run identity tests passed 27/27 (`run-bNjkUB`, `focused-test-Nklf0k`). Targeted
Node fixture/profile/manifest and historical vector checks passed 66/66
(`run-cNuY9u`, `focused-test-UIIPBn`). Generators completed with 384 canonical
identities (`run-DPeFc5`). Changed MoonBit formatting was checked with the pinned
formatter; no unrelated source formatting is included. Fresh fixed-SHA public
execution is still required after this integration and fixture correction.
The query API generator and read-only compilation manifest, document metadata,
spec-family and 384 canonical identity checks passed (`run-PHcANn`).
