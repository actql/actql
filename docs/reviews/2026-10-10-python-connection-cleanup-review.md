# Python Remote Client connection cleanup review

This is a review of the first shared async/sync Remote Client slice, not a
completion claim for the Python work order. Current main 2953cd783 was normally
integrated without changing wire versions or Host execution semantics.

## Finding and repair

At original PR head 765e97e6a, an invalid Host profile followed by transport
cleanup failure replaced the negotiation error and left no returned Client.
The sync facade additionally closed the Runner needed by that unfinished
cleanup. Both new facade regressions failed before the repair.

`ClientConnectionCleanupFailed` now retains the original negotiation error,
cleanup failure, and the same cleanup Client. The synchronous facade retains
its original Runner until explicit cleanup succeeds. Neither path reconnects,
submits, cancels, or retries an unknown operation. Successful cleanup is
idempotent. Public stubs and the README describe this exceptional return path.

## Independent verification

Executed source: `2f879aaf11d249633c1060a9e9ae78a3f777d420`.

- Generated contract freshness, 37/37 focused tests with no skips, and the
  public typed consumer passed: `run-KMAefp`.
- A wheel was built from that committed source and installed with its pinned
  Remote dependencies into a new external virtual environment.
- All 15 package/license payloads matched `git show` bytes from the execution
  source. Wheel SHA-256:
  `6848c305ed9bd0e38e2d00841ea699e822516eb2756a5eb1bce37e74eb6e555d`.
- The installed wheel passed the actual HTTPS Host test: async and sync normal
  execution, separate Python-process lookup/attach/read, and original text
  rejection diagnostics. Six consumer processes succeeded; only the two
  explicit valid submissions computed. Receipt `run-6ZadvT`, focused detail
  `root-python-public/focused-test-UZESjw`.
- Only the consuming Local Node/Run Host runtime packages were prepared.
  This is not a fresh complete packed cohort campaign.

These runs used Python 3.12.12 on darwin-arm64. The declared Python 3.11 minimum
and other environments were not independently exercised here. Hosted CI stays
disabled and was not started.

Real Source execution, Host restart and signed Checkpoint continuation, the
remaining public fault matrix, and the separate Local Wasm prototype remain
work-order items. Merging this slice does not mark those items complete.
