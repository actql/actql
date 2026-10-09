# Object member scope after INTERSECT and EXCEPT

Status: Frontend repair, selected compile/check regressions and fresh packed
Local/HTTPS acceptance complete at the recorded source. Submitted-HEAD required
CI remains unverified. This is a
separate unit from retained ARRAY/object star scope in #1077.

Adopted main: `4ab43f593453425fe4fb43214565af227ea3bef8`.

## Existing requirement and minimal counterexample

`docs/spec/query-text.md` requires ASCII case-insensitive field lookup, including
backtick names. Ordinary machine `property` retains the declared exact name.
The common set owner already defines complete typed-row comparison, schema
alignment and output nullability; this repair adds no set or object semantics.

```sql
WITH chosen AS (
  SELECT id, payload FROM objects
  INTERSECT DISTINCT
  SELECT id, payload FROM objects WHERE id <> 1
)
SELECT id, payload.SCORE AS score FROM chosen ORDER BY id
```

Independent input schema: nonnullable numeric `id`, nullable closed `payload`
with a nonnullable numeric `score`. Rows are:

```json
[{"id":2,"payload":{"score":10}},
 {"id":1,"payload":{"score":20}},
 {"id":3,"payload":null}]
```

The independently authored JSON Program compares `id,payload` before extracting
`property.name = "score"`. INTERSECT output must be
`[{"id":2,"score":10},{"id":3,"score":null}]`; EXCEPT output must be
`[{"id":1,"score":20}]`. Both have ordered `id,score` columns with nonnullable
number and nullable number contracts respectively.

Before repair, the independent INTERSECT/EXCEPT controls both passed ordinary
checking. CTE and DATA INTERSECT source probes failed at common checking with
`Pipeline.Operation.Expression.UnknownField("SCORE")`. Guard `run-8TeJWS`,
focused receipt `focused-test-p0R2u0`: 1/3 passed. Each failing test stopped at its
first INTERSECT iteration; this is not separate executed pre-repair EXCEPT
failure evidence.

## Cause and repair

`query_program/member_resolution.mbt::operation_schema` propagated common
schemas through append and ordinary Relation operations but returned no schema
for intersect/except. The subsequent property resolver consequently could not
bind authored `SCORE` to declared `score`.

The new branches resolve the existing right producer and call
`relation_set.check` with both actual schemas and the remaining probe budget.
They retain `relation_set.output_schema` and debit its reported work. Common
semantic refusals retain the allowance and stop probing; budget exhaustion
remains an expression WorkLimit. Final ordinary checking remains mandatory.

No name folding is applied to data, machine object keys or parameter values.
No row inference, key/presence/order proof, capacity change, planner/provider
modification, legacy fallback or additional execution owner is introduced.

## Independent public acceptance obligations

The existing computed-object-property public cohort now also includes:

- Independently authored JSON controls for INTERSECT and EXCEPT DISTINCT.
- CTE source and DATA source with quoted uppercase member names.
- Input duplicates, a NULL receiver, a non-NULL object with a NULL field, and
  empty typed input. DISTINCT must remove the duplicated complete id=2 row.
- Two missing-member refusals with `ClientProgramInvalidInput`, before Run
  admission and Source I/O.

Public inputs use the unchanged installed `records` Source and typed object
parameters through the existing DATA acquisition/capture path. Expected public
INTERSECT rows are id=2/score=10, id=3/score=NULL, id=4/score=NULL; EXCEPT returns
id=1/score=20. Declared column order and nullability are independently authored.
All positive cases require one acquisition session, exact Named Result rows and
Result.describe contracts, no internal columns, and no additional Run or Source
acquisition from rereading, attaching or resubmitting the same request.

The cases join the existing normal packed corpus as well as its existing
`--computed-object-property-only` selection. No compiled Program is patched.

## Selected local checks

Pinned Node 22.22.0 and MoonBit 0.10.12+1634b282e were used.

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 240 -- --target js \
  src/query_program/set_member_public_source_test.mbt \
  src/query_program/set_member_scope_test.mbt \
  src/query_program/set_member_budget_wbtest.mbt \
  src/query_program/member_probe_budget_wbtest.mbt \
  src/query_program/object_member_case_probe_test.mbt \
  src/relation_set/set_test.mbt
node scripts/local-checks.mjs test node --timeout-seconds 120 -- \
  scripts/computed-object-property-source-input.test.mjs
