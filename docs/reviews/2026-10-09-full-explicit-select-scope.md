# FULL JOIN: explicit SELECT uses the shared joined-row scope

## Scope and counterexample

Adopted main: `2aa04151149093c8a0c62a493518f2af2d7fcd44`.
This is an independent frontend connection, without an unmerged dependency.

```aql
DATA base = FROM records |> ASSERT UNIQUE BY (id);
DATA lefts = FROM base |> WHERE id <= 2;
DATA rights = FROM base |> WHERE id >= 2;
SELECT l.amount, l.id, r.id AS rid
FROM lefts AS l FULL JOIN rights AS r
  ON l.id = r.id MAX_OUTPUT_ROWS 10
ORDER BY id NULLS LAST, rid NULLS LAST
```

The equivalent `SELECT l.*, r.id AS rid` already used the shared JOIN scope.
Explicit SELECT, including DISTINCT, instead selected the older projection
specialization. `compile_join_query` refuses every FULL join in that path,
even when ordinary DATA assertions supply the necessary input identities.
This was a routing gap, not a new JOIN contract or a lack of sampled keys.

The pre-repair focused JS test selected two new tests and passed 0/2, stopping
at lowering before checking. Evidence: `_build/local-checks/attempts/run-hVWMdL`
and `_build/focused-evidence/focused-test-lRzJD8`. The pre-repair source has
both the routing exception and the explicit `UnsupportedJoin` guard.

`join_requires_group_scope` now selects the existing shared scope for every
FULL JOIN, just as it already does for RIGHT JOIN. Projection, expressions,
DISTINCT and ORDER use the existing common value/column owners. The internal
projection specialization's guard remains; no fallback is introduced.

The existing unkeyed Values test now checks the actual common rejection,
`Closure(Joins(MissingEvidence(...)))`, rather than expecting a frontend
refusal. It still forbids inventing a key or accepting an unproved FULL join.
There is no checker, identity, provider, task, capacity or resource-limit change.
The surface grammar and contract preimages are unchanged.
Affected generated Programs now use the shared JOIN slots; their Program/Run
identities can change with that structure. Existing saved Runs are not rewritten
or treated as if they were compiled from the new structure.

## Independent expectations and public registration

`full_select_scope_test.mbt` contains a complete independent Values/assert/
Stage-input/FULL/projection/sort/Result Program and compares the generated CTE
Program to it. Both are checked normally. DATA SQL/Pipe/DISTINCT callers retain
asserted keys, the authored ceiling 10, ordered public columns and private slots.

The existing `full-join-scope-source-input.mjs` contains a complete independently
authored acquired-source JSON control. The new explicit SQL/Pipe/CTE forms use
the same expected rows and column contracts, without modifying compiled output:

```json
[{"amount":null,"id":1,"rid":null},
 {"amount":20,"id":2,"rid":2},
 {"amount":null,"id":null,"rid":3}]
```

Columns are `amount,id,rid`, in that order, all nullable numbers. Additional
counterexamples cover the empty typed result; duplicate NULL values collapsing
under DISTINCT before ORDER helpers; and opposite orders for `id + 1` versus
`l.id + 1` after `SELECT -l.id AS id`. Ambiguous bare `id` remains a preparation
refusal. All additions are in the existing normal packed corpus, not only its
`--full-join-scope-only` selector. This cohort has 20 successes and four refusals
per transport, including its unchanged FULL ON/USING controls.

The existing public application reads Named Result rows and `Result.describe()`
columns, checks authored order/types/nullability and excludes hidden fields.
It checks one real Source acquisition session per case and unchanged counters
after Result reread, attach and identical-request resend. Refusals check no
Run admission or Source I/O. Registration alone does not prove execution.

## Focused verification

