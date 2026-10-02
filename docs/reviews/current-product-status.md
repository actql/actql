# Current implementation status

Snapshot: 2026-10-02. Source baseline: main
[`50fcc1ccd7e1cfb4ac379687f95a19043fdc113f`](https://github.com/actql/actql/commit/50fcc1ccd7e1cfb4ac379687f95a19043fdc113f).
This is a source-and-evidence reconciliation, not a new acceptance run or a
language specification. Results below remain attached to their recorded test
SHAs; they are not a claim that those runs were repeated at this baseline.
A public symbol or a checked Program alone does not establish installed
execution, recovery, packaged availability, or live-service acceptance.

## Public Client and installed Program profiles

- **Public entry:** [`@actql/node.connect()`](../../packages/node/index.mjs)
  selects Embedded Local or a connected HTTP Host. The lightweight
  [`@actql/sdk`](../../packages/sdk/README.md) supplies the same submit,
  request lookup, attach, Run observation, Checkpoint, Named Result and
  cancellation operations. JSON/YAML machine Programs and explicit
  `aql-text`/`sql` query input use the installed Host's checked preparation;
  selecting a transport or alias grants no execution or source authority.
- **Accepted shapes:** the source-free profile includes Values and the
  supported checked task graphs, rather than only one Values task/one Result.
  An explicitly installed DuckDB or Salesforce source enables its bounded
  acquired-input profile. The installed Host still selects **one Source
  profile**, with exact admitted Source binding. Relational CTE/set/Pipe
  composition over that input is not general independent-source composition.
  See the actual [Host selection](../../adapters/host-node/embedded-local.mjs)
  and [public query expectations](../../scripts/fixtures/public-query-input.mjs).
- **Packaged Local/HTTP evidence:** the
  [public Frontend connection](2026-09-29-public-frontend-host-connection.md#current-integration-status)
  records external tarball acceptance, explicit alias publication and real
  DuckDB reads. Later [#162](https://github.com/actql/actql/pull/162), tested at
  `d800ec7f0d26ad1a608bf1a7cb4c5736c4a163a3`, records 26 successful composition
  cases and 18 preparation refusals per transport. [#163](https://github.com/actql/actql/pull/163),
  submitted at `72c8edd97f057772ac422a04016e2669d54555b7`, records tree-identical
  packed acceptance of 15 named intermediate Pipe Result cases, 8 preparation
  refusals and 1 downstream failure per transport. These are packed development
  artifacts, not evidence of an npm registry release or a deployed Cloud service.
- **Recovery and limits:** [Client parity](2026-09-29-local-remote-client-parity.md)
  records separate-process approval/restart, lookup/attach, unknown acceptance,
  cancellation and no automatic resend. #162/#163 separately record no new
  acquisition/Compute on replay or reread; this is not a new crash matrix for
  every composed query. [Exact String evidence](2026-10-02-exact-string-values.md#verification-boundaries)
  includes saved Result restoration in a later process. General multi-Source
  execution ([#167](https://github.com/actql/actql/issues/167)), `RESULT(name)`
  source references, general Graph/INFER execution and full adopted-language
  conformance are not established by these cases. Native CLI transport and
  [its recorded acceptance limits](2026-09-29-public-frontend-cli.md) remain a
  separate surface; Node evidence does not prove every CLI operation.

## Source and Effect installation

- **Public entry and packaging:** the installed Local package exports
  [`publishSource` and `publishEffect`](../../packages/local-node/index.mjs).
  Embedded `connect()` and the HTTP Host restore both publications from the
  same Host root. The Host
  [composes checked declarations and verifies physical bindings](../../adapters/host-node/installed-check-environment.mjs);
  Source-read and Effect-commit authorization remain separate. The
  [co-installation report](2026-09-28-source-effect-coinstallation.md)
  covers Local/HTTP and repository-external tarballs. Its exclusion of a
  combined acquired Effect Program is historical, superseded by the next section.
- **Supported shape and recovery:** a read Program and a separate Values-origin
  Result-referencing Effect can share the installation. Checkpoint answers,
  restart, current-use checks, cleanup ownership and changed-installation
  refusal are covered by that report and the
  [installed Host tests](../../adapters/host-node/embedded-installation.test.mjs).
  Publication restoration performs no provider I/O. Co-installation alone does
  not authorize additional Sources, arbitrary Effect shapes or Cloud placement.
- **Provider evidence:** Salesforce installed create/update/upsert and
  multi-Resource Sets have mock-provider public-path evidence in the
  [standard-Host Effect report](2026-09-28-salesforce-standard-host-effects.md).
  The historical live checks below and the later acquired-Effect run use a
  dedicated test object/one Resource; they do not prove live multi-Resource Sets.

## Acquired Read → Compute → Effect

- **Installed shape:** one acquired bounded Relation feeds checked Local
  computation and a Result-referencing Effect in the same Program. Source read
  is immediately allowed or denied; read deferral within this Effect profile
  remains unsupported. Commit approval may wait across Host restarts. The
  [shared computation owner](../../adapters/host-node/acquired-effect-computation.mjs)
  and [Salesforce source adapter](../../adapters/connectors/salesforce/host/installed-salesforce-source.mjs)
  use the checked captured owner; this is not a second execution engine.
- **Fixed-SHA public/packed acceptance:** the
  [Salesforce acceptance](2026-09-29-salesforce-read-compute-effect.md#current-status)
  records source `4e4e29da0`, common `c58699ce9`, and CI run `36572192554`.
  Remote HTTP/Embedded acceptance is 17/17, provider tests 227/227, and packed
  read-compute-effect passes. The report preserves earlier 13/15 failures and
  their subsequent corrections; those old failures are not the current map.
- **Recovery coverage:** the same record includes actual Compute counts
  (initial 1, recovery 0), six Host capture crash points and three capture
  crash points, damaged-input isolation, partial apply and unknown replies.
  After the complete durable capture/Preview boundary, restart does not
  reacquire Source or recompute; known writes are not repeated, and an unknown
  send remains for reconciliation. Target-confirmation reads are separate from
  Source reacquisition. See [partial recovery](2026-09-29-partial-effect-recovery.md)
  and the [durable boundary](2026-09-29-source-effect-run-boundary.md#durable-boundary-and-recovery).
- **Live evidence and unknowns:** the
  [2026-09-29 instrumented real-org rerun](2026-09-29-salesforce-read-compute-effect.md#instrumented-rerun-current-evidence),
  Salesforce `00f1b48db` (same product code as `4e4e29da0`), used Embedded Local
  with process restarts: 0 writes before approval, 2 writes on approved resume,
  0 requests on a later restart, and 0 writes after a changed-target refusal.
  Cleanup was checked. This is bounded test-org evidence, not a realistic-size
  live workload, live multi-Resource proof or Cloud execution. That report did
  not observe the typed cause of the target-change refusal; current typed-cause
  coverage is not established here. Collections partial results remain
  provider-test evidence, not installed Read→Compute→Effect acceptance.

## Local execution and ownership proof limits

The [Local coverage inventory](2026-09-18-local-compute-coverage.json),
[family coverage](2026-09-19-sga-veca-tea-local-coverage.json),
[resource audit](2026-09-23-local-resource-accounting-audit.json) and
[production routes](2026-09-23-local-resource-production-routes.json) identify
operation/route-specific evidence. Their counts do not prove every frontend
shape, retained Carrier obligation, performance floor, or public installation.
Use the [chronological Local review](2026-09-19-sga-veca-tea-local-gaps.md#status-interpretation-2026-09-28)
with its later closure sections, not its initial strict-gate failure alone.
The [shared completion report](2026-09-20-managed-completion-unification-result.md#follow-up-status-2026-09-28)
and [publication ABI review](2026-09-30-publication-boundary-abi.md) describe
integrated owners; they do not replace public Program acceptance.

## Remote, Cloud and ecosystem boundaries

Local HTTP/HTTPS Hosts and mock HTTPS providers are local evidence. Cloud
Values is a separate installed profile; even successful Values execution does
not establish general query composition, arbitrary acquisition/Effects,
Hybrid ownership or complete normal-release recovery. This OSS reconciliation
has not verified current deployed Cloud package provenance, live acceptance,
or its complete release/cleanup path. The
[Cloud adoption handoff](2026-09-29-local-remote-client-parity.md#cloud-adoption-handoff)
records OSS namespace input `7fa9ace4857cbd48b1c067c230d6b56736b40653`; it is
not a current Cloud release attestation. Embedded Local-owned Hybrid remains
unavailable in the installed Host.

As required by [the status reconciliation scope](https://github.com/actql/actql/issues/169),
`actql://` service/workspace identity and HTTPS transport are different layers.
Historical HTTPS guidance does not reject that identity direction. This
statement does not claim that this OSS package implements an `actql://`
resolver. [Execution namespace](../design/execution-namespace.md) remains an
OSS isolation coordinate mapped by the Cloud adapter, not a provider tenant.
Repository-splitting choices remain unresolved. The presence of the separate
[`src/actsql` module](../../src/actsql/literal_select.mbt) and its
[initial boundary](../design/actsql-frontend.md) does not authorize relocating
ActSQL, creating repositories, or replacing the current public SQL frontend.

## Historical 2026-09-28 integration evidence

The following record is retained from the previous status snapshot, whose
merged baseline was `d4d64d1cdfc810b8466e0ed66b98b044f33589e3`. References to
"the baseline above" in that record mean this historical SHA, not the new
2026-10-02 source baseline.

- [PR #27](https://github.com/actql/actql/pull/27), `db645d634`:
  Merged into main: Salesforce standard Host discovery/read, retained declarations, Checkpoint
  read handoff, acquisition stop observations, larger bounded Local input and
  packed-package coverage. All 14 required CI checks succeeded; performance
  matrix was intentionally skipped. The earlier live-org evidence used short
  values. Realistic-size input is tested locally, not yet established by that
  live-org evidence. The merge is confirmed at the baseline above.
- [PR #29](https://github.com/actql/actql/pull/29) and
  [PR #35](https://github.com/actql/actql/pull/35) (`74d24e272`), merged:
  the connector-independent installed Effect on Remote HTTP, Embedded Local and
  the packed `connect()`, with the Salesforce Effect factory reviewed in draft
  #32. Multi-Resource Sets recheck every tuple; a definitive pre-send refusal
  fails the Run and retires its capture; uncertain sends keep reconciliation.
- [PR #36](https://github.com/actql/actql/pull/36): mock-org evidence on the
  public paths for two-Resource Sets in both member orders (4 writes and the
  Named Result; refusal of the later Resource writes nothing, fails the Run and
  retires the capture), a lost reply kept unknown without resend, and the
  packed Local Host writing a two-Resource Set after approval and restart.
- Live Dev org, 2026-09-28, through Embedded Local on the dedicated test
  object: two rows created by the check, held for approval with no write,
  approved and resumed in restarted Hosts, each row updated once, the Named
  Result published, no write on a further restart, and the created rows
  deleted. One Resource only; multi-Resource Sets are not exercised live.

## Reading older reviews

Dated reviews describe their own baselines, branch owners and failures. Their
"current", "open" and "unsupported" statements are historical unless a later
section or fixed-SHA replacement establishes the same claim at a newer baseline.
In particular:

- [Distribution/Connector integration](2026-09-26-distribution-connector-integration.md)
  and [R2 disposition](2026-09-24-distribution-r2-disposition.md) predate later
  public acquisition/Effect and Frontend integration; use the profile-specific
  evidence above rather than treating every old gap as open or every gap as closed.
- [Source/Effect co-installation](2026-09-28-source-effect-coinstallation.md)
  proves separate Programs at that point; acquired-Effect acceptance later
  supersedes only its combined-Program exclusion.
- [Source-to-Effect handoff](2026-09-29-source-effect-run-boundary.md) retains
  intermediate custody failures; the later
  [Salesforce resolution table](2026-09-29-salesforce-read-compute-effect.md#current-status)
  records the fixed common dependencies and full bounded acceptance.
- [Frontend Host connection](2026-09-29-public-frontend-host-connection.md)
  has a later status section that supersedes its earlier partial probes;
  #162/#163 extend its bounded relational surface, not the whole language.

Preserve historical SHAs, counts, failed gates and evidence bytes. Update this
map from concrete source plus accepted public-path evidence, and keep missing
coverage explicitly unknown. Existing `check:links` and document-validation
checks validate local links/anchors and JSON syntax; coverage/evidence checkers
validate their registered references. None is a runtime acceptance run.
