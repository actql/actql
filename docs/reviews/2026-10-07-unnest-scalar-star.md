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
- Three-target/full Core, full packed corpus, CLI/native and CI have not been
  run for this unit. Selected local success is not CI success.

## Resume and cleanup

Only B's expired formatter copies at
`/Users/t14i/workspace/20260822/worktrees/actql-frontend-googlesql-strings/_build/wasm-gc/release/format`
were deleted: 34,902,016 allocated bytes in 3,491 generated files. Clean tracked
sources, integrated commits, original tarballs, logs and borrowed dependencies
were retained. The exact receipt is
`review-artifacts/b-resume-2026-10-07/cleanup-old-string-format.json`.
No other worktree or shared cache was removed.

## Fresh packed Local/HTTPS evidence

Implementation and normal five-package producer SHA:
`d1b71482c0cbcfcfd2ca618bb88000ad0f715419`.
No prepack scripts were skipped, no adapter overlay was applied, and the shared
manifest's clean-build-input and tarball digest checks were retained.

```sh
node scripts/packed-client-packages.mjs /private/tmp/actql-b-unnest-star-d1b71482c-pack
ACTQL_PACKED_CLIENT_PACKAGES=/private/tmp/actql-b-unnest-star-d1b71482c-pack \
ACTQL_TEST_NPM_CACHE=/private/tmp/actql-graph-composition-probe-e90/npm-cache \
node scripts/test-packed-public-query.mjs --unnest-source-only
```

The private external installation passed thirteen successes (one independent
JSON control plus twelve source cases) and eight preparation refusals in each
Embedded Local and HTTPS mode. Named Result rows, exact ordered contracts,
nullability, column order, stream completion, absence of private fields,
same-request Run reuse and rereading without provider acquisition were checked
by the unchanged public harness. Refusals preserve zero Run admission/provider
I/O. The selected corpus uses no external Source or Model calls.

Original receipt and logs:
`/Users/t14i/workspace/20260822/worktrees/.codex-scratch/public-query-evidence-R9mX6z`.
Command `008` exited 0 with no signal, complete output, elapsed 185,928.513459 ms.
The receipt is `passed`, `complete:true`, `artifactsRemoved:true`, with no
`evidenceErrors`. Successful private installations were removed; receipts,
stdout/stderr and original producer tarballs remain. The receipt's `dirty:true`
is the pre-existing protected, untracked `review-artifacts/` directory; tracked
sources and build inputs were clean, as enforced by normal pack/reuse.

The enclosing producer also passed its ordinary eleven profile checks, README
Local/HTTPS and expected missing-generated-asset refusal. These are separate
checks, not additional UNNEST cases or a full packed campaign.

SHA-256 tarball digests:

| Package | Digest |
|---|---|
| client-wire | `d519367b6ba51f21953d396564ff7b9e08ad8030ac0df336a98719f84b83a84d` |
| sdk | `844ee1e2a1a1b4be8499630f9d75d144ecb61f94b9252c184361c7f5b7100e9b` |
| run-host-core | `b37ae34317c7e46d78626631f8f7d2d200e5385e8a198c14cabc255049c01bd5` |
| local-node | `20ee9320ab4dd940a88be1edad376bf4d9110d603e041dc0b3b713f6c7a5cc0a` |
| node | `89a340b9d0a80c4ade483e471c06a5503f81c347ced3a17f3c4e4d4a21b1eb64` |

The final evidence-record commit changes only this report. Its source, fixture,
adapter and machine-contract trees remain identical to the tested producer SHA.
The execution evidence retains its actual SHA rather than being relabeled as
execution at the documentation commit. Draft CI and review remain outstanding;
no manual CI run or merge was performed.
