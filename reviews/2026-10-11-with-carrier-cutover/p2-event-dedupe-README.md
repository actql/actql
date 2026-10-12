# Event dedupe source connection

This finite P2-T unit connects the adopted `dedupe_events(by, order_by)` call
to the existing common Program and Event checker. It adds no execution owner,
provider, numeric law, value representation, or compatibility fallback.

```aql
WITH rows AS (
  SELECT 1 AS event_id, 20 AS occurred_ms, CAST(NULL AS FLOAT64) AS bucket,
    CAST(NULL AS FLOAT64) AS score
  UNION ALL SELECT 2, 10, CAST(NULL AS FLOAT64), 7
  UNION ALL SELECT 3, 30, 2, 5
  UNION ALL SELECT 4, 5, 2, CAST(NULL AS FLOAT64)
), ev AS (FROM rows |> to_events(id: event_id, time: occurred_ms)),
picked AS (
  FROM ev |> dedupe_events(
    by: [bucket, BUCKET],
    order_by: [{field: SCORE, dir: 'desc', nulls: 'last'}]
  )
), result_rows AS (FROM picked |> events())
SELECT event_id, occurred_ms, bucket, score
FROM result_rows ORDER BY event_id
```

The independent expected event IDs are `2, 3`. The source also accepts the
common shorthand `{OCCURRED_MS: 'asc'}`; its implicit NULL placement stays with
the common OrderKey contract. Full and shorthand field names retain their
source role and ordinary scope until lowering. Empty and repeated grouping
lists remain authored; no implicit event-ID or arrival-order tie breaker is
added. Wrong Carriers and invalid orders retain common typed causes. Unknown
or dropped fields and old aliases are refused in frontend name resolution.

Before the fix, clean `26521e7d8` produced JS1/3: the independent JSON control
passed, while both source forms failed at parsing. Clean
`234d0f86f5a1a52f72b97ae9b931a0a71fba3ef1` passed JS27/27, the selected grammar canonical JS1/1,
Node130/130 and four read-only freshness checks. Its aggregate guard ended
255 because package-level format selection reached an unchanged Model capture
file. The raw failure remains. Clean `592728aafdd041ce41b21a8f7514713bc74f2d80`
then passed exact-file pinned `moonfmt` comparison for eight authored files and
product/specification whitespace. Only the tracked verification plan changed
between these sources; no product or build input changed.

`prepared-p2-event-dedupe.mjs` retains the actual 60-second / 5-second grace,
non-heavy commands. `p2-event-dedupe-execution.json` indexes original summaries,
outputs, focused receipts and member SHA256 hashes, including every retained
failure. Older grammar/rules, complete Values preimages, the former public
inventory and retired refusal sources remain immutable. Current grammar-bound
Values expectations come from the independent oracle, never runtime output.

The prior Graph MATCH aggregate alias imports were not understood by the
existing independent inventory enumerator. They now use equivalent direct
spread registration; the enumerator and rejection policies are unchanged.
The independent current inventory is 4018 cases. The formerly pinned 3980
inventory stays historical; neither inventory implies execution.

Public preparation contains ten normal cases, six pre-admission refusals and
two top-tie execution failures. JSON and text controls have explicit independent
rows and full ordered contracts, including nullable fields and typed empty
input. They participate in normal packed registration and the existing bounded
`--event-dedupe-only` selection. This selection avoids unrelated Planner,
Effect and retained-String campaigns.

**Not executed:** public Local/HTTPS, fresh matching five-package production,
actual winner rows/schema, same-request/re-read observations, top-tie terminal
failure, Native/Wasm execution and hosted CI. A shared Heavy window is required
before the ordinary package producer and selected public consumer can run.
Prepared fixtures, common checking and source lowering are not Host evidence.
Remaining P2 operations and full frontend completion remain separate work.
