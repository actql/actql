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

Three existing constant-partition refusal fixtures now require the exact
`ClientProgramImplementationLimit` code. This follows the unchanged
`client_check.mbt` mapping of `UnsupportedAnalytic` to `implementation_limit`;
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

The final nullable-member fixture check and exact-source five-package
Local/HTTPS acceptance are recorded below when complete. Focused JS success
does not establish packed success, full Core, Wasm/native, Cloud or final CI.
