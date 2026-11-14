# Client CI groups

The Host job retains `check:local-node-source-assets`: source input/type checks,
clean prepack from an empty producer, and external connector compositions. These
construct different inputs and do not consume the normal shared tarballs. The
local `check:local-node-assets` command still includes the normal asset consumer
and its existing Sheets postcheck. CI schedules those consumers in `client-packed`
instead, without making the source-backed Host job wait for package production.

The `client` required check remains the aggregate result for all Client
acceptance. The workflow now schedules these independent workloads:

- `client-packages` packs the same five Client distributions once
- `client-supported-versions` installs the same run's normal tarballs in fresh
  external consumers for the minimum and latest supported Node versions. SDK
  cases check import and a fixture HTTP round trip; Local cases check open, query and
  close. These consumers cannot rebuild packages or resolve checkout runtime.
- `client-distribution` runs the source-backed distribution contract tests
- `client-distribution-callers` runs the existing Host preparation and resource callers
- `client-distribution-mutations` runs the four original mutation commands
- `client-distribution-packed` uses the shared tarballs for Delivery, dependency-free
  Local, Node, Workspace, Graph and Checkpoint acceptance without a source runtime build
- `native-cli-installed` builds the versioned Remote CLI, exercises its fresh
  installation, and runs the unchanged Native Client transport/contract corpus
  against that exact installed binary; no second plain Remote build is needed
- `client-packed` uses the shared tarballs for normal Local asset and Sheets
  consumers, and runs the unchanged Embedded Checkpoint, single INFER,
  public SQL/Pipe and Result description acceptance, with existing evidence uploads
- `client-packed-composition` uses the same exact tarballs for the complete
  Source JOIN INFER Effect approval and process-recovery acceptance
- `client-salesforce` runs the unchanged Salesforce and recovery gates, including
  both Compute-count probes and all nine process-death boundaries

The package consumers and source-backed distribution jobs depend on the exact
package producer. Native Client transport shares the existing installed Remote owner and its exact
normal package input; Salesforce starts independently.
Salesforce's source-backed recovery imports require the Local runtime bridges;
it prepares these in its own checkout before the existing gates.
The existing distribution and installed-query workloads retain their 30-minute
limits. Each supported-version case has a separate 10-minute limit and does not
multiply the Native, proof or mutation campaigns. Source composition has its
own runner so the other installed-query consumers cannot consume that budget.
Its complete command is unchanged and remains required by `client`.
The old 53-command
`check:distribution-client` local umbrella is unchanged. Its independent CI
workloads retain the 48 remaining original commands once: only the duplicate
plain Remote compiler is retired, while its transport suite uses the versioned
installed binary through `ACTQL_TEST_NATIVE_CLIENT_BINARY`. The local umbrella
still keeps its original build-and-test command. The four common source
preparation commands repeat only in the three source-backed jobs. Each job has
private installation, mutation and compiler state. After successful preparation,
independent cases continue after a sibling failure and respect cancellation.
The five-minute `client` aggregate requires every workload and rejects failure,
cancellation and unexpected skip. The existing global `check` still requires
`client`. Performance and diagnostic-probe modes retain their original
conditional behavior, as does
the optional macOS gate.

## Change-scoped PR verification

Main integration retains all runtime families. Ready PRs may use the existing
maintenance/focused profiles or a compiler-owned Moon test plan; a failed or
unavailable diff never authorizes omission.

- Reviewed modifications to contribution/CI prose and the standalone performance
  report assessor retain lint and spec, including their actual synthetic tests,
  without starting unrelated product, Native, wheel or proof producers. New,
  deleted, renamed, executable or aliased files stay full. The list is explicit
  in `scripts/ci-targets.mjs`, not every Markdown or JavaScript file.
- `docs/development.md` is also an executable input: packed acceptance reads its
  Quickstart through `readmeQuickstart`. A prose-only edit may stay maintenance;
  changed or missing Program, client, expected output or shell blocks restore
  normal product verification.
- For a regular Moon-only PR modification, the pinned compiler supplies
  `moon tree --package --json`. Selection includes the changed packages and all
  reverse source, whitebox-test and blackbox-test imports. The graph must cover
  every tracked package manifest. Selected direct files avoid accidentally
  executing unrelated nested packages.
