# Grouped and positive ROWS boundaries

Status: parser connection and independent controls prepared. Compile, runtime,
packed Local/HTTPS and CI are unexecuted by B. This branch retains parent
#1469 at `03562477d6c5515249203c21205d8926ab0b51aa` and normally merges fetched
main `1887855e9bf867ba9c3abb724dc52ebe4be3daa1` into integration base
`9777812bee444f3c9653c513e49e22057ab2fefd`.
The unpublished integration title was normalized to Conventional Commits, yielding
`6d17f8e0ff3de2e886db3895a9184c0fc53cce34` with identical tree and parents. The original capture
object `9777812bee444f3c9653c513e49e22057ab2fefd` remains on
`baseline/frontend-grouped-rows-977`; [title-only evidence](integration-title-only.json)
records the unchanged tree/parents and exit-0 Git diff.
The parent HEAD is not rewritten; target the parent branch until it reaches
main, then retarget main. Already merged Native holder changes are adopted
from main unchanged, not an additional Frontend semantic edit.

## Missing connection and expected meaning

```sql
SELECT id,
  FIRST_VALUE(amount) OVER (
    ORDER BY id ROWS BETWEEN (+@before) PRECEDING AND ((@after)) FOLLOWING
  ) AS first,
  LAST_VALUE(amount) OVER (
    ORDER BY id ROWS BETWEEN (+@before) PRECEDING AND ((@after)) FOLLOWING
  ) AS last
FROM records WHERE id > 0 ORDER BY id
```

With before=1 and after=2, authored input
`[(4,30),(1,NULL),(3,20),(2,10),(5,40),(0,99)]` in `(id,amount)` order
requires `[(1,NULL,20),(2,NULL,30),(3,10,40),(4,20,40),(5,30,40)]` in
`(id,first,last)` order. The independent common Program uses ordinary
`preceding: {$param: 'before'}` / `following: {$param: 'after'}`.
[The existing authored control](../../scripts/fixtures/analytic-frame-parameter-source-input.mjs)
and [new source fixture](../../scripts/fixtures/grouped-rows-boundary-source-input.mjs)
retain expected rows, complete ordered schema and a single Source capture.
No expected Program, row or contract is taken from product output.

The [original parser excerpt](baseline-frame-boundary.mbt.txt) admits bare
Parameter or Number only, so `ROWS (+1) PRECEDING` and grouped/sign-wrapped
Parameters cannot reach the existing frame boundary. This is code-derived
rejection evidence, not an executed pre-fix reproduction.
The new syntax tests fix exact rejection reasons, integer/Parameter roles,
authored direction and the expression node budget. New lowering tests compare
complete independently authored Programs for SQL/Pipe and both zero-direction
literal projection and illegal boundary categories.

The selected source is `google/googlesql@d82db99a923a46571f543a13899dc791a7b6f743`:
[window grammar](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/googlesql/parser/googlesql.tm),
[analytic resolver](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/googlesql/analyzer/analytic_function_resolver.cc),
and [numeric unary resolution](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/googlesql/analyzer/resolver_expr.cc).
The official [window frame description](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/window-function-calls#defining_the_window_frame_clause)
uses constant nonnegative integer or Parameter numeric offsets. Transparent
grouping and numeric unary plus retain the existing child's role. Broader
constant expression/RANGE/GROUPS and zero Parameter support remain the existing
explicit common-profile gaps, not restrictions of GoogleSQL.

## Minimal change and invariants

`frame_boundary` calls the existing `limit_integer(true)` from #1469 instead
of a separate token-only Number/Parameter branch. Only its returned role and
the authored PRECEDING/FOLLOWING keyword determine the FrameBoundary variant.
UNBOUNDED and CURRENT ROW remain unchanged. No helper copy, constant folder,
new Owner, evaluator, type rule or wire/storage format is introduced.

Integer overflow/nonintegrality, arbitrary arithmetic, row references and
negative operands remain refused. Grouping/sign wrappers use the bounded
expression parser, including its actual node/depth cost. Parameter declaration,
value and interval validation remain with the common checker. Literal zero
retains its syntax direction and the existing lowerer projects its valid physical
boundary to CURRENT ROW only after category validation. Parameter zero is still
refused by the existing common contract; this change does not infer a default.

The existing packed consumer includes the same **7 normal + 7 refusal** arrays
in ordinary registration and selects them with `--grouped-rows-boundary-only`.
They cover JSON control, SQL/Pipe distinct bindings, empty following frames,
literal operands, zero physical distance, typed empty, invalid/unsafe operands,
Parameter zero and illegal zero FOLLOWING short frame. The existing profile
and all capacity/work/timeout limits are retained. All public checks, including
full schema/values, no hidden columns, one acquisition, refusal admission/I/O,
same-request and cleanup observations, are **prepared, not executed**.

## Identity and actual static evidence

Both predecessor grammar bodies and complete Values preimages are retained:
[merged integration predecessor](../../scripts/fixtures/pre-grouped-rows-boundaries-values-identities.json)
and [adopted main](../../scripts/fixtures/pre-grouped-rows-main-values-identities.json).
Their Runs remain respectively `sha256:6acb90ffeedbff7215c077d01d5c2b5ce346dce5221ada232dde95565c986258`
and `sha256:eb21384725cf00fd1f92cd651308d9918cd713547fce1aacdd35fb0b34212290`.
[Independent oracle preparation](identity-preimage-preparation.mjs) uses only
normative declarations; [current preimages](current-values-preimages.json)
determine the new grammar-bound template/executable/compiled/Run expectations.
The current Run is `sha256:03dd34dc87a2964c94ab03991ba517faba7863ae2faef43cce7664a1b7e4ca8d`.
Values Unit/ResultPlan/Program identity and common contracts are unchanged.

[Preparation receipts](preparation-commands.json) show exit 0 for old preimage
capture, existing generators and new preimage calculation.
[Static receipts](static-commands.json) show exit 0 for five individual pinned
formatter commands, seven Node syntax checks, five read-only freshness checks
(553 canonical identities), and unstaged whitespace. [Focused followup receipts](followup-static-commands.json)
retain formatting of the stronger budget positive/refusal controls and final
link/whitespace checks. The large generated
canonical source is checked by its own freshness generator, not broad formatting.
The [source registration inventory](current-public-inventory.json) has 3,943
authored cases (2,483 normal, 50 expected execution failures, 1,410 refusals),
digest `bf707ce64580cf61d253b42d6442799611d43051a6a2fd5aca2ef771d06f2e33`.
These are declared data counts, not executed test/acceptance counts.

## Remaining execution

[Tracked prepared-checks](prepared-checks.json) gives exact focused JS/Node
and existing public commands. No compiler/tests or Heavy/producer has been
started by B. B retains its original process-inspection approval rejection and
does not retry or bypass it. Root can review using its independently authorized
worktree; public acceptance requires an explicitly handed-off shared window,
keeping original producer/public 300-second caps and existing child limits.
Retain actual source/tree, all five package hashes/manifest, per-transport
inventory, Run/value/schema/refusal and termination/release evidence separately.
No full Core/targets, performance/proof campaign, manual CI rerun or merge is
part of this submission.
