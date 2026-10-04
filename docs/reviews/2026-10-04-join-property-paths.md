# Object paths at the two-input JOIN boundary

## Scope and baseline

This branch starts at `3bcada80e678a8d7919d1129a6a1c282c543659c`, the
published HEAD of [#374](https://github.com/actql/actql/pull/374). Its underlying
main is `3c443c5bf3483170aa941feac767650a76b532f2`. The child depends on
#374's receiver-identity check for ORDER expression reuse; it does not copy
that fix. Integrate the parent before retargeting this PR to main.

The adopted [query scope](../spec/query-text.md#scope-and-lowering) and
[nullable property contract](../spec/query-text.md#infer-keep-source-projection)
already allow nested fields after resolving a visible column or range prefix.
SELECT siblings and WHERE use the input snapshot. Final ORDER uses evaluated
output aliases first and retains qualified inputs. The common checker owns
object types, missing members and nullable receiver propagation.

The two-input JOIN boundary had two gaps: it required every reference to be a
complete scalar column, and then used scalar-only expression lowering. Existing
JOIN-chain post-projection already uses the shared Pipe property path and is
not rewritten. Direct equality keys in ON retain their existing support profile;
property-derived ON keys remain a separate unconnected boundary, not a claim
that they are invalid GoogleSQL.

## Independent counterexample

```sql
SELECT l.payload.score
FROM objects AS l JOIN others AS r ON l.id = r.id;
```

The [complete handwritten three-stage Program](../../src/query_program/join_property_paths_test.mbt)
joins direct ID keys, carries the nullable object receiver and uses the existing
property expression before publishing only `score`. Ordinary checker acceptance
of that Program passed, while both SQL and equivalent Pipe lowering failed:
**1/3** baseline (`run-KXn66f`, `focused-test-Pnyasr`). The oracle was authored
before the product repair and is not obtained from compiler output.

The repair resolves the longest column prefix, retaining ambiguity failures,
and carries that receiver through the JOIN. The remainder lowers through
`append_with_properties`. Direct column projection remains direct. SELECT
expressions are computed once, ORDER aliases refer to those slots, and private
receiver/sort fields are removed before the public Result. ORDER's required
inputs use the same prefix precedence, so an alias receiver does not accidentally
retain or revive an input. The Stage Result pre-JOIN filter uses that same
existing expression entry. CTE capture, predicate sharing, assert, Effect,
checker, physical strategy, provider, Host and SDK are not modified.

## Acceptance obligations

The [public fixture](../../scripts/fixtures/join-property-source-input.mjs)
contains a complete independent JSON control and authored SQL/Pipe/DATA inputs.
Two right rows share ID 2, deliberately retaining JOIN multiplicity. Independent
expectations include nullable scores, implicit/quoted property names, WHERE's
input snapshot, selected-property receiver rebinding, qualified receiver control,
DISTINCT on selected expressions, LEFT JOIN's absent right object, typed empty
output and a pre-JOIN Pipe filter. Authored JOIN bounds remain 12.

With `payload.score AS original_score, r.other AS payload`, ORDER by the output
receiver must yield IDs **1,3,2,2**. The qualified input control instead yields
**2,2,1,3**. The original scores and object values are checked alongside the
order; a syntactic match cannot substitute SELECT's input receiver. The WHERE
case retains only input score 20 even though the projected receiver has score 5.

Five preparation refusals cover an ambiguous receiver, an unknown receiver,
a missing member, a scalar receiver and an input removed by DISTINCT. They must
retain the existing typed public input errors, zero durable Run admission and
zero provider I/O. Missing member/scalar errors are delegated to the common
checker rather than fabricated in the Frontend.

These cases are registered in the normal packed corpus. The focused command is
`node scripts/test-packed-public-query.mjs --join-property-only`; its selection
excludes unrelated native, graph, inference, restart and planner campaigns.
The existing public harness checks Named rows, complete ordered Result.describe
contracts (also on empty rows), internal-column exclusion, stream completion,
same-Run resend/lookup/attach and no additional acquisition. No lowered Program
is patched, no row is sampled to infer a type and no test-only Host route is used.

## Executed evidence

After repair, the new JS selection passed **9/9** (`run-XajraL`,
`focused-test-i71Zfs`). Existing/new JOIN callers passed **50/50**
(`run-B7JC5z`, `focused-test-3A0bBh`), including the added output-receiver
versus ambiguous-input assertion; these counts overlap. A CTE test first
used a bare GeneratedValues right input in a path requiring Stage Results;
both sides now explicitly bind CTEs, without changing CTE implementation or
expanding its current support claim. Two temporary test/compiler errors were
corrected before submission and are not execution passes.

Packed execution and submitted-HEAD CI are pending. This is implementation and
focused checker evidence, not yet a claim of public JOIN property execution.
No grammar, wire, schema, saved-data or contract-version changes. Corrected
sources produce their normal Program identities. Full Core, all targets, native,
proof, performance and a Google service differential run are not local checks
for this bounded unit. No merge is performed.