- JS/Wasm consumers independently reproduce the normalized graph digest and
  original file inventory at the tested checkout before calling the existing
  nonzero test wrapper. Every Core target still runs whole-module
  `moon check --deny-warn`. Native receives the same checked package closure
  inside its existing full-classification entrance. Its compiler first discovers
  the complete original case inventory, then checks the selected drivers against
  those exact inputs/case identities. Original HTTP, Source, ordinary and scoped
  provider profiles remain distinct; physical cases never move to an ordinary
  or unfunded invocation. Both ordinary partitions remain nonempty/disjoint,
  with auxiliary profiles owned once by partition 1.
  If a backend has no runnable selected compiler cases (including testless or
  benchmark-only inputs, or a JS-only package on Wasm), that backend retains its complete nonzero suite.
  The reason is printed; zero discovery never becomes a successful test result.
  Native also prints an explicit full fallback when the requested closure lacks
  two nonempty ordinary packages, has no runnable original cases, or would admit
  an unselected nested package through a directory input. Neither the metadata
  deadline nor the original execution/compiler budgets are extended or reduced.
- FFI/platform, generator/build, JS bridge/distribution and proof-snapshot
  relationships are declared in `ci-moon-test-plan.mjs`. They are not inferred
  from Moon imports. Their existing product jobs remain required. In particular,
  the proof snapshot still includes all `src`/`vendor`, so a selected Moon test
  plan does not narrow the registered three-target proof campaign.

Manifest, toolchain, CI infrastructure, structural and unfamiliar target/ownership
changes retain broad verification. Unsupported/malformed compiler metadata or an
oversized plan produces an explained full fallback. The same final gate still
rejects failed, cancelled, missing and unexpectedly skipped required jobs. An
unselected family supplies no execution evidence. Graph acquisition is metadata
only and never substitutes a new package/runtime build for an existing producer.

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

Each independent workload remains available through
`node scripts/local-checks.mjs run <job>`, including the five
`client-distribution*` jobs, both `client-packed*` jobs and `client-salesforce`.
`npm run check:distribution-client` retains the complete original local sequence.
Local execution does not emulate Actions artifact transport;
without `ACTQL_PACKED_CLIENT_PACKAGES`, scripts retain their existing normal-pack
fallback. To reuse distributions locally, first commit all source changes, run
`node scripts/packed-client-packages.mjs <outside-checkout-directory>` and point
`ACTQL_PACKED_CLIENT_PACKAGES` at that exact directory. Source changes invalidate
it. `client` itself is CI-only aggregation. Hosted CI verifies the final submitted
revision, actual artifact handoff and complete foundation Git history.

## Controlled ordinary-operation performance check

Normal CI runs the quick behavioral validation and assessment-policy tests.
Statistically sampled public operations belong to the separately requested
performance matrix, not every PR or ordinary integration run. Select the exact
artifact ID from a successful `client-packages` job in a completed normal CI
run at the same commit:

```sh
gh workflow run CI --ref <same-source-ref> -f performance_matrix=true \
  -f performance_package_run_id=<normal-run-id> \
  -f performance_package_artifact_id=<client-package-artifact-id>
```

The required ordinary-operation job verifies the original run, attempt, source,
package job and artifact identity, then reuses those five tarballs. It checks
their digests and independent unpacked member inventories, performs a fresh
default npm installation, and verifies the installed members. Missing, expired,
foreign or changed inputs fail without invoking a compiler, pack or replacement
producer. Other failures in the original CI run remain failures; authenticating
its successful package job is not whole-run acceptance.

The existing public collector runs in final mode and the complete performance
assessor runs even after measurement failure. Slow, malformed or missing raw
measurements cannot produce a successful performance workflow. Raw samples,
controls, source/package identities and failed or incomplete assessment are
retained separately from ordinary functional acceptance. The collectors cover
warm SELECT, saved Result and status, existing-state reads in distinct child
processes, and first initialization in distinct new states. Each uses the same
package consumer and explicit combined protocol. The combined report verifies
the source, cohort, environment and protocol identities and matches each sample
against its retained raw JSONL. Missing families remain absent; missing or
different raw samples refuse. Missing JOIN, UNION, Decimal SUM, Mock, history,
chunk, structural or fault evidence keeps the full release assessment incomplete.
Harness tests or a passing subset do not establish the release latency gate.

## Focused packed Content recovery acceptance

After committing a coherent Content implementation, use the normal five-package
producer above and run `node scripts/test-packed-files-content.mjs` with
`ACTQL_PACKED_CLIENT_PACKAGES` pointing to that verified package directory.
The consumer refuses dirty source and audits the actual installed package graph.
Without the variable it uses each package's normal `npm pack`/`prepack`; it does
not replace packing with checkout imports.

