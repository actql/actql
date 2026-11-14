# Native approval performance

The `nativeApprovalTarget` profile in `scripts/operation-performance.mjs` applies
only to the existing small `deal-review-mock` and `churn-risk-mock` workflows.
Each template needs 30 completed, independently verified approvals on one fixed
runner and one immutable Native cohort. The target is approval p95 <= 4000 ms
and maximum <= 5000 ms, with zero functional failures or timeouts. This does
not change the portable SQL profiles or turn a command timeout into acceptance.

The timer begins immediately before the public `approve --wait --json` process
and ends after its cleanup and exit. It excludes initialization, initial Run
capture, and human waiting. The unchanged installed consumer additionally checks
the two Effects, complete Result, separate-process Saved reread, no Model
restart, and no extra writes. The formal collector reuses that consumer and its
fresh private installation/state; it never replays a failed business state.

The required ordinary Linux Local producer already executes both installed Mock
workflows. Its ordinary consumer now checks each complete approval process
against the same maximum of 5000 ms as the formal profile, using the existing
monotonic `wallNs` observation.
Missing, invalid, failed or duplicate observations cannot pass. This is a
two-fixture maximum-only smoke check; it supplies no p95 or formal acceptance.
Both functional workflows and their counter checks finish first, and the
original receipt, raw timings and smoke verdict are saved after registry close
before a slow verdict exits nonzero. The existing 120-second command timeout
and cleanup behavior remain unchanged.

Resource-enabled formal collection retains every slow sample for its own
30-per-template, 4000/5000 ms assessment. It does not use the ordinary smoke
cutoff. This smoke check needs no timing baseline and adds no workflow runs.
The separate Health Quick comparison remains warning-only for latency; adopting
a reviewed comparable Quick baseline alone does not turn its timing warnings
into a failing performance gate.

Prepare the exact immutable Native release with the existing canonical producer,
then run through the existing bounded local-check guard:

```sh
node scripts/test-native-approval-performance.mjs \
  --normal /absolute/path/to/fixed-native-release \
  --output /absolute/path/to/new-report.json \
  --runner fixed-runner-name
```

Use `--diagnostic` for three samples per template before the final campaign.
That mode reports median/max and `incomplete`; it cannot supply an acceptance
p95. A final incomplete or failed campaign exits nonzero. Failed attempts remain
in the report and cannot be filtered into a faster successful population.
An unfinished process receives no invented completion latency.

The consumer requires clean fixture source matching the release manifest. The
report retains source/artifact receipts, fixture and sampler digests, Node/OS/
architecture/CPU/runner identity, load averages, raw approval durations and
success/failure counts. Load observations do not establish machine isolation.
Opt-in Native counters and phases remain enabled and are disclosed.

CPU and peak RSS come from the OS `time` sampler for the Node launcher and its
waited Native child, rather than the collector's own resource usage. Its report
uses a separate file so Native stderr remains unchanged. The monotonic wall
timer conservatively includes sampler overhead. CPU has the OS sampler's
reported precision; RSS is not a whole-Host live-memory or cleanup-ACK claim.

The normal installed mock consumer also enforces a structural work regression
independently of latency. Original Source/adoption/current and SQL observations
are bounded relative to actual external/signing boundaries and Effect writes.
Missing, duplicate, overflowed or disabled counters fail. Slot 64 names actual
full signing boundary observations; it does not reuse slot 21's Environment
admission. Slot 65 must remain zero: it observes any repeated Source/package/
adoption/material admission inside the same valid signing-original helper.
These observations never supply currentness or alter execution. The fixed allowances are conservative controls for this small
workflow, not runtime budgets, generic tariffs, or cached Allow decisions.

Checkpoint restoration, material completion, Reviewer signing, independent Host
signing, resolution commit, apply, publish and close have separate bounded
phase observations. Inclusive phases and their process-counter SQL/current deltas may nest and
must not be added together. `parallel_observed` identifies overlapping process
work; these deltas are not exclusive SQLite-I/O costs.

The actual Arena Read fixture separately checks immutable material reuse, Read
exit, fresh public entry and actual Source replacement. It has no signing Store
receiver and does not qualify signing. That qualification belongs to the normal
installed approval consumer and final matching artifact.
