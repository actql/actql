# STRING_AGG delimiter literal chunks

Owner: B. Destination: main. Adopted main:
`90c4801a40d57bada514108586ac29f070add8ca`.
Implementation/package source: `de3ac848df35f5237ccf39f54124d1b278b81f06`.
No unmerged dependency. The default delimiter unit (#709) is integrated.

## Counterexample and existing contract

```sql
SELECT STRING_AGG(name, '' /* separator */ '|' ORDER BY payload.score NULLS LAST, id)
  AS names FROM objects
```

The aggregate parser consumed only the first Text token, then rejected the
remaining literal chunk as the expected ORDER clause. An independent complete
Program using the ordinary delimiter `"|"` already passes the common checker.
The pre-fix focused regression failed 0/1:
`_build/focused-evidence/focused-test-cBPvFO`.

The selected [pinned GoogleSQL lexical reference](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/docs/lexical.md#string_and_bytes_literals)
and [official literal-concatenation rules](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/lexical#literal_concatenation)
allow compatible STRING chunks separated by whitespace or comments, including
mixed quoting and per-chunk raw prefixes. This rule is already adopted in
`docs/spec/query-text.md` and the query grammar's `query_string` production.
It is not a new delimiter meaning or a live differential Google-service test.

## Minimal connection and independent expectations

`QueryParser::aggregate` sends an explicitly authored STRING delimiter through
the existing bounded expression parser and requires a StringLiteral root.
The ordinary parser owns decoding, chunk separation, source origins and work/
node accounting. The aggregate still receives one String, through the existing
lowerer, checker and execution owner. No new evaluator or string normalizer.

Keep the comma default, explicit empty delimiter, aggregate WHERE and ORDER,
parameter identity, byte limits and output schema unchanged. Computed delimiter
expressions and non-STRING delimiters remain outside the existing profile;
they are not accepted as literal chunks. The absence of a separator and an
invalid octal escape retain precise syntax/lexical reasons.

The complete independent `"|"` Program is compared against SQL and Pipe source;
the normal checker accepts both. Syntax expectations independently distinguish
backslash plus n from LF, escaped CR/CRLF from decoded line normalization, and
decomposed `e` plus combining acute from composed e-acute.

The existing ordinary packed aggregate corpus retains its 17 normal, seven
preparation-refusal and one deliberate execution-failure cases. Three added
normal cases cover mixed/comment-separated SQL, raw/decoded Pipe and decomposed
Unicode with aggregate WHERE. Three added refusals cover unseparated chunks,
`\\400` in a later chunk and a computed delimiter. No expected row or ceiling
was weakened. The ordered non-NULL contributions remain `b,b,a,c`:

- Comment-separated `"|"`: `b|b|a|c`.
- Raw `\\n` plus decoded CR: `b\\n\rb\\n\ra\\n\rc` (backslash/n/CR between values).
- Decomposed delimiter: `be\u0301be\u0301ae\u0301c`.

No grammar body, common contract, schema, identity domain or dependent pin
changes. Existing accepted inputs retain their Program meanings; newly
accepted text uses normal Program and request identity calculation. No legacy
Graph alias, fallback or teammate-owned repair is introduced.

## Focused checks

With pinned Node/MoonBit PATH and MOON_HOME:

```sh
node scripts/local-checks.mjs test moon -- --target js src/query_program/string_agg_literal_chunks_test.mbt src/query_program/string_agg_default_delimiter_test.mbt src/query_syntax/string_agg_delimiter_test.mbt
node scripts/local-checks.mjs test node -- scripts/aggregate-property-order-source-input.test.mjs
```

JS 7/7: `_build/focused-evidence/focused-test-hOYAUg`.
Node 6/6: `_build/focused-evidence/focused-test-drEH41`.
These ran on the implementation working tree before its commit; their receipts
record base `90c4801a...` with changes, not a pristine submitted-HEAD run.
Changed MoonBit formatting and `git diff --check` also passed. One local syntax
error during implementation is retained separately as `focused-test-IehzyR`;
it is not a product/runtime failure or a successful check.

## Public five-package acceptance

Normally prepacked manifest:
`/private/tmp/actql-b-string-agg-chunks-de3ac848d-pack/packed-client-packages.json`.
Its source revision is the complete implementation SHA above. Build inputs and
tracked source were clean; protected untracked review evidence remains outside
package build inputs. Later report-only changes are not relabeled as this
package source.

```sh
node scripts/packed-client-packages.mjs /private/tmp/actql-b-string-agg-chunks-de3ac848d-pack
ACTQL_TEST_NPM_CACHE=/private/tmp/actql-graph-composition-probe-e90/npm-cache npm_config_offline=true npm_config_include=optional ACTQL_PACKED_CLIENT_PACKAGES=/private/tmp/actql-b-string-agg-chunks-de3ac848d-pack node scripts/test-packed-public-query.mjs --aggregate-property-order-only
```

External Embedded Local and public HTTPS each passed 20 normal cases, ten
preparation refusals and one deliberate execution failure. The shared runner
checks independent JSON controls, exact Named Result rows, describe types/
nullability/column order, stream completion, no private sort columns, acquisition
once, same-request Run identity and no acquisition on reread/attach. Refusals
check zero Run admission/provider acquisition and absent request lookup;
the execution failure publishes no partial Result.

Receipt: `worktrees/.codex-scratch/public-query-evidence-5NSdBB`,
passed/complete, no evidence errors, artifactsRemoved true. Command 008 exited
0 in 173504 ms using the runner's unchanged acceptance budget. The runner also
passed its 11 profile checks and README/SDK-asset smoke checks.

The first installation attempt, `public-query-evidence-QIEHGN`, failed before
Host execution with npm ENOTCACHED: npm_config_cache is replaced by the runner's
private default. The retry used its supported ACTQL_TEST_NPM_CACHE setting with
the existing offline cache and the same verified tarballs, without repacking.
Both receipts/logs are retained and both temporary installations were removed.

| Package | SHA-256 |
|---|---|
| client-wire | `0212e9f37cde525589a0e8d48b62151e73ce53153ef75948974cb9f672659523` |
| sdk | `fe085d7d7e2cce344c2c4daf18f33ca477dcee9189e96552816cf9eee6b10972` |
| run-host-core | `c30ec73dbc24d074d9d887b0eaab3387b95d55cd4b5ac11879cfe5775f7542de` |
| local-node | `4ed8180a412fbf43c45e5b9ff5086ad3a9ed7f5c83350879b21219615117129d` |
| node | `89a340b9d0a80c4ade483e471c06a5503f81c347ced3a17f3c4e4d4a21b1eb64` |

Full Core, Wasm/Native execution, proof, broad packed, performance and Cloud were
not run. Local success is not CI success. Keep Draft pending content review and
required exact-HEAD verification; no manual CI rerun or merge.
