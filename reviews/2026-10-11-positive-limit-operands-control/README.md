# Positive LIMIT/OFFSET operand connection

Status: implementation and independent fixtures prepared; compiler, runtime,
packed Local/HTTPS and CI acceptance are not executed by B for this unit.
The base is `63ec78414dabaed697a05adeff910aff922982c3` (ordinary fetched main).
The separately submitted hex-integer and positive-navigation-offset PRs are
not rewritten or dependencies of this branch.

## Counterexample and selected contract

```sql
SELECT amount, id FROM records WHERE id > 0 ORDER BY id
LIMIT +@count OFFSET +(@skip)
```

For count=2, skip=1 and the authored input
`[(3,30),(1,NULL),(2,20),(3,30),(0,99)]` in `(id,amount)` order, require
`[{"amount":20,"id":2},{"amount":30,"id":3}]` and the ordered complete
nullable Number `amount`, nonnullable Number `id` contracts.
The [independent JSON control](../../scripts/fixtures/limit-parameter-source-input.mjs)
uses ordinary `take.count` / `take.offset` Parameter slots. The additional
SQL/Pipe complete Program expectations are authored in
[grouped_limit_test.mbt](../../src/query_program/grouped_limit_test.mbt).
No installed compiler or result is used to generate an expectation.

[The original parser](baseline-limit-integer.mbt.txt) selects the expression
path only for `(`, then peels Parenthesized only. Its bare-number path requires
Number, so bare `+2` / `+@count` cannot reach their ordinary slot; its
[original refusal test](baseline-grouped-refusals.mbt.txt) explicitly rejects
`(+2)`. This is source-derived evidence of the old rejection, **not an executed
pre-fix reproduction**. New exact-issue, role and budget regression tests are
prepared in [positive_limit_test.mbt](../../src/query_syntax/positive_limit_test.mbt).

The selected reference is `google/googlesql@d82db99a923a46571f543a13899dc791a7b6f743`:
[integer signs](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/docs/lexical.md#integer_literals),
[ResolveUnaryExpr](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/googlesql/analyzer/resolver_expr.cc),
and [ResolveLimitOrOffsetExpr](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/googlesql/analyzer/resolver_query.cc).
Numeric unary plus resolves to its numeric child, retaining the literal or
whole-parameter role. This connection does not implement constant folding.
The existing positive-count, nonnegative-offset, safe-integer, parameter and
input-order contracts remain unchanged. GoogleSQL's zero-count and broader
constant-expression support remain separate documented coverage gaps.

## Minimal implementation

`QueryParser::limit_integer` uses the existing bounded expression parser for
`(` or `+`, peels only Parenthesized and Unary("+"), then calls the unchanged
`safe_integer_text` or retains a BoundParameter. It does not change the common
checker, Owner, evaluator, wire, parameter binding or source acquisition.
The EBNF and query rules document include the same recursive selected operand
forms. Expression depth/node budgets still include every wrapper.

The existing packed consumer copies one new fixture and selects it with
`--positive-limit-only`; the same arrays are included in ordinary registration.
The declared limited cohort has **7 normal + 6 refusal** cases: independent
JSON, SQL/Pipe, mixed literal/parameter, literal-only, zero offset with NULL and
duplicates, typed empty; row/arithmetic/NULL/zero/fraction operands and a NULL
binding are refused. Full ordered schema, rows, one Source read, admission/I/O
refusal counters and existing resend/attach/cleanup observations use the
existing public boundary. Those public assertions are **not yet executed**.

## Identity and static evidence

The complete predecessor grammar and Values preimages are retained in
[the predecessor fixture](../../scripts/fixtures/pre-positive-limit-operands-values-identities.json)
and [baseline grammar](baseline-grammar.json).
[identity-preimage-preparation.mjs](identity-preimage-preparation.mjs) extracts
only independent oracle declarations; it does not register tests or import an
installed product. [Current complete preimages](current-values-preimages.json)
determine the grammar-bound template, executable, compiled and Run expectations.
The previous Run `sha256:eb21384725cf00fd1f92cd651308d9918cd713547fce1aacdd35fb0b34212290`
remains immutable. The current Run is `sha256:6acb90ffeedbff7215c077d01d5c2b5ce346dce5221ada232dde95565c986258`.
Values Unit/ResultPlan/Program identities and contracts do not change.

The registration-only independent enumerator yields 3,929 authored occurrences
(2,476 normal, 50 execution failures, 1,403 refusals), inventory
`7fafe644c11e6798312c14831753fa17b3338abcf92a2fbcdbbacbbee98a4eee`.
[Baseline](baseline-public-inventory.json) and [current](current-public-inventory.json)
registration records are separate. Declaration counts are not executed tests.

[preparation-commands.json](preparation-commands.json) records the initial
source-document generation; [grammar-preparation-commands.json](grammar-preparation-commands.json)
records the subsequent EBNF inclusion and final generation. Both are static
preparation, not compiler/runtime acceptance.
[static-commands.json](static-commands.json) records six individual pinned
MoonBit formatter commands, seven Node syntax checks, five read-only freshness
checks (including 553 canonical identities) and diff whitespace check, all exit 0.
The first staged whitespace check found an EOF delimiter blank in the newly
tracked baseline parser excerpt. [The original excerpt and failed check](initial-excerpt-whitespace.json)
are retained; only its display-copy delimiter was trimmed before final submission.
The earlier unstaged whitespace checks did not include that untracked file.
The large generated canonical test is checked by its read-only generator;
a whole-file formatter, full Core/targets, packed, performance and Hosted CI
are not claimed.

## Remaining handoff

[prepared-checks.json](prepared-checks.json) is tracked and supplies exact
focused JS/Node commands plus the original packed consumer selection. B's prior
process-inspection approval rejection is preserved and is not retried or
bypassed. Runtime checks may be performed in Root's independently authorized
worktree. Shared public Heavy is unreserved/not started: use only an explicitly
handed-off window with the original producer/public 300-second caps and existing
child limits. Keep package/source/digests, actual counts, values/schema/refusals,
same-request behavior and terminal/child/group/lock release receipts separate
from this static evidence. No broad campaign, upper-limit change or merge is
part of this submission.
