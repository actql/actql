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

## Completed clean-package public acceptance

Normal producer/fixture SHA: **2aecf46b520817fcf66ec1521affa5c32fc547bf**.
The later evidence commit changes this report only. The producer ran the normal
five prepack paths at this clean SHA; no overlay, relabeling or prepack bypass.
An independent verifier compared git HEAD and manifest revision, then calculated
each original tarball SHA256 before the existing public consumer ran.

```sh
node scripts/packed-client-packages.mjs /private/tmp/actql-b-scalar-receiver-2aecf46b5-pack
ACTQL_PACKED_CLIENT_PACKAGES=/private/tmp/actql-b-scalar-receiver-2aecf46b5-pack \
ACTQL_TEST_NPM_CACHE=/private/tmp/actql-b-group-key-slot-collision-integrated-pack/npm-cache \
node scripts/test-packed-public-query.mjs --unnest-source-only
```

The existing serialized bounded wrapper, run-vgt4E7, completed all three steps
with exit 0 and complete streams. Both Embedded Local and HTTPS complete
**99 positives / 46 refusal loops**. **33 exact-code refusals** per transport
are logged; thirteen older broad-code loops remain separate. Every one of the
thirteen new positives and four new precise refusals is present in each log.
The ordinary named rows, complete types/nullability/column order, describe,
stream completion, private-column absence, resend/attach/reread and no-extra-
execution assertions pass. New refusal logs explicitly record zero durable
admission and zero Source I/O. README Local/HTTPS and the intentional missing-
generated-asset child refusal also pass.

Receipt: `/Users/t14i/workspace/20260822/worktrees/.codex-scratch/public-query-evidence-EH0brE`.
Independent inspection confirms revision above, status=passed, complete=true,
ten result commands with status 0, complete/outputComplete=true, no errors or
signals, every command source clean and bound to that exact revision,
evidenceErrors=[], artifactsRemoved=true and the artifacts directory absent.
Successful private installations/Stores were reclaimed; original receipt/logs
and exact producer packages are retained. Local success is not CI success.

Original tarball SHA256:

| Package | SHA256 |
|---|---|
| client-wire | `ca7aaf03f3f1d78aff24c42a4ebe94ae2136ce29ba3fdf8ed81478e359e3df60` |
| sdk | `64eca760cdce9f0da1ea53542ede457ec9f5c80603d9b13721077d90c7b91c1e` |
| run-host-core | `f5487ba69e88efbab8e99930482c27254b8055f421280045a46c0532f8349d1b` |
| local-node | `b2bd60c76e164e22ab8ad2887b7baa2435b3ae89b091bbf1847a95a828567c65` |
| node | `a77756e97078c7df0ea0a318e5ccd74bd7aee2891caa148da2688f9c3eb2d9eb` |

No full Core/all-target/all-packed/performance campaign, Cloud, complete retained
history validation or live Google conformance was run. Value-table ORDER ordinals
remain a separate observed source/profile gap, not resolved by receiver precedence.
The full public-text Frontend objective remains active. Keep parent dependencies
and Draft; exact submitted-HEAD PR CI is recorded after publication. No manual
retry, Ready transition or merge.
