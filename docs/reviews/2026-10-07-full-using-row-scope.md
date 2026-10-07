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
five-package Embedded Local/HTTPS results are pending.
No full Core, all-target, proof, performance, manual CI run or merge was added.
Draft status is maintained; focused local success is not submitted-HEAD CI.
