# Pipe column edits with same-named range variables

Date: 2026-10-09. Status: localized Frontend repair with independent Program
fixtures and focused fresh packed Embedded Local/HTTPS acceptance. This unit
is not completion of the full public-text Frontend objective or full GoogleSQL
conformance.

## Selected meaning and counterexamples

The adopted GoogleSQL Pipe rules distinguish SET/DROP from RENAME. The pinned
reference is google/googlesql@d82db99a923a46571f543a13899dc791a7b6f743:

- `googlesql/analyzer/resolver_query.cc::FillItemStructFromNameListColumns`
  validates RENAME in both the current name list and name scope. A range name
  hides a same-named current column, so RENAME refuses that target.
- `ResolvePipeSet` resolves every sibling expression before applying the
  replacement name list. SET accepts a unique current target and removes a
  matching range name in favor of the replacement value.
- `ResolvePipeDrop` and `googlesql/analyzer/name_scope.cc::NameList::Copy`
  exclude both matching columns and range names. Other range snapshots survive.
- `googlesql/analyzer/testdata/pipe_set.test`, `pipe_drop.test` and
  `pipe_rename.test` contain the corresponding range/column collision cases.

This refines the adopted [GoogleSQL Pipe profile](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/pipe-syntax),
not a new ActQL execution operation or live Google-service differential result.
The previous unconditional range-retention prose in query-text is corrected;
no compatibility fallback preserves the old conflicting behavior.

For independently specified input x=7,y=9 and replacement object {x:99}:

```aql
FROM pair AS x |> SET x = @replacement |> SELECT x.x AS value
FROM pair AS x |> DROP x |> SELECT x.y
FROM pair AS x |> RENAME x AS current |> SELECT current
```

The first must derive the x member from the replacement parameter and publish
99. Previously it selected the old input x slot, which would publish 7. The
second must fail with Expression/UnknownReference, and the third with
AmbiguousColumn. Previously both were accepted. These initial observations
are compiler output/typed rejection evidence; they are not pre-fix Host runs.

The fixed MoonBit fixture independently authors complete ordinary Programs,
including declarations, schemas, values, derivations, projection and Named
Result. Their common checker acceptance is asserted. Quoted/case variants and
SET followed by RENAME are included. SET siblings still resolve their old
range before it disappears. Unrelated range names preserve their original
slots, including columns dropped from the current row.

## Repair and identities

`compile_steps` removes only matching ranges and value-table receivers after
all SET assignments have lowered, and after DROP target validation. RENAME
checks range/receiver shadowing before applying its current-column rename map.
Existing column lookup, property evaluation and typed diagnostics are reused.

No common checker/executor, Source acquisition, capacity ceiling, wire/schema,
registry, grammar, law or pin is changed. Actual generated Program structure
continues to determine its identity. D's CTE/assert/Effect/predicate functions
are unchanged. Document metadata generation reports no changes.

- Adopted main: 01cfdf03bf529f490a80ca521b727cee1e775fe3; parent #1138 is merged.
- Initial repair commit: 2d9ecc9b782897e18b1c7ad17873869c19c8f1e3.
- Normal integration: 47d988016bd8fa9b1861a75fc6efc0759eda50ff. It imports
  current main's existing Source diagnostic contracts and declarations without
  conflicts or independent declaration duplication.
- Final clean product/fixture SHA tested with normal five-package production:
  **79a3139a51b8945b5ca7341ab8b764f0b97b2efd**.

## Limited compiler and fixture evidence

Corrected pre-fix baseline: run-XJ2aph / focused-test-AfRkcb, **2/5 passed,
three failed**. The two controls already pass. The rejection loops stop at
first failure; later variants are not claimed as separately observed pre-fix.
An earlier scratch SET test used unsupported STRUCT constructor syntax and
failed during parsing (run-w6Dyyk). It was replaced with the already-supported
closed-object parameter contract before establishing the lowering defect.
No intended value or result expectation changed.

After repair: run-uGapPW / focused-test-WgAbeB, **32/32 passed**, including
new collision tests and SET target, RENAME, Pipe scope, JOIN ranges, property
and window-assignment callers. Additional quoted/post-SET cases plus direct
compiler callers: run-zNbGiC / focused-test-rU8HSr, **66/66 passed**. These
selections preceded the main merge; merged public execution is evidenced below.

