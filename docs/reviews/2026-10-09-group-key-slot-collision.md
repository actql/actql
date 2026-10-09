# Computed GROUP keys and authored column names

Date: 2026-10-09. Owner: B. Base: `b40818e09295dba39de6b570b977610e95c75b1e`.
This repairs private-slot allocation under the existing query contract. It does
not reserve a new public identifier prefix or change grouping semantics.

## Counterexample and repair

An input Relation may legitimately contain `aql_group_key_0`. With that input,
the ordinary query below rejected with `UnsupportedGrouping`, although the
independently written Values/derive/GROUP/select/sort Program checks normally:

```sql
SELECT x + 1 AS bucket, COUNT(*) AS n
FROM t GROUP BY x + 1 ORDER BY bucket
```

The computed-key allocator in `compile.mbt` treated a collision with its first
private name as unsupported grouping. It also did not reserve SELECT output
aliases before choosing the private key. It now advances to an unused name,
checking input fields, earlier private keys and output aliases under existing
case-insensitive Frontend name resolution. Noncolliding allocations retain
their existing names. Expressions, grouping, projection, sort and checker
obligations are unchanged. No parser, common execution Owner, capacity limit,
schema/grammar pin, CTE, predicate, assertion or Effect path is modified.

## Independent expectations

The full Values Program independently specifies nullable x, unequal authored
values on two equal x rows, derive `x + 1`, COUNT, output projection and ascending
NULLS FIRST ordering. Input-name, uppercase-name and output-alias collisions
must have the same semantic Program. GROUP BY ALL, scoped Pipe AGGREGATE,
SET followed by grouping, and successive computed keys retain common checking.
Reading an ungrouped authored field in HAVING remains exactly
`Expression(UnknownReference)`; collision handling does not restore that field.

The public JSON control separately specifies one Source capture with `id > 0`,
the two-stage GROUP Program and Named Result. For input amounts 2, 1, 2, NULL,
plus excluded ID 0, the result is:

```json
[{"bucket":null,"n":1},{"bucket":2,"n":1},{"bucket":3,"n":2}]
```

Column order is bucket then n; bucket is nullable number and n is nonnullable
number. Authored output `aql_group_key_0` remains a public column when explicitly
requested; other private columns must not leak. An empty input returns no rows
with the same declared schema. Cases are registered in normal public acceptance
and the existing focused Group selection, not a new execution harness.

## Focused evidence

Pinned Node 22.22.0 / MoonBit 0.10.12+1634b282e, existing bounded/nonzero wrappers.
Evidence is retained in this worktree's ignored `_build` directories.

- Pre-repair: `run-uPnoDL` / `focused-test-CBGtXi`, 0/1,
  exact `UnsupportedGrouping`; independent JSON control checked first.
- First repaired expectations used an incorrect private sort-before-SELECT
  layout. The existing output-alias layout is SELECT then sort bucket. Only
  that independently authored layout was corrected, retaining the key, rows,
  types and order. A subsequent expectation helper used single replacement for
  a renamed COUNT column, leaving old references; changing it to replace all
  authored occurrences restored the complete expected Program. Intermediate
  diagnostic compile failures did not execute tests and are not passes.
- JS: `run-FQ32cO` / `focused-test-nl87t2`, **19/19**:
  `node scripts/local-checks.mjs test moon --timeout-seconds 240 -- --target js
  src/query_program/group_key_slot_collision_test.mbt
  src/query_program/sql_group_by_all_test.mbt
  src/query_program/pipe_group_key_alias_test.mbt
  src/query_program/group_property_receiver_scope_test.mbt`.
- Node: `run-lU7Mty` / `focused-test-MRoN13`, **2/2**:
  `node scripts/local-checks.mjs test node --timeout-seconds 120 --
  scripts/group-key-slot-collision-source-input.test.mjs`.
- Changed MoonBit files formatted; `git diff --check` passed.
- Refusal-specific JS: `run-YcM0No` / `focused-test-zSJbG4`, **7/7**,
  collision tests plus `group_numeric_literal_test.mbt`. The existing
  unselected DISTINCT sort key remains exactly `UnsupportedOrdering`; the
  invalid numeric value remains `Expression(InvalidNumber)`.
- Final refusal fixture Node check: `run-BYIe7L` /
  `focused-test-0GCq88`, **2/2**, same command above.

## Public acceptance and remaining work

