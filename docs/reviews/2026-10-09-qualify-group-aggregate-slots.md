# Grouped aggregate aliases in QUALIFY and ORDER windows

## Boundary and counterexample

Initial main baseline: `c3e71b879989f82aab45508ff70112a91da165a9`.
This repairs the existing query-text alias rules, not a new language contract.
QUALIFY and query ORDER windows prefer evaluated SELECT aliases; qualified
input references keep their input meaning. SELECT-owned window specifications
continue to use the SELECT input snapshot.

```sql
SELECT t.x AS original, COUNT(*) AS x,
       ROW_NUMBER() OVER (ORDER BY t.x) AS rn
FROM t GROUP BY t.x
QUALIFY x > 1
ORDER BY original
```

For independently authored input `[{x:1,y:20},{x:1,y:21},{x:2,y:10}]`, the
expected row is `{original:1,x:2,rn:1}`. The two groups have counts 2 and 1.
Reading the retained input key instead of COUNT would retain the other group.
The independent complete Program passes the ordinary checker. Before repair,
the compiler emitted a filter on `x` instead of its evaluated aggregate slot.
This is a confirmed lowering counterexample; a wrong published Run was not
executed before repair.

The same alias materializer is used by inline windows in query ORDER BY:

```sql
SELECT t.x AS original, COUNT(*) AS x
FROM t GROUP BY t.x
ORDER BY ROW_NUMBER() OVER (ORDER BY x DESC), original
```

Descending COUNT orders original keys 1 then 2. The qualified-input control
`ORDER BY ROW_NUMBER() OVER (ORDER BY t.x DESC), original` orders 2 then 1.
Both complete expected Programs are handwritten; product output does not
generate them.

## Repair and independent controls

GROUP already records authored aggregate names and their evaluated output
slots. Pass that mapping to `materialize_clause_aliases` from QUALIFY and
ORDER-window callers. The materializer reuses those slots instead of assuming
an authored alias is its physical field. No COUNT reevaluation, new executor,
capacity adjustment, parser change or common contract/pin change is required.

Focused controls cover case-insensitive and backtick aliases, qualified input,
noncolliding aliases, ordinary checker admission, and discarded input columns.
Discarded QUALIFY expressions retain `Expression(UnknownReference)`; direct
discarded window keys retain `UnknownColumn` through the existing analytic key
resolver. No input is restored after grouping.

The public fixture adds three independently authored JSON Programs and nine
text counterparts/contrasts to the existing QUALIFY corpus. Expectations cover
duplicate COUNT contributions, nullable grouping keys versus nonnullable
COUNT, empty typed Results, alias versus qualified-input ordering, declared
column order, and hidden slot exclusion. Two new refusals require the existing
`ClientProgramInvalidInput` classification. The existing public consumer checks
Result descriptions, rows, admission/I/O and request reuse. Both ordinary and
`--qualify-only` corpora use the same fixtures; no new acceptance driver exists.

## Evidence

- Pre-repair: `run-KEuyh5` / `focused-test-AN770H` failed the complete Program
  comparison. The initial control placed SELECT before sort; it was corrected
  to the existing scoped sort-before-final-projection layout without changing
  values, predicate or ordering.
- Pre-repair: `run-BbCE18` / `focused-test-Nv73cd` then failed the explicit
  assertion that QUALIFY must read COUNT rather than the retained input key.
- Repaired focused JS: `run-ByoPhC` / `focused-test-df9T39`, 30/30 passed.
  Selection: `qualify_group_aggregate_slots_test.mbt`, `qualify_test.mbt`,
  `quoted_qualify_test.mbt`, `group_select_input_scope_test.mbt`, and
  `order_window_expression_test.mbt` under `src/query_program`.
- Fixture and ordinary/narrow corpus registration: `run-j1A315` /
  `focused-test-JdMZsv`, `scripts/qualify-source-input.test.mjs`, 3/3 passed.
- While adding the ORDER control, a string assertion incorrectly assumed
  noncanonical JSON member order. It was replaced by a complete independent
  Program comparison, not a change to the expected public order.

All commands use `scripts/local-checks.mjs`, the pinned Node/MoonBit toolchain,
finite time budgets and the nonzero-test guard. Formatting and `git diff
--check` are checked before publication.

## Integration and public delivery evidence

