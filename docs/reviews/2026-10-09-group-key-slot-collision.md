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

The revised normal five-package exact-source campaign using
`scripts/test-packed-public-query.mjs --group-select-scope-only` external
Local/HTTPS consumer remains pending. Preserve one Source read, Result.describe
types and column order, no extra hidden fields, same-request Run identity and
no additional acquisition on reread/reattach/resend; refusal must admit no Run
and perform no provider I/O.

Full Core, Wasm/native, unfiltered packed acceptance, proof/performance and
submitted-HEAD required CI have not been run. This unit does not claim the
entire Frontend goal complete.
