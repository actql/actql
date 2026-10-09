# Window keys: reuse proven input receivers

Date: 2026-10-10. Owner: B. Adopted main:
`4890f8c3830d2a8e3ecaac635e8e279597938c29`.
This independent unit changes source lowering only. It does not amend a common
value law, schema, grammar, registry pin, execution owner or capacity ceiling.

## Confirmed defect and scope

The [query specification](../spec/query-text.md) requires repeated OVER keys
within an immutable input scope to share their evaluated slot, including
partition/order keys and different windows. However,
`query_analytic_order.mbt::analytic_order_field` compared their source syntax.
These three keys denote the same nullable input value:

```sql
COALESCE(payload.bucket, 'missing')
COALESCE((objects.payload).`BUCKET`, 'missing')
COALESCE((payload).bucket, 'missing')
```

The independently authored complete Program computes that value once and keeps
the authored partition-key repetitions and ASC/DESC order lists. Both the
expected Program and the actual source Program pass the ordinary checker.
Before repair their full-Program comparison fails: actual lowering emits three
private derives. This confirms unnecessary reevaluation, not an observed wrong
row, public failure or proven capacity overestimate.

## Repair and boundaries

Reuse the existing `same_group_expression_in_scopes` comparison with the actual
resolver for both expressions. That comparator preserves explicit object
receiver boundaries, resolves range/column prefixes, and compares members under
the adopted name rules. Each evaluated list already belongs to one immutable
analytic clause scope; it is not retained across a subsequent Pipe mutation or
between SELECT-input and ORDER-alias processing.

Charge expression-node work for each comparison and retain the original key
origin when its bounded budget is exhausted. Keep all authored partition-list
occurrences, window order/direction/NULL rules and separate analytic operations.
The common checker still decides member and key validity. No input column,
schema, uniqueness evidence or order guarantee is fabricated.

Fewer private derives change affected generated Program identities and normal
Run preimages. No existing Program input changes meaning, and no old saved Run
is relabelled as the new output. There is no contract-pin change.

## Independent fixtures

- A complete nullable-object Program and equivalent SQL/Pipe sources establish
  one derive with two repeated partition occurrences and separately ordered
  ROW_NUMBER/RANK windows.
- Distinct current/original Pipe slots and explicit object/Relation range
  receivers remain distinct. Work exhaustion retains a typed diagnostic.
- Six public cases enter the existing ordinary partition-expression corpus:
  independent JSON control, qualified SQL, equivalent Pipe, empty typed output,
  nullable receiver/member projection and a different object receiver.
- The Boolean control expects `(pos, ranking)` pairs
  `(1,2),(2,1),(1,2),(1,2),(2,1),(2,1)` in final ID order. Distinct object
  receivers deliberately change ranks from `1,1,4,3,2,1` to `6,5,4,3,2,1`.
  These values are written independently of the product compiler.

Three existing constant-partition and one unsupported-function refusal fixtures now require the exact
`ClientProgramImplementationLimit` code. This follows the unchanged
`client_check.mbt` mapping of `UnsupportedAnalytic` / `UnsupportedFunction` to `implementation_limit`;
the old generic unsupported expectation was stale. Inputs and rejection
requirements are unchanged, and no default refusal allowlist is broadened.

## Focused verification

Use the pinned Node and MoonBit from the repository toolchain:

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js \
  src/query_program/window_key_receiver_reuse_test.mbt \
  src/query_program/analytic_order_expression_test.mbt \
  src/query_program/analytic_partition_expression_test.mbt \
  src/query_program/analytic_partition_property_test.mbt \
  src/query_program/analytic_frame_parameter_test.mbt \
  src/query_program/order_window_expression_test.mbt \
  src/query_program/qualify_test.mbt
node scripts/local-checks.mjs test node -- \
  scripts/window-key-receiver-source.test.mjs \
  scripts/analytic-partition-expression-source-input.test.mjs
