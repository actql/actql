# ActQL Health Monitor v0.1

This local monitor records distribution and public operation measurements. It
uses normal Release/prepack artifacts and the existing ordinary collectors;
it does not replace [Conformance](../../docs/spec/conformance.md), the fixed
SQLite comparison, or the full all-path performance requirements.

```sh
npm run health:quick
npm run health:release -- --packages /path/to/same-sha/packages \
  --native-manifest /path/to/release.json --native-consumer /path/to/native-install \
  --python-manifest /path/to/cohort.json --python-consumer /path/to/site-packages \
  --python-venv /path/to/venv --node-controls /path/to/node-controls.json \
  --python-controls /path/to/python-controls.json
npm run health:compare -- --base baseline.json --current report.json
```

Use the repository's prepared, pinned Node/MoonBit/tools environment and
[ordinary resource admission](../../docs/development.md#bounded-local-execution).
Quick runs under that existing guard. Without `--packages` it executes normal
`npm pack --json` and each package's original prepack. Actual npm JSON filenames
and versions are authoritative. With `--packages`, supply the existing normal
package directory/`packed-client-packages.json`, or an ordinary collector
manifest. Exact selected source SHA, clean source, archive hashes/integrities
and complete installed payloads are checked; mismatch is an error, never an
implicit rebuild or source-package substitution. A fresh private installation
is created in the run. An offline installation must have any required npm
dependencies in its prepared cache. No real credential or provider is needed.

Quick records the five full Node package tarballs, installed cohort bytes,
Remote SDK browser raw/gzip bytes, and separately the Run Host Core tarball.
Installed bytes are logical file bytes, not filesystem-exclusive allocation.
Bundled DuckDB/Wasmtime/Wasm members retain their actual names and sizes.
Ten samples each cover retained-Host SELECT, the existing literal JOIN and
Decimal SUM Aggregate, original saved Named Result and same-Run status. Five
new processes for each of two separate cold cases cover import/open/a NEW
query/all Result rows/first awaited close. `cold-existing-state` is initialized
and closed through the same installed candidate's public API in a separate
preparation process; each timed process submits a different new Run against
that state. It is not a Saved-only read or an older candidate's migration.
`cold-new-state` gives every timed child a new state, including normal first
initialization. Warm operations remain on one original open Host. Five complete Mock workflows
reuse the exact tracked `mock-project-effect-public.mjs` consumer and original
seven-file `churn-risk-mock` template: separate capture/approve/recover
processes retain all 9/11/7 assertions, actual review/approval/continuation,
target and original Result checks. Every phase keeps its existing 30-second
whole-child limit. Workload errors stop sampling and retain the original cause.
No automatic retry or failed-state replay occurs.

Node peak RSS comes from the actual sample process's
`process.resourceUsage().maxRSS` high-water mark (Node reports KiB, converted
to bytes), excluding compiler/parent/other process memory. Build/prepack,
packaging, browser bundling and installation remain separate reference work,
never included in retained operation latency. Cold-process wall time includes
process startup through natural exit; it does not mean a cold OS page cache.
Parent launch-to-first-Result records the arrival of a fixed all-rows IPC
notification, including its delivery delay. Parent launch-to-natural-exit is a
separate clock. Child monotonic spans separate product import, public open,
new-Run submission, wait/execution/publication, all-row materialization and
first close. The import span covers the public `@actql/node` entry; Local
provider imports selected inside `open` remain in the public-open span.
Query spans retain their parent relationship; neither child
phases nor nested Host work may be added to parent elapsed time. Activation,
prepare/check/compile/Plan, execution and durable-commit internals remain
explicitly unobserved until an actual Host diagnostic supplies them. No wall
span is an exclusive CPU partition. Output/report writes stay outside child
public spans; parent-to-exit retains collector setup, IPC and reporting costs.

Missing CPU observations remain unavailable. Optional Native/Python Quick
coverage is explicit unmeasured; supplied ordinary manifests can additionally
measure their artifacts.

## Reports and comparison

Each invocation creates `_build/health/<time>-<uuid>/report.json`, `summary.md`
and `raw/`. Existing output directories are refused. Failures, including
pre-admission failure, produce reports too. Fresh owned business state, keys,
handoffs and original failed evidence are retained there; they are not replayed
or cleaned by the monitor. Routine reports are ignored by Git. Quick and Release
automatically read `benchmarks/health/baselines/<platform>-<arch>.json` for the
observed platform/architecture, including the zero-option command used by CI.
`--base <file>` overrides that selection. A missing default baseline is
measurement-only: it says comparison unavailable, and does not assert regression
freedom. An existing unreviewed/incompatible baseline is incomplete; malformed
or unreadable evidence is an error. A missing explicit override is an error and
never falls back. The monitor never creates, adopts or updates a baseline file.

Reports bind source SHA/dirty diff, before/after environment and package
inventories, source-bound artifact hashes, fixtures, raw samples, exact counts,
median and min/max reference range. A small Quick sample supplies no formal
p95. Comparison requires the same OS/architecture/**CPU model**, runtime and
tool versions, build settings/load/instrumentation, artifact kind and fixture
methodology. Different commits are expected; each artifact must belong to its
own report's source. Dirty or changing source/environment is ineligible for a
formal baseline. Non-comparable fields/reasons stay explicit.
The report retains its fixed `methodologyFiles` source digest map. Both modes
bind the selected public fixtures, Node collector, runner, statistics and
artifact readers; Release additionally binds its cold-process, Native/Python
collectors and installed-artifact inspectors. A selected collector change
invalidates methodology compatibility even if the SQL literal is unchanged.
Earlier reports keep their original digest; the monitor does not relabel them
or regenerate a baseline to match this expanded source inventory.
The fixed Quick/Release inventory and sample counts are checked independently
of a saved report's required flags/count claims. Collector errors disqualify a
baseline; an expected verdict exit (such as size-regression exit 1) does not.
Build/reuse reference timing never gates otherwise comparable size/runtime data.

Size deltas show both bytes and percentage: npm/wheel/Native/Wasm +10% warns,
+25% regresses; browser gzip +5%/+15%. Quick median warnings require both +30%
and +3 ms warm, or +30% and +50 ms cold. Peak RSS +20% warns. Performance
warnings alone exit zero. First failures remain retained if a human later
deliberately repeats an experiment.
Installed bytes and raw-browser bytes retain their measured deltas without an
invented size gate; the initial policy specifies package and browser-gzip gates.

To establish/rebaseline, review an actual clean, complete report and copy it
to `baselines/<platform>-<arch>.json`, adding `baseline: {id, reason,
reviewed: true}`. Commit that real reviewed report and reason. There are no
placeholder metric values in this repository. CI never writes baselines;
until a real baseline is reviewed, size comparisons do not gate an initial run.
Baseline selection does not weaken CPU/OS/toolchain/fixture/methodology checks;
use an explicit matching Release baseline when the platform default is Quick.

Exit codes: pass/warning **0**; size regression **1**; required missing or
non-comparable evidence **2**; build, execution, fixture, collector or integrity
error **3**. Optional first-baseline absence and optional platform absence do
not fail Quick. Missing required Release artifacts/evidence is nonzero.

## Release boundaries

Release selects at least 100 warm/30 cold samples by invoking the existing
Node warm/process and ordinary Native/Python collectors in **final** mode,
with their fixed SQLite comparator, formal assessments, early stops and failure
semantics unchanged. Missing artifacts/comparison are detected before a large
formal workload starts. Python wheels are checked by the existing ordinary
package verifier, including payload RECORD hashes; actual contained Wasm is
measured. Native retains its normal release manifest/verifier and also uses the
ordinary collector's package verifier against the selected installed consumer.
Installed Native metrics sum the verified selected package payload bytes; npm
metadata, unrelated dependencies and filesystem allocation are outside that
scope. Other platforms' archives retain acquisition sizes with installed size
explicitly unmeasured. Missing, linked or changed installed payloads are errors.
The same read-only verifier checks the selected Native cohort and installed
payload inventory again after collection, including an early collector error.
The report retains the original failure and the separate after-check result;
missing before/after identity observations cannot qualify a Release comparison.
Python wheel expansion bytes remain separate from actual installed bytes.
The Python product installed metric inventories only the union of namespaces
owned by the three selected wheels, including installed metadata and generated
bytecode. It excludes unrelated dependency roots and filesystem allocation;
archive totals and bundled component breakdown remain intact. Original verified
payloads must match that inventory, and the same namespaces are checked again
after collection. Changes retain the original collector error and fail the
report. No alternate backend stands in for an unavailable target.
Node controls are the existing collector's original source/cohort/environment,
history protocol, fixed comparison and actual per-operation comparison/settings
observations. Python controls retain their own source/cohort/environment,
runtime-matched comparison and observed operation/settings/result-key matches.
Release separately records the version and executable hash of the selected
`--python-venv/bin/python`, alongside the controller interpreter. Each ordinary
Python collector must report that same runtime. Different, missing or malformed
selected-runtime identities prevent comparison; earlier Release reports without
this observation remain incomplete. Quick without a Python venv is unchanged.
The monitor checks those bindings and invokes the existing assessor; it never
copies baseline conditions into candidate observations. Missing facts remain
incomplete. Python's existing retained-Host collector additionally selects the
same JOIN/Decimal SUM literals/oracles; its prior default routes and 100 ms
early-stop rule remain unchanged.

Native Release uses the existing `native-operations` selection and
`assessNativeOperations` gate: one separate initialization child and first query
remain reference observations, followed by the collector's original 100 varied
durable NEW/file-row operations and 100 cyclic original saved Result reads.
Each operation uses its own CLI child and includes startup through exit. These
replace the older combined Native first-init/cold-existing routes; Node and
Python selections are unchanged. The original raw report is not rewritten;
the separate assessment binds its hash and preserves the existing gate's
latency/functional-only purpose and unverified comparator/safety boundaries.
A failed child is never retried; any already-written partial raw report and
failed samples remain visible, and the original command error is retained.

The existing Native CLI adapter explicitly lacks retained-Host warm operations.
Those required entries stay **incomplete**; a fresh CLI invocation is never
called warm. Unsupported platform artifacts also stay incomplete. Even a full
set of latency samples does not supply unrelated-history, once-validation,
durability, fault or all-path Conformance proof. `formalAcceptance` stays false.
Release's three-process Mock workflow keeps the actual coordinator PID/clock
and CPU scope (child CPU excluded), each phase PID and original public checks.
It invokes the existing 30-sample/5000 ms Mock assessor without subtracting
startup or inventing an allowance. That assessment may fail or remain incomplete;
five successful Quick workflows do not qualify it. Release Node RSS scopes
the actual collector process including package verification/reporting, excluding
spawned compiler/Native/Python processes. Both Release paths remain unexecuted
here. Missing mandatory Release paths/controls exit incomplete before a build.
This implementation's fast unit tests do not establish Native/Python runtime
or a completed Release population.

## CI and implementation evidence map

Phase 1 is local. Phase 2 runs in the enabled workflow when repository visibility
is `public` and private is exactly `false`. Private/unknown visibility skips
execution, including dispatch. No activation variable is required; workflow
enable/disable controls execution.
Main-push Quick consumes the same successful normal package job's artifact;
a skipped docs-only package job allows ordinary preparation. Failed producers
are not replaced. Dispatch requires exact completed same-SHA producer/artifact
IDs. Both invoke the same command, publish Job Summary and retain original
JSON/Markdown/raw/guard evidence for 30 days. Schedule/PR and release-detail
automation remain later phases.

| AC | Implementation / evidence boundary |
| --- | --- |
| 01 | `health:quick` runner, normal pack adapter, terminal table; requires an actual Quick receipt |
| 02 | Exclusive report directory and error finalization; CLI/error tests |
| 03 | Actual npm JSON, browser bundle, public sample processes/RSS and unchanged Mock consumer; requires real Quick |
| 04 | Comparator CPU/tool/fixture/source compatibility tests; actual baseline remains absent |
| 05 | Fixed package/browser size delta unit vectors |
| 06 | Warm/cold/RSS warning exit-zero unit vectors |
| 07 | Required-missing, failed sample, dirty and unbound artifact negative tests |
| 08 | Existing formal Node/Python adapters and Native separate CLI-operation selection/assessor, Python JOIN/Aggregate and wheel/Wasm inspection; Native retained warm unavailable, full matching-artifact Release unexecuted |
| 09 | Local offline public fixtures; Compare works without command tools/network |
| 10 | Same command in fail-closed reusable/dispatch workflow; hosted execution unverified |
| 11 | Monitor/collector adaptation only; no public API, Runtime or capacity change |
| 12 | `node scripts/local-checks.mjs test node -- scripts/health-monitor.test.mjs`; no Runtime build |

## Public end-to-end acceptance

The existing operation assessor now requires both **p95 <= 200 ms** and
**observed maximum <= 200 ms** for the in-scope public short-query operations,
including retained SELECT, two-row UNION, parameters and short Unicode, saved
Result, status, process-cold existing state and normal first initialization.
Node `cold-existing` is a NEW query after same-candidate public initialization
and close; `first-init` is cold-new-state. Historical Saved-only process
measurements retain their original protocol and cannot qualify these cases.
Normal initialization is included; a warm-only number cannot qualify the cold
entry. The separate Mock workflow keeps its own workflow budget and cannot
substitute for a short-query measurement. Native CLI launches remain process
operations, never retained-Host warm samples.

Final measurements retain the existing 100 warm/30 cold populations (the
separate Native operation selection retains its existing 100 process samples).
Every original duration, including a failed or slow sample, contributes to the
raw summary; successful-oracle counts are reported separately. Diagnostic
populations do not supply an acceptance p95. Failed, incomplete, profiled,
undersampled, mixed-artifact or unmatched measurements cannot pass. The
SQLite diagnostic comparison remains separate from a fully matched public
work comparator; the absolute limit does not discharge missing comparison
coverage.

Public timing observations bind the actual call to materialized ordinary
Result rows. SDK process observations retain Result-before-close, first close
and whole-process timing separately. CLI observations retain actual child exit
and the later materialized-output oracle without inventing a public close API
or internal physical ACK. A timer stopped before its observed Result or close
is rejected. CPU and peak RSS keep their actual process/child scopes; peak RSS
is a high-water observation, not per-operation allocation or initialized bytes.

Quick remains a small diagnostic with warning-only comparison semantics.
Release additionally requires a reviewed, environment/build/load/fixture- and
artifact-bound baseline. Its existing relative-plus-absolute thresholds apply
to median, p95 and maximum latency as regressions, not warnings; CPU/RSS
statistics and their scopes remain visible. Missing or incompatible baselines
are incomplete. No source change, baseline adoption, final sampling campaign
or release qualification follows merely from passing the assessor unit tests.
