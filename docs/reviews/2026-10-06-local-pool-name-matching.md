# Bounded Pool reference-name matching

## Scope and ownership

This component starts at #581,
`e217a5840377068a9172277f94f1ff12476f4ae2`. The parent is unmerged;
the eventual destination remains main. It closes Pool input role matching
and output group-name search, not every retained Local boundary.

Pool previously flattened each reference name and compared the complete
String while binding a field. Output construction also scanned every group
name in one transition. Stepped value admission and record emission did not
bound these earlier algorithmic scans.

The same Pool Session now retains one private name offset. The shared
`relation_schema.compare_reference_fragment` compares at most 64 raw UTF-16
code-unit pairs while borrowing qualification and spelling. It proves only
reference-spelling equality, not typed-role equality, admission or identity.
Those guarantees remain with the existing checked input and record owners.
No data normalization, second evaluator or name-sized buffer is introduced.

Input component, group and identity phases retain the current field between
fragments. The first component fragment occupies the original binding poll;
only further fragments add control work. Output construction reuses the
existing group probe, with at most eight probes and 64 compared pairs per
poll. Component/count/group/one-group alias precedence remains unchanged.
Different-length names do not need a content scan.

One position slot is reserved before input reads or output allocation. Stop
requests do not release it or the current field: confirmed Session stop is
followed by the existing separate cleanup, once. Input owners remain live.
Logical record construction work and short-name control schedules are
unchanged; long/wide searches add cumulative, quantum-independent polls.

## Independent boundaries and negative evidence

- The 8,096-unit group has 127 fragments. The scalar Carrier fixture needs
  61 polls; seven retained binding/wire scans and two Pool name scans add
  nine times 126: control 1,195/1,194. Construction stays 18; workspace is
  15 structural plus 56 retained append plus one position: 72/71.
- Array-90 and a 513-unit group require control
  `592 - 2*(257-90) + 9*8 = 330`, not the former 314. Workspace is
  18 structural + 13 recheck + 35 append + one position = 67/66.
- Moving Array-116 before that group adds `2*(116-90) = 52`: 382/381.
  Setup is 3 initialization + 238 Array read/recheck/matches + 8 Vector
  read/recheck/matches + 3 group read/recheck = 252. Name matching begins
  at 253; Host poll 256 retains offset 256 before any collected record.
  Quanta 1, 7 and 256 keep both exact work and typed one-short failure.
- Private fixtures stop inside input identity/group/component and output
  group/component scans, with offset 64. Cleanup before confirmed stop
  refuses; the offset/current field survive, then cleanup clears them once.
  A nine-group fixture yields before completing its output search, checks
  each independently specified group value, and stops at that boundary.
- Replacing input fragment advancement with a synchronous drain makes the
  actual scan-custody fixture fail: 1/2 passed, 1 failed, `run-Whu0Cn` /
  `focused-test-N0H56e`. The mutation was removed before runtime generation.
- Existing registered Relation Pool caller tests still used the pre-parent
  append premise 45. Current append is 16 fixed/name + 9 field
  snapshot/bucket/link + 1 identity + 30 depth-stack slots = 56. Their
  reservation is independently corrected to `18 + 20 + 56 + 1 = 95/94`.
  Eleven slots belong to the parent field-binding change; only one is new
  here. Their unchanged control boundary remains 72/71.
- Required Pool gate roles now include the real common comparison, input/
  output scan custody, wide search, independent limits and installed Host
  barrier. Missing roles, missing public evidence or mapping the common
  fixture to a foreign package are rejected. Declared target coverage is
  not a claim that those targets were executed locally.

## Executed candidate checks

The focused shared/Pool JS selection passed 65/65 (`run-ZyMZQf`,
`focused-test-cQySQy`). The affected registered caller boundary selection
passed 3/3 (`run-qIA7gq`, `focused-test-SAAeuM`) after the independent
reservation correction. An earlier wider Pool name selection timed out
at 120 seconds (`run-vRuRmV`); it is not counted as successful evidence.
The subsequent narrower diagnostic showed the stale caller premise, not a
reason to increase product limits.

Only local-node and run-host-core were rebuilt from the restored source
inputs. The new public input-name barrier, existing retained field-binding
and Object-name cases, and gate mutations passed 4/4 (`run-JfEqZE`,
`focused-test-40I8lT`). They use ordinary JSON Program preparation/submit,
real retained output, three explicit Named Results, two consumers, repeated
request reuse without another dispatch, and requested cancellation before
physical stop confirmation. Literal expected rows include the complete
513-unit group name, `[1,2]` and member count 1.

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 120 -- --target js \
  src/relation_schema src/local_veca \
  src/query_integration/pool_field_binding_wbtest.mbt \
  src/query_integration/pool_member_encoding_wbtest.mbt \
  src/query_integration/pool_object_name_recheck_wbtest.mbt \
  src/query_integration/vector_input_recheck_wbtest.mbt
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js \
  src/query_integration/local_carrier_vectors_wbtest.mbt --index 64-67
moon info --target js,wasm,native src/relation_schema
npm run build:runtime-packages -- local-node run-host-core
node scripts/local-checks.mjs test node --timeout-seconds 90 -- \
  --test-name-pattern 'input group name matching|retained field binding|typed Object name admission|Pool output requires' \
  adapters/host-node/public-pool-key-retention.test.mjs \
  scripts/check-local-resource-accounting.test.mjs
node scripts/check-local-resource-accounting.mjs
```

The interface inspection reported no backend divergence; it is not execution
on Wasm/native. Runtime bundles are ignored artifacts, not tracked source.
Node Host and Workers freshness checks passed with the pinned MOON_HOME;
their generated files needed no changes. Changed MoonBit files were formatted
individually and `git diff --check` passed.
Clean committed-SHA receipts and the automatic Draft CI state are recorded
in the PR separately from candidate and negative-mutation checks.

## Residuals

Preparation/schema lookup, runtime JSON identifier normalization, legacy
synchronous drains and runtime StringBuilder assembly remain separate
boundaries. Aggregate intermediate bytes and whole-Run physical accounting
are not proved by these structural slot fixtures. This does not establish
qualified public Program, packed Local/HTTP, all fault/retry, full Core,
Wasm/native execution or required CI acceptance. Other operators' matching
and remaining retained paths must be closed at their existing owners; this
component is not Local Compute completion.
