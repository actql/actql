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
- Compilation, document metadata, canonical JSON and spec-family freshness
  passed; spec-family reports `conformance:false`, not overall conformance.
- `moon info src/query_syntax` regenerated the public interface; changed
  MoonBit files were formatted.
- A prior existing-build JSON preparation probe accepted the independent
  expansion through normal checking and Values Plan issuance. It used a
  previously built bridge, not a clean rebuild or public runtime execution;
  it is diagnostic evidence only.

## Fresh packed public acceptance

Runtime/fixture revision: `fd6aa6885349cf427548db596a4a048f6c67b2ac`.
All compiled inputs were committed before ordinary `prepack`; no adapter
overlay, modified manifest, extra runtime owner or lowered-Program patch was
used. Untracked review evidence is retained separately from compiled inputs.

```sh
node scripts/packed-client-packages.mjs /private/tmp/actql-b-unnest-source-pack-IX9rKk
ACTQL_PACKED_CLIENT_PACKAGES=/private/tmp/actql-b-unnest-source-pack-IX9rKk \
  node scripts/test-packed-public-query.mjs --unnest-source-only
```

The commands ran sequentially under the shared heavy guard, `run-AWkkVx`.
External Embedded Local and HTTPS each completed 8 successes (7 source cases
and one independent JSON control) and 7 preparation refusals. The existing
harness compared Named Result rows and describe columns/nullable contracts,
checked attach and same-request resubmission, and observed no Source I/O.
Preparation refusals left accepted Run and provider I/O counters unchanged.
No test ceiling or expected row/schema was relaxed. The ordinary README
quickstart and packed consumer's prerequisite profile checks also passed.

Evidence: `worktrees/.codex-scratch/public-query-evidence-3KM7N1/summary.json`,
`008.result.json`, `008.stdout.log` and `008.stderr.log`. The receipt reports
`status:passed`, `complete:true`; the consumer-owned temporary installation was
removed after evidence capture. The retained manifest fixes these tarball
SHA-256 digests:

| Package | SHA-256 |
|---|---|
| client-wire | `68e1aa6b3539f5833630693a5a10e084f61a2ab7f4e2e4f978722a33ce6e9e90` |
| sdk | `490c059f055124c8f32771f214d6bbb1b0b4bf8dd71a6e58f63eb985401e6359` |
| run-host-core | `6e51ac81bd4158b9d68000c5296a600bb014af224bf8d6a9c013ff8ab522e09d` |
| local-node | `fced038f6eb5091e24946021c87f3f70507a0abad6abc484f6c1bd6528e14320` |
| node | `89a340b9d0a80c4ade483e471c06a5503f81c347ced3a17f3c4e4d4a21b1eb64` |

Any subsequent report-only commit does not relabel this tested revision as a
new-SHA execution. Full Core, Wasm/native, proof, performance and complete
packed campaigns were not run locally. Direct star, array constructor literal,
implicit/correlated expansion and complete ARRAY/STRUCT semantics remain open.
CI and content review are separate requirements; no merge is performed by B.