With pinned Node `22.22.0` and MoonBit `0.10.12+1634b282e`:

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 240 -- --target js src/query_program/full_select_scope_test.mbt src/query_program/full_join_scope_test.mbt src/query_program/full_using_scope_test.mbt src/query_program/compile_test.mbt --filter '*FULL*'
node scripts/local-checks.mjs test moon --timeout-seconds 240 -- --target js src/query_program/join_chain_test.mbt src/query_program/join_distinct_order_test.mbt src/query_program/join_star_test.mbt src/query_program/right_join_test.mbt src/query_program/single_join_group_test.mbt
node scripts/local-checks.mjs test node --timeout-seconds 120 -- scripts/full-join-scope-source-input.test.mjs scripts/right-join-source-input.test.mjs scripts/join-star-source-input.test.mjs
```

- FULL JS: 10/10, `run-auVLSl` / `focused-test-knLZ1j`.
- Shared JOIN callers JS: 20/20, `run-gylbpz` / `focused-test-hTYKu3`.
- Node fixture and normal-corpus registration: 8/8, `run-PETVrk` /
  `focused-test-LCuwcV`.

These are bounded local results, not CI results. Packed Local/HTTPS evidence is
pending at this commit; it must use a normal five-package producer from a clean
fixed source revision with independently verified tarball digests. Full Core,
Wasm, Native, Cloud, performance and manual CI reruns were not executed.

## First packed attempt and refusal-contract correction

Normal five-package production and independent digest verification succeeded
at `62bd1ca5797492d16062448a1c9d57e4a305c717` (`run-1b2ryw`). The external
receipt is `worktrees/.codex-scratch/public-query-evidence-WiOYQN`; all twenty
Local positive cases passed, including every new explicit SELECT case. Command
010 then stopped at the first refusal's obsolete broad fixture allowlist:
the Host returned `ClientProgramImplementationLimit`, which that allowlist
omits. HTTPS was not reached. The failed attempt's receipt and stdout/stderr
are retained; its owned expanded installation was removed by the normal runner.

The correction follows existing public contracts rather than replacing an
expected code with an arbitrary measured result. The common public check in
`connectors_builtin_node/client_check.mbt` projects `UnsupportedJoin` as
`Limit("implementation_limit")`, and ambiguous columns as a violation. The
audience-checked submission adapter projects these respectively to
`ClientProgramImplementationLimit` and `ClientProgramInvalidInput`. The query
parser refuses `MAX_OUTPUT_ROWS 0` as invalid syntax. The FULL fixture now
requires those exact codes for its two UnsupportedJoin cases, zero ceiling
and ambiguous column. The shared generic refusal allowlist is unchanged, as
are the expected rows, bounds, Run-admission and provider-I/O assertions.

The corrected fixture and existing disclosure-owner tests passed 29/29 using:

```sh
node scripts/local-checks.mjs test node --timeout-seconds 120 -- scripts/full-join-scope-source-input.test.mjs adapters/host-node/client-preparation-disclosure.test.mjs
```

Evidence: `run-SZrs2S` / `focused-test-iwpn2w`. The product implementation has
not changed since the first packed attempt; only this fixture and report did.

## Completed packed Local/HTTPS acceptance

Tested clean implementation/fixture revision:
`749d254638a12e705a17c2d38f9511d4582f5e98`.
The subsequent evidence-report commit is not the package producer revision.

The existing bounded supervisor ran these steps with a 1,200-second wall-clock
budget, five-second termination grace and the shared heavy-work lock:

```sh
node scripts/packed-client-packages.mjs /private/tmp/actql-b-full-explicit-749d25463-pack
# Independently rehash all five tarballs and verify manifest.revision = HEAD.
ACTQL_PACKED_CLIENT_PACKAGES=/private/tmp/actql-b-full-explicit-749d25463-pack node scripts/test-packed-public-query.mjs --full-join-scope-only
```

The normal producer executed prepack; no payload revision override, skipped
build, patched generated Program or package overlay was used. Only this unit's
private npm content cache from the first attempt was reused. Exact wrapper:
`/private/tmp/actql-b-full-explicit-749d25463-packed-20261009.mjs`.

All three supervisor steps passed: `run-ULKRCu`, complete output, exit 0,
locks released. External receipt:
`worktrees/.codex-scratch/public-query-evidence-L9f0Y2`.
All ten captured commands have that clean source revision, status and
verificationStatus 0, complete output and no error/signal/evidence failure.
The normal runner removed only its owned expanded installation after preserving
logs, receipts and tarball digests (`artifactsRemoved: true`).

| Transport | Normal Named Results | Exact preparation refusals | New explicit SELECT positives |
|---|---:|---:|---:|
| Embedded Local | 20 | 4 | 7 |
| Remote HTTP over real HTTPS | 20 | 4 | 7 |

Every positive compares the independent ordered rows and full ordered column
contracts from `Result.describe()`, including NULL and the empty result. The
DISTINCT fixture publishes two values, not three rows or hidden sort fields.
The alias/qualified ORDER pair preserves its deliberately opposite order.
Each case retains one real Source acquisition session; Result reads, reattach,
resend and lookup retain the same Run without extra admission or Source I/O.
Every refusal has an explicit code log and unchanged Run/Source counters.
The unchanged source-free README Local/HTTPS quickstart and public-check probes
also passed in this selected driver; this is not a full packed campaign.

| Package | SHA-256 |
|---|---|
| client-wire | `18762bb0bf434d939ff153d485e2aed28f0fa3c77c9d1e82eee4983765947905` |
| sdk | `c468fa4d31016b3d10539f1edc49a113241a52a67d34493ff165bfac30ed102c` |
| run-host-core | `41b5d6e6ecdb0ce8efc311766524225d9bb46f0fef3d21506194635c18c20d7f` |
| local-node | `9b0e76b7a4398595442b4b0f551d06c14723b51b4c7d467f9b64398979ef0ef0` |
| node | `2989926be6f87295d48551e3c83e64dd6fb26f7b943e4004ad69176e19b98cda` |

A separate read-only receipt audit independently rehashed all five actual
tarballs, compared manifest/receipt identity, checked every command's clean
source/completion and matched every positive and exact refusal name for both
transports. It passed:
`/private/tmp/actql-b-full-explicit-749d25463-acceptance-audit-20261009.{mjs,json}`.
The earlier `62bd1ca5` failure remains historical evidence; its twenty Local
positives are not substituted for this clean completed Local/HTTPS run.

Submitted-HEAD CI, full Core, Wasm/Native execution, Cloud and broader packed
coverage remain unverified here. No manual CI rerun or merge was performed.

## Remaining boundaries

This report supersedes only the explicit FULL SELECT routing gap. Prior FULL
ON/USING reports retain their historical source/transport evidence. It does not
claim universal outer-join composition. The existing common diagnostic category
gap for unkeyed FULL (`MissingEvidence` becoming `check_unclassified`) is separate;
this unit preserves the checker rejection instead of manufacturing its proof.
No common diagnostic, SDK uncertainty or execution-owner implementation is added.
