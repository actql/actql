# Client CI groups

The `client` required check remains the aggregate result for all Client
acceptance. The workflow now schedules these independent workloads:

- `client-packages` packs the same five Client distributions once
- `client-distribution` runs the unchanged distribution gate, including source
  fixtures, packed Node/Checkpoint acceptance and native Client verification
- `client-packed` runs the unchanged Embedded Checkpoint, single INFER,
  public SQL/Pipe and Result description acceptance, with existing evidence uploads
- `client-salesforce` runs the unchanged Salesforce and recovery gates, including
  both Compute-count probes and all nine process-death boundaries

Distribution and packed-public jobs need only the package producer. Salesforce
starts independently. Its source-backed recovery imports require the Local
runtime bridges; it prepares these in its own checkout before the existing gates.
Each workload retains the previous 30-minute limit. The five-minute `client`
aggregate runs even if a dependency fails and rejects failure, cancellation and
unexpected skip. The existing global `check` still requires `client`. Performance
and diagnostic-probe modes retain their original conditional behavior, as does
the optional macOS gate.

## Immutable package handoff

The producer uses `scripts/packed-client-packages.mjs` without skipping `prepack`.
Its existing manifest records the actual Git checkout SHA and the SHA-256 of each
tarball. It is published only when tracked source and untracked build inputs are
clean both before and after packing. In PR CI, this can be the test-merge SHA;
the PR branch head alone does not identify the tested source.

The artifact contains only that manifest and the five named tarballs. Consumers
download its exact artifact ID through the producer's output, rather than
searching for an artifact by branch or matching a name from another attempt.
The producer's artifact name includes run, attempt and event SHA. A new producer
attempt creates a new artifact; a targeted consumer retry can keep using the
successful producer's original immutable artifact. Seven-day retention is for
short-lived acceptance inputs; an expired artifact fails the retry and requires
a new producer run, never an unverified fallback.

Every consuming script still checks actual checkout SHA, clean source and each
tarball's digest before copying it into its own fresh installation root. Missing,
stale or tampered artifacts fail rather than silently repacking. No `node_modules`,
Moon `_build`, native executable, mutable installation or observation is shared
between jobs, OSes or targets. The npm download cache is private to each job;
installation roots remain private to each consumer.

## Local and hosted verification

Run the narrow scheduling and artifact fixtures while editing:

```
node --test scripts/client-ci.test.mjs scripts/packed-client-packages.test.mjs
```

The independent acceptance commands remain available through
`node scripts/local-checks.mjs run client-distribution`, `client-packed` and
`client-salesforce`. Local execution does not emulate Actions artifact transport;
without `ACTQL_PACKED_CLIENT_PACKAGES`, scripts retain their existing normal-pack
fallback. To reuse distributions locally, first commit all source changes, run
`node scripts/packed-client-packages.mjs <outside-checkout-directory>` and point
`ACTQL_PACKED_CLIENT_PACKAGES` at that exact directory. Source changes invalidate
it. `client` itself is CI-only aggregation. Hosted CI verifies the final submitted
revision, actual artifact handoff and complete foundation Git history.

## Assessing the result

Report both elapsed wall span (first Client dependency start to aggregate finish)
and summed runner duration across all five Client jobs, including setup, packing,
artifact transfer, private runtime/native builds and aggregation. Also report
queue/dependency delay separately when available. A shorter wall span can cost
more total runner time; added cold native compilation must remain visible.

The pre-change observations are separate samples: main run
[37008805516](https://github.com/actql/actql/actions/runs/37008805516) completed
Client in 16m04s, and reporting-only PR run
[37015420457](https://github.com/actql/actql/actions/runs/37015420457) took 19m50s.
Run [37017118941](https://github.com/actql/actql/actions/runs/37017118941) cancelled
at 30m20s during Salesforce, leaving its recovery probes unexecuted. Packing was
only 26–35s. Different source/runner/load and failed/incomplete runs are not
controlled successful comparisons. Independent retry scope and reduced per-job
timeout exposure are the immediate goals. Pipeline evidence remains a separate,
longer critical path; this split does not establish a whole-workflow speedup.
