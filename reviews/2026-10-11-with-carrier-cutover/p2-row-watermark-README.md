# Row watermark source connection

This finite P2-T unit connects the adopted `watermark_rows` source signature to
the existing common Relation watermark checker. It changes no evaluator,
execution owner, wire schema, watermark law, or compatibility behavior.

```aql
WITH rows AS (
  SELECT 1 AS id, 10 AS at UNION ALL SELECT 2, 3 UNION ALL SELECT 3, 9
), ordered AS (FROM rows |> ORDER BY id), marked AS (
  FROM ordered AS r
  |> watermark_rows(time: r.AT, late_policy: 'mark', max_skew: 1)
)
SELECT id, at, watermark_ms, watermark_late, watermark_decision
FROM marked ORDER BY id
```

The independently designed thresholds are `9, 9, 9`; late flags are
`false, true, false`. Equality with the threshold is not late. A fixed threshold
of 3 instead keeps all three rows as non-late. Drop policy retains IDs 1 and 3
on the prefix case. These are prepared expectations, not observed Host results.

`time` retains ordinary FieldRef resolution, including a visible range and
case-insensitive lookup; dropped fields and old aliases cannot return. Policy
is an exact String. Fixed thresholds, positive numeric/duration skews and
permitted whole Parameters reach their unchanged common owner without default
insertion, evaluation or choosing between two threshold sources. Both or no
threshold retain `Operation(InvalidBody)`; invalid skews retain
`Operation(InvalidCount)`. Existing prefix input-order, generated-field,
clock-type, Parameter and resource obligations remain required.

Before the fix, clean `93da47679` produced JS1/3: the independent complete JSON
Program checked while both source cases failed at parsing. The initial runner
argument error `run-wSLS73` executed no tests and remains retained.
Clean `9761a63f2` passed the same three controls; `08ca9d675` passed five
including common typed refusals and scope counterexamples.

Clean `d57736ea54cced2bf4ef820e6481f36a2397c6c3`, tree
`2161fd606e348f185455448e233a460a5175f34d`, passed actual JS23/23, selected
grammar canonical JS1/1, Node133/133, and compilation/metadata freshness in
`run-mIIDCX`. Its aggregate ended 124 at the family check after the 60-second
budget; that timeout is not a pass. Clean
`54fd05a7859ed273fd8cce0770fced927b053d8a` changed only the tracked plan and
passed the remaining family/canonical freshness, exact authored-file formatting
and product/spec whitespace in `run-ZTU6kF`, complete exit 0. No product/build
inputs changed and successful tests were not repeated.

`p2-row-watermark-execution.json` retains original summaries, logs, focused
receipts and member SHA256 hashes for all attempts. `prepared-p2-row-watermark.mjs`
keeps the pinned commands and original 60-second / 5-second grace, non-heavy
guard. Final Owners 31918 and 33562, their groups and the own worktree lock
were observed absent after terminal receipts; no shared Heavy lock was acquired.

Existing generators update the grammar manifest, document metadata, spec family
and canonical consumer. Independent Values preimages reseal only the authored
grammar/rules dependencies. The complete dedupe predecessor, original grammar,
rules and public inventory remain frozen. No historical Run is reinterpreted.
The unchanged independent enumerator counts 4032 declared public cases, adding
eight normal and six refusal fixtures; declared inventory is not execution.

**Unexecuted:** ordinary matching five-package production, Local/HTTPS actual
rows/full ordered schema, admission refusals, same-request/re-read observations,
cleanup, Native/Wasm execution and hosted CI. The normal corpus and existing
`--row-watermark-only` consumer contain the prepared controls. Public execution
needs a coordinated Heavy window and remains an unfinished acceptance boundary.
Parent #1604 remains a dependency; the target is main after normal integration.
The full four-Carrier/P2 frontend goal is not complete.
