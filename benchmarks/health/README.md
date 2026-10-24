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
  --python-venv /path/to/venv --comparison /path/to/fixed-sqlite-comparison.json
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
new processes each cover import/open/first query/Result/awaited close; inner
open and first-query timings remain separate. Five complete Mock workflows
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
Missing CPU observations remain unavailable. Optional Native/Python Quick
coverage is explicit unmeasured; supplied ordinary manifests can additionally
measure their artifacts.

## Reports and comparison

Each invocation creates `_build/health/<time>-<uuid>/report.json`, `summary.md`
and `raw/`. Existing output directories are refused. Failures, including
pre-admission failure, produce reports too. Fresh owned business state, keys,
handoffs and original failed evidence are retained there; they are not replayed
or cleaned by the monitor. Routine reports are ignored by Git. No baseline is
invented or automatically updated. A first run without `--base` is measurement
only: it says comparison unavailable, and does not assert regression freedom.

Reports bind source SHA/dirty diff, before/after environment and package
inventories, source-bound artifact hashes, fixtures, raw samples, exact counts,
median and min/max reference range. A small Quick sample supplies no formal
p95. Comparison requires the same OS/architecture/**CPU model**, runtime and
tool versions, build settings/load/instrumentation, artifact kind and fixture
methodology. Different commits are expected; each artifact must belong to its
own report's source. Dirty or changing source/environment is ineligible for a
formal baseline. Non-comparable fields/reasons stay explicit.

Size deltas show both bytes and percentage: npm/wheel/Native/Wasm +10% warns,
+25% regresses; browser gzip +5%/+15%. Quick median warnings require both +30%
and +3 ms warm, or +30% and +50 ms cold. Peak RSS +20% warns. Performance
warnings alone exit zero. First failures remain retained if a human later
deliberately repeats an experiment.

To establish/rebaseline, review an actual clean, complete report and copy it
to `baselines/<platform>-<arch>.json`, adding `baseline: {id, reason,
reviewed: true}`. Commit that real reviewed report and reason. There are no
placeholder metric values in this repository. CI never writes baselines;
until a real baseline is reviewed, size comparisons do not gate an initial run.

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
measured. Native uses its normal release manifest/verifier. No alternate
backend stands in for an unavailable target.

The existing Native CLI adapter explicitly lacks retained-Host warm operations.
Those required entries stay **incomplete**; a fresh CLI invocation is never
called warm. Unsupported platform artifacts also stay incomplete. Even a full
set of latency samples does not supply unrelated-history, once-validation,
durability, fault or all-path Conformance proof. `formalAcceptance` stays false.
Release's three-process Mock workflow retains its actual observations but
cannot claim the formal single-sample PID/CPU/approved-work interval. That
binding and Release Node peak RSS remain explicitly incomplete. Missing
mandatory Release paths/comparison exit incomplete before a Runtime build.
This implementation's fast unit tests do not establish Native/Python runtime
or a completed Release population.

## CI and implementation evidence map

Phase 1 is local. Phase 2 is committed but every job requires all three existing
conditions: `ACTQL_MAIN_CI_ENABLED == 'true'`, repository visibility `public`,
and private exactly `false`. Missing/private/unknown values skip execution,
including dispatch. Nothing here changes visibility/variables or triggers CI.
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
| 08 | Existing formal Node/Native/Python adapters plus wheel/Wasm inspection; full Release unexecuted |
| 09 | Local offline public fixtures; Compare works without command tools/network |
| 10 | Same command in fail-closed reusable/dispatch workflow; hosted execution unverified |
| 11 | Monitor/collector adaptation only; no public API, Runtime or capacity change |
| 12 | `node scripts/local-checks.mjs test node -- scripts/health-monitor.test.mjs`; no Runtime build |
