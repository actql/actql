# Authorization and diagnostic lifetimes

This change addresses the second boundary-review unit on
`fix/authorization-observation-lifetimes`. Its base is
`c1ed3f526e2e5576e3cdd172b4b6a66c893fdd4f`. It does not change account
policy, the Checkpoint wire contract, or Effect apply semantics.

## Baseline findings

| Finding | Baseline result | Product boundary |
| --- | --- | --- |
| Decision retention | Reproduced: exact decisions accumulated in an unbounded gate Map, including across `withContext()` scopes. | A decision scope now owns a bounded Map and must close at execution end. A Host installation shares capacity without sharing judgments. |
| Decision timeout | Reproduced: a timeout returned while the `decide()` signal remained live. | A child signal receives the deadline and parent abort. An uncooperative callback retains its physical slot until settlement; another request cannot exceed the installation limit. |
| Diagnostic observation | Reproduced: an unresolved authentication observer blocked refusal. Dispatch observations were awaited and could fail execution. | A bounded diagnostic owner drops excess events and cannot change execution. Explicit fault injection remains awaited; execution retention remains mandatory. |

The installed Checkpoint Host creates a short-lived decision scope for each
new acceptance or source-read decision and closes it after judgment. These
scopes share one installation budget. Resume gates use the same current
account and durable Checkpoint admission; cache eviction does not grant or
extend permission. The Host closes its diagnostic owner and reports whether
physical authorization or diagnostic delivery is still pending at close.

Tests cover child abort without parent abort, cooperative and uncooperative
callbacks, cross-request capacity at the installed HTTPS Host, exact decision
reuse, scope release, diagnostic throw/reject/non-settlement, and a new Host
after diagnostic owner close. The existing held-read, restart, cancellation,
dispatch cleanup, packed Checkpoint, and native Client tests remain in the
Client and Host jobs.

## Validation

- Implementation SHA: `da46295e22f48f4efd21c1b717239e11cd26598e`.
- Focused authorization and Host tests: 88/88 passed.
- `node scripts/local-checks.mjs run client`: passed after correcting a
  `null` authorization regression found by the first run.
- `node scripts/local-checks.mjs run host`: passed with a workspace-local npm
  cache. The first run could not write the pre-existing home npm cache and
  stopped before code tests.
- Linux CI on the final PR SHA: pending at the time of this record.

This unit does not implement the separate Effect commit Checkpoint connection
or the Local Compute accounting-checker review item.
