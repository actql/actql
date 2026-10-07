# FULL JOIN: shared row scope

Base: `2d4dc269cdc8d35fe6af2bb1facc91e9f019685f`.
Status: focused lowering/checker tests and packed Embedded Local/HTTPS pass at
the implementation revision below. Review and exact submitted-HEAD CI are pending.

## Counterexample and connection

```aql
DATA base = FROM records |> ASSERT UNIQUE BY (id);
DATA lefts = FROM base |> WHERE id <= 2;
DATA rights = FROM base |> WHERE id >= 2;
SELECT l.*, r.id AS rid
FROM lefts AS l FULL JOIN rights AS r
  ON l.id = r.id MAX_OUTPUT_ROWS 10
ORDER BY id NULLS LAST, rid NULLS LAST;
```

The shared JOIN scope rejected every FULL join before calling the normal
projection/ORDER lowerer. An independently authored FULL Program with explicit
key assertions passes the ordinary checker; the equivalent text reached that
frontend refusal. The assertion is a real conditional key obligation, not an
assumption based on an `id` column name or sample rows.

`compile_join_chain_steps` now emits the existing `kind: "full"` operation for
ON joins. The common checker still selects stable row identities for both
operands. An unkeyed Values control remains rejected with
`Closure(Joins(MissingEvidence(...)))`. No key, cardinality, order proof,
provider, task strategy or alternative execution owner is introduced.

The existing visible/qualified column scope and alias-aware expression lowerer
handle the projected row. The common JOIN retains unmatched rows and assigns
nullable contracts. Private physical fields are removed by ordinary projection
before publication. The authored output ceiling remains 10.

FULL USING in this shared scope remains explicitly unsupported: its unqualified
key needs coalescence. Existing keyed single-CTE FULL projection handling is
unchanged. This unit does not claim unrestricted FULL composition or remove the
existing standalone Values specialization's refusal. Existing non-equality ON,
ambiguous names and invalid bounds keep their existing refusal boundaries.

## Independent expectations

`scripts/fixtures/full-join-scope-source-input.mjs` contains a complete JSON
control written using the existing acquisition/assert/filter/FULL/sort/Result
contracts. It is not compiler output and is never patched after lowering.
Source rows are `(id,amount) = (3,30),(1,NULL),(2,20)`. Expected ordered output:

```json
[{"amount":null,"id":1,"rid":null},
 {"amount":20,"id":2,"rid":2},
 {"amount":null,"id":null,"rid":3}]
```

The declared column order is `amount,id,rid`, all nullable numbers. The corpus
also covers Pipe syntax, NULL match keys and an empty typed result. It contains
five positive obligations and three preparation refusals per transport, and
is registered in the normal packed corpus as well as a focused selector.
The existing public driver checks schema, rows, stream completion, hidden-field
absence, one Source acquisition and same-request/Result reuse. This registration
does not establish execution success until that driver actually passes.

## Executed checks

Using the repository's pinned toolchain and bounded/nonzero-test wrappers:

```sh
node scripts/local-checks.mjs test moon -- --target js src/query_program/full_join_scope_test.mbt src/query_program/single_join_group_test.mbt src/query_program/join_star_test.mbt
node scripts/local-checks.mjs test node -- scripts/full-join-scope-source-input.test.mjs scripts/right-join-source-input.test.mjs scripts/join-star-source-input.test.mjs
```

- JS: 10/10, `_build/focused-evidence/focused-test-g6swdA`.
- Node: 6/6, `_build/focused-evidence/focused-test-8pcvSF`.
- Correctly keyed pre-fix text failed in
  `_build/focused-evidence/focused-test-AvHedZ`; the same focused case passed
  after the connection in `focused-test-i1jEEA`.
- The initial unkeyed JSON diagnostic failed common closure in
  `focused-test-O4gPuK`. It is not a frontend defect or execution evidence.
- A diagnostic-test formatting mistake is retained in `focused-test-RApARX`;
  a parser-level zero-bound refusal was corrected in the test selection after
  `focused-test-lWkTK5`. Neither required relaxing product validation.

No full Core, Wasm/native campaign, performance suite, manual CI run or merge
was performed. Packed Local/HTTPS is recorded separately below; exact submitted-HEAD CI remains pending.
The FULL shared-row connection has no dependency on the CEIL/floor execution
gap recorded by Draft #722.

## Packed evidence

Implementation/package/acceptance revision:
`2e2d11657ceac02a46d380eb3d108c31cee97c6a`.
The subsequent evidence-only commit changes this report, not compiled inputs.
The normal producer ran `prepack` for all five packages with clean tracked
build inputs. The command receipt reports `dirty: true` solely because retained
untracked `review-artifacts/` exists; no untracked build inputs were included.

```sh
node scripts/packed-client-packages.mjs /private/tmp/actql-b-full-join-2e2d11657-pack
ACTQL_TEST_NPM_CACHE=/private/tmp/actql-graph-composition-probe-e90/npm-cache npm_config_offline=true npm_config_include=optional ACTQL_PACKED_CLIENT_PACKAGES=/private/tmp/actql-b-full-join-2e2d11657-pack node scripts/test-packed-public-query.mjs --full-join-scope-only
```

The external installation passed five positive cases and three preparation
refusals **on each** of Embedded Local and HTTPS, through actual Named Result
reading and stream completion. This includes the independent JSON control,
SQL projection, Pipe projection, NULL join keys and empty typed rows. Schema,
nullable fields, declared column order, hidden-field absence, one Source
acquisition and same-request/Result reuse are checked by the unchanged driver.
Preparation refusals preserve zero Run admissions and zero provider I/O.

Evidence:
`/Users/t14i/workspace/20260822/worktrees/.codex-scratch/public-query-evidence-p9ADzL`.
Command `008` completed with exit 0, no signal, complete output and elapsed time
30,509.862 ms. The wrapper also passed its existing 11 profile tests, README
Local/HTTPS quickstart and missing-generated-asset refusal. Those are separate
from the five FULL cases per transport. The runner removed its owned private
installation after saving evidence (`artifactsRemoved: true`, no evidence
errors); logs, manifest and original tarballs remain.

Manifest SHA-256 digests:

| Package | SHA-256 |
|---|---|
| client-wire | `d519367b6ba51f21953d396564ff7b9e08ad8030ac0df336a98719f84b83a84d` |
| sdk | `12fe75e3860d112bc314c1ebb8586fbdc37efad05b8a472dfe68c4e5cc7389d2` |
| run-host-core | `7baafd41632a352af0b3554c3d4ab674eddaf5e3a9470f19507f23721edc9777` |
| local-node | `5556f7a9d5fb734bf079c5f3ee75d72c5b480bd1623ef431805a8599e4f6c8de` |
| node | `89a340b9d0a80c4ade483e471c06a5503f81c347ced3a17f3c4e4d4a21b1eb64` |

No all-packed campaign, full Core, Wasm/native execution, Cloud acceptance or
manual CI was added. This is the selected FULL ON shared-row unit, not a claim
that all SQL FULL JOIN forms are implemented. The source grammar, common
contract bodies and their pins did not change; no old Run was reinterpreted.
