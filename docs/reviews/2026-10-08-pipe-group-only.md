# Pipe grouping-only AGGREGATE: existing common group connection

This Frontend unit connects an omitted aggregate expression list to the existing
`group` operation. It does not add a group executor, synthesize an aggregate,
alter limits, normalize NULLs or expose private key slots.

## Requirement and counterexample

The adopted GoogleSQL checkout is
`d82db99a923a46571f543a13899dc791a7b6f743` (`docs/pipe-syntax.md`, AGGREGATE).
Its aggregate expression list is optional. The ordinary ActQL group contract
(`docs/spec/language.md`, grouping) already accepts an empty aggregate map.

```aql
FROM pair |> AGGREGATE GROUP BY x
```

On the worktree baseline `ca39ec1a82c89a0e038af3862af4de8a383b26fb`, the
independently authored complete JSON Program passes the ordinary checker, but
this source is rejected by the parser. The pre-fix focused regression failed
1/1 (`_build/local-checks/attempts/run-eOwM8l`,
`_build/focused-evidence/focused-test-3DCmsC`). This establishes a missing
Frontend connection, not a group execution failure.

`QueryParser::pipe_tail` now distinguishes a leading GROUP clause from an
aggregate projection list, using the existing `group_keys`, Group AST and
lowerer. AGGREGATE without expressions or a GROUP clause is still malformed.
The grammar also records the existing parser's explicit `GROUP BY ()` form.

## Independent expectations

Complete Program fixtures are handwritten in
`src/query_program/pipe_group_only_test.mbt`. The common checker accepts the
JSON control before the source is compiled; full semantic Program bodies are
compared rather than inferred from product output. Plain, qualified and quoted
keys keep the same grouping meaning. After grouping, the original input range
is unavailable and predicates consume the new output scope.

The public corpus reuses `scripts/fixtures/group-property-source-input.mjs`
and the existing normal packed consumer. Nullable receiver and nullable field
values join the same NULL group; repeated keys create one group each. Expected
key-only rows are `[null, 10, 20]` in explicit NULLS FIRST order. The cases also
cover post-group WHERE/ORDER/LIMIT, empty typed groups, authored column order
and the old range refusal. Full Result.describe contracts and streamed rows are
checked by the unchanged consumer. No test patches the lowered Program.

For `GROUP BY ()`, the common group produces one empty object, including on
empty input. An explicitly authored `EXTEND 1 AS marker` then produces
`[{"marker":1}]`; it is not an implicit Frontend output. Both the JSON control
and source forms are included.

## Separate common Result boundary

A direct zero-column Named Result is **not** complete. The minimal source,
independent Program and unchanged expected `[{}]` / zero-column schema are
retained in `2026-10-08-pipe-group-only-zero-column.json`.

The independent Program without any final SELECT is rejected at
`Source(SourceView(Program(Program(Results(_, InvalidBody)))))`.
`relation_results/check.mbt::closed_fields` requires a nonempty result field
list. A focused regression records that exact owner boundary; it does not
assert that a zero-key group is invalid or redefine the target language.
Direct source lowering also emits an empty final SELECT, while the common
select contract requires a nonempty selection. Supporting direct zero-column
publication therefore needs an explicit common Result contract/consumer unit,
plus omission of a redundant empty Frontend projection. It must preserve the
empty object's row count, not invent a public sentinel column. No such common
contract change is included here. The direct zero-column source-to-Host path
has not been executed; the recorded rejection is checker evidence.

## Pins and verification

The generators update the grammar manifest, embedded manifest, normative
imports and generated canonical vector. Independent sorted-key preimages
retain predecessor identities and derive the new grammar and Values Run CIDs:

| Identity | Before | This unit |
|---|---|---|
| Grammar manifest | `sha256:e14a88db3f98d88cb24edefca31ecd1c0d63f81e152a61d464756a83c5850329` | `sha256:bb311179f5afee3d6e03181b66113f045cbd6190ce4174b32d40ac9a67459a8d` |
| Ordinary Values Run | `sha256:3ed63e2c45d68425784a904b0378099fe284027a35e2c3e78d016bdc854f6903` | `sha256:af4b746a75926ddcf8a506348a9df55147a10bf9c0b64e4f950d0ec6d513e9d5` |

The source/Program value laws, Unit and ResultPlan contracts are unchanged.
The changed grammar closure affects Run identity; old vectors remain historical
and old Runs are not relabeled with the new pin. Expected CIDs are derived from
independent complete preimages, not copied from an issued runtime result.

Focused JS/Node evidence before main integration:

- Parser: 3/3. Lowering/checker: 3/3 (`run-06MCXO`). Separate common
  zero-column Result rejection: 1/1 (`run-6DEFMZ`).
- Final pin/caller guard `run-MlZCR8`: Node vectors/profile checks 28/28,
  Values Run caller 1/1, canonical grammar caller 1/1. Read-only
  compilation-manifests, document metadata, spec family and canonical checks
  pass; 377 canonical identities verified.

A fresh exact-SHA five-package Local/HTTPS acceptance remains to be run after
normal main integration. Its result and package digests will be recorded in the
PR body without claiming that pre-integration checks prove the submitted HEAD.
Full Core/all-target/proof/performance checks are not rerun locally. Draft CI,
required final CI and the broad Frontend completion goal remain separate.
