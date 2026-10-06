# Standalone UNNEST source connection

Date: 2026-10-06. Base: `1e611bdaffd775d569772f09c148e667351d7f53`.
This connects an existing common operation; it does not establish full
GoogleSQL ARRAY/STRUCT or value-table conformance.

## Missing boundary and selected contract

The common JSON `unnest` accepts a typed array column, preserves duplicate and
NULL elements and can produce the zero-based position. The public parser did
not accept the equivalent standalone `FROM UNNEST(@items)` SQL or Pipe source.
The independently authored complete Program in
`src/query_program/unnest_source_test.mbt` was accepted by the normal checker
before the source parser failed on the base revision. The pre-repair selected
check failed 0/1 (`run-J00zim`, `focused-test-aBI66T`).

The selected [GoogleSQL UNNEST reference](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#unnest_operator)
requires zero rows for NULL/empty arrays and keeps NULL elements. Explicit
ORDER BY on WITH OFFSET requests element order; the frontend does not create
an implicit sorting or Named Result declaration. OFFSET is absent from the
[GoogleSQL reserved-keyword list](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/lexical#reserved_keywords),
so the default `offset` column can be referenced without backticks.

```aql
SELECT element, position
FROM UNNEST(@items) AS element WITH OFFSET AS position
ORDER BY position
```

The equivalent FROM-headed Pipe uses the same parsed source operation. An
ordinary generated single-row Values input evaluates the array expression once;
ordinary `unnest` then expands it. Private slots avoid authored alias collisions.
Only the element and optional position enter the visible scope. Current Pipe
AS/projection rules apply afterwards; neither the private witness nor a removed
range alias becomes accessible. Typing, parameter bounds, NULL handling and
execution stay with the existing checker/planner/Host and relation kernel.

This unit requires an explicit element alias and does not connect direct
value-table star expansion, array constructor literals, implicit paths or
correlated JOIN UNNEST. These remain coverage gaps, not new permanent language
restrictions. In particular, direct star is rejected rather than flattening an
object incorrectly or exposing private fields. The JSON control and text
fixtures use explicit scalar selection and declared bounded array parameters.

## Identity and fixtures

The EBNF and query rules change the grammar manifest to
`sha256:fa861e86e6e0859bd5a77f5c070b79a1dfe3c7211477bba7a7bba1da8c283530`.
The existing independent fixed Values Program then has Run CID
`sha256:b11522eb94f1e774a9deaf27c104e3b34ab17081491fe8d218c6a02cecb4e3e2`.
Both follow independently assembled canonical preimages, not compiler output.
The previous complete grammar body and its Values Run vector remain tested
under their original identities. The Program's value meaning is unchanged;
its admitted grammar dependency changes the containing Run identity.
Generated metadata and canonical vectors come from their existing generators.

`scripts/fixtures/unnest-source-input.mjs` independently defines one JSON
control and seven source successes plus seven preparation refusals. It tests
NULL/empty arrays, nullable elements, duplicates, explicit descending offset,
WHERE/current scope and private-slot name collisions. Ordinary packed corpus
registration is retained; `--unnest-source-only` selects this same corpus.
The existing public harness checks Named Result values, ordered schema and
nullable contracts (including empty Results), same-Run resubmission and no
source/provider acquisition. Refusals must leave Run admission and provider
I/O unchanged. It never patches a lowered Program.

## Verification so far

Pinned MoonBit `0.10.12+1634b282e`, Node `22.23.2`:

```sh
node scripts/local-checks.mjs test moon -- --target js \
  src/query_syntax/unnest_source_test.mbt \
  src/query_program/unnest_source_test.mbt \
  src/query_program/source_free_test.mbt \
  src/query_syntax/limit_parameter_test.mbt \
  src/run_publication_host/client_values_run_materials_wbtest.mbt
node scripts/local-checks.mjs test node -- \
  scripts/unnest-source-input.test.mjs \
  scripts/sga-query-call-contract.test.mjs \
  scripts/client-values-run-materials-vector.test.mjs
node scripts/compilation-manifests.mjs
node scripts/update-document-metadata.mjs
node scripts/check-canonical-json.mjs
node scripts/check-actql-spec-family.mjs
```

- Selected JS: 12/12, `run-rDEwK4`, `focused-test-v7Lfbf`.
- Selected Node: 5/5, `run-0FkMs8`, `focused-test-1FV9Dz`.
- Compilation, document metadata and canonical JSON freshness passed.
- `moon info src/query_syntax` regenerated the public interface; changed
  MoonBit files were formatted.
- A prior existing-build JSON preparation probe accepted the independent
  expansion through normal checking and Values Plan issuance. It used a
  previously built bridge, not a clean rebuild or public runtime execution;
  it is diagnostic evidence only.

Fresh packed Local/HTTPS acceptance remains to be run on a clean committed
revision. Full Core, Wasm/native, proof, performance and complete packed
campaigns were not run locally. CI and content review are separate requirements;
no merge is performed by B.
