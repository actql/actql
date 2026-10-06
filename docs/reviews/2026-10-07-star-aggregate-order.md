# Star replacement aggregate snapshot during ORDER

Owner: B. Main baseline: `0a4a53f7fe28646f703ac60dd65bbdf2b9c8635e`.
This is independent of #680 capacity and #698 JOIN star routing. Destination:
main; no unmerged feature dependency and no merge operation.

## Counterexample and independent expectation

```sql
SELECT * REPLACE (SUM(y) AS x, y + 1 AS y)
FROM t GROUP BY y ORDER BY `x`
```

For `(x,y)=(1,20),(2,10)`, output is `(10,11),(20,21)` in x,y order.
SUM reads original y, while GROUP BY the selected y alias groups y+1. Quoting
x must not change which input SUM sees. The pre-fix Program instead passes
`aql_group_key_0` (y+1) to SUM; the unquoted control retains original y.
Focused red evidence: `focused-test-06tKiU`, at the baseline with only the
new regression. `focused-test-v1M0CY` is an earlier test-authoring error
(field-form versus expr-form oracle), not product failure evidence.

The [adopted SELECT REPLACE contract](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#select_replace)
retains column names/order while replacing values. All replacement expressions
use the SELECT input snapshot; ORDER references evaluated output aliases.
The independently authored complete Program in `star_aggregate_order_test.mbt`
checks through the ordinary checker and matches bare/quoted aliases,
quoted replacement names and qualified input references.

## Minimal correction and collision boundary

`order_aggregate_calls` was comparing expanded GROUP projections to the authored
SELECT star. Its alias classification therefore mistook a replacement aggregate
for an ORDER-only call and applied the wrong argument scope. Pass the existing
expanded SELECT projections and compare names with existing `same_name`.
Only selected aggregate declarations qualify: an ordinary input with the same
spelling as a parser-private call must remain a separate slot. The intermediate
name-only fix fails that collision regression (`focused-test-JuXMZe`); the final
fix keeps both values. No aggregate, scalar, checker, order, capacity or Host
owner is implemented or relaxed here. No new syntax or normative identity is
introduced.

## Focused verification and public fixture

- JS 22/22: new full Program/collision regressions and existing star replacement,
  ORDER aggregate and filter-scope callers (`focused-test-W83DQ8`).
- Node 14/14: independent fixture and existing public/analytic profile selectors
  (`focused-test-5KGrsy`). Changed MoonBit formatting and `git diff --check` pass.
- All evidence directories are under `_build/focused-evidence` in the B worktree.

Five new public successes join the ordinary star replacement corpus: independent
JSON control, bare ORDER, quoted ORDER, quoted replacement and qualified star.
Independent inputs `(id,amount)=(1,10),(1,10),(2,30),(3,NULL)` require rows
`[{amount:11,id:20},{amount:31,id:30},{amount:null,id:null}]`, with amount,id column
order and both nullable number contracts. Wrong snapshot sums are 22 and 31,
so quoting cannot silently change values. The JSON control groups original
amount, then projects its increment: on these numeric/NULL inputs it gives
the same groups as the source's incremented group key. No product output
generates rows, types or Programs.

Normal five-package Local/HTTPS acceptance is still pending at this checkpoint.
Use the existing `--star-replace-only` runner: 18 successes and 8 pre-admission
refusals per transport, including the original unchanged cases. Preserve Named
Result/describe, stream completion, hidden-column absence, source once and
same-request/read/attach replay checks. No full Core, all-target, proof,
performance, Cloud or manual CI campaign is claimed. Keep Draft pending review
and actual submitted-HEAD CI; earlier SHA successes are not current CI evidence.

## Initial public control correction

Normal five packages from `4a9cb7b83be34101616ffaeaa4dbd79109412e3e`
passed the original 13 Local successes, then refused the newly authored JSON
control before admission (`ClientProgramRejected`). HTTPS and subsequent new
cases were not reached. Evidence: `worktrees/.codex-scratch/public-query-evidence-AvBE82`.
The control attempted to overwrite the existing amount through derive, which
is an additive operation. It now derives a fresh `incremented_amount` slot,
then selects it as amount. Expected rows/contracts/order are unchanged.

A direct diagnostic against the normally built bridge and query-amount fixture
environment found that rejection at main step 1 derive.amount; all four source
forms prepared successfully. The corrected JSON control also prepares through
the same bridge. This is a fixture authoring correction, not evidence of a new
product bug or public acceptance success. The tracked source change is confined
to the JSON control and this report; the frontend implementation is unchanged.

## Corrected normal packed acceptance

Source `6b263eb126829a23fe3d444fe5206e6fb5d2fc24` completed 18/18 successes
and 8/8 pre-admission refusals in both Embedded Local and public HTTPS.
All authored sources/expectations and installed Host ceilings were retained.
Result.describe full type/nullability/column order, exact rows and stream
completion, one shared acquisition, same Run on request resend and no added
I/O on re-read/attach were checked by the existing acceptance helper. No private
physical fields leaked into Results. The later report-only commit is not a
new runtime build or CI result.

```sh
node scripts/packed-client-packages.mjs /private/tmp/actql-b-star-aggregate-order-corrected-20261007-pack
ACTQL_PACKED_CLIENT_PACKAGES=/private/tmp/actql-b-star-aggregate-order-corrected-20261007-pack \
ACTQL_TEST_NPM_CACHE=/private/tmp/actql-graph-composition-probe-e90/npm-cache \
npm_config_offline=true npm_config_include=optional \
node scripts/test-packed-public-query.mjs --star-replace-only
```

Producer used pinned MoonBit/Node PATH and MOON_HOME, ordinary prepack and the
normal manifest/digest checks. Receipt and complete logs are retained under
`worktrees/.codex-scratch/public-query-evidence-7ktiF0`; its external installation
was removed after evidence preservation. The dirty flag reflects protected
untracked review evidence, not changed tracked runtime/fixture build inputs.
The corrected fixture's Node selection passed 3/3 (`focused-test-I5jGCb`).
The 22 JS and 14 Node successes above belong to the implementation checkpoint;
only the independent control/report changed afterward, with packed acceptance
now executed at the explicitly recorded source SHA.

| Package | SHA-256 |
|---|---|
| client-wire | `0212e9f37cde525589a0e8d48b62151e73ce53153ef75948974cb9f672659523` |
| sdk | `fe085d7d7e2cce344c2c4daf18f33ca477dcee9189e96552816cf9eee6b10972` |
| run-host-core | `1efe8b4522f222c7f0e39a84a45a76004f652f01ecc450bc3985078b805f5649` |
| local-node | `dd87e4031eae5ce506d86b8618fb622b5eb87e600b34cf60b9aa4b8f69ba766b` |
| node | `89a340b9d0a80c4ade483e471c06a5503f81c347ced3a17f3c4e4d4a21b1eb64` |

No runtime overlay, post-lowering patch, fallback or second execution owner was
used. Submitted-HEAD CI/content review remain separate; final destination main.
