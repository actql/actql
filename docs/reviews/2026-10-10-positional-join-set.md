# Positional JOIN set operands: shared SELECT connection

## Counterexample and existing meaning

Initial main: `ab69cd06a94b1c5a998521435e61c9f201a5c9a9`.
Initial implementation parent: #1240,
`ca6436aae9b14267052cdca2b3761358bdad0207`.

```aql
SELECT 0 AS n
UNION ALL
SELECT l.x + r.k FROM t AS l JOIN r ON l.x = r.k
ORDER BY n
```

For `t.x = [1,2]` and `r.k = [1,2]`, the independently expected ordered
result is `[{"n":0},{"n":2},{"n":4}]`, with a nonnullable number column.
The named right-operand control (`AS n`) passes the ordinary checker. The
anonymous operand fails with `UnsupportedJoin` before the patch
(`run-gBU6om`, `focused-test-hD4H1i`). This establishes a frontend connection
defect, not an execution-owner failure.

The adopted [GoogleSQL set-operator rules](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax.md#set_operators)
pair ordinary set operands positionally, retain the first operand's names, and
preserve UNION ALL multiplicity. No new public name or alias rule is introduced.

## Minimal repair and independent controls

Forward the existing positional-output flag through the script JOIN entry and
JOIN-chain tail into the shared SELECT compiler. Only a positional operand with
an anonymous terminal SELECT needs to leave the existing single-JOIN named
projection specialization. Named ordinary JOINs retain their specialized path.
The first operand, BY NAME, nonterminal anonymous projections and unrelated
CTE definitions receive no new permission.

The product changes twelve lines and removes one in
`query_script_program.mbt`, `query_join_bindings.mbt` and
`query_join_chain.mbt`. Existing JOIN, expression, ordinal alignment, append,
sort, checker and execution owners retain their contracts. No acquisition,
physical task, wire, grammar, limit or fallback implementation is added.

- An independently authored complete Values/JOIN/derive/append/sort Program
  fixes the same `0,2,4` result. It is checked directly; it is not generated from
  or appended to frontend output.
- CTE, DATA and two-JOIN lowering controls preserve every explicit test ceiling
  of seven and pass the ordinary checker.
- BY NAME asserts `UnsupportedJoin` specifically. Final references to `l.x`,
  `r.k` and the actual internal `aql_chain_column_2` assert `UnknownReference`.
- Public controls retain the original Source rows, one shared acquisition,
  key equality and JOIN ceiling ten. The anonymous right side selects
  `l.id + r.id, r.amount + 0` under `l.id >= 2`. The independent sorted rows are
  one `{id:1,amount:10}`, four `{id:4,amount:20}`, and one
  `{id:6,amount:null}`. Incorrect alias alignment, duplicate elimination,
  predicate loss or NULL substitution changes these results.
- Independent JSON, named text, anonymous text, CTE output and typed empty
  controls use the existing public registration and packed consumer. BY NAME
  and private-slot refusals retain their exact existing public classifications
  and zero Run admission/provider I/O requirements. Rows, describe contracts,
  declared column order, hidden-field absence, resend and reread are checked
  by the existing harness, without patching generated Programs.

## Focused verification before main integration

- JS JOIN/set/DATA/chain callers: 22/22 (`run-D9LkXb`,
  `focused-test-ebl4VC`).
- Node fixture/profile registration: 41/41 (`run-RONL7E`,
  `focused-test-Yy1JXB`).
- Final actual-private-slot refusal and independent Program selection: 4/4
  (`run-0ZMp5m`, `focused-test-u7eYAS`).

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js src/query_program/positional_join_set_test.mbt src/query_program/set_join_entry_test.mbt src/query_program/data_join_test.mbt src/query_program/join_chain_test.mbt
node scripts/local-checks.mjs test node --timeout-seconds 180 -- scripts/set-join-source-input.test.mjs scripts/set-corresponding-source-input.test.mjs scripts/public-query-profiles.test.mjs
```

The existing `--set-corresponding-only` consumer now contains 39 cases: 25
normal and 14 refusal cases. All are also registered in ordinary packed
acceptance. Normal clean-SHA five-package production and this scoped
Embedded Local/authenticated HTTPS consumer remain required; parser/checker
success above is not public execution evidence. Main integration, actual
package identities and public receipts are recorded separately below.
Full Core, Wasm/Native, the complete packed corpus and hosted CI have not been
run locally for this unit. The wider frontend goal remains active.

## Main integration and submitted state

Both #1240 and #1241 are merged. Main
`ce027a937cf780f617d5ed98bb4d56ecbb010877` was normally merged as
`8cbd23561836af5d93ea35d676dc9ced2abe9aa7`. The only conflicts were the
authored fixture inventory and its explicit count/baseline assertions. Both
main's aggregate scope cases and these JOIN cases remain registered, with no
workflow or historical declaration changes. The combined inventory has 3,310
occurrences and digest
`a9b33dd6c2c27513b90d0d33f96e97bb1dee601f17527639a2cbc16713a51896`.
This digest enumerates authored inputs and expectations; it does not derive
expected values from product output.

At that clean integration SHA, the same selected JS callers passed 22/22
(`run-1MxL73`, `focused-test-F5fHQ7`) and selected Node checks passed 41/41
(`run-yekO1E`, `focused-test-Ha1945`). An initial wrapper attempt lacked the
MoonBit executable (`run-xauZ28`) and executed no tests. The subsequent run
used the repository-pinned MoonBit/Node environment; the failed discovery is
not counted as a passing check.

The exact-SHA normal-pack/39-case consumer was requested with
`/private/tmp/actql-b-positional-join-set-packed.mjs`. Its 60-second bounded
slot wait verified G's active gate using the recorded PID and actual worktree
cwd, retained the shared lock, and exited 75 without starting either the
producer or consumer. This is scheduling deferral, not a product failure or
public acceptance success. No five-package distribution or Local/HTTPS receipt
for this JOIN fix is claimed yet. The Draft targets main and has no unmerged
dependency. Public acceptance and submitted-HEAD required CI remain incomplete.

```sh
node scripts/packed-client-packages.mjs /private/tmp/actql-b-positional-join-set-8cbd23561-pack
ACTQL_PACKED_CLIENT_PACKAGES=/private/tmp/actql-b-positional-join-set-8cbd23561-pack node scripts/test-packed-public-query.mjs --set-corresponding-only
```

Those commands are the pending producer/consumer steps, not executed evidence.
The wrapper adds the exclusive gate, pinned tools, 1,200-second aggregate
deadline and independent verification of the source revision and all five
tarball digests. A later documentation-only evidence commit must preserve the
actual tested source SHA rather than relabel older success as new-HEAD success.

## Actual packed failure and capacity handoff

The scheduling deferral above is historical. Normal five-package production
and the scoped public consumer subsequently ran at the combined diagnostic
revision `81250607ee8621659276653afa6c9bbc1fc680e3` (`run-jIjmTT`).
The retained [package manifest](fixtures/positional-join-set-capacity/packed-client-packages.json)
records that revision and all five SHA-256 digests. This revision also contained
the independently delivered Graph-row set changes; they are now separated in
[Draft #1248](https://github.com/actql/actql/pull/1248). No old Graph conversion
or fallback is involved.

The pristine public receipt is
`../.codex-scratch/public-query-evidence-NkA5An/{summary.json,010.stdout.log,010.stderr.log}`.
Earlier existing cases and the authored anonymous JSON control passed both
transports. The first new named text control,
`set-join-anonymous-named-control`, failed on Local with
`ACTQL_E_UNPUBLISHED_RUN`. Its HTTPS sibling was cancelled; later cases and
complete cohort inventories were not verified. The receipt is failed/incomplete,
not successful acceptance. Both children terminated and the harness reclaimed
its owned installations.

The saved named and anonymous [generated Programs](fixtures/positional-join-set-capacity/)
are actual frontend output, not independent expected vectors. The accompanying
source and expectation record is copied from the unchanged authored fixture.
The independent JSON control remains in
`scripts/fixtures/set-join-source-input.mjs`; it is never generated from these
Programs. Both generated forms retain one Source capture, predicates,
JOIN equality, explicit ceiling ten, computed expressions, append and ordering.

A subsequent minimal diagnostic used the verified revision's tarballs in a
private installation, with cause-only logging in `client-dispatch-owner.mjs`
and `strategy-bundle.mjs`. It changed no dispatch or capacity decision. This
logging overlay is diagnostic evidence, not pristine packed acceptance. The
final run is `run-P6J0xP`, using
`/private/tmp/actql-b-join-set-diagnostic-check.mjs` and
`/private/tmp/actql-b-join-set-public-diagnostic.mjs`. Retained observations,
DB and Store are at `/private/tmp/actql-b-join-set-diagnostic-zIsas8`.
The private installed packages are at
`/private/tmp/actql-b-join-set-diagnostic-UfFh8g`. Do not commit their
authorization material or delete their custody records.

Named text and its exact generated JSON both acquired the Source successfully
and then failed at `adapters/local-node/strategy-bundle.mjs::runPrepared`,
when calling `strategyModule_local_ManagedStart`. The underlying source variant
is `LocalManagedStart(Execution(Physical(ExecutionLimit)))`. Public unpublished
Run / `CapturedRunPublicationFailed` observations are terminal symptoms.
For task one the logged retained requirement is 14,240,000 bytes and the
execution requirement is 546,446,080 bytes. The unchanged Host budget is
536,870,912 bytes (512 MiB); execution exceeds it by 9,575,168 bytes.
The diagnostic command exits zero after recording these failures; it does
not establish successful execution. A prior logging-instrumentation TypeError
(`run-bgwPdk`) is excluded from product evidence.

**Handoff to A:** determine whether the checked upper bound is excessive or
this particular generated Program legitimately exceeds the budget. Trace
input retention, output holding, scratch, transfer and concurrency lifetimes,
including duplicate accounting and avoidable sequential summation. The
Frontend must not move WHERE across the JOIN ceiling without semantic proof,
reduce the declared ceiling, increase the Host budget, replace an upper bound
with observations, or change the independent rows to obtain acceptance. No
common capacity defect is asserted solely from this rejection. The normal
JSON control's different filter/projection structure is a comparison, not
permission to substitute its Program after frontend lowering.

## Subsequent main integration

Published JOIN parent `e5a13747ba2a448f2f97b81d22c2777b916b2e1e` was normally
merged with main `2953cd7834cc7243cff116940722c056dd355bec` as
`ca9112a7e305b517ab2dafbd63dc0a1e86a7f8f1`, without conflicts. No workflow,
history declaration or limit was changed. This integration does not relabel
the earlier distribution or diagnostic evidence as new-HEAD acceptance.
The Draft remains incomplete pending capacity resolution and completion of
all unchanged Local/HTTPS cases. Graph-row acceptance is tracked independently.

At the integration revision `ca9112a7e305b517ab2dafbd63dc0a1e86a7f8f1`,
the selected JS JOIN/set/DATA/chain callers passed 22/22
(`run-EUweV9`, `focused-test-D9M6sI`) and selected Node fixture/profile
checks passed 41/41 (`run-SgRr9s`, `focused-test-Tvce0v`). These checks
ran with pinned tools and the bounded/nonzero-test wrappers. Documentation
and copied reproduction records were the only uncommitted changes.
`git diff --check` passed. No new runtime build or repeat packed campaign was
performed for this evidence update; latest-HEAD public acceptance, hosted
required CI, full Core and other targets remain unverified.

## Integration correction: Append scratch lifetime

The integration review reproduced the named and anonymous Source-backed
programs under the unchanged 512 MiB Host capacity policy. Both reached the
existing `ExecutionLimit` refusal. The anonymous chain's execution requirement
was 593,217,536 bytes; the named chain's earlier requirement above remains
historical evidence. Neither independent result nor declared JOIN ceiling was
changed.

`AppendStep` was excluded from the reviewed serial early-retirement predicate.
That exclusion selected both conservative scratch summation and retention of
completed child executions for the whole chain. The existing bounded Append
cleanup separately preserves accepted output rows and releases execution
scratch. Include that audited built-in in the existing predicate: the parent
now confirms each intermediate cleanup and drops its execution before starting
the next child, while retaining all output generations for their exact edges.
The capacity path uses the same predicate, sums every retained child envelope,
and reserves the largest sequential scratch envelope and existing handles.
This does not change operation bounds, Host limits, row values, work budgets,
or the lifecycle of unaudited providers.

Independent lifetime fixtures exercise repeated Append input occurrences,
reuse of an accepted intermediate on two later edges, all twelve ordered
number values, cleanup callback counts, and output availability after final
cleanup. Both ordinary rows and Append now exercise pending cleanup, errors,
same-child retry, and cancellation without successor creation. The conservative
fallback fixture uses an unaudited intersect kernel and still requires summed
scratch and retained child custody. The existing mutation assertion remains
mandatory; only its indentation anchor follows the expanded test loop. The
conditional retirement scope lists Append without claiming physical GC/RSS or
universal provider refinement.

The initial selected JS check passed 19/19 (`run-kqz2sl`). A larger Node
selection reached its 180-second limit (`run-9Pspjk`); that run is not a pass.
The changed retirement/capacity validation and mutation-witness selection then
passed 30/30 (`run-ap1IKC`, `focused-test-ajKfKo`). Clean submitted-source caller
checks and pristine packed Local/HTTPS acceptance are recorded separately after
execution. No hosted CI was started.
