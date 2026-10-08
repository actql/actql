# DISTINCT ORDER expressions retain selected input members

Base inspected: main `e2a7dc74eaa774e9ffa21791c0361d616debfa35`.
This closes a Frontend connection gap for a selected scalar property path,
not a new checker/evaluator, object DISTINCT support or full Frontend completion.

## Existing meaning and independent counterexample

```sql
SELECT DISTINCT payload.score AS score
FROM objects
ORDER BY (payload).score + 1 NULLS LAST
```

The selected nullable number already has a checked, evaluated output slot.
ORDER can add one to that slot after DISTINCT without recovering `payload` or
re-evaluating its property. The previous fallback instead tried to resolve the
removed object and refused. Whole-expression reuse does not cover this tree.

The adopted `docs/spec/query-text.md` ORDER scope requires resolution from
selected expressions/aliases and one SELECT evaluation. The pinned external
reference is GoogleSQL `d82db99a923a46571f543a13899dc791a7b6f743`:
[`Resolver::ResolveSelectDistinct`](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/googlesql/analyzer/resolver_query.cc)
collects resolved path mappings for post-DISTINCT ORDER; the corresponding
[`orderby.test`](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/googlesql/analyzer/testdata/orderby.test)
contains selected nested-path controls and scalar expressions on retained keys.
This does not assert arbitrary algebraic equivalence or live service validation.

## Repair and scope

Bind a complete selected static-path subtree to its public evaluated slot,
using the existing scoped receiver/member comparison and field-binding AST
facility. Compare SELECT's input scope with ORDER's alias-first scope before
binding. Then use the common property/expression bridge for remaining operators,
parameters, NULL propagation, failure and demand. Only the DISTINCT fallback
calls the new small helper; ordinary/grouped paths keep their existing owners.

Keep exact aliases, explicit receiver boundaries, field member order and
availability. Do not restore another member, range column, removed object or
unselected arithmetic input. Reuse does not fabricate key/order evidence.
Existing bounded binding work and private-name collision protection apply.

The independent complete Values Program derives the property once, projects
`score`, deduplicates it, derives the sort-only addition, sorts and removes the
helper. Separate SQL/Pipe, quotation and qualification controls retain this
meaning. Negative range/object receiver contrasts and unselected fields keep
`UnsupportedOrdering`; public Check disclosure uses the existing
`ClientProgramImplementationLimit` projection.

## Public obligations

Seven normal cases and five refusals extend the existing normal packed corpus
and its `--distinct-order-only` route. No new acceptance harness is introduced.
The independent JSON Program is authored directly. The source derives objects
from declared parameters after `WHERE id > 0`; it includes duplicate values,
a NULL receiver, a NULL member and deliberately different range-column scores.

Expected descending member rows are 20, 10, NULL. Addition sorts 10, 20, NULL;
LIMIT 2 OFFSET 1 retains 10, NULL. Empty input retains the nullable number type.
The existing acceptance owner checks Named Result rows, Result.describe column
order/contracts, private-slot absence, source acquisition once, same-Run resend,
reattach/reread and zero admission/source I/O for refusals.

## Separate common boundary retained for handoff

Two additional sources retain an object output alias:

```sql
SELECT DISTINCT payload.score AS original_score, other AS payload
FROM objects
ORDER BY -payload.score NULLS LAST, original_score NULLS LAST
```

The qualified `-objects.payload.score` control instead uses `original_score`.
Their independently authored target rows differ in order and are preserved in
`distinctOrderMemberOwnerCases`, alongside `distinctOrderMemberOwnerProgram`.
They are explicitly not counted among the seven scalar public acceptance cases;
acceptance is still pending at this committed snapshot.
Current common checking rejects the object DISTINCT key before ORDER:
`Operation(NotKeyComparable("payload"))` at
`stages[0].steps[3].distinct[1]` in the minimal Values reproduction.
The Frontend does not bypass or relax this common key contract. The exact
refusal and alias/qualified lowering are retained by a dedicated test; the
normal scalar-property connection proceeds independently. Public execution of
these two object cases remains unverified and requires common-owner support.

## Evidence and remaining work

Pre-repair four focused tests: three passed, the selected-member scalar ORDER
case failed (`run-OJrcTN` / `focused-test-Xzu3Hh`). The independent common Program
control passed. First repaired caller selection: 25/25; after Pipe and exact
common-boundary controls: 27/27 JS (`run-s8PLGf` / `focused-test-njtrQm`).

The exploratory object positive was rejected by the common checker; the
structured diagnostic was captured in `run-lZWTz3`. A preceding diagnostic
print attempt failed compilation because its types use Debug, not Show
(`run-nTyib7`); no executed test success is attributed to that attempt.

Record the final integrated SHA, focused checks, exact-SHA normal package
manifest/digests and terminal Local/HTTPS result in the PR body. Earlier focused
results are not new-HEAD executions. CI, other targets, full Core, other cohorts,
Cloud and the broader Frontend objective remain separate until verified.

The six existing DISTINCT ORDER refusal fixtures adopt the exact public code
already pinned in #1038 (`51593a7bbf59bae9e27cf71b202e6cdd75bcab05`). This is
fixture classification from the common Owner contract, not a new diagnostic
mapping or dependency on #1038's product repair. The new selected-member helper
uses machinery already on the inspected main and has no unmerged dependency.
