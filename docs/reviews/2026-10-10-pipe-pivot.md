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
No packed success, submitted-HEAD CI, full Core or Wasm/Native execution is
claimed by this record. UNPIVOT PR #1230's separate common capacity handoff is
not an unmerged code dependency or a reason to stop this independent connection.
The wider frontend goal remains incomplete; no merge is performed.

## Integration review

Normal integration includes main's adopted UNPIVOT and its completed-scratch
lifetime fix. Both syntax forms, fresh scopes and authored registrations are
preserved. The combined independent inventory contains 3,287 cases (2,077
normal, 1,163 refusal and 47 execution failure occurrences). Complete parent
Run preimages are retained and validated by the independent oracle.

Integrated JS selection: 19/19 (`run-jFSfWP`). Node fixture/profile/identity
selection: 60/60 (`run-XDOPP1`). Read-only grammar manifests, document metadata
and 384 canonical identities passed (`run-em6B80`). Applied formatter output
only to changed files; unchanged main formatting findings are not hidden.
Fresh public packed acceptance is pending at this source revision. CI remains
stopped; these results do not establish full Core or all-target coverage.

The first integrated packed run at `fab19aa12` exposed an independently
incorrect fixture schema: text literal `kale` carries its existing four-byte
UTF-8 bound, unlike the explicitly unbounded machine control schema. The
fixture now records that literal-derived bound; neither product typing nor
the independent rows changed. Node fixture/inventory checks pass 38/38
(`run-vfFKQc`). The failed receipt remains at
`/private/tmp/.codex-scratch/public-query-evidence-K85XBw/summary.json`.

The next packed run at `63084e122` passed seven normal cases per transport;
its last original source used anonymous literal projections in two UNION
operands. The exact compiler diagnosis is `UnsupportedProjection`, before
PIVOT execution. This is the pre-existing anonymous-output-label profile gap
explicitly recorded in `docs/spec/query-text.md` (Source-free SELECT), not a
PIVOT or set continuation implementation defect.

The duplicate/NULL normal case now supplies explicit operand aliases while
keeping identical values, multiplicity, PIVOT and expected output. The exact
original input is retained as an additional implementation-limit refusal,
not discarded or called invalid SQL. Added a compiler regression checking
both the named continuation and the original typed gap. Its focused selection
passed 6/6 (`run-wvVEWU`); fixture/inventory Node checks passed 38/38. The public
selection is eight normal plus nine refusal cases. Anonymous label support
remains unimplemented and is not claimed as part of this PR.

The failed second receipt is retained at
`/private/tmp/.codex-scratch/public-query-evidence-ovg9Aj/summary.json`.