Only authored test fixtures are bundled. Product imports resolve to the fresh
consumer's installed distributions; undeclared imports, linked product files
and checkout fallback are refused. Normative fixture inputs are copied exactly,
with their original digests recorded separately from the fixture bundle digest.
Children run without a MoonBit toolchain on PATH.

This focused acceptance covers generated Content, intermediate SERIALIZE Result
recovery, separate Model and COMMAND approval, process restart and unknown
COMMAND non-resend on Local/HTTPS. It is not the complete files/keyed-capture or
real GCS campaign. The separate staging and observation-detector tests establish
only harness behavior, never execution of a public Run.

Command receipts, five tarball digests and phase observations remain in the
reported `packed-files-content-evidence-*` directory. Its `custody/` directory
also retains the fixture's Store/journal and private synthetic keys, including
unknown writes. Do not upload or delete that custody as ordinary diagnostics.
The successful disposable npm installation is removed only after all children
finish; custody is never inside that disposable installation.

## Explicit real GCS Content diagnostic

`node scripts/test-gcs-files-content.mjs /absolute/authorized-environment.json`
uses the standard installed GCS Source through public Local and HTTPS Clients.
It requires an explicit manifest accepted by
`scripts/gcs-files-content-environment.mjs`: project, bucket, exact prefix,
impersonated service account, logged-in account, absolute gcloud executable,
read-only permissions, finite campaign limits, cost allowance and independently
authored expected object digests/sizes. Merely having credentials is not
authorization to choose another bucket or enable writes.

The gcloud CLI must have a supported Python interpreter; the operator can name
it with the CLI's existing `CLOUDSDK_PYTHON` environment variable. The harness
does not install Python, create secret keys, mutate IAM or log token output.
Short-lived tokens stay in memory behind the existing scoped credential port.
The same campaign shares a pre-send request/response reservation and deadline
across both public entrances; failures do not automatically remint or retry.
Response reservations bound maximum allowed bytes, not measured received bytes.
The dollar allowance is not an automatic billing hard cap.

The authored Program explicitly uses the installed query Owner's current
scan/filter/select capture boundary, retaining every listing column before
resource/version keyed JOIN. A one-item page ceiling exercises real pagination.
The test compares ContentRef byte digests and sizes with independent expected
objects, rereads the same Named Result by reattach, and verifies an empty
selection sends nothing. It then closes the original Host and opens each public
entrance in a fresh process, comparing the same Run Ref, complete description
and rows while its credential resolver rejects every call. It performs no
object writes, deletes or version-change
injection; those require separate explicit authority and evidence.

Evidence and original Run/credential journals remain in the reported
`gcs-real-content-*` directory, including failures. Synthetic Host signing keys
are private custody, not uploadable diagnostics. This runner records the actual
checkout state and compiled runtime digest. Its source-built result must not be
described as pristine packed acceptance, restart of unfinished capture, paid Model
acceptance or complete INFER/COMMAND composition.

`node scripts/test-gcs-content-retained-restart.mjs /absolute/original-acceptance.json`
checks the same separate-process Result recovery against an explicitly named
successful real-service record without reacquiring its objects. It retains the
original record's digest, original source revision and fresh-process observations
separately. This tests retained Result recovery, not restart of an unfinished
capture or pending Model/COMMAND operation. Runtime artifact provenance remains
the same explicit source-built limitation above.

## Assessing the result

### Packed real GCS Content campaign

With a clean source revision and its normal five-package producer, run
`node scripts/test-packed-gcs-content.mjs /absolute/authorized-environment.json`.
Set `ACTQL_PACKED_CLIENT_PACKAGES` to that exact verified producer directory
to reuse the packages. Stale source, changed tarballs and dirty build inputs
remain refusals; no prepack or artifact checks are bypassed.

The external application uses installed public Local/HTTPS Client, runtime and
SDK entrances. Trusted installation bootstrap also loads the actual installed
GCS declaration asset, recording its digest and generating aliases through its
existing owner. It does not invent Catalog CIDs. Only four authored fixture/helper
modules are bundled. Copied product source, compiled checkout runtime, source
overlays and undisclosed imports are forbidden. Fixture digests and the bundle digest are recorded
separately from all five actual tarball digests.

Both entrances execute the independently expected version-fixed capture and
empty-selection Programs. A fresh process then attaches the original Runs with
all credential resolution forbidden, comparing full rows and descriptions.
The two capture children split the authorized request/response reservation
ceilings and share one absolute campaign deadline. No GCS write, delete or
version mutation is included. This is not unfinished capture or Model/COMMAND
recovery, full Core or Hosted CI evidence.