The first normal five-package campaign used clean source
`5f0338a8bc6f81cbaface39b92acb59f5dd08940`, `run-1txtNX` and
receipt `public-query-evidence-yCbVKl`. All **20 Local positives** passed,
including the seven new cases and the independent JSON control. It stopped in
the existing negative cohort: the generic input-code allowlist does not include
the actual `ClientProgramImplementationLimit` for the unselected DISTINCT sort
key. HTTPS and subsequent refusals were not reached; this is not a full pass.
The fixture now checks that exact public implementation-limit code rather than
expanding the generic allowlist. The new ungrouped-field refusal separately
requires `ClientProgramInvalidInput`. Source, row/schema expectations and
product refusal conditions are unchanged. Logs and package digests are retained;
the failed campaign's temporary installation was reclaimed after evidence capture.

The revised campaign passed for clean source
`b7b6d8a8700b8cbe66b6a947a16edc077f26465b`, `run-VBCL4t`, receipt
`public-query-evidence-SeQcos`: **20 positives and 8 refusals on each of
Embedded Local and HTTPS**. The existing
`scripts/test-packed-public-query.mjs --group-select-scope-only` consumer installed
normal tarballs outside the repository with no MoonBit toolchain at runtime,
adapter overlay or post-lowering Program correction. Each success checks Named
Result values, complete describe columns/types/nullability/order, no extra hidden
fields, one Source acquisition where declared, same-request Run identity and no
additional acquisition on reread/reattach/resend. Refusals retain zero Run
admission and provider I/O. The same driver also passed 14 profile tests, the
Local/HTTPS README quickstart and the missing-generated-asset negative check.
Receipt status is passed/complete with no evidence errors; its temporary
installation was reclaimed after logs/digests were saved.

The bounded outer command runs the normal producer
`node scripts/packed-client-packages.mjs <owned-outside-checkout-directory>`,
independently verifies the manifest source and all five SHA-256 digests, then
runs the selected consumer above with `ACTQL_PACKED_CLIENT_PACKAGES` pointing to
those packages. The cooperative shared heavy slot and 1200-second budget were
maintained. Digests for the verified source are:

| Package | SHA-256 |
|---|---|
| client-wire | `18762bb0bf434d939ff153d485e2aed28f0fa3c77c9d1e82eee4983765947905` |
| sdk | `c468fa4d31016b3d10539f1edc49a113241a52a67d34493ff165bfac30ed102c` |
| run-host-core | `332a770a589f74f697fca8427c364da9b89dfc23c3fea9a1bd7c59c5d0e0401d` |
| local-node | `84c5beb80d0524257a1776b9d541cd030b67281cf1d1163db86122f3bb8d62dd` |
| node | `2989926be6f87295d48551e3c83e64dd6fb26f7b943e4004ad69176e19b98cda` |

## Integrated main evidence

After the campaign above, main advanced with #1080/#1082/#1083. Adopted main
`c1650812ed1aabb9b88527adb69f581d671e5aa7` was normally merged with no conflict;
no existing declaration or workflow was removed. The resulting clean integration
source is `9f918b30e24448a598b66d0e396e4320ae602912`.

- JS: `run-xvKVUj` / `focused-test-BxhX3o`, **23/23**, the four original
  selected files plus `group_numeric_literal_test.mbt`.
- Node: `run-WVhyJT` / `focused-test-ZkdlkV`, **2/2**, the fixture check above.
- Integrated normal five-package producer and the same selected public
  consumer: `run-pSFs2d` / `public-query-evidence-3nokEd`, **20 positives and
  8 refusals on each of Local and HTTPS**. Named Result/describe, input
  acquisition, same-Run resend, no extra I/O and refusal counters all passed.
  The receipt is passed/complete with no evidence errors and temporary
  artifacts reclaimed. The 14 driver profile tests, README and missing-asset
  negative check also passed.
- All five source/digest bindings were independently checked. client-wire,
  sdk, run-host-core and node digests are unchanged from the table above. The
  integrated local-node digest is
  `14e4ad5615c4e1686b2740e9e20ce29781d2a9fddd02fa6211d8026d540571b7`.

The following evidence-only commit records the integrated results; it is not
itself the source revision used for those packages. Submitted-HEAD CI must be
checked separately. Target branch is main, with no unmerged dependency; keep
Draft pending review and required CI, and do not merge here.

Full Core, Wasm/native, unfiltered packed acceptance, proof/performance and
submitted-HEAD required CI have not been run. This unit does not claim the
entire Frontend goal complete.
