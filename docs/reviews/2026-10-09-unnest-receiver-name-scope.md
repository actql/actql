# UNNEST original receiver and same-named field

Status: Frontend repair, selected compile/check verification and fresh packed
Local/HTTPS acceptance complete at the recorded clean source. Submitted-HEAD
required CI remains unverified. This is a focused unit,
not completion of the full GoogleSQL/Frontend profile.

Adopted main: `802a947220cd6cae9f09dcd499669cd1cae48881`, including #1077/#1078.
Implementation commit: `3a1a3d004bf33133cc84f03589d2c9e9a71114c2`.
Refusal fixture correction: `fd0bea1fd2e6e0b731aaedca3f106a1aa2e797af`.

## Requirement and independent counterexample

The selected [GoogleSQL range-variable rules](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#range_variables)
make a value-table alias denote its original row value. The pinned primary
resolver distinguishes that range from its exposed fields:
[NameScope at d82db99a](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/googlesql/analyzer/name_scope.cc#L224).
`NameList::AddValueTableColumn` registers the alias as a range;
`NameScope::LookupName` does not replace an existing range with an implicit
value-table field. This is source/reference inspection, not a live differential
run against a Google service.

```sql
SELECT element AS original, element.element AS field_value, position
FROM UNNEST(@items) element WITH OFFSET position
ORDER BY position
```

`items` is a bounded nullable ARRAY of nullable closed objects. The object
contains nullable numeric `element` and nonnullable numeric `id`. Input:

```json
[{"element":null,"id":2},null,{"element":9,"id":1},{"element":9,"id":1}]
```

Independent expected rows, in offset order:

```json
[{"original":{"element":null,"id":2},"field_value":null,"position":0},
 {"original":null,"field_value":null,"position":1},
 {"original":{"element":9,"id":1},"field_value":9,"position":2},
 {"original":{"element":9,"id":1},"field_value":9,"position":3}]
```

The independent full Program selects the UNNEST object slot for `original`
and the ordinary property slot for `field_value`. It passes the common checker.
Before repair the first SQL comparison failed: 0/1, guard `run-ETYTfp`, focused
receipt `focused-test-yaCh5S`. The spelling variants followed that comparison
in one test and were not separately executed before repair. Pre-repair public
execution was not performed; the failure is actual compile/Program comparison,
with the wrong receiver identified by source inspection.

## Cause and minimal repair

`query_program/unnest_source.mbt::unnest_expression_columns` previously kept a
visible field when its name collided with a whole-value receiver. Both bare
range references and explicit parenthesized object receivers could consequently
resolve to a scalar property slot instead of the original object.

The helper now removes colliding fields from its expression-only lookup copy
and supplies the original receiver. It uses existing `same_name`; it does not
normalize user values or machine property names. The actual visible-field list
is unchanged, so plain and qualified stars still expand numeric `element`,
nullable `id` and the offset. SET can change that current numeric column while
the range still denotes the original object. SELECT and AS still terminate the
old range scope. Ordinary checking determines every object/member contract.

No grammar, schema, law, pin, public interface, capacity limit, planner, provider,
serialization or execution Owner changes. The generated collision Program
changes because its reference is corrected; existing machine Program meaning
and canonical identity rules are unchanged. No compatibility fallback is added.

## Selected verification and existing diagnostic fixture

Pinned Node 22.22.0 and MoonBit 0.10.12+1634b282e were used.

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 240 -- --target js \
  src/query_program/unnest_receiver_scope_test.mbt \
  src/query_program/unnest_struct_star_test.mbt \
  src/query_program/unnest_parameter_path_test.mbt \
  src/query_program/unnest_source_test.mbt \
  src/query_program/unnest_join_continuation_test.mbt \
  src/query_program/correlated_unnest_test.mbt
node scripts/local-checks.mjs test moon --timeout-seconds 120 -- --target js \
  src/query_program/unnest_checked_array_test.mbt
node scripts/local-checks.mjs test node --timeout-seconds 120 -- \
  scripts/unnest-source-input.test.mjs \
  scripts/unnest-checked-array-source-input.test.mjs
```

- Receiver and affected callers: **24/24**, `run-ToK4A8` / `focused-test-mcv49V`.
- Existing exact unresolved/type refusals: **3/3**, `run-69VUAd` / `focused-test-qYAGCS`.
- Fixture controls and normal-corpus registration: **7/7**,
  `run-QLLCsz` / `focused-test-dX15bB`.
- Both changed MoonBit files match the pinned formatter; whitespace check passes.
- An intermediate selection used a nonexistent test filename and ran zero tests:
  `run-iJPovD` / `focused-test-WF5JOG`. The corrected selection above passed;
  the selection failure is not a product failure or verification success.

Initial clean five-package acceptance at `3a1a3d004...` reached all 65 Local
positive cases, including the 12 new receiver cases. It stopped in the existing
unresolved ARRAY-star refusal phase; HTTPS was not reached. Guard `run-sgoAW7`;
receipt `worktrees/.codex-scratch/public-query-evidence-OpPydn`.

The cause is a stale generic fixture error set, not the receiver fix.
`unnest_checked_array_test.mbt` independently requires `UnsupportedProjection`
for `[]` and `[NULL]`, `TypeMismatch` for mixed/wrong declared types and
`UnknownColumn` for scalar qualified star. The documented finite Number profile
does not invent GoogleSQL INT64's unresolved empty-array default. The current
public preparation Owner projects unsupported checking as
`ClientProgramImplementationLimit`.

The fixture now checks exactly that code for the two unresolved cases, and
`ClientProgramInvalidInput` for the three genuine type/name violations. The
Owner, generic error whitelist, source inputs and positive expectations are
unchanged. The follow-up commit changes only these two fixture/test files.
MoonBit source used by the recorded selected checks is identical at both
implementation and follow-up commits; the checks are not relabeled as fresh
submitted-HEAD executions.

## Public acceptance

Clean tested source: `fd0bea1fd2e6e0b731aaedca3f106a1aa2e797af`.
Normal five-package producer and existing scoped consumer were executed under
`local-checks-guard.mjs` with the shared heavy-work lock and a 1,200-second budget.
Guard `run-8kzKsS` completed successfully, with output/caller capture complete
and both locks released. No overlay, revision override or skipped prepack was
used. Executed commands include:

```sh
node scripts/packed-client-packages.mjs /private/tmp/actql-b-unnest-receiver-fd0bea1fd-pack
ACTQL_PACKED_CLIENT_PACKAGES=/private/tmp/actql-b-unnest-receiver-fd0bea1fd-pack \
ACTQL_TEST_NPM_CACHE=/private/tmp/actql-b-unnest-receiver-fd0bea1fd-pack/npm-cache \
  node scripts/test-packed-public-query.mjs --unnest-source-only
```

Receipt: `worktrees/.codex-scratch/public-query-evidence-rvjVUi`.
All ten command receipts record the same clean source, exit/verification status
0, no signal/error and complete output. The successful consumer installation
was outside the checkout and was removed by the existing evidence owner;
receipts and logs remain. Each transport passed **65 positives / 25 preparation
refusals**, including 12 new positives and three exact new invalid-input refusals.
The initial failing attempt remains separate evidence, not a HTTPS success.

The unchanged public application checks Named Result values, ordered columns
and complete Result.describe contracts, including the nullable original object,
its nonnullable inner id, and nullable projected fields. It compares complete
rows to independent fixtures, checks no hidden columns, preserves duplicates
and requires zero acquisition for the new source-free cases. Reads, attach,
resubmit and lookup preserve the Run and cause no additional acquisition.
Preparation refusals leave Run admission and Source I/O counters unchanged.
Twelve refusals have individual exact-code success logs per transport; 13 older
generic refusals are proven by the complete unchanged application loop, not
individual named code logs.

A separate read-only audit rehashed actual tarballs against both the producer
manifest and receipt, checked every positive name and every exact-code refusal
in both transport logs, and checked command completion/cleanup:
`/private/tmp/actql-b-unnest-receiver-fd0bea1fd-acceptance-audit-20261009.{mjs,json}`.
Producer/consumer wrapper:
`/private/tmp/actql-b-unnest-receiver-fd0bea1fd-packed-20261009.mjs`.

| Package | Actual SHA-256 |
|---|---|
| client-wire | `18762bb0bf434d939ff153d485e2aed28f0fa3c77c9d1e82eee4983765947905` |
| sdk | `c468fa4d31016b3d10539f1edc49a113241a52a67d34493ff165bfac30ed102c` |
| run-host-core | `332a770a589f74f697fca8427c364da9b89dfc23c3fea9a1bd7c59c5d0e0401d` |
| local-node | `2eb428d7bd7e4f0e82b5c7c9b4958d96c73a1b766c0a1782bf60b74ab63363c6` |
| node | `2989926be6f87295d48551e3c83e64dd6fb26f7b943e4004ad69176e19b98cda` |

The preceding failed attempt's same five runtime byte digests are unchanged by
the fixture-only correction, but its manifest and partial acceptance stay bound
to its own source revision. The final evidence document is a subsequent
metadata-only commit; these packages are not relabeled as built from that HEAD.

The driver also completed its existing 14 selected profile/scheduling probes,
README Local/HTTPS example and deliberate missing-asset check. This is not a
full packed campaign or complete backend verification.


## Coverage limits

Submitted-HEAD required CI, full Core, Wasm/Native execution, full packed,
proof/performance, Cloud and all GoogleSQL value-table forms are unverified.
The new cases are part of the ordinary packed corpus and its existing scoped
UNNEST consumer, not a private compiler adapter. No PR merge or CI rerun was
requested by this work.
