# Strict BY NAME ON source connection

Base: `266dd5e0c74669c314b0f5adc2ef568daacaaa4d` (main). This unit does
not depend on the separate GROUP BY ALL or shorthand-frame branches.

## Contract and regression

The adopted [GoogleSQL set modifier](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#by_name_or_corresponding)
makes unprefixed `BY NAME ON` equivalent to `STRICT CORRESPONDING BY`.
The pinned `google/googlesql@d82db99a923a46571f543a13899dc791a7b6f743`
resolver (`GetColumnPropagationMode`, `CalculateFinalColumnNamesForCorrespondingBy`)
and `analyzer/testdata/pipe_set_operation.test` corroborate exact input/list
name sets, case-insensitive matching, and authored ON-list spelling/order.
The reference is evidence for the selected rules, not a new immutable contract
authority or a live BigQuery conformance test. Mode-prefixed subset/padding
semantics remain a distinct unimplemented surface.

```sql
DATA e = SELECT 1 AS x, 2 AS y
  UNION ALL BY NAME ON (y, x)
  SELECT 3 AS y, 4 AS x;
FROM e |> SELECT y, x
```

Expected rows are `{y:2,x:1}` and `{y:3,x:4}`, with columns `y,x`.
The independently authored complete Program in
`src/query_program/set_by_name_list_test.mbt` checks before the source case.
Before the fix, that Program passed the common checker and the source failed
in the parser: one executed test, zero passed (`run-yRGqxN`,
`focused-test-uM0tNq`). After connection it matched the authored Program and
passed the same checker (`run-k5367o`, one passed).

## Implementation

- Query syntax retains and snapshots the optional identifier list. SQL set
  chains require equivalent ordered modifiers and use the first list's display
  spelling; successive Pipe operators can reorder the current Relation.
- Root/CTE and logical DATA lowering share name/list validation. They project
  evaluated input fields to the explicit output order, then reuse existing
  append/intersect/except, duplicate handling and final ORDER/LIMIT machinery.
- The initial root left projection stays in its existing term Stage. DATA
  alignment adds only ordinary select steps. No source recapture, graph adapter,
  alternate owner, altered ceilings or D-owned predicate/assert/Effect changes.
- The common checker owns type/equality/nullability rules. Invalid lists retain
  the existing typed `UnsupportedSet` diagnostic and public implementation-limit
  projection; malformed syntax follows ordinary parser refusal.

## Evidence and remaining verification

Ten final focused JS tests passed at `run-74AJip` / `focused-test-GAvQ2D`, including
root/CTE/Pipe and DATA cases, existing DATA regressions, the changed Run
identity, explicit refusal reasons, list snapshots and common type rejection.
Targeted Node fixture/profile/manifest/import/independent-vector tests passed
33/33 at `run-WKWHYI` / `focused-test-vkx5L4`. Read-only manifest, metadata,
spec-family and canonical checks passed (380 identities). The earlier 31/33
Node attempt identified missing canonical regeneration and stale profile status;
both were corrected without changing the independent row expectations. This is source/lowering evidence, not public execution.
The packed fixture authors ten normal cases (including an independent JSON
control) and eight refusal cases. The normal corpus includes them, separately
from `--set-by-name-list-only`. Existing acceptance compares Named Result rows,
complete ordered contracts, NULL, duplicates, hidden-column absence, source
read counts, same-request reattachment and admission/I/O-free refusal.
Public Local/HTTPS execution, final exact-SHA required CI and content review
remain unverified at this checkpoint. No merge has been performed.

Grammar/pin changes use existing generators. The independent Values Run
preimage retains main's grammar/Run history and adds the new complete closure:
`sha256:e42554bffefec21c3d2ca451aba842fb7b353b1c2580477916c02a13a540b90c`
(grammar) and
`sha256:c7f33c1d74c88186b8354a28021c1146e4042115d7e17ae62f9edccf49ddffa4`
(Run). Values Unit/Result Plan and barrier contracts are unchanged. The Run
expectation is not replaced with a CID observed from product execution.

## Main integration and public-control correction

The ordinary merge adopts main `f080615fc4be0731a9f5fa4549c307ba0a2930e8`,
including the now-landed shorthand ROWS unit (#1005). Both narrow selectors
and normal public corpus registrations are retained. Grammar metadata and
canonical generated vectors were regenerated from the combined authored
source. Both parents' independent Values Run preimages are retained.

The first ordinary five-package run from
`e980b941de74f52d0494db1f11a5d54b324023b3` stopped at the independent JSON
control: its hand-authored filter used the nonexistent wire spelling `le`
instead of existing `lte`. Commit
`a25a9f7b24d48291532e5c81be8acd7adf301101` corrects only that operator spelling
and its source-fixture assertion; expected rows, types and order are unchanged.
The terminal evidence is `public-query-evidence-n3zvvE` / `run-440U21`.
That attempt did not execute the new source cases or the HTTPS cohort and
must not be presented as feature acceptance. The original tarballs, digests
and failure logs are retained separately from the integrated rerun.

The combined grammar manifest is `sha256:06af2bb4ef4b70809d026cce5a051ad442eba4484a4defd49a097aecdbc9b34e`; the independent complete
normative-preimage oracle yields Run `sha256:1341bd6588f20cde58f0b89676618dad7fff8e589ea245b622b3d7b1a409d9bb`. Values Unit, Result Plan and
barrier contracts remain unchanged. Exact-SHA public execution and mandatory
CI remain unverified at this pre-commit checkpoint.

The merged working tree passed the six selected MoonBit test files (14/14,
`run-btzscy` / `focused-test-6luCYI`) and seven selected Node test files
(35/35, `run-QqdHcq` / `focused-test-L1ggTi`). This includes the adopted
shorthand-ROWS parser/lowerer and both public-corpus registrations. Read-only
manifest, document metadata, spec-family and canonical freshness checks passed
(380 canonical identities). Authored changed MoonBit files match pinned
`moonfmt`; generated files match their generators. These pre-commit checks
are not exact-SHA packed or CI success. The integrated packed result is
recorded separately in PR #1009 after the ordinary merge commit is fixed.