```

- Moon: **33/33**, `run-VYreAp` / `focused-test-H7bckC`.
- Node: **8/8**, `run-iNPYCE` / `focused-test-wnsvin`.
- The new probe regressions require actual common output nullability, exact
  work debit, refusal with no remaining allowance, and retained incompatible
  schema refusal. Existing member/refusal and common set bounds also pass.
- The exact four public CTE/DATA text inputs are compiled with authored
  declarations and values and ordinarily checked using a local Values input.

An intermediate local test tried the public JSON controls in that local-only
checker environment. It failed with `LocalConstructionFailure.Source`
(`run-niCqba`, 32/33), because that environment has no external Source
registration. It does not establish a product or packed failure. The independent
local JSON controls remain in the focused suite; external-Source controls remain
in the actual packed Host cohort. The source text and expectations were not
changed to accommodate this environment limitation.

Not run: full Core, Wasm/native execution, proof/performance campaigns or the
full packed corpus. Selected tests do not establish broad Frontend conformance.


## Clean-source packed Local/HTTPS evidence

Tested implementation and fixture source:
`a818bc6312e09c192bbf4a28ff1d09aa189ae995`. The following evidence update changes
only this review document. Do not attribute the packages to the later
submitted document-only revision.

```sh
node scripts/packed-client-packages.mjs /private/tmp/actql-b-set-member-a818bc631-pack
ACTQL_PACKED_CLIENT_PACKAGES=/private/tmp/actql-b-set-member-a818bc631-pack \
  ACTQL_TEST_NPM_CACHE=/private/tmp/actql-b-set-member-a818bc631-pack/npm-cache \
  node scripts/test-packed-public-query.mjs --computed-object-property-only
```

The producer, independent digest check and consumer ran once under the existing
shared heavy guard with a 1,200-second budget. Wrapper:
`/private/tmp/actql-b-set-member-a818bc631-packed-20261009.mjs`.
Guard `run-aP5MkJ` completed with exit 0 and complete output; its locks released.

Receipt:
`/Users/t14i/workspace/20260822/worktrees/.codex-scratch/public-query-evidence-hOqdmd`.
All ten consumer commands record the same clean source, exit/verification status
0, null signal/error and complete output. Evidence errors are empty. The
framework removed its own temporary installed artifacts after preserving logs
and the receipt. The source worktree, tarballs and manifest are retained.

Both Embedded Local and actual HTTPS passed the unchanged application with:

- **45 positive cases**, including all eight new set-member cases, exact Named
  Result rows/column contracts and no additional Run/Source acquisition from
  attach, read, resubmit or lookup.
- **18 preparation refusals**, including both new missing-member refusals with
  exact `ClientProgramInvalidInput` and no admission/Source I/O.
- **One existing demanded-expression execution failure**, separate from
  preparation refusal; the lazy-receiver positive remains valid.

There are 13 individually logged exact-code refusals and five original generic
refusals checked by the unchanged application loop. Do not describe the latter
as individually logged typed-code evidence. README Local/HTTPS acceptance and
the driver's 14 profile/selection probes also passed; no full packed campaign
is claimed.

An independent read-only audit checked every positive name and exact-code
refusal for both transports, command/source completion, actual tarball SHA-256
against both manifest and receipt, and removal of the temporary installation:
`/private/tmp/actql-b-set-member-a818bc631-acceptance-audit-20261009.{mjs,json}`.

| Package | SHA-256 |
|---|---|
| client-wire | `18762bb0bf434d939ff153d485e2aed28f0fa3c77c9d1e82eee4983765947905` |
| sdk | `c468fa4d31016b3d10539f1edc49a113241a52a67d34493ff165bfac30ed102c` |
| run-host-core | `332a770a589f74f697fca8427c364da9b89dfc23c3fea9a1bd7c59c5d0e0401d` |
| local-node | `5b9467f4d40753c574c214c789bef2ea48e6abd8300daaa014671e889b0d6f96` |
| node | `2989926be6f87295d48551e3c83e64dd6fb26f7b943e4004ad69176e19b98cda` |

No unmerged implementation dependency is required. This repair does not replace
#1077's distinct ARRAY/object star scope work. Full Core, Wasm/native execution,
proof/performance coverage and required submitted-HEAD CI remain separate.
