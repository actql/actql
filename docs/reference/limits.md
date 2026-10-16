# Runtime limits

Every runnable Program has a finite ceiling for each quantity that matters.
A ceiling is never a request for the first N items: exceeding it fails the
protected work with an error, and nothing is truncated or returned as if it
were complete.
Which forms run today in each environment is on
[Implementation status](status.md).

## Where a limit comes from

| Source | Example |
| --- | --- |
| Program proof | A `LIMIT 10` or a proven unique key bounds the rows that follow. |
| Author guard | `MAX_OUTPUT_ROWS n` on a join, `MAX ITEMS n` on `INFER`, a guard bound from `--params`. |
| Connector contract | A source's page size and maximum rows; an Effect's maximum items per request. |
| Language law | Fixed ceilings such as the decimal precision of 38. |
| Host policy | Capacity limits the operator configures for the Host. |

The effective limit is the smallest applicable candidate. An author guard that
is stricter than everything else is *binding*; otherwise it is kept and
reported as *currently non-binding*. The plan (`actql explain --json`) shows
every resolved limit with its source.

## Default ceilings

| Quantity | Default | Set by |
| --- | --- | --- |
| Rows in a local `VALUES` Program | 100 (configurable up to 10,000) | Host installation (`valuesMaxRows`, an `installation` option where the SDK creates the Host) |
| Rows read from a source per Run | Connector contract | Connector |
| Bytes read per Run and total work | Host capacity policy (512 MiB in the default Local profile) | Host |
| Model calls per `INFER` | Row count, capped by `MAX ITEMS` when set; no call is made if the count would exceed the limit | Program and Connector |
| Model retries | Transient failures only, within a fixed bound | Language law |
| Rows produced by a join | `MAX_OUTPUT_ROWS` when set, otherwise Host capacity policy | Program and Host |
| Effect items per Set | Connector contract | Connector |
| Result read response | 1 MiB per read by default, 16 MiB maximum | Client option |
| Query text | A fixed decoded size and token budget | Language law |

## Author guards

A guard is a positive integer the author adds to a Program, as a literal or a
parameter: `JOIN … MAX_OUTPUT_ROWS 1000`, `INFER … MAX ITEMS 500`, and the
per-operation guards listed in the [language specification](../spec/language.md).
Guards are kept even when a proof or a ceiling is tighter, so a reviewer can
see the author's intent.

## What a limit does not do

- It does not select rows. `LIMIT` selects; a guard only fails.
- It does not change meaning when the Host changes; only whether the Program
  may run.
- It does not promise that an external system answers. Finite work can still
  wait for a reply, and an unknown outcome is reconciled, not timed out into
  failure.

See [Execution model and guarantees](../concepts/execution-model.md#bounded-execution)
for the guarantee these limits implement.
