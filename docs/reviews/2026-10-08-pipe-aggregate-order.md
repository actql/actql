# Pipe AGGREGATE shorthand ordering

## Problem and selected meaning

The independent complete JSON Program in
`src/query_program/pipe_aggregate_order_test.mbt` passes the ordinary checker,
but this equivalent source was rejected by the parser:

```aql
FROM pair
|> AGGREGATE COUNT(*) AS n GROUP AND ORDER BY x AS bucket
```

Pre-fix evidence: `run-HUXgCz`, `focused-test-YLEy4f`, 0/1. The failure occurs
at source parsing after the independently authored control has checked; it is
not evidence of a public Host execution failure.

The adopted GoogleSQL checkout is
`d82db99a923a46571f543a13899dc791a7b6f743`. Its
[Pipe shorthand ordering section](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/docs/pipe-syntax.md#shorthand_order_pipe_syntax)
specifies grouping outputs first and aggregate outputs afterward. Without
AND ORDER, only suffixed columns sort; with it, all grouping outputs sort with
ASC NULLS FIRST defaults. The pinned parser's `selection_item_order` and
`opt_grouping_item_order` distinguish aggregate suffixes, which require ASC/DESC,
from grouping suffixes, which also permit NULLS FIRST/LAST alone.

This connects that adopted meaning. It does not introduce an ActQL sort law,
relax capacity or order evidence, or expand the supported aggregate-expression
profile. SQL GROUP BY retains its separate grammar.

## Implementation boundary

The query parser records suffixes and emits the existing Group followed by
the existing Order operation. Order terms refer to output positions, including
aliases and unnamed computed keys. The ordinary lowerer resolves those positions
to already evaluated slots. There is no input-expression expansion, private
sort helper, common owner modification, range revival or runtime fallback.
Generated references retain the original item span and consume expression-node,
syntax-node and work budgets. The existing ORDER suffix parser is shared.

Grouping-only empty/global groups and the unresolved zero-column Result boundary
remain as recorded in #901. Shorthand with no grouping outputs creates no key
sort; an explicitly suffixed aggregate can still sort its output. No implicit
Result, marker or ordering is added to an unsuffixed AGGREGATE.

## Independent expectations and executed focused evidence

- Parser placement, suffix ordering, empty grouping and generated-node budget:
  5/5, `run-nVpYUo`, `focused-test-wBsQiw`.
- Complete checked Program controls: 3/3, `focused-test-Bd8AFt` in the same guard.
  They cover renamed key slots, grouping-before-aggregate sort priority and a
  computed key evaluated once. Expectations are literal JSON, not generated
  compiler output.
- Existing SQL/Pipe grouping-scope parser caller: 1/1,
  `focused-test-4uxqjz`.
- Independent grammar/Values Run vectors and existing public profile controls:
  17/17, `focused-test-EbsemV`.
- Ordinary Values Run identity caller: 1/1, `focused-test-AxlBy6`.
- Generated canonical grammar caller: 1/1, `focused-test-276Kmr`.
- Existing generators updated compilation manifests, normative imports,
  spec-family metadata and canonical vectors. All four read-only checks pass;
  canonical validation covers 377 vectors. Parent preimages remain immutable.

New independently verified grammar preimage:
`sha256:fc3d401cf6db3bf3349114cc019111bbc32a112317d1e397b9573776d9ee7d6b`.
Grammar file SHA-256:
`6f25704123fd2d1fd4ee3a7fd57d4d7d2502b76994743edbc6322de0e54641ca`.
Rules SHA-256:
`0c288ee063666d6e529fa354ded3539b32556d65e425a40ce05657b9740376e3`.
The independently assembled ordinary Values Run becomes
`sha256:7b7be234b94ec1a22ed33e054e503320c171d39d58c4ed9cf6246e0988f5a460`.
Value, Unit and ResultPlan laws are unchanged; the compiler grammar dependency
in the containing Run changes. The full preimage is retained locally under
`_build/independent-evidence/aggregate-order-run-preimage.json`.

## Public acceptance prepared, not yet executed at this record

The existing public fixture/consumer has nine independently authored normal
cases and five refusals for this unit. The normal group corpus includes them;
`--pipe-aggregate-order-only` selects the same cases without unrelated suites.
They cover NULL/duplicate groups, key-before-aggregate priority, aggregate-only
suffixes with distinct counts, repeated keys, empty typed groups, computed keys
followed by WHERE/LIMIT, invalid placement and removed ranges.

The unchanged consumer compares Named Result rows, declared column order and
complete describe contracts, completion, hidden-field absence, refusals before
Run admission/provider I/O and same owned-submission resend/attach/reread.
No lowering output is patched. The next action is a normal same-clean-HEAD
five-package producer followed by the selected external Local/HTTPS consumer,
under one bounded shared heavy guard. PR metadata will record its actual result
and digests separately; this preparation record is not execution evidence.

Base work adopts main `2664bcf3203c42eafe0ca5919763dbe8ad081b40` through the
ordinary merge `13f68790fc25e65c301acb229dd15dff8b66d33b`. Grouping aliases
depend on #902; final merge target is main after that dependency is adopted.
No full Core, all-target, proof campaign, full packed suite, performance run,
manual CI rerun or merge is part of this local evidence. The broader Frontend
objective and other unconnected adopted forms remain unfinished.
