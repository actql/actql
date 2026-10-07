# FULL USING: coalesced public row scope

Adopted main: `9d16de8c5101f5b343e048b4279267d495988fcf`.
Dependency: Draft [#728](https://github.com/actql/actql/pull/728),
`136977363c915795431d0db01fa6cb4e4556b695`. This child remains based on its
unmerged parent. Final integration is into main after the parent is adopted.

## Missing connection and minimal change

```aql
DATA base = FROM records |> ASSERT UNIQUE BY (id);
DATA lefts = FROM base |> WHERE id <= 2;
DATA rights = FROM base |> WHERE id >= 2;
SELECT * EXCEPT (amount), l.id AS lid, r.id AS rid
FROM lefts AS l FULL JOIN rights AS r USING (id) MAX_OUTPUT_ROWS 10
ORDER BY id;
```

The common FULL join, COALESCE, assertion and projection contracts already
express this operation. A complete independent JSON control passes the checker,
while the shared text lowering previously rejected FULL USING. The red test is
retained at `_build/focused-evidence/focused-test-thxZ9I` (0/1).

`join_requires_group_scope` selects the shared row scope for FULL USING.
`compile_join_chain_steps` keeps the two original qualified keys and derives
one new public key with existing COALESCE, left then right. Composite keys lead
the visible row in authored USING order. A later JOIN uses the merged current
key; `l.id` and `r.id` continue to refer to their original nullable slots.
The normal projection/alias-aware ORDER lowerer removes helper fields.

These are existing adopted rules, including FULL key coalescence in
`docs/spec/query-text.md`, and the selected
[GoogleSQL USING rules](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#using_clause).
The new derivation is an ordinary Program operation. No runtime, checker,
identity evidence, input acquisition, owner or fallback is added. The explicit
ceiling remains 10; conditional stable keys come from real assertions checked
by the common owner. Unkeyed FULL inputs retain the exact common missing-evidence
refusal. Neither sample data nor the merged column supplies an inferred key.

The parent report describes its historical FULL ON evidence and earlier USING
gap. This child supersedes only that gap. It does not assert that every FULL
chain or the existing standalone Values specialization is supported. The
common checker still controls legal compositions and stable identities.
Normative grammar/contract bodies and pins are unchanged.

## Independent expectations

`full_using_scope_test.mbt` contains a complete independently written expected
Program, checked before compiling the equivalent CTE text. Final comparison
includes predicates, assertions, join keys/ceiling, coalescence, sort, ordered
public fields and Result binding. The first post-fix comparison exposed a test
encoding omission: SORT explicitly names the current merged producer in the
generated Program. The expected control was amended to state that same producer,
without changing values, type, ordering or operation meaning. This diagnostic
is retained in `focused-test-UoRw7d` (6/7); it was not a runtime defect.

The public fixture contains another complete JSON control authored from the
common contracts. Expected ordered rows, on source IDs 3,1,2:

```json
[{"id":1,"lid":1,"rid":null},
 {"id":2,"lid":2,"rid":2},
 {"id":3,"lid":null,"rid":3}]
```

Public columns are `id,lid,rid` with the common nullable-number contracts.
The common COALESCE type remains conservative when both input slots are
nullable; the frontend does not strengthen its evidence.

Additional boundary obligations distinguish alias `-id AS id` ordering
(`-3,-2,-1`) from qualified `l.id` ordering (`-1,-2,-3`), preserve two unmatched
rows for a NULL composite key, retain authored composite column order, use the
merged key in a later INNER JOIN, exercise Pipe syntax and empty typed results.
They retain the unchanged public reader's schema/nullability/column-order,
hidden-column, stream-completion, single-acquisition and same-request/Result
reuse checks. No compiled Program is corrected by the test driver.

The old positive USING source has moved out of the parent's refusal obligation;
the refusal now specifies duplicate case-insensitive keys ``USING (id, `ID`)``.
Non-equality ON and a zero output ceiling retain their existing rejection
boundaries. Preparation refusals must preserve zero admissions and zero I/O.
The selected normal corpus contains eight new USING positives plus the parent's
five FULL ON positives, and three genuine preparation refusals per transport.

## Verification

```sh
node scripts/local-checks.mjs test moon -- --target js src/query_program/full_using_scope_test.mbt src/query_program/full_join_scope_test.mbt src/query_program/right_join_test.mbt
node scripts/local-checks.mjs test node -- scripts/full-join-scope-source-input.test.mjs scripts/right-join-source-input.test.mjs scripts/join-star-source-input.test.mjs
```

JS: 9/9, `_build/focused-evidence/focused-test-ir1x50`. The complete expected
Program, composite scope and later merged-key consumers pass the ordinary
checker. Node: 7/7, `_build/focused-evidence/focused-test-9IxgYR`. Fresh
five-package Embedded Local/HTTPS results passed as recorded below.
No full Core, all-target, proof, performance, manual CI run or merge was added.
Draft status is maintained; focused local success is not submitted-HEAD CI.


## Fresh packed acceptance

Implementation/package/acceptance revision:
`28c5003ca359cbb343f89e5974f6d23a90f5d211`.
The subsequent report-only commit does not change compiled inputs. The normal
five-package producer ran each prepack with clean tracked/untracked build inputs.
The public receipt's `dirty: true` reflects only protected untracked
`review-artifacts/`, not modified source or an adapter overlay.

```sh
node scripts/packed-client-packages.mjs /private/tmp/actql-b-full-using-28c5003ca-pack
ACTQL_TEST_NPM_CACHE=/private/tmp/actql-graph-composition-probe-e90/npm-cache npm_config_offline=true npm_config_include=optional ACTQL_PACKED_CLIENT_PACKAGES=/private/tmp/actql-b-full-using-28c5003ca-pack node scripts/test-packed-public-query.mjs --full-join-scope-only
```

Both Embedded Local and HTTPS passed all eight new USING positives and five
parent FULL ON positives through actual Named Result reading. Each transport
also passed three preparation refusals, with zero admissions and provider I/O.
The common reader verified independent rows, schema, nullability, declared
column order, no hidden columns, stream completion, one shared Source
acquisition and same-request/Result reuse. This includes the later JOIN's
right-only ID 3 and the two NULL-key unmatched rows; neither expected value nor
ceiling was weakened to obtain success.

Evidence:
`/Users/t14i/workspace/20260822/worktrees/.codex-scratch/public-query-evidence-8FxJU7`.
Command `008` exited 0 with no signal, complete output and elapsed time
89,666.3785 ms. Its receipt is complete, `artifactsRemoved: true`, with no
evidence errors. The runner removed only its owned private installation after
preserving evidence. Its existing 11 profile checks, README Local/HTTPS
quickstart and missing-generated-asset refusal passed separately.

Manifest SHA-256 digests:

| Package | SHA-256 |
|---|---|
| client-wire | `d519367b6ba51f21953d396564ff7b9e08ad8030ac0df336a98719f84b83a84d` |
| sdk | `844ee1e2a1a1b4be8499630f9d75d144ecb61f94b9252c184361c7f5b7100e9b` |
| run-host-core | `7baafd41632a352af0b3554c3d4ab674eddaf5e3a9470f19507f23721edc9777` |
| local-node | `ceafd3be9adde938899d0566ed02ec1919dd5861eed83dd8f4663aac8361013f` |
| node | `89a340b9d0a80c4ade483e471c06a5503f81c347ced3a17f3c4e4d4a21b1eb64` |

No full Core, Wasm/native execution, all-packed campaign, Cloud acceptance,
performance run, manual CI run or merge was performed. Submitted-HEAD CI is
recorded on the Draft PR separately; these local results are not CI success.

## Owned cleanup

After all producer/consumer processes completed, only the finished private npm
content caches (`npm-cache/_cacache`) under the FULL USING, parent FULL ON and
CEIL package directories were removed. Total allocated size: 12,521,472 bytes
(about 12 MiB). Original tarballs/manifests, npm logs, public receipts, failure
reproductions, current incremental build and borrowed dependency/toolchain
paths remain. Receipt:
`review-artifacts/b-resume-2026-10-07/cleanup-full-join-pack-caches.json`.
This is additional to the previously recorded 122 MiB old string build cleanup;
no other owner's files or shared cache were deleted.