Normally merged main `87e2debf6a8724bb453fb2b83caf622d39f11c7c` (including
the separately merged computed GROUP-key collision repair). No conflicts or
unmerged dependencies remain for this unit. Verified integrated source and
normal five-package producer revision:
`e2a61b126b7393274fcb29cc1e2c3da9f70273b0`.

- Integrated focused JS: `run-Telq2B` / `focused-test-qvc8j9`, 34/34 passed.
  The earlier five-file selection plus `group_key_slot_collision_test.mbt`
  checks the allocator boundary changed by the main merge.
- Integrated Node: `run-ZfhiXq` / `focused-test-UHuyfF`, 5/5 passed.
  Selection: `scripts/qualify-source-input.test.mjs` and
  `scripts/group-key-slot-collision-source-input.test.mjs`.
- Bounded producer/digest/public-consumer invocation: `run-SKAMoM`, exit 0.
- Consumer receipt: `public-query-evidence-X3DGvP`, revision above,
  `status: passed`, `complete: true`, ten commands all exit 0, no signal,
  `evidenceErrors: []`, `artifactsRemoved: true`. The successful temporary
  installation was removed after evidence preservation.
- Packed Embedded Local and remote HTTPS each passed 32 positive cases,
  10 refusals, and one deliberately failing demanded-expression case. The
  standard profile runs 31 positives and all refusals/failure; the existing
  analytic-property profile runs the remaining positive. All 12 new grouped
  positive cases and both new refusals pass through the standard public Host.
- The public consumer compares Named Result rows and `describe().columns`
  exactly, including column order and nullability for empty Results. All new
  source cases acquire once. Reattach, Result reread, resubmit and submission
  lookup retain the Run and counters. Refusals preserve zero Run admission and
  zero Source I/O. Expected Results contain no private group/window slots.
- The driver's existing profile controls passed 14/14. Its README Local/HTTPS
  quickstart and missing-generated-asset negative control also passed.

Evidence root:
`/Users/t14i/workspace/20260822/worktrees/.codex-scratch/public-query-evidence-X3DGvP`.
Public application stdout/stderr/result are `010.stdout.log`,
`010.stderr.log`, and `010.result.json`. The summary retains source identity,
package digests, child exit/status/timing and cleanup outcome.

Normal producer directory:
`/private/tmp/actql-b-qualify-group-aggregate-slots-pack`.
The manifest revision matches the clean checked-out source; SHA-256 was also
checked independently against every tarball before the consumer started.

| Package | SHA-256 |
|---|---|
| client-wire | `18762bb0bf434d939ff153d485e2aed28f0fa3c77c9d1e82eee4983765947905` |
| sdk | `c468fa4d31016b3d10539f1edc49a113241a52a67d34493ff165bfac30ed102c` |
| run-host-core | `332a770a589f74f697fca8427c364da9b89dfc23c3fea9a1bd7c59c5d0e0401d` |
| local-node | `d9f38b888b235065ea183724b7f9c59326a00e327b5a3b574f043b64ccc15218` |
| node | `2989926be6f87295d48551e3c83e64dd6fb26f7b943e4004ad69176e19b98cda` |

The actual bounded orchestrator is retained at
`/private/tmp/actql-b-qualify-group-aggregate-slots-packed.mjs`. It validates
the shared heavy-check owner while waiting, pins the checkout revision, and
runs these normal commands sequentially with a 1,200-second budget:

```sh
node scripts/packed-client-packages.mjs /private/tmp/actql-b-qualify-group-aggregate-slots-pack
# Independently compare the manifest revision and all five tarball digests.
ACTQL_PACKED_CLIENT_PACKAGES=/private/tmp/actql-b-qualify-group-aggregate-slots-pack \
  node scripts/test-packed-public-query.mjs --qualify-only
```

The command uses pinned Node `22.22.0` and MoonBit `0.10.12+1634b282e`, normal
prepack hooks, an external private consumer and the existing nonzero/bounded
guards. No dependency overlay or post-lowering correction is used.

## Remaining verification

The evidence-recording commit changes this report only. Its submitted HEAD
must not be described as a newly packed revision; the verified source remains
the explicit integrated SHA above. Exact submitted-HEAD Actions status will be
reported separately in the PR. Full Core, Wasm/native, proof, performance and
full packed corpora have not been run locally for this change. No merge or
manual CI rerun is performed.
