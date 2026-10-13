# Vector scalar receipt follow-up

This independent child of #1867 retains observations that the existing public
query helper already compares. The original submitted parent was fixed at
`50ed4a8b9e91b61d8cbf647172f2c1aec025465a`; this follow-up does not change its
typed supplier or initialization cleanup implementation.

The success hook now carries the counter snapshot observed after the existing
attach, resend, lookup and result reread checks. The refusal hook carries both
counter snapshots and the actual not-accepted outcome. The collector saves these
observations without another Client call. The Vector runner awaits refusal
receipt persistence before adding that case to its completion inventory.

`public-audit.mjs` independently compares saved observations with the original
12 normal and 8 refusal fixtures for each transport. It checks exact ordered
rows and schemas, the declared acquisition counts, unchanged replay/refusal
counters, inventory completeness and the existing fixture Site close count.
It performs no Client I/O and does not qualify package identities; the existing
producer manifest and digest checks retain that responsibility. Its three new
Node tests use synthetic verifier inputs and are not public execution evidence.

The original fixture body remains byte-identical:
`9717e6a803428dadf392562f891687bad8ddbb88691cfbbe6e37137e0fff804f`.
The independent 20-case inventory remains
`1c25524497d9626e0535730a92ea05f314a8f5b756896821cf975fa96986d99c`.
Rows, types, order, parameters, Source ownership and execution limits are unchanged.

## Executed checks

At `dedb6d0a64daab77b2f6d3bd4747a9cda230ae87`, the selected Node gate
`run-az6Elf` exited 1 with 19/20 passing. The existing CTE receipt snapshot
omitted the new `afterReplay` field. Its independently specified expected
counters were extended to one accepted Run and zero source reads/I/O; its full
row/schema assertions and existing two-reader/one-description checks remain.
The original failed summary and output are preserved.

At clean `461649beba5f970703931294f3dac36ccaf07677`, tree
`3e74301f12a6fea54833697d2d323f0808858363`, the same selection passed 20/20:

```sh
node scripts/local-checks.mjs test node --timeout-seconds 60 --kill-grace-seconds 5 -- \
  scripts/vector-scalar-public-audit.test.mjs \
  scripts/vector-scalar-installed-source.test.mjs \
  scripts/vector-scalar-source.test.mjs \
  scripts/cte-value-table-source-input.test.mjs \
  scripts/from-unpivot-source-input.test.mjs
```

This used pinned Node 22.22.0 and the existing nonHeavy guard. `run-wKWNrP`
completed with exit 0; focused evidence is `focused-test-jSTlak`. Owner 61134,
its process group and the worktree lock were observed absent after completion.
The raw success/failure receipts are retained in the workspace's
`reviews/2026-10-13-b-vector-scalar-installed-source-evidence` directory.
This document-only commit does not extend those results to a new runtime source.

After the integration owner merged #1867 into main
`d676dc5c85fbbcba23d85659777d2ccdf975c526`, this child normally merged that
main. At clean `83e1bd3d0f0ad10c47f2995110d753d8dec8154f`, tree
`4194f728c589601b10e3cb62f76229ad6ac6f682`, the same exact 20 Node checks
passed in `run-tgwmqQ`, complete exit 0, focused `focused-test-UrbvBn`,
under the unchanged 60-second / TERM-five nonHeavy bound. These are current
fixture/collector/verifier checks, not execution of the checked supplier through
Host capture/dispatch. The earlier pass/failure sources above remain separate.

## Pending public boundary

Producer and installed Local/HTTPS consumer executions remain zero. No new
external E2E scenario, Host capture/dispatch qualification, fresh-process replay,
Hosted CI or release claim follows from these checks. The existing same-clean-
source five-package producer 300 seconds / TERM 5 followed by the same-cohort
consumer 300 seconds / TERM 5 remains preparation only, awaiting the coordinator's
shared window. The original 12+8 cases must complete on both transports; this
follow-up does not exclude failures or weaken their assertions.

After that execution, audit the retained consumer directory without modifying it:

```sh
node reviews/2026-10-13-vector-scalar-installed-source/public-audit.mjs /absolute/consumer/evidence
```
