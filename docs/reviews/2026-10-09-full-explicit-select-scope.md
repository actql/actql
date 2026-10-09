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

## Remaining boundaries

This report supersedes only the explicit FULL SELECT routing gap. Prior FULL
ON/USING reports retain their historical source/transport evidence. It does not
claim universal outer-join composition. The existing common diagnostic category
gap for unkeyed FULL (`MissingEvidence` becoming `check_unclassified`) is separate;
this unit preserves the checker rejection instead of manufacturing its proof.
No common diagnostic, SDK uncertainty or execution-owner implementation is added.
