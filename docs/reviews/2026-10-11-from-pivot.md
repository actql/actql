# FROM postfix PIVOT through the existing producer path

## Fixed reference and source gap

The selected [GoogleSQL PIVOT profile](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#pivot_operator)
uses a table postfix before surrounding SELECT/WHERE/JOIN. Confirmed against
[google/googlesql@d82db99 resolver_query.cc](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/googlesql/analyzer/resolver_query.cc#L12769):
ResolvePivotClause builds a new output NameList from unreferenced grouping
columns and bucket columns, adding only the optional postfix output alias.
Original input ranges do not survive. The same pinned source separately notes
that projected columns must not collapse merely because they have equal values.
This is a selected reference profile, not a claim of full ISO conformance or a
live differential run against a Google service.

At main eefdda1a85c4e033d6dcefcc774095949cc97262, this complete source is refused
with Syntax("Expected end of one query"):

```sql
SELECT id,customer_id,opened,closed
FROM orders PIVOT(COUNT(amount) FOR status IN ('open' AS opened,'closed'))
ORDER BY id
```

With existing fixture rows (a,one,open,1),(b,two,open,2), independent rows are
(a,one,1,0),(b,two,1,0), columns id/customer_id/opened/closed. The independently
authored common pivot Program already passes the checker. Baseline run-KOEfYe
is 1/2, source only failing. Preserve source, obligations and baseline at
/private/tmp/actql-b-from-pivot-eefdda1a8-baseline.json and .mbt.

The equal-valued projected-alias concern was tested before implementation:
run-ZiVslw is 2/2 on unmodified main. Existing SELECT materializes distinct
output slots, so no product change is needed there. Preserve matched source,
JSON and expected rows at
/private/tmp/actql-b-pivot-projection-identity-independent-control.json.
Its public controls remain part of this acceptance rather than inventing a fix.

## Connection and ownership

QueryParser::query_source invokes a small from_pivot_source helper after its
ordinary base Relation resolution. Reserve unquoted PIVOT as a postfix starter
in optional_source_alias; quoted identifiers remain names. A parenthesized
PIVOT input can omit the pre-pivot alias without changing other subquery paths.
The existing pivot_clause parser supplies the clause; bind_query supplies its
ordinary projected producer before any surrounding JOIN or WHERE. Only the
postfix output alias is exposed to the outer query. Both JOIN sides consequently
consume the transformed Relation and retain authored ON and MAX_OUTPUT_ROWS.

No compiler-string rewriting, execution Owner, storage format, acquisition
replay or compatibility path is introduced. The existing common Program Stage
Result carries the producer through checker/planner/Host. That existing producer
boundary is observable in Program structure; this change does not claim it is
an arbitrary provider pushdown boundary or introduce a physical-placement policy.
No CTE capture/predicate/Effect implementation or shared execution code is edited.

## Independent obligations and initial checks

- run-0lbDYD: initial common checker connection, 2/2.
- run-WjIqgr: 17/19. One newly authored Program expected sort before select,
  although the existing SQL route selects surviving columns then sorts them;
  one refusal assertion expected only UnknownColumn instead of the existing
  UnknownReference variant. No product rows, predicate, key, order or bound changed.
- Keep independently authored Program v1/v2 at
  /private/tmp/actql-b-from-pivot-independent-program-v1.json and -v2.json.
  Both select all four columns including the exact id sort key; the authored v2
  states the existing SQL projection/sort structure. It is not runtime-generated.
- run-DkHImd: 18/18, complete independent producer Program, input/output aliases,
  derived tables, both JOIN sides, original nested-query and capture callers.
- Exact existing missing-column/reference refusals are asserted, rather than Err(_).
- run-ESatKj: selected query_syntax interface compilation and existing normative
  generators. JS/Wasm/native interfaces covered, unsupported wasm-gc skipped.
- run-x1JSv1: independent current/historical identity and authored fixture checks,
  64/64. Inventory accounting is not execution of the whole corpus.

The public PIVOT cohort adds matched JSON/source NULL/duplicate controls,
quoted aliases, optional subquery alias, WHERE over output, empty global/keyed
input, both JOIN sides, LEFT padding, input/consumed-column refusals and projected
identity. The acquired pair uses authored rows with id=0 and NULL/duplicate
values; WHERE id>0 must survive and Source acquisition must be one. Its independent
JSON control preserves the same rows, predicate, fields and expected counts
(first=3,second=1). Explicit JOIN ceiling remains 10, never a larger default.

## Pins and remaining gate

Grammar self CID changes from
81c194e574cb92623e23bf9e81075a718e14111cdfcb0308507c4f6d0b6b0586 to
f2bf87c10285fe83d42ef8f5f8dd4071b1d21269186acf8abfd335572996f413.
Common Values Unit, ResultPlan and Program identity remain unchanged; grammar-bound
template/executable/compiled Plan/Run change. Independent complete preimages are
kept in scripts/fixtures/pre-from-pivot-values-identities.json and
/private/tmp/actql-b-from-pivot-current-run-preimages.json. Old Run
0bf6c0cf5627553679b5bdf942fdd14f8f1f94f1d424d905b11f848339851094 retains
its old closure; current Run expectation
1d4ff0853432dfbd1d1c92db64aa2a064ae8dcd930bd0b915ecc233b01ee57c2
comes from independent normative inputs and sorted-JSON hashing.

Normal clean-HEAD five-package production and selected --pipe-pivot-only
Local/HTTPS acceptance are pending at document creation. Record the exact source,
actual digests, terminal process/receipt and public Named Result proof in the PR.
Do not equate source/checker success to execution or local success to CI.

Pending sibling #1343 COUNT(*) and #1344 scalar arguments are not dependencies.
Integrate their grammar/API/rules pins together if they land. This unit does not
add multiple aggregates, modifiers, non-String axes, NULL buckets, other postfix
operators, outer-row correlation or a new unaliased-subquery profile outside
PIVOT. These are coverage obligations, not invalid-GoogleSQL claims. No full
Core/all-target runtime/proof/performance/all-packed campaign is claimed.

Final local preparation: run-PqRXwQ is 7/7 for the selected FROM PIVOT and
Values Run consuming tests, including exact max_output_rows=10 checks on the
JOIN Programs. Compilation manifest, document metadata, spec family, canonical,
Workers and Node fixture read-only freshness checks pass. Main remains
eefdda1a85c4e033d6dcefcc774095949cc97262 at the pre-submission fetch.

## First public gate and retained identity projection

Normal five-package producer at fc52b3998ab434ba8fa6d9c510c43e3ceac44428 passed
actual digest/revision checks. Public guard run-abheUb then failed at
pipe-pivot-from-empty-global: local Host preparation returned 500, surfaced as
SubmissionUnknown. Seven preceding new FROM cases passed on both transports;
no completed inventory or later-case success is claimed. Original receipt/logs:
/Users/t14i/workspace/20260822/worktrees/.codex-scratch/public-query-evidence-r6HfEe.
Both children terminated, failed guard released locks; private install removed.

run-OdIM3e shows lowering/common checker success (1/1) and retains the exact
Program at /private/tmp/actql-b-from-pivot-empty-program-fc52b3998.json. The main
stage had steps=[] because SELECT * was elided when its input was a Stage Result.
The exact packaged runtime module (SHA-256
897d55bbcc38a9bae560b96a94e5db3b71d8323ac88558b247c8526c000633cf) matches its
bytes in the retained local-node tarball. run-uAe48r diagnoses both source and
unchanged JSON as prepared but task compilation rejected. Source-matched
unminified diagnostic run-ehROdp decodes the same failure:
ClientTaskCompilationIssue.Plan → ClientValuesExecutablePlanIssue.TaskGraph →
ClientTaskPlanGraphIssue.Fragment → ClientTaskFragmentIssue.Pipeline →
ClientTaskPipelineIssue.MissingOutput. Direct Values rejects this multi-stage
profile as UnsupportedGraph; that is not an alternate accepted execution route.
No public pass is inferred from these diagnostics.

B fixes only compile_steps' identity-select elision: retain the explicit SELECT
when a Stage Result consumer has no other operation, using the ordinary existing
projection branch. Already materialized JOIN continuations keep their existing
elision. This does not alter CTE capture/predicate handling, common task emission,
Run owners, input rows, limits or the expected global row A=0. run-jaz5F7 is 28/28
for the new projection plus FROM/nested/CTE/range-lifetime callers.

The independently legal JSON pass-through stage remains a separate common-owner
counterexample for A: src/run_publication_host/client_program.mbt::
emit_prepared_client_task_pipeline returns MissingOutput when
client_task_output_step/node_at cannot identify an output step. Preserve source/JSON, issue chains and fixed
runtime at /private/tmp/actql-b-from-pivot-empty-{program,bridge-diagnostic,
unminified-diagnostic}-fc52b3998.json. The frontend now preserves its authored
projection instead of introducing that unimplemented empty consumer. This
common JSON coverage obligation is not silently marked fixed by the frontend
optimization change. No Owner implementation is duplicated here.