Original Run/credential journals, expected rows and private synthetic Host keys
remain outside the disposable npm installation under the reported evidence
directory. The successful installation is reclaimed only after every child
and Host has ended. Failed campaigns and their custody are retained.

Report both elapsed wall span (first Client dependency start to aggregate finish)
and summed runner duration across all Client jobs, including setup, packing,
artifact transfer, private runtime/native builds and aggregation. Also report
queue/dependency delay separately when available. A shorter wall span can cost
more total runner time; added cold native compilation must remain visible.

The packed consumer matrix separates connectors, INFER, portable SQL/Pipe and
the complete Native Graph campaign. All four jobs download the same successful
producer's exact artifact ID and retain the existing source/tarball checks.
They never share application state, keys or an installed Host. Each campaign
step has exactly one matrix owner; the existing Client aggregate requires the
whole matrix to succeed, including its evidence-retention steps.

`test-packed-public-query.mjs --ci-part=portable` retains the full Local/HTTPS
corpus, original Saved/restart checks and public graph cases, omitting only the
final Native campaign. `--ci-part=native` runs that complete original Native
campaign, including its source-free control, after the common installation
prerequisites. The two CI parts refuse narrower selectors and ambient `*_ONLY`
overrides. Running without either option preserves the original serial route.
Compilation occurs only in the Native part; the portable part does not install
the Native compiler. Shared package-installation checks remain prerequisites,
not additional independent acceptance samples.

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

## Source-backed preparation observation

The existing `ci-evidence` / `ci-timing` collector read completed run
[42410011597](https://github.com/actql/actql/actions/runs/42410011597), attempt 1,
reported head `3930886d10d1b0a50ee9a77bae376c196b078b87`. All three selected
Client jobs and their preparation steps passed; the overall run failed.

| Preparation step | Distribution | Callers | Mutations |
| --- | ---: | ---: | ---: |
| Runtime build | 73 s | 74 s | 70 s |
| Adapter build | 4 s | 3 s | 3 s |
| Each wire freshness check | 0 s | 0 s | 0 s |
| Existing normal-tar download | 2 s | 2 s | 2 s |

These are API timestamp differences at whole-second precision: a zero-second
wire observation is not zero work. The normal-tar download does not measure
transfer of a new runtime-output artifact. The runtime stages total 217 runner
seconds; replacing them with one hypothetical 70–74-second build would remove
143–147 seconds before upload, transfer and dependency waiting. That arithmetic
is not measured savings, and the preparation stages already overlap in time.

Do not introduce another shared runtime artifact from this observation alone.
Adapter and freshness work is small, while runtime sharing still lacks a
same-source relocated consumer and mutation-private-copy qualification plus a
net timing comparison. Keep the measured boundaries and private builds until
those requirements justify the extra producer and dependency. The failed run's
35,501 total job-seconds and 4,532-second final-check interval remain separate
observations, never a successful optimization comparison.

## Ready PR and main performance observations

Every public `main` push and full Ready PR runs `main-performance` on Linux with
the normal `client-packages` artifact from that same run. Draft and lightweight
maintenance/focused profiles retain their skips and acquire no new producer.
The selector and final aggregate require the same selected observation job;
missing, failed, cancelled or unexpectedly skipped observations fail that gate.
The job waits only for selection and its original package producer. It does not rebuild packages or
start the heavy performance matrix. The existing ordinary consumer preparer,
`benchmark-node-operations.mjs`, and `benchmark-node-process-operations.mjs`
run in explicit `record-only` mode. Diagnostic/final acceptance modes and their
thresholds are unchanged.

The fixed small SQL fixtures collect three repetitions of warm query/Run,
original Saved Result reread and status, plus actual new-process first-init and
cold-existing operations. Cold-existing submits a new Run; it is **not** a
cross-process Saved benchmark, and no OS cache eviction is performed. These
small fixtures do not establish large-data throughput. Correctness, protocol,
package-integrity and cleanup failures fail the job; elapsed time alone does not.

The job summary shows median/max and process high-water RSS. Three samples do
not establish a meaningful p95; that field remains null. Warm RSS includes
setup and earlier operations in the same process. Child RSS covers only that
actual process, not other workers or subprocesses, and is not per-operation
allocation. Raw wall/CPU samples, child public spans, fixed fixture and protocol
hashes, source/tarball/installed-payload identities, producer artifact/run IDs,
Node/OS/CPU configuration and runner image are retained for 90 days. Compare
like protocols and environments; hosted-runner variance is not a regression
verdict. Full acceptance and larger campaigns remain separate, manually selected
existing performance tooling.
