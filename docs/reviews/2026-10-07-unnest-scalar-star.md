# Scalar UNNEST star connection

Adopted main: `6a083adc55fdf91a3c3f105393ce4eb870b285d7`.
FULL USING #734 is already integrated; this unit has no unmerged parent.

## Missing boundary and repair

```sql
SELECT *
FROM UNNEST(@items) AS element WITH OFFSET AS position
ORDER BY position
```

For a bounded nullable number array parameter `[2,null,2]`, the independent
expected columns are nullable number `element` then nonnullable number
`position`; rows are `(2,0),(NULL,1),(2,2)`. NULL/empty arrays produce zero
rows with the same schema. The complete independent JSON Program already passes
the normal checker, but this text was refused by the value-table star guard.
The pre-repair selected test fails 0/1 at
`_build/focused-evidence/focused-test-25wTGZ` (`run-ShVGX9`).

The selected [GoogleSQL UNNEST rules](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#unnest_operator)
distinguish a scalar value column from STRUCT field expansion. The frontend
now reads the admitted parameter's existing element contract before allowing a
star. Parentheses do not change that contract. It uses the existing visible
physical element/index slots and ordinary star projection; no payload sampling,
new type system, execution owner, identity proof or array evaluator is added.
The array expression is still evaluated once by ordinary derive/unnest.

`compile_steps` receives the existing declarations from standalone compilation,
CTE bodies and DATA relation terms. The script connection is one optional argument
in `lower_script_relation_term`; CTE reference collection, acquisition predicates,
assertion, JOIN ceilings and Effect branches are unchanged. Object value-table
star expansion and other unclassified array expressions remain unsupported,
not silently interpreted as one object column. Explicit element aliases remain
required by the existing subset. This is not full ARRAY/STRUCT conformance.
Grammar, common contract bodies and pins are unchanged.

## Independent fixtures and verification

The complete existing JSON expectation is compared against explicit selections
and scalar-star SQL/Pipe, including parenthesized array parameters. Empty input
checks use declared boolean/string/object element types, with exact
`UnsupportedProjection` for the unimplemented object expansion and exact
`UnknownColumn` for a scalar receiver's qualified star. No expected Program is
produced from compiler output.

The public corpus contains one independent JSON control, twelve source successes
and eight preparation refusals. Five added source cases exercise SQL/Pipe stars,
empty/NULL arrays and a DATA binding. Existing duplicate/NULL, offset, current
scope and hidden-slot cases remain. The old scalar-star refusal becomes an
empty object-array refusal, so lack of rows cannot mask a wrong type decision.

A targeted existing registration test also exposed that current main omitted
this corpus from the packed driver and default acceptance. It failed 2/3 at
`focused-test-qhyQHs` (`run-Q9xrKO`). Restore fixture copying, the existing
`--unnest-source-only` selection and normal-corpus registration together. The
narrow mode exits after its own acceptance and does not launch unrelated suites.

Pinned MoonBit `0.10.12+1634b282e`, Node `22.23.2`:

```sh
node scripts/local-checks.mjs test moon -- --target js \
  src/query_program/unnest_source_test.mbt \
  src/query_program/source_free_test.mbt \
  src/query_program/data_script_test.mbt
node scripts/local-checks.mjs test node -- \
  scripts/unnest-source-input.test.mjs scripts/public-query-profiles.test.mjs
```

- Selected JS: 11/11, `focused-test-zBwZtl`, `run-bdYYG2`.
- Selected Node: 10/10, `focused-test-QHjJvb`, `run-eoB3ny`.
- An intermediate test used a forbidden JSON parameter declaration and expected
  a projection issue instead of the existing qualified-star column issue.
  Those test mistakes are retained in `focused-test-E6OHxj` (9/11). They did not
  justify changing common parameter admission or refusal rules.
- Changed MoonBit files were formatted; `git diff --check` passed.
- Packed Local/HTTPS acceptance is the remaining verification step at this
  commit. Three-target/full Core, full packed corpus, CLI/native and CI have not
  been run for this unit. Selected local success is not CI success.

## Resume and cleanup

Only B's expired formatter copies at
`/Users/t14i/workspace/20260822/worktrees/actql-frontend-googlesql-strings/_build/wasm-gc/release/format`
were deleted: 34,902,016 allocated bytes in 3,491 generated files. Clean tracked
sources, integrated commits, original tarballs, logs and borrowed dependencies
were retained. The exact receipt is
`review-artifacts/b-resume-2026-10-07/cleanup-old-string-format.json`.
No other worktree or shared cache was removed.
