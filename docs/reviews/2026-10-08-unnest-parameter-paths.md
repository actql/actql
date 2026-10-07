# Declared parameter paths into UNNEST value tables

Base: main `c6a1a8e7ab3726cccbf1fddc897bde15a5927e5a`.
Branch: `feat/frontend-unnest-parameter-paths`. No unmerged parent dependency;
this is independent of correlated expansion and its common-capacity failure.

Integration adopts main `0fe4e039551f18b3438d485f7aa4019c49f71ff7` by a normal
merge, preserving current submission epochs and diagnostics. The shared public
consumer is connected to `newSubmission`/`lookupSubmission`: repeats use the
same original reference, and refusals inspect the retained `not_accepted`
problem without mistaking its record for Run acceptance. No legacy request-ID
submission or older wire fallback is used. Pre-integration checks below remain
evidence for their original source rather than the integrated HEAD.

## Counterexample and connection

```sql
SELECT element.*, position
FROM UNNEST(@payload.nested.items) element WITH OFFSET position
ORDER BY position
```

The payload is a declared nullable closed object containing a nullable nested
object and a bounded nullable ARRAY of nullable closed objects. An independent
complete JSON Program uses ordinary parameter/property expressions, UNNEST,
nullable property projections, sort and select. Its normal checker accepts
NULL parents, NULL containers, NULL/empty arrays, NULL elements and duplicates.
Before the fix the equivalent text fails compilation at the star contract
lookup (`run-wzb87H`, `focused-test-8Xh3ZX`, 0/1), after the JSON control checks.

The contract lookup formerly recognized only a bare parameter. It now follows
parenthesized property paths into the admitted declaration using bounded
field access. It supplies no new type, nullability, uniqueness, order or runtime
evidence. Unknown/computed receiver contracts are not inferred from values.
Common property evaluation and the existing checker retain responsibility for
NULL propagation, invalid parameters, field types and ARRAY bounds. The same
normal parser/lowerer serves SQL and Pipe; no JSON patch, compatibility path or
execution owner is introduced.

## Independent execution obligations

The public fixture preserves three rows, including a NULL element and repeated
ID, at offsets 0, 1 and 2. Ordered columns are nullable number `id`, nullable
string `label` and nonnullable number `position`. The eight positive cases
include JSON, SQL, Pipe, quoted/parenthesized paths and four empty-result forms.
Five pre-admission refusals cover undeclared parameters, unknown property,
non-ARRAY input, exceeded ARRAY bounds and wrong item-field types.

These cases are registered in the normal UNNEST corpus and the same external
Local/HTTPS consumer's `--unnest-parameter-path-only` selection. Expected rows
and contracts are authored independently of lowering and are never repaired by
the consumer. Whole-object canonical field order remains the existing common
contract; this does not establish GoogleSQL's ordered STRUCT type or broader
computed-expression star support.

## Evidence and remaining work

After the connection, the affected JS UNNEST selection passed 9/9
(`run-EmWWvc`, `focused-test-B4woDN`), before the additional refusal/work-limit
regression. Final bounded selections are:

- `node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js src/query_program --filter '*UNNEST*'`: 10/10, `run-9ulUoT`, `focused-test-9Y7kcL`.
- `node scripts/local-checks.mjs test node --timeout-seconds 120 -- scripts/unnest-parameter-path-source-input.test.mjs scripts/unnest-source-input.test.mjs scripts/client-values-run-materials-vector.test.mjs scripts/compilation-manifests.test.mjs`: 16/16, `run-bsmITP`, `focused-test-V0mUot`.
- `node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js src/run_publication_host --filter '*run materials rebuild exactly*'`: 1/1, `run-b4HgPZ`, `focused-test-e5vddE`.

After merging current main, the UNNEST selection passed 10/10 again
(`run-khCfwa`, `focused-test-N48vzk`). The Node selection above, with
`scripts/acquired-data-acceptance.test.mjs` added for the epoch-bound consumer,
passed 22/22 (`run-tT6ZW0`, `focused-test-qkSgbh`). Manifest/metadata checks and
375 canonical vectors also pass after integration. These do not stand in for
external distribution execution.

Normal manifest/metadata/canonical generators are used. Their read-only checks
pass, including 375 canonical vectors. The query rules change grammar CID to
`sha256:38b2c821bd3b65aeeac218ef8300f9bc25a8dba90956fdfda1313651fdebef15`.
Complete independent Values Run preimages yield
`sha256:9bd9abd436fd9564578f921adcb16ba105274cdaaad118717d08b13d30183a2d`.
The previous main grammar/Run vector is retained. Unit/Result Plan and common
expression identities are unchanged; old Runs are not relabeled.

Normal fixed-source five-package Local/HTTPS execution remains required:
`node scripts/test-packed-public-query.mjs --unnest-parameter-path-only`.
Preparation and checker success are not reported as public execution success.
The shared heavy lock is retained; no other worktree's build or evidence is
removed. Full Core, native/Wasm and CI are not claimed. The new worktree borrows
only the command's YAML dependency at
`/Users/t14i/workspace/20260822/actql/node_modules/yaml` and the pinned MoonBit
toolchain under that repository's `.toolchains`; it does not borrow old Client
wire/runtime packages or patch a distribution for acceptance.
