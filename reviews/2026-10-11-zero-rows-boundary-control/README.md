# Literal zero ROWS boundaries: Frontend connection

Adopted main: `340f70afffcd828a6650929eb61c5dc124607658`.
Separate from #1451 grouped PIVOT, #1453 grouped STRING_AGG, completed #1422
UNPIVOT and the unresolved generic NULL set-context contract. No unmerged
implementation dependency.

## Counterexample and reference meaning

```sql
SELECT id, SUM(amount) OVER (
  ORDER BY id ROWS BETWEEN 0 PRECEDING AND 0 FOLLOWING
) AS total FROM records WHERE id > 0 ORDER BY id
```

At the baseline `QueryParser::frame_boundary` calls `safe_integer(false)`;
it rejects literal zero with `Expected positive integer literal`. This is
source-inspected evidence, not an executed baseline failure or public Run
reproduction. The existing common Program already admits
`frame: {start: "current_row", end: "current_row"}`.

The [GoogleSQL window-frame specification](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/window-function-calls#defining_the_window_frame_clause),
consulted 2026-10-11, permits non-negative integer boundaries and defines ROWS
as physical offsets from the current row. Offset zero therefore denotes that
same physical row. This is not a RANGE peer group or a new analytic evaluator.
Its boundary-category grammar still forbids CURRENT ROW to numeric PRECEDING,
numeric FOLLOWING to CURRENT ROW/numeric PRECEDING, and a FOLLOWING short frame.
Zero does not erase those authored restrictions.

## Implementation

The parser admits literal zero and preserves `Preceding(0)`/`Following(0)`
in its existing AST. The ordinary analytic lowerer validates the authored
categories before mapping just those literal boundaries to `current_row`.
Every call is validated before ordinary common-function lowering. A valid
sibling window cannot conceal an invalid zero interval through window reuse.
Positive distances and bound parameters retain their exact existing slots;
common checker/Owner retain numerical interval, type, demand, work, resource
and execution responsibility. No parameter value is evaluated in the Frontend.

The common parameter distance domain remains positive. Bound parameter zero is
still an explicitly recorded coverage gap, not silently coerced to CURRENT ROW.
Grouped/computed, signed, fractional, NULL and row-dependent distance syntax
remain outside this selected literal/whole-parameter profile. Common numeric
contracts, default/RANGE frames and typed NULL inference are not changed.
D confirmed no overlapping parser/lowerer edits.

## Independent obligations

New syntax tests preserve both zero directions and invalid literal forms.
Full independently authored Values Programs cover current/current,
current/following-one and preceding-one/current; SQL, Pipe and named-window
sources compare against those complete Programs and normal checker controls.
Four forbidden-category cases require `InvalidQuery`, including a valid first
window followed by the invalid call. Existing bound-parameter tests remain.

The existing short-ROWS public route adds five normal and five refusal cases, including bound-parameter zero.
Its new JSON control directly declares the existing current/current frame.
Expected ordered rows, complete schemas and Source acquisition counts are
handwritten. NULL observations and two amount=20 occurrences are retained;
current/current totals are NULL,20,10,20,NULL in id order, while
current/following-one totals are 20,30,30,20,NULL. WHERE excludes id=0; typed
empty input retains the complete schema. No expectation is generated from
compiler, checker or runtime output, and no new public driver is introduced.

## Identity and evidence

Retain complete adopted-main grammar/dependency/Run preimages in
`pre-zero-rows-boundary-values-identities.json`. Current grammar-bound
Template/Executable/Compiled/Run CIDs are derived from the independent
hand-assembled oracle. Program/semantic identity and Values Unit/proof/ResultPlan
remain unchanged. Existing generators own manifests, metadata, references and
canonical registration; generated files are not hand-edited. Regeneration also
registers eight already-present main Model/decision schemas and three main
INFER requirements as pending evidence; this is adopted-main freshness, not
new common contracts or proof authored by this change. Historical
preimages remain historical, not relabeled as current success.

`prepared-checks.json` records bounded runtime commands and the existing public
route. Static/freshness receipts are separate. No JS/Node runtime test, public
Local/HTTPS, target runtime or required CI success is claimed. B's prior
process-inspection guard rejection is neither retried nor bypassed. No Heavy
slot has started; actual execution acceptance remains required separately.
The independent authored inventory is 3,892 occurrences (2,458 normal, 50
execution failures, 1,384 refusals), not executed test counts.