```

Pre-repair: 0/1 in `run-LDAS34`, `focused-test-gMF11N`.
Repair/callers: 44/44 in `run-aSaaeX`, `focused-test-l3MVYz`.
The first Node fixture check: 4/4 in `run-ZQV351`, `focused-test-8sVajA`.
Receipts remain in this worktree's `_build/local-checks/attempts/` and
`_build/focused-evidence/`. One initial command lacked MoonBit on PATH, and
one caller selection used a nonexistent filename; neither executed tests or
counts as a pass. Both were corrected before these recorded results.

The final nullable-member fixture check passes 4/4 in `run-OIstiM`,
`focused-test-VIwH5J`. Moonfmt and `git diff --check` pass.
After the unsupported-function fixture correction, final Node checks pass
4/4 in `run-AEQXP7`, `focused-test-PMjYWh`.

## Initial packed attempt

The normal five-package producer and independent digest checks run at clean
`d82a817820644660bb07f2788f7e897a080ad595` in `run-2yYBdA`. All 17 Local
positive cases and the expected demanded-expression execution failure pass.
After the constant refusals pass, the existing unsupported-function fixture
fails because its generic default does not permit the unchanged exact
`ClientProgramImplementationLimit` category. The exact fixture is corrected;
product rejection and acceptance ceilings are not changed. HTTPS is unreached
in this attempt. Receipt/logs:
`worktrees/.codex-scratch/public-query-evidence-KzTyws/`.
Its status is failed and incomplete; evidence errors are empty. Its consumer
installation is reclaimed after preserving all logs. The failed attempt is
not a whole-cohort acceptance success.

## Final exact-source public acceptance

The successful product/fixture source is clean
`ca4dcf6a52370424ca3965b9bc1b498df9853d96`. The normal five-package producer
retains prepack and records this revision in
`/private/tmp/actql-b-window-key-receivers-ca4dcf6a5-pack/packed-client-packages.json`.
The independent file hashes agree with that manifest and the receipt:

| Package | SHA-256 |
| --- | --- |
| client-wire | ca7aaf03f3f1d78aff24c42a4ebe94ae2136ce29ba3fdf8ed81478e359e3df60 |
| sdk | 64eca760cdce9f0da1ea53542ede457ec9f5c80603d9b13721077d90c7b91c1e |
| run-host-core | 7c6053aa4f618ff3d66ffd7886da538f0abc628be29f9f7b4eeb6accf831da50 |
| local-node | 8adad5c0fc6e191db72f501108739e4254424e56c9494c4a2abd2c92adfdd5ba |
| node | a77756e97078c7df0ea0a318e5ccd74bd7aee2891caa148da2688f9c3eb2d9eb |

The existing selected consumer is:

```sh
node scripts/packed-client-packages.mjs /private/tmp/actql-b-window-key-receivers-ca4dcf6a5-pack
ACTQL_PACKED_CLIENT_PACKAGES=/private/tmp/actql-b-window-key-receivers-ca4dcf6a5-pack \
  node scripts/test-packed-public-query.mjs --analytic-partition-expression-only
```

Actual execution uses the existing shared heavy guard in
`/private/tmp/actql-b-window-key-receivers-packed.mjs`, 1200-second bound and
five-second TERM grace (`run-jqlSLH`). Both Embedded Local and authenticated
HTTPS pass the same 17 normal cases, eight preparation refusals and one
expected demanded-expression execution failure. This includes all original
11 normal cases plus the six new cases; none is excluded or rewritten.

The unchanged driver checks Named Result rows, complete declared type and
nullability, column order, stream completion, absence of private output columns,
repeated Result reads, attach and same-request Run reuse. Each new acquired
case retains exactly one Source read session, including empty input. All
preparation refusals preserve zero additional Run admissions and Source I/O.
The expected execution failure retains one admitted failed Run and refuses
Result rows/description; reread and resubmit add no acquisition or execution.

Original receipt/logs:
`worktrees/.codex-scratch/public-query-evidence-SjlAuK/`.
`summary.json` is passed and complete, source is clean and exact, all ten
command outcomes are status zero, complete and output-complete, signals are
absent, and `evidenceErrors` is empty. The consumer installation is reclaimed
(`artifactsRemoved: true`) after preserving evidence. Packs and original
receipts remain available; no teammate/shared artifact is deleted.

The final documentation commit records these earlier-source results and does
not change tested product or fixture inputs. Submitted-HEAD CI is separate;
no full Core, Wasm/native, Cloud, proof/performance campaign, manual CI rerun or
merge is performed. The broader Frontend goal and existing common capacity
blockers remain incomplete.

## Latest-main integration

Normally merged main `54ea974e0839efadfdaf2003185683c5edbf31fa` after the
initial submission. The merge had no conflicts and retains the merged Pipe
private-window and immutable EXTEND sibling-input repairs, Graph vocabulary
updates, current CI configuration and all existing history declarations.
The window-key repair and independent row/Program expectations are unchanged.

At clean integration commit `88fa19bfe0bdd3cd34346a4c4c7aed5944bb84f7`, bounded JS verification runs
the seven files above plus `src/query_program/pipe_window_private_scope_test.mbt`:
49/49 pass in `run-ipGcWm`, `focused-test-6rYwGO`. Targeted Node verification
runs the two files above plus `scripts/window-scalar-source-input.test.mjs`:
13/13 pass in `run-hwk4lZ`, `focused-test-7mZn9B`. Both wrappers terminate with
status zero. No broad local suite or repeated packed campaign is run merely
for the main merge.

The Local/HTTPS five-package results above remain evidence for
`ca4dcf6a52370424ca3965b9bc1b498df9853d96`, not for the integrated HEAD.
Integrated public acceptance and required CI are not established by these
focused checks. Keep the PR Draft pending their applicable review/gates; no
manual CI rerun or merge is performed.
