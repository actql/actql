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

A joined caller now owns its wait independently of the first caller's shared
decision operation. Its own abort ends that wait and removes its listener
without cancelling the physical callback or returning the in-flight slot.
The first caller's abort still stops the shared decision; joined callers
observe that failure. Scope close ends every waiter while an uncooperative
callback retains its slot until it settles.

## Validation

- Implementation SHAs: `da46295e22f48f4efd21c1b717239e11cd26598e`
  and `306ec37d76d1592c7fd94044274b587272530278`.
- Focused authorization and Host tests: 88/88 passed.
- `node scripts/local-checks.mjs run client`: passed on the rebased code,
  including 183/183 Node distribution tests and the packed Checkpoint and
  native Client checks. The initial pre-rebase run found and fixed a `null`
  authorization regression. The first rebased run found that a known
  pre-Run technical delegation failure became `SubmissionUnknown` after the
  transport change on main; the exact non-admission code is now classified
  consistently across both transports.
- `node scripts/local-checks.mjs run host`: passed on the rebased code with a
  workspace-local npm cache. An earlier attempt could not write the
  pre-existing home npm cache and stopped before code tests.
- Linux CI on `9aa171839a3d4493402bf5961e49b21eee40f34e`: all 14 required
  jobs passed. That result predates the joined-wait correction.
- After the correction, the authorization, dispatch-owner, and HTTP tests
  passed together: 55/55. Linux CI on the corrected SHA is required before
  merge and is not represented by the earlier green run.

This unit does not implement the separate Effect commit Checkpoint connection
or the Local Compute accounting-checker review item.
