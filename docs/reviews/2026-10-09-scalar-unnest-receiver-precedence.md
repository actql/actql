# Scalar UNNEST receiver precedence

Adopted main: `1b0ae88c87683b94cfd96e73f96f969cb4ecf355`.
Parent: #1149 at `fa01cb098d1922a4bb17158137a4c2f7c9b75b66`, retaining
#1148 and #1146. Final destination is main after the parents integrate;
no merge into a dependency branch. Independent of #1144.

## Existing contract and actual discrepancy

```sql
FROM parents p
|> CROSS JOIN UNNEST(p.items) element WITH OFFSET position
|> WHERE element > 0
|> SELECT element, p.element AS original,
          position, p.position AS original_position
|> ORDER BY position
```

Parent columns are element=100, position=50, items=[2,NULL,1]. The bare
receivers must select the array element and offset, while qualified p columns
retain 100/50. The predicate therefore removes the NULL element; it must not
read 100. The unfiltered public control independently expects elements
2,NULL,1 and offsets 0,1,2. Sorting by element instead yields 1,2,NULL.

The pinned [GoogleSQL NameScope implementation](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/googlesql/analyzer/name_scope.cc)
explicitly makes range variables take precedence over columns. The pinned
[ResolveArrayScan](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/googlesql/analyzer/resolver_query.cc)
adds array aliases and WITH OFFSET through value-table range registration.
This is primary source inspection, not live Google differential execution.

Actual pre-repair run-Ie6gUm / focused-test-YUCRYG: **1/2**. The independent
complete ordinary JSON Program passes the normal checker; the first Pipe
counterexample refuses with Expression/UnknownReference. The post-SELECT
removed-range refusal already passes. Other loop members are not claimed as
separately executed before repair. Earlier harness iterations corrected a
hand-authored zero literal and unsupported diagnostic formatting; those are
not product defects or verification successes.

## Minimal connection

Private scalar range metadata now stores the existing physical value slot,
just as object receiver metadata already does. The shared expression-column
helper applies the same range precedence to scalar values and offsets.
Column editing and star expansion retain their separate existing rules.
JOIN remaps receiver slots through its actual projection, and ON/pre-JOIN
conditions resolve the original receiver. USING continues its column-target
resolution. SQL GROUP retains only evaluated grouped receiver keys; Pipe
AGGREGATE and SELECT retain their existing scope replacement. Removed ranges
cannot reappear through stale private slot metadata.

No new language semantics, checker/evaluator/Owner, fallback, wire, acquisition
boundary, resource exception or grammar/schema/law/registry pin is added.
D's CTE/assert/Effect/predicate functions are unchanged. The complete independently
written expected Program fixes Values, array derivation, UNNEST ports, predicate,
ORDER, projection, column order and Named Result before exact SQL/Pipe comparison.

## Limited verification

- Initial repaired selection: **32/32**, run-BpV6qD / focused-test-Y9HlkF.
- Final UNNEST/JOIN/GROUP callers: **59/59**, run-N5xf8r /
  focused-test-yvrI9N. These overlap and are not summed.
- Node independent fixture/normal corpus/import checks: **14/14**,
  run-emsY2u / focused-test-iiL0lH.
- One attempted selection named a nonexistent group_key_alias_test.mbt;
  discovery failed without a test summary. The corrected existing-file
  selection is the final 59/59 above.
- Changed MoonBit files use the pinned formatter; git diff --check passes.

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js \
  src/query_program/unnest_scalar_receiver_precedence_test.mbt \
  src/query_program/unnest_offset_range_scope_test.mbt \
  src/query_program/unnest_scalar_range_target_test.mbt \
  src/query_program/unnest_receiver_scope_test.mbt \
  src/query_program/unnest_join_continuation_test.mbt \
  src/query_program/unnest_pipe_edit_scope_test.mbt \
  src/query_program/unnest_struct_star_test.mbt \
  src/query_program/joined_unnest_star_test.mbt \
  src/query_program/group_select_input_scope_test.mbt \
  src/query_program/group_property_receiver_scope_test.mbt \
  src/query_program/group_scope_test.mbt src/query_program/join_chain_test.mbt \
  src/query_program/full_join_scope_test.mbt
node scripts/local-checks.mjs test node --timeout-seconds 120 -- \
  scripts/unnest-source-input.test.mjs scripts/unnest-checked-array-source-input.test.mjs \
  scripts/spec-family-imports.test.mjs
```

## Public execution obligations

The normal UNNEST corpus and its existing --unnest-source-only consumer both
register thirteen new positives and four precise refusals. The intended full
cohort is 99 positives / 46 refusal loops per Embedded Local/HTTPS.
Independent JSON uses ordinary parameter/property/UNNEST operations with
separate names. SQL, Pipe, quoted receivers, element/offset/computed predicates,
receiver ordering, typed empty/NULL arrays, JOIN remapping and SQL/Pipe GROUP
have independently authored rows, full types/nullability and column order.

The existing consumer also checks Result.describe, stream completion,
private-slot absence and same-Run resend/attach/reread without additional
acquisition/execution. New invalid/removed receivers require exact
ClientProgramInvalidInput with zero durable admission and zero Source I/O.
No fixture values, limits or expected rows are relaxed.

Fresh clean-SHA normal five-package production and public execution remain
pending at this product commit. Actual package SHA/digests and terminal evidence
will be appended after execution; preparation and unit success are not public
execution evidence. Full Core/Native/Wasm/Cloud, full retained-history validation,
value-table ORDER ordinals and overall Frontend completion remain unverified.
CI is separate; no manual retry or merge. runtime_conformance:false remains.
