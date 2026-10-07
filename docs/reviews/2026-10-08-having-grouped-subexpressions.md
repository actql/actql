# HAVING grouped subexpressions: evaluated-key connection

Date: 2026-10-08. Owner: B. Stacked on #915 (`fix/frontend-sql-grouped-subexpressions`), which depends on #910. Final target is main after those dependencies are merged. Main `db4f80870345c48744f44023df5fe8c9617b30ed` was normally merged before work. No PR merge or history rewrite.

## Defect and independent control

```sql
SELECT COUNT(*) AS n FROM pair
GROUP BY x + 1
HAVING n + (pair.x + 1) > 8
```

Input `{x:7,y:9}` independently requires `{n:1}`. The complete hand-authored JSON Program in `src/query_program/having_grouped_subexpression_test.mbt` uses Values -> derive x+1 -> group/count -> filter count+key > 8 -> select n. Ordinary checking succeeds before equivalent source compilation fails. Red evidence: `run-fq1OBK`, `focused-test-oYsEkk`, 0/1. This is a Frontend connection gap; no Program is corrected by the test.

The adopted [query scope specification](../spec/query-text.md) already makes HAVING aliases take precedence over inputs. Google's [HAVING reference](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#having_clause) also describes grouping/aggregate expressions, SELECT aliases and this precedence. No new grammar, common value law or semantic restriction is introduced.

## Repair and alias counterexamples

The private grouped-subtree binder accepts clause-aware reference comparison and ordinary value resolution. SELECT/Pipe callers retain their input snapshot. HAVING compares the GROUP input receiver against HAVING's own alias-aware receiver meaning. A simple alias may prove identical input-slot provenance. Computed/aggregate or ambiguous aliases cannot establish that proof. Qualified input ranges keep their meaning; nullable property paths retain exact receiver and member matching.

Only a complete matching key subtree is replaced by its evaluated physical slot. Private names avoid authored names/references. The original expression owner, spans and bounded work checks are retained. Evaluation still uses the existing property/expression bridge and filter owner. The implementation does not restore the original object or allow a partial computed key to access removed input columns. It does not expand aliases into a second evaluation.

A complete independent Program for `SELECT -x AS x, COUNT(*) AS n FROM t GROUP BY t.x HAVING x + 1 > 0` fixes the filter to the evaluated negative alias. Input x=1,2 gives no rows. Using `HAVING t.x + 1 > 0` instead retains both rows; ORDER BY output x yields -2,-1. Reusing the input key for bare x would change the first result.

For nullable input payload.score 10,20,NULL,20,NULL, grouping by score+1 produces NULL/11/21 with counts 2/1/2. A constant SELECT alias `@b AS payload` whose score=20 makes `HAVING payload.score + 1 > 12` retain all groups; the qualified `objects.payload.score + 1 > 12` retains only key 21. These expectations are independently authored and detect receiver confusion.

No common checker, planner, Host, capacity ceiling, acquisition, save/replay format, contract pin or legacy wire fallback changes. No grammar/Run identity changes are required by this implementation-only connection. Parent independent vectors are retained.

## Focused evidence

- First repaired complete Program: `run-nccOOf`, `focused-test-bwtEsH`, 1/1.
- `run-nZ9F9i`: new HAVING controls 7/7 (`focused-test-ok3cCA`), inherited SQL grouped subexpressions 5/5 (`focused-test-qg97aB`), existing HAVING projection aliases 6/6 (`focused-test-ob14Fl`). The attempt then stops on a misspelled Pipe test filter with zero discovery. That selection is not a pass; its actual existing name is used below.
- `run-WbW4aI`: Pipe aggregate scalar expressions 4/4 (`focused-test-ppuKYT`), nullable HAVING object callers 5/5 (`focused-test-DoBkR1`), GROUP SELECT scopes 5/5 (`focused-test-UYyxaK`).
- Final new controls after scoped formatting: `run-z6v47s`, `focused-test-Mww0pr`, 7/7. Readonly compilation manifest freshness passes with the unchanged parent grammar CID. New test/helper formatting and fixture/runner JavaScript syntax checks pass.

The property matrix also probed object-valued GROUP keys. Ordinary checker construction refused that exploratory input (`run-gVPZQg`, `focused-test-vhX8W8`), so it is not counted as supported or successful execution. The unchanged logs retain the exact source. Receiver collision acceptance uses already-supported typed object parameters rather than asserting new object-grouping support. No common contract or key-checking rule is weakened.

## Public acceptance

Eleven normal cases and four preparation refusals are registered in the ordinary group-property corpus. `--having-grouped-subexpression-only` selects those same cases for bounded public acceptance. They include independently authored JSON, direct and hidden COUNT, alias/input collisions, nullable keys/objects, duplicate groups, qualified/backtick paths, JOIN, empty input and negative scalar alias controls. Existing acceptance verifies Result.describe type/nullability/column order, rows and completion, hidden-field absence, owned-request resend/attach/reread and rejection admission/provider-I/O counts.

Fresh normal five-package Local/HTTPS execution is pending at this document revision. Parser/checker success alone is not claimed as public execution. Use a clean fixed source revision and preserve its manifest/digests; do not patch generated Programs, install an old wire fallback, or relabel an earlier manifest. Successful private install/Store artifacts are reclaimed by the existing evidence runner.

Required exact-HEAD CI, Wasm/native/full Core/full packed/proof/performance and broader HAVING/ORDER coverage remain unverified. No manual CI run/rerun or merge.

## Internal-name control and shared heavy capacity

The hidden COUNT/input-name probe did not reproduce a defect. `QueryParser::fresh_producer` scans authored Word/QuotedName tokens and allocates a different placeholder. The independent complete expected Program and explicit placeholder inequality pass: `run-HX1c2D`, `focused-test-b3nv3m`, 1/1. A public control retains input `aql_having_aggregate_0=100` while requiring COUNT+1=2 not to pass >10. No guard is relaxed.

The first selected fresh-pack attempt `run-OgWeSA` stopped at shared-heavy lock acquisition. D's cancellation work held the lock; no package producer or consumer started (`steps: []`). It is neither a product failure nor execution success. The other owner's lock/artifacts are untouched.
