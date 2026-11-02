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
| Rows admitted by a local Values lowering sequence | 100 across its Values roots | Host profile; `valuesMaxRows` configures only the source-free, single-task Values profile, not every Program using `VALUES` |
| Rows read from a source per Run | Connector contract | Connector |
| Logical retained and execution byte capacities | 512 MiB for each counter in the default Local policy | Host policy |
| Transfer bytes and total work | Separate admitted Host and operation limits | Host and selected profile |
| Model calls per `INFER` | Row count, capped by `MAX ITEMS` when set; no call is made if the count would exceed the limit | Program and Connector |
| Model retries | Transient failures only, within a fixed bound | Language law |
| Rows produced by a join | `MAX_OUTPUT_ROWS` when set, otherwise Host capacity policy | Program and Host |
| Effect items per Set | Connector contract | Connector |
| Result wire bytes | Selected Host limits; the current Node Local profile advertises 10 MiB total per read and 1 MiB per row | Host; client options can only tighten |
| Query text | A fixed decoded size and token budget | Language law |

### Capacity and Result quantities

The Local policy's 512 MiB figures are separate logical retained-byte and
execution-byte ceilings. They are not a per-Run network-transfer allowance,
a process RSS limit, a physical allocation, or a latency bound. Transfer and
work have their own counters. A policy ceiling does not supply the backing for
a constructor: its actual input, workspace, output and failed-child overlap
still need admission under the same original resource.

Result limits are negotiated independently. The current Node Local profile
advertises `maxReadWireBytes` of 10 MiB and `maxRowWireBytes` of 1 MiB. Its
separate decoded-value bounds are `maxRetainedValueBytes` of 10 MiB and
`maxRowRetainedValueBytes` of 1 MiB; batch rows and retained bytes have their own
bounds too. A total wire limit is not a per-row or decoded-retention limit.
Client Result-read options default to the negotiated bounds and may only make
them smaller. Other Host profiles must state their own selected bounds; these
Node Local values do not establish a universal Result maximum. See the
[Local Host profile](../../packages/local-node/README.md).

### Local Values profiles and JOIN

The ordinary Local profile can execute bounded source-free `VALUES` joins,
including filter, derive, group and sort pipelines. Its finite preparation
budget is shared by the Values roots of a lowered sequence: 90 order rows
plus 10 customer rows fit the default 100-row budget; 100 plus 10 do not.
Separate output guards and work, cell, value and byte ceilings still apply.

`installation: {valuesMaxRows: 2000}` selects the configurable **single-task**
Values profile. The option accepts a positive signed 32-bit integer; this is a
representation bound, not a workload admission guarantee or a separate 10,000-row
product cap. Cell, value, byte, work and Host resource limits still apply.
It is not a general increase to the ordinary multi-task
profile's capacity. A single authored Stage can normalize into several tasks,
as a two-root Values JOIN does; that Program is refused under this explicit
profile even when each input contains only one row. Omit this option to use
the ordinary profile within its existing limits, rather than using it as a
blanket setting for a mixed workload. See the
[Local Host profile](../../packages/local-node/README.md).

`check()` can report `verified` and contextual `runnable: yes` for such a
Program without admitting execution under the selected physical profile.
Checking neither runs the JOIN nor grants additional capacity; execution
admission can still refuse it. See [Checking](../design/check-sdk.md).

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
