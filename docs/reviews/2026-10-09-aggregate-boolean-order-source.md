# Aggregate Boolean ordering: source-to-Program connection

Baseline: `802a947220cd6cae9f09dcd499669cd1cae48881` (main). This unit is
independent of the submitted UNNEST receiver PR. It changes only Frontend
aggregate-order admission, its independent fixtures and documentation.

## Contract and counterexample

The selected GoogleSQL reference is
[`d82db99a` aggregate function calls](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/docs/aggregate-function-calls.md).
It preserves the authored sort key/direction, requires DISTINCT ordering to
match the aggregate argument, and places aggregate WHERE before collection
ordering. The pinned primary file retained at
`/private/tmp/actql-b-googlesql-aggregate-calls-d82db99a.md` has SHA-256
`1a19a09d01afe4a77e4df56914d3d7e376d77bd21d19848d83a24bfc5b25b540`.
Current official documentation was also inspected; no live Google-service
execution or complete standard-conformance claim is made.

```sql
SELECT STRING_AGG(name, '|' ORDER BY payload.score IS NULL NULLS LAST, id)
  AS names
FROM objects
```

The independent complete Program uses ordinary `derive` with
`is_null(property(payload, score))`, followed by `group.string_agg` with that
Boolean field and `id` as its two ordering keys. Before repair the common
checker accepted this Program, but the source lowerer refused
`UnsupportedAggregate`. The focused test failed 0/1 at the explicit source
refusal (`run-2olyay`, `focused-test-5XG1ZV`). This is an executed lowering
counterexample, not a pre-repair public-Run failure.

The root dispatch in `aggregate_order_fields` admitted references, parameters
and conditional calls but excluded comparisons, predicates and NOT. Its
existing total-expression guard already classified the supported Boolean
operand trees. The repair connects those roots to that same guard and ordinary
expression lowerer. It does not create an evaluator, change common sorting,
infer key evidence, remove DISTINCT checks, or relax demand restrictions.

## Independent obligations

The existing conditional-order public fixture now also carries independently
written STRING and ARRAY JSON controls and authored SQL/Pipe counterparts.
Expected rows are fixed independently of compiler or runtime output:

- Input names include `a`, duplicate `b`, `c` and NULL; payloads include a NULL
  object and a nullable member. `IS NULL` gives `a|b|b|c`; `score > 15` with
  NULLS LAST gives `b|b|a|c`; NOT reverses the Boolean groups while retaining
  NULL propagation. AND with a false other operand retains three-valued logic.
- Opposite per-call directions remain independent. Aggregate inputs resolve
  before sibling SELECT aliases. SET current values and immutable range
  snapshots produce different expected strings.
- Named parameters retain declarations and values; empty input and masked
  failing aggregate arguments return the common nullable STRING result.
- ARRAY_AGG uses the existing explicit uniqueness assertion and bounded input;
  its JSON and source controls expect `[1,2,3,4]`, with nonnullable numeric
  items. No uniqueness is inferred from the ORDER list.
- Invalid Boolean operand types, missing properties and removed ranges retain
  typed input refusal. Potentially failing operands and mismatched DISTINCT
  ordering retain implementation-limit refusal before Run/provider I/O.

These additions use the existing normal public corpus and existing
`--aggregate-property-order-only` selection. No new acceptance framework or
Host profile is introduced. Existing cases, ceilings and expected values are
unchanged.

## Limited verification

Commands use the pinned Node/MoonBit toolchain and the existing bounded,
nonzero-test wrapper:

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 300 -- --target js src/query_program/aggregate_predicate_order_test.mbt src/query_program/aggregate_conditional_order_test.mbt src/query_program/aggregate_signed_order_test.mbt src/query_program/distinct_aggregate_order_test.mbt
node scripts/local-checks.mjs test node --timeout-seconds 120 -- scripts/aggregate-conditional-order-source-input.test.mjs scripts/aggregate-signed-order-source-input.test.mjs scripts/aggregate-property-order-source-input.test.mjs
```

- MoonBit JS: 19/19 (`run-vnnV8j`, `focused-test-D52DNI`).
- Final Node fixtures: 12/12 (`run-vj2EfH`, `focused-test-PhvhsH`).
- Both changed MoonBit files match pinned formatter output; `git diff --check`
  passes.
- An initial unsupported `--file` wrapper option ran no tests. The supported
  file-path selection above was then used. The first post-repair test run was
  17/19: two independent fixture details were corrected (the common
  `is_unknown` tag, and an omitted authored NULLS LAST). Product behavior and
  result expectations were not changed to hide a failure.

## Fresh public execution

Clean tested source: `73a8fd1347068071fea1142c7a6ad537c09ccaa6`.
The later evidence-only documentation commit does not claim a new package build.

```sh
node scripts/packed-client-packages.mjs /private/tmp/actql-b-aggregate-predicate-73a8fd134-pack
ACTQL_PACKED_CLIENT_PACKAGES=/private/tmp/actql-b-aggregate-predicate-73a8fd134-pack ACTQL_TEST_NPM_CACHE=/private/tmp/actql-b-aggregate-predicate-73a8fd134-pack/npm-cache node scripts/test-packed-public-query.mjs --aggregate-property-order-only
```

These were executed in one existing bounded heavy-work guard via
`/private/tmp/actql-b-aggregate-predicate-73a8fd134-packed-20261009.mjs`.
`run-pzMTs1` completed with exit 0, complete output and released locks
(2026-10-09 01:54:59–02:01:29 UTC). Normal prepack was not skipped; manifest
revision, actual five tarball digests and clean source were independently checked.
The consumer installed outside the repository and used the real standard Hosts.

Embedded Local and actual HTTPS each completed 79 normal cases, 36 preparation
refusals and the existing demanded-argument execution-failure case. All 15 new
Boolean-order normal cases passed. Named Result rows, declared column order and
full `Result.describe()` contracts matched. Each new acquired-source case had
one read session; reread, attach, resubmit and lookup caused no additional Run
admission or acquisition. All four new refusals matched their exact typed codes
with zero admission/provider I/O. Existing generic refusals were also executed
by the unchanged complete application loop; 12 refusals per transport have
individual exact-code logs and 24 retain the original generic-code assertions.

Original receipt:
`/Users/t14i/workspace/20260822/worktrees/.codex-scratch/public-query-evidence-yyb25x`.
It records ten successful commands at the same clean source SHA, complete output,
no evidence errors and removal of its own temporary installation. The independent
receipt/package/case audit is
`/private/tmp/actql-b-aggregate-predicate-73a8fd134-acceptance-audit-20261009.json`.

| Package | SHA-256 |
|---|---|
| client-wire | `18762bb0bf434d939ff153d485e2aed28f0fa3c77c9d1e82eee4983765947905` |
| sdk | `c468fa4d31016b3d10539f1edc49a113241a52a67d34493ff165bfac30ed102c` |
| run-host-core | `332a770a589f74f697fca8427c364da9b89dfc23c3fea9a1bd7c59c5d0e0401d` |
| local-node | `3f7341ecce85371abdb6403cd0c7f58632b48d1f072ec7ab392ccc7d08bee477` |
| node | `2989926be6f87295d48551e3c83e64dd6fb26f7b943e4004ad69176e19b98cda` |

Only this completed attempt's private npm content cache was additionally removed;
tarballs, manifest, logs, receipts and the shared dependency donor were retained.
No other worktree or shared cache was removed.

Full Core, Wasm/native, proof and performance campaigns were not run locally.
Submitted-HEAD required CI and content review remain separate obligations; this
focused public success does not prove completion of the entire Frontend.
