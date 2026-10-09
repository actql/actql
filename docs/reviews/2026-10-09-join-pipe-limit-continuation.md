# Pure Pipe continuation after a projected JOIN

Date: 2026-10-09. Status: localized Frontend connection repaired and selected
fresh packed Embedded Local/HTTPS acceptance complete. The full public-text
Frontend objective and complete GoogleSQL conformance remain open.

## Existing meaning and missing connection

The adopted GoogleSQL Pipe profile composes pure operators in authored order.
A second LIMIT consumes the first LIMIT's completed Relation; it does not
replace the first count/offset pair. WHERE and SELECT after a take consume
that completed output. A materialized SELECT does not restore its input ranges.
See the pinned google/googlesql@d82db99a923a46571f543a13899dc791a7b6f743
[Pipe LIMIT reference](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/docs/pipe-syntax.md#limit_pipe_operator).
This is selected reference/profile evidence, not a live Google execution.

The ordinary shared Pipe lowerer already emits each take in sequence. The
single-JOIN projection specialization instead gated its continuation on a
retained RESULT tap and imposed a four-operation shape cap. Valid pure tails
were refused with UnsupportedJoin/UnsupportedCte before reaching that lowerer.
These are Frontend shape restrictions, not Host resource ceilings.

Independent source example:

```aql
FROM t
|> JOIN r ON t.x = r.k MAX_OUTPUT_ROWS 10
|> SELECT t.x AS id, t.y AS amount
|> ORDER BY id
|> LIMIT 1 OFFSET 1
|> LIMIT 1
```

With t={(x=1,y=20),(x=2,y=10)} and r={k=1,k=2}, the expected output is
{id=2,amount=10}. Applying only the final LIMIT would instead return id=1.
A complete independently authored Program retains the JOIN bound/ports,
projection, sort, both takes and Named Result; it passes the ordinary checker.
Both FROM- and SELECT-headed sources compare with that exact expectation.
A second complete expected Program fixes WHERE id=2 and final SELECT id after
the first take. A negative control demands Expression/UnknownReference for
WHERE t.x=2 after materialization, rather than accepting the removed range.

## Localized connection

- `append_join_order_steps` can send an ordinary pure tail into existing
  `compile_steps`, using projected_input=true. It does not recover JOIN operand
  ranges or expand already evaluated SELECT expressions.
- `join_continuation_context` supplies existing Limits for a pure continuation
  even when the caller has no retained-Result collection. A caller unable to
  export authored retained Results still receives no such context.
- `compile_join_steps` and `compile_join_query` remove the artificial four-op
  shape gate. Existing query syntax-node/work, construction bytes/nodes/depth,
  expression work, ordinary checker and Host capacity admission remain intact.
- The continuing output updates Result columns in its actual final order.
  No Source is reacquired, implicit Result is added or separate executor created.

No grammar/schema/registry/law/pin or common Owner/capacity/wire contract changes.
D's CTE/assert/Effect/predicate implementations are unchanged. One existing
Source routing condition is reformatted by pinned moonfmt without logic changes.

## Fixed source and limited compiler evidence

- Parent #1140: 7288e50deb875718e30231d9e0f3cac3b0009b33, now merged.
- Initially adopted main: aa083f961917a3822c359a4c01d544ffef4af548.
- Repair commit: d30aef00ff8a2f67f6fdcdb811b09da327e0e816.
- Latest adopted main: 1b0ae88c87683b94cfd96e73f96f969cb4ecf355.
- Clean integrated product/fixture SHA tested with normal five-package packing:
  **8def90ee066e729d5cdc5ab5c34b39a6dda04beb**.
- Main was normally merged without conflicts. Existing declarations are retained;
  no duplicate declaration, rebase or history-validator modification was added.

Baseline run-qABaZT / focused-test-67Z902: **0/3 passed**. Both independently
checked positive Programs are valid; their text compilations return exact
UnsupportedJoin. The range rejection assertion also fails because the generic
shape refusal precedes reference resolution. Later variants in a loop are not
claimed as individually observed before the fix.

Intermediate run-8trqEL / focused-test-Xw4tO0: **18/20 passed** after continuation
connection. The remaining two expose the standalone JOIN's separate shape cap.
Removing that duplicate cap yields run-DrWSAE / focused-test-mTxuCw, **20/20**.
Final public-script plus direct compiler, parameter, JOIN order and retained
Result callers: run-DHAIZj / focused-test-Be4qnn, **82/82 passed**. These focused
JS tests precede the final main merge; integrated public execution is separate.
Node independent fixtures/imports: run-Z0b8F0 / focused-test-7CjsAn, **8/8**;
final exact rejection expectations: run-lpWI3t / focused-test-CNzRm4, **5/5**.
Read-only document metadata generation reports no changes; git diff --check passes.

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js \
  src/query_program/join_pipe_limit_tail_test.mbt \
  src/query_program/limit_parameter_test.mbt src/query_program/pipe_result_test.mbt \
  src/query_program/join_order_test.mbt src/query_program/compile_test.mbt
node scripts/local-checks.mjs test node --timeout-seconds 120 -- \
  scripts/limit-parameter-source-input.test.mjs scripts/spec-family-imports.test.mjs
```

## Fresh packed Embedded Local/HTTPS

The existing serialized bounded wrapper run-qZ2Olr normally produces five
packages from exact clean SHA 8def90ee0 and independently verifies revision and
original SHA-256 digests. No overlay, producer prepack bypass, manifest relabeling,
new acceptance harness or limit increase is used. The existing LIMIT cohort is
selected and also remains registered in ordinary packed acceptance.

```sh
node scripts/packed-client-packages.mjs /private/tmp/actql-b-join-limit-tail-8def90ee0-pack
ACTQL_PACKED_CLIENT_PACKAGES=/private/tmp/actql-b-join-limit-tail-8def90ee0-pack \
ACTQL_TEST_NPM_CACHE=/private/tmp/actql-b-group-key-slot-collision-integrated-pack/npm-cache \
node scripts/test-packed-public-query.mjs --limit-parameter-only
```

Embedded Local and HTTPS each complete **21 positives and 16 refusals**,
retaining all original 14/13 cases. New cases cover independent JSON, Pipe and
SQL heads, WHERE/reprojection/ORDER after the take, empty typed output,
nullable values, duplicates and different first/second operand bindings.

The new public input sorts joined rows to (1,NULL),(2,20),(3,30),(3,30).
The first take count=3,offset=1 yields (2,20),(3,30),(3,30); the second
count=2,offset=1 yields **two identical (amount=30,id=3) rows**. Ignoring the
first take instead produces (2,20),(3,30), so the fixture detects the error.
Different operands return (amount=NULL,id=1). Final reprojection explicitly
changes column order to id,amount. The JOIN's authored max_output_rows remains 10.

Existing assertions compare Named Result rows, complete column contracts and
order, NULLs/multiplicity, stream completion, private-field absence, one Source
acquisition and same-Run resend/attach/reread without extra acquisition/execution.
Invalid first and second counts and removed input-range references explicitly
assert ClientProgramInvalidInput with zero durable Run admission/Source I/O.
The original twelve broad-code refusal checks remain unchanged; the original
ambiguous-declaration refusal and all three new refusals log their exact codes.
No known failure or old obligation is omitted.

Receipt **worktrees/.codex-scratch/public-query-evidence-2Juk8V** was independently
inspected: exact clean source revision, passed/complete, ten zero-exit commands,
complete streams, no signal/error/evidence errors, all expected positive names
and explicit refusal codes in both transports, artifactsRemoved=true. The
complete consumer also asserts all sixteen refusal counter snapshots unchanged.
README Local/HTTPS and the missing-generated-asset check pass. Logs/receipt
remain while successful temporary installation and Host Stores are removed.

| Package | Original SHA-256 |
|---|---|
| client-wire | ca7aaf03f3f1d78aff24c42a4ebe94ae2136ce29ba3fdf8ed81478e359e3df60 |
| sdk | 64eca760cdce9f0da1ea53542ede457ec9f5c80603d9b13721077d90c7b91c1e |
| run-host-core | f5487ba69e88efbab8e99930482c27254b8055f421280045a46c0532f8349d1b |
| local-node | cc210545971406e35519bdc2cb030dda07e5ea4d23917765be2551c3b5effa0b |
| node | a77756e97078c7df0ea0a318e5ccd74bd7aee2891caa148da2688f9c3eb2d9eb |

## Remaining verification

The subsequent evidence commit is documentation only, not a new packed run.
Full Core, all targets, all packed families, performance, complete retained-history
validation and live Google differential execution are not verified locally.
Exact submitted-HEAD CI must be reported separately. Draft preparation does not
establish merge verification. LIMIT 0, broader constant expressions and the
wider unordered-limit contract remain separate common/profile gaps recorded
in the prior LIMIT work; this connection does not reinterpret them or claim
that those standard-valid forms are invalid GoogleSQL. The full Frontend
completion objective remains active.