Independent public fixture and machine-import checks: run-MhSmTL, **8/8**.
Final refusal-fixture checks: run-XGNJEy / focused-test-k2Udwp, **8/8**.
Document-validator unit fixtures: run-SLADgo / focused-test-OQxSLG, **12/12**;
these are validator tests, not direct validation of every changed document.
Actual read-only `node scripts/check-document-links.mjs` initially found an
inherited main review link using ../../spec instead of ../spec. The one link
in 2026-10-09-correlated-unnest-visible-star.md was corrected without changing
its original execution evidence. The final actual checker passes **1718 local
links / 362 JSON files**, with runtime_conformance:false retained.

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js \
  src/query_program/pipe_edit_range_collision_test.mbt \
  src/query_program/pipe_set_target_scope_test.mbt \
  src/query_program/pipe_rename_target_scope_test.mbt \
  src/query_program/pipe_scope_test.mbt src/query_program/pipe_join_ranges_test.mbt \
  src/query_program/pipe_range_property_test.mbt src/query_program/pipe_set_window_test.mbt
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js \
  src/query_program/pipe_edit_range_collision_test.mbt src/query_program/compile_test.mbt
node scripts/local-checks.mjs test node --timeout-seconds 120 -- \
  scripts/pipe-join-ranges.test.mjs scripts/spec-family-imports.test.mjs
```

## Fresh packed public acceptance

The existing shared-heavy bounded wrapper normally packs five packages at a
clean HEAD, verifies revision and each original tarball digest, then runs only
the existing Pipe range cohort. No overlay, manifest relabeling, producer
prepack bypass, execution budget increase or new test harness is used.

Initial integrated campaign run-SNc8Pt / public-query-evidence-QOPtff passed
28 positives and 20 refusals per transport at SHA 47d988016. Read-back found
unused declarations on four new refusal cases: those could cause a different
rejection if scope lowering regressed. They were removed and independently
asserted absent. This strengthens the rejection oracle; values/limits and
product code are unchanged.

Final campaign run-jKYwOV / **public-query-evidence-FdBGz2** uses clean SHA
79a3139a5. Embedded Local and HTTPS each pass **28 positives and 20 refusals**.
All previous 22 positives/15 refusals are retained. New cases include independent
JSON, replacement-object property access, quoted names, sibling pre-SET range,
RENAME after range removal, DROP with retained current columns, and empty typed
output. The public expected current value is 99, independent of original IDs
1/2; duplicates and nullable amount are preserved. Expected column order is
current,amount with non-NULL number and nullable number respectively.

Existing checks assert Named Result rows, schema/type/nullability/column order,
private-slot absence, one Source acquisition, and same-Run resend/attach/reread
without additional acquisition or execution. Refusals assert exact
ClientProgramInvalidInput and zero durable Run admission/Source I/O. Non-parameter
refusals contain no external parameter declarations or values. The final receipt
is independently inspected: exact clean revision, passed/complete, ten zero-exit
commands, complete streams, no error/signal/evidence errors and successful
artifact cleanup. README Local/HTTPS and deliberate missing-generated-asset
checks also pass. Logs and receipts remain under worktrees/.codex-scratch.

```sh
node scripts/packed-client-packages.mjs /private/tmp/actql-b-pipe-edit-79a3139a5-pack
ACTQL_PACKED_CLIENT_PACKAGES=/private/tmp/actql-b-pipe-edit-79a3139a5-pack \
ACTQL_TEST_NPM_CACHE=/private/tmp/actql-b-group-key-slot-collision-integrated-pack/npm-cache \
node scripts/test-packed-public-query.mjs --pipe-join-ranges-only
```

Original SHA-256 digests:

| Package | Digest |
|---|---|
| client-wire | ca7aaf03f3f1d78aff24c42a4ebe94ae2136ce29ba3fdf8ed81478e359e3df60 |
| sdk | 3d8c00b9b3ab8391838e90b8581973280e73a464eb785f5bf54cf6eeac8e711e |
| run-host-core | 358b9de7de99fa6c8f4496e9707a8b70a032be5b146b31df82517de1c97d503a |
| local-node | beefacc8d097708f85b56f885fbfaca3104ee7a2b463af1fff023c135eee4301 |
| node | a77756e97078c7df0ea0a318e5ccd74bd7aee2891caa148da2688f9c3eb2d9eb |

## Unverified scope

The evidence-recording commit does not modify product or fixture paths and is
not itself a new packed run. Full Core, Wasm/native execution, all packed
families, performance, complete retained-history validation and live Google
conformance remain unverified locally. Submitted-HEAD CI is separate and must
be read for its exact SHA; Draft preparation is not merge verification. The
full Frontend completion goal remains active.
