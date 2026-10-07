# Development

## Setup and verification

With Node.js 22 or newer, Python 3.10 or newer, a C compiler and `make`:

```sh
npm ci
```

Node.js is used for documentation and toolchain setup. Product implementation
is developed in MoonBit; see the [implementation guide](design/implementation-port.md).
Specification checks also verify generated connector code using the pinned
MoonBit formatter. Complete the MoonBit setup below before running `check:spec`.

### Checkpoint Effect settlement layout

The Node Checkpoint journal uses the private layout
`actql-checkpoint-journal/0.1;model-call-provenance=1;effect-settlement=1`.
The [settlement design](design/effect-refusal-settlement.md) explains the
observation-only claim and its authority boundary. Existing journals with the
preceding `actql-checkpoint-journal/0.1;model-call-provenance=1` layout are
refused by ordinary startup; they are never silently recreated or upgraded.

To update one such journal, stop **every** Host and other process using it,
including old binaries. Use Node 24 with the checked-out upgrade tool:

```sh
node scripts/upgrade-checkpoint-effect-settlement.mjs --offline --root JOURNAL_DIRECTORY --backup NEW_BACKUP_FILE
```

`JOURNAL_DIRECTORY` is the directory containing
`checkpoint-journal.sqlite3`, not an arbitrary parent Host directory. The
backup path must be new, separate from that database, and on storage where
the operator can retain it. `--offline` explicitly confirms that all users of
the journal have stopped. A SQLite writer lock cannot revoke an already-open
old connection, so it does not replace that shutdown requirement.

The tool checks the exact old marker and SQLite integrity, checkpoints WAL,
acquires an exclusive writer transaction, and refuses concurrent WAL changes.
It creates and synchronizes a private standalone backup before adding the
empty settlement table and changing the marker in one transaction. It prints
the backup path and SHA-256. Existing Run, Checkpoint, Resolution, claim,
admission, Model, and Effect evidence records are retained without rewriting.
An existing backup, missing journal, unknown layout, or active writer is a
refusal. A failed transaction leaves the old layout and any completed backup
available for inspection.

Restart only binaries supporting the new marker. Reverting the marker or
dropping the settlement table is unsafe: it would discard persisted refusal
decisions. An offline restoration of the full pre-upgrade backup is possible
only before new activity is accepted; once new activity exists, restoring that
backup would lose newer evidence and requires a separate recovery decision.
The tool never performs that restoration or modifies any other journal.

### MoonBit

Development supports Apple Silicon macOS and x86-64 Linux, with Linux CI on
Ubuntu 24.04. Git, curl and tar are required. Install the exact stable toolchain
and matching core from [toolchain.json](../toolchain.json):

```sh
node scripts/setup-moonbit.mjs
export MOON_HOME="$PWD/.toolchains/moonbit-$(node -p "require('./toolchain.json').version")"
export PATH="$MOON_HOME/bin:$PATH"
moon version --all
```

That sequence installs and identifies the pinned toolchain; it does not run
a full test suite. For everyday changes, use [Local verification](#local-verification).

Setup verifies archive SHA-256 pins before extraction and installs only inside
the ignored `.toolchains/` directory. It does not modify a global installation
or shell startup files. Downloads remain in `install-*` directories for inspection.
Reuse checks the installation marker, tool versions, executable files, core
manifest and three prelude bundles. This is a health check, not a full integrity
scan of installed core sources. If it fails, move only the named toolchain
directory aside and rerun setup; an existing installation is never overwritten.
Use the same environment variables in the editor's launch environment.
Do not run `moon upgrade` inside this installation: update the reviewed version
and archive pins together, then reinstall. Verify the changed toolchain on the
supported targets in CI; local target diagnostics are explicit.

The root `moon.mod` defines the single `actql/actql` module. JS is the default;
common-core packages support JS, Wasm (not Wasm GC), and native. JS is the
daily development default for the shared core, not a restriction on CLI or Host
deployment. Wasm GC is outside the initial validation scope; adding it requires
toolchain setup and target tests, not just a metadata change.

### Target-specific diagnostics

A native-only package, C FFI, target-specific behavior or a failing backend may
need a focused diagnostic on that backend. Select it explicitly; JS success
does not validate native-only code. An explicitly requested whole-target
diagnostic uses `node scripts/local-checks.mjs run core --target <target>
--allow-heavy`, with the workflow budget or an explicit `--timeout-seconds`.
This is not an everyday local check. Manual integration CI retains the full
supported-target matrix.

`node scripts/check-moonbit-api.mjs` invokes `moon info` on all three targets
and checks tracked interfaces. Preserve this cross-target gate in CI; run it
locally only for an explicit public-interface or target diagnosis.

Native core verification uses `scripts/test-native-core.mjs`, including
`node scripts/local-checks.mjs run core --target native --allow-heavy`. Each invocation
creates a fresh `native-*` SQLite namespace with the existing owned-scratch
helper, then runs `moon test --target native` with the remaining arguments.
For an explicit narrow trusted-clock diagnostic, use:

```sh
node scripts/test-native-core.mjs --deny-warn src/platform_native/trusted_clock
```

This native helper owns SQLite scratch; it does not itself add the bounded
wrapper's wall-clock budget, worktree/machine locks or focused nonzero-test
validation. Confirm the intended cases actually ran; exit zero alone does not
establish that a native selection executed.

`ACTQL_TEST_NATIVE_SQLITE_ROOT`, when supplied to this wrapper, is a **parent**
for the newly owned namespace, not an existing database root to reuse or
remove. Relative parents resolve from the caller's working directory. The
default parent is `$RUNNER_TEMP/core-sqlite`, or the system temporary directory's
`core-sqlite` when `RUNNER_TEMP` is unset. Existing DB/WAL/SHM files in that parent
remain untouched. Only the child receives the new namespace; the fixture still
reopens its same `trusted-clock.sqlite` within the invocation and checks the
unchanged 1000/1002 monotonicity assertions. The native HTTP harness already
creates its own invocation root and is unchanged.

The wrapper defaults the SQLite library to the supported platform's system
library; `ACTQL_TEST_NATIVE_SQLITE_LIBRARY` can override it. After a successful,
stopped child, owned scratch is removed and checked absent. Failure, a signal,
spawn failure, or `ACTQL_TEST_PRESERVE_SCRATCH=1` retains evidence and reports its
path; cleanup failure remains a failed command. Raw `moon test` does not acquire
this namespace for callers: use the wrapper when testing native SQLite fixtures,
and do not point an unwrapped test at a previous run's database.

The completed-output recovery boundary has a narrow Native runner:
`node scripts/test-native-completed-restoration.mjs`. It creates private signed
bundle, file and SQLite fixtures and invokes the bounded focused-test wrapper
for `remote_standard_host/native_test`. Optional Moon test filters are forwarded;
the nonzero-test guard still applies. It does not build or run query integration.

Use `moon info` to regenerate `.mbti` files and review and commit them when the
public API intentionally changes. The API guard rejects cross-target differences,
modified files and newly untracked interfaces. Its report parser is tested
against the pinned build tool with a real backend-specific signature mismatch;
rerun that test on toolchain upgrades. Keep
host-specific packages separate from the common core rather than weakening its
target checks or narrowing a common-core package's supported targets. An
environment smoke test is not language conformance. Implementation migration,
AoA linkage and distribution packaging are separate work.

The checks are read-only:

- `check:contracts`: contract pins, requirement ownership and generated registry freshness.
- `check:links`: Markdown local files and anchors, plus JSON syntax.
- `check:examples`: YAML Program fixtures, valid-example root layout, example registration and acceptance-case references.
- `test:docs`: validator regression tests.
- `check:nest`: independent Python lowering and JavaScript identity-preimage checks for the authored nest fixture subset.
- `check:calendar` (included in `check:events`): rebuild pinned IANA zic source in
  isolation, reproduce the selected-zone TZDB fixture exactly, and test the TZif
  reader. It also checks fixed Calendar boundary intervals with an independent
  Python oracle and its regressions. No installed timezone database is used.
  `generate:calendar` updates only the transition JSON and embedded MoonBit
  fixture, never boundary expectations. See
  [fixture provenance](../vendor/tzdb/2025b/README.md) and
  [boundary vector scope](design/calendar-checking.md#independent-boundary-vectors).
- `check:encoding`: kernel manifest pin, fixed scalar spelling expectations and generated encoding-test freshness.
- `check:text-rank-numeric` (included in `check:vector`): fixed pretokenized BM25
  score bits and ranks, rational-interval logarithm checks and independent
  high-precision regression tests. This does not test a product tokenizer or scorer.
- `check:text-rank-tokenizer` (included in `check:vector`): fixed Unicode 16
  tokenizer vectors from pinned source tables, full enumerated NFC/NFKC corpus
  checks and default-fold map regressions for the independent oracle. No Host
  Unicode implementation or product evaluator is used.
- `check:text-rank-profile` (included in `check:vector`): exact selected-profile
  reproduction, canonical byte validation and pin/version regressions.
  `generate:text-rank-profile` refreshes that profile after an intentional input,
  law or vector change; it does not regenerate the expectations or admit a
  production Check Environment.
- `check:canonical`: canonical JSON corpus, existing contract CIDs and generated identity-test freshness.
- `check:value-contracts`: fixed contract vectors, generated-test freshness and embedded schema consistency.
- `check:value-admission`: fixed value-admission vectors, generated-test freshness and generator regressions.
- `check:parameters`: fixed Parameter binding cases, recursive schema consistency and generator regressions.
- `check:expression-syntax`: fixed mixed-Expression cases, text-corpus integration, generated-test freshness and generator regressions.
- `check:expression-typing`: fixed expression type/rejection vectors, generated-test freshness and generator regressions; not expression evaluation or complete Program admission.
- `check:relation-typing`: fixed single-operation schemas, projection order and rejection vectors; generated-test freshness and generator regressions, not Relation execution.
- `check:relation-join`: fixed local join fields, nullability, key counts and failures; generated-test freshness and generator regressions, not execution or complete proof admission. See the [join checking guide](design/relation-join.md).
- `check:relation-append`: fixed recursive schema joins and rejection vectors; generated-test freshness and generator regressions, not row concatenation or identity proof. See the [append checking guide](design/relation-append.md).
- `check:relation-nest`: fixed payload schemas and rejection vectors, embedded projection schema pins and generator regressions; not nest execution or order/capacity proof. See the [nest checking guide](design/relation-nest.md).
- `check:pipeline-typing`: fixed unary Relation pipeline edges, output types and rejection cases; generated-test freshness, not execution or whole-Program admission. See the [pipeline guide](design/pipeline-typing.md) and [Relation schema boundary](design/relation-schema.md).
- `check:relation-results`: fixed Result projections, ordering types and rejection cases; generated-test freshness, not total-order proof or publication admission. See the [Result checking guide](design/relation-results.md).
- `check:aoa`: owned AoA 0.1 contract/law identifiers and exact law-manifest pins; included in `check:contracts`, not runtime conformance. See the [repository versioning policy](design/versioning.md).
- `check:parameter-identities`: fixed Parameter value preimages/CIDs, projected-value schema and generator regressions.
- `check:expression-text`: fixed expression-text trees/rejections, generated-test freshness and generator regressions.

Dependencies are pinned in `package-lock.json`. External URL availability is
not part of the deterministic local checks.

Case definitions contain expectations, not execution results. Execution evidence
belongs in separate reports tied to case IDs and the implementation revision.
YAML parsing does not establish ActQL semantic validity. The MoonBit checker and
runtime must verify these same fixtures as implementation becomes available.

## Local verification

The default is the affected MoonBit core packages on the JS backend, plus
targeted Node tests for changed SDK, adapter and script behavior. These are
different test layers: MoonBit tests compiled to JS do not replace public Node
API or package-boundary tests. Select native-only/FFI diagnostics explicitly;
do not automatically expand every core change to all targets.

Use [the local verification skill](../.agents/skills/actql-local-verification/SKILL.md)
for command selection. `node scripts/local-checks.mjs changed` is an advisory
path-based list, not a complete reverse-dependency closure. Inspect affected
callers and test imports before deciding coverage. Its CI-job suggestions do
not require running those jobs locally. Broad Core, proof, packed acceptance
and performance gates remain explicit diagnostics, not local defaults.

Keep incremental `_build` artifacts. Use the bounded/nonzero-test wrapper below
for selected tests and builds; do not run competing gates or mutate a worktree
while a gate uses it. Report the observed test counts, failures, skipped or
unrun checks and any remaining target/boundary coverage. Manual integration CI
retains full verification; local and PR results prove only their executed selection.

## Runtime package artifacts

Compiled JavaScript under `packages/local-node/_build` and the `dist`
directories of `run-host-core`, `coordinator-core`, and `transfer-core` is
ignored, not committed. After changing MoonBit sources or merging another
branch, prepare the affected packages before importing them directly. Pass only
the package names being consumed, for example
`npm run build:runtime-packages -- local-node`. The related npm checks prepare
their runtime dependencies automatically; do not add an all-package preparation
step before a check that already prepares its own dependencies.

`npm pack` in each runtime package builds its payload through `prepack`;
use the pinned MoonBit toolchain and root npm dependencies. Do not use
`--ignore-scripts` when producing tarballs. Consumers may install the resulting
tarballs with `--ignore-scripts` and need no MoonBit toolchain. Generated API
interfaces, schema/pins, fixtures, and the tracked Run Host service wrappers
remain reviewed source artifacts. Regenerate wrapper changes explicitly;
runtime preparation checks them but does not silently update them.

## Bounded local execution

`local-checks.mjs` remains the local entry point for the workflow's actual
commands and the existing nonzero-test guard. It now applies cooperative
exclusion and a wall-clock budget to routed executions on macOS and Linux.
`list`, `changed` and `run <job> --dry-run` only report; they acquire no locks
and launch no checks. Incremental `_build` artifacts are never removed.

```sh
node scripts/local-checks.mjs test node -- scripts/local-checks.test.mjs
node scripts/local-checks.mjs test moon -- --target js src/query_integration
node scripts/local-checks.mjs build moon -- --target js src/query_integration
```

The small shared [classification](local-checks-hooks.md#what-the-policy-recognizes)
requires `--allow-heavy` only for known full suites/builds. This is a deliberate
choice by the caller, not human approval or an authorization grant. Unknown
Moon options/jobs are refused until explicitly classified. A package/file
selection is a narrower scope, not a promise about its runtime or dependencies.
The first unit does not intercept npm aliases, direct proof campaigns, arbitrary
shell commands, raw Node suites, or processes started outside this wrapper.
Hosted CI commands, coverage, gates and results remain authoritative.

The split `pipeline-mutations`, `pipeline-capacity` and final `pipeline-evidence`
job wrappers are explicitly CI-only. Producer begin/stage/seal requires real
GitHub source SHA, run, attempt and output metadata; the final join requires
sealed exact-artifact producer inputs from the same run and attempt. These
wrappers refuse local execution before creating locks or evidence, even with
`--allow-heavy` and supplied GitHub environment variables. `list` and `changed`
label them CI-only; `run <job> --dry-run` prints their literal workflow commands
without constructing fake CI context. Raw underlying proof campaigns remain
ordinary heavy work outside this wrapper's guard. They are not an alternate
local acceptance route for the hosted producer/join boundary.

### Budgets and output

`run <job>` defaults to that job's `timeout-minutes` in
`.github/workflows/ci.yml`, covering the whole sequence, not each step anew.
Focused `test node` uses the lint job's budget; focused Moon test/build uses
core's budget. `--timeout-seconds N` replaces that default for this invocation.
An unscoped Moon test/build has no default: supply both `--allow-heavy` and an
explicit `--timeout-seconds N`. If the workflow has no numeric timeout, the
wrapper requires an explicit budget rather than inventing one.

Every execution reports its budget before starting. On expiration or caller
cancellation it sends TERM to only the invocation's process group, waits
5 seconds, then escalates to KILL if needed. `--kill-grace-seconds N` changes
that termination grace; it is not an extra test budget. Durations must be
positive and fit Node's timer range. A timeout exits 124; caller cancellation
exits 130; child failures preserve their nonzero status. There is no automatic
retry, timeout increase, dependency installation, build-cache deletion or repair.

Each invocation retains `_build/local-checks/attempts/run-*`, including failures
and timeouts, and reports its exact directory. `summary.json` separates process
exit observations from overall completeness; `output.log` retains the bounded
combined diagnostic output. The existing evidence redactor and 8 MiB output
limit are reused. Overflow stops the invocation, fails it, and marks output
incomplete. Output is buffered and printed at completion rather than streamed;
steps and their evidence directory are announced immediately. The supervisor
waits for caller stdout and stderr writes with a separate, shared five-second
forwarding budget after command cleanup. A stalled or closed receiver marks
`callerOutputComplete: false` and fails an otherwise successful invocation;
an existing command failure or cancellation keeps its original status. This
does not change the saved command log or its `outputComplete` capture flag.
Focused tests also retain their existing per-test evidence. Abrupt supervisor death can
leave only the last written, incomplete snapshot. Redaction is diagnostic
best-effort, not proof that arbitrary application output has no secrets.

### Lock ownership and stopped processes

The canonical worktree path gets one exclusive lock for every routed
execution. Classified-heavy work additionally gets one lock across this
user's worktrees on this host. State is beneath the canonical home directory
at `.cache/actql/local-checks/<host-hash>/`, independent of `TMPDIR` and
`RUNNER_TEMP`. Other users or containers with separate homes/state are outside
this cooperative lock scope. Existing state-directory symlinks or foreign
ownership are refused; the wrapper does not change permissions or user config.

A lock records a random owner token, supervisor PID, user/host, worktree and
evidence path. Acquisition is exclusive; release checks file identity and the
same token. A failed second acquisition releases only locks it acquired before
starting any command. A busy or incomplete lock fails immediately, without
waiting or retrying. PID liveness is diagnostic only: PID reuse, missing PIDs,
reboots, incomplete metadata and surviving descendants never authorize removal.
There is no automatic stale-lock recovery or generic cleanup command. Inspect
the exact reported owner/evidence and confirm its processes have stopped
before manually recovering that lock. Never remove another active worker's
lock or use a broad process-kill command.

The per-invocation Node supervisor stays alive as its own process-group leader.
Commands inherit that group; signals never target a PID read from an old lock.
Parent IPC disconnect cancels the group even after the calling agent/wrapper
is killed. macOS/Linux `ps` verifies group liveness before normal release.
An inspection/ownership failure retains locks. KILL escalation also kills the
supervisor and deliberately retains locks for inspection. If the supervisor
itself is killed, no new watchdog is started and locks stay in place.

This is not a security sandbox or OS resource quota. Detached/daemonized children
that intentionally escape the group, raw commands, edits or branch switches
outside the wrapper, and manual lock removal are not prevented. Continue to
follow the same-worktree/one-heavy-gate rules in [AGENTS.md](../AGENTS.md).
The optional [Claude Code and Codex hooks](local-checks-hooks.md) add pre-launch
reminders for a small literal-command grammar; they do not broaden these limits.

## Focused test execution

Use the existing local verification tool when a selected test must actually run:

```sh
node scripts/local-checks.mjs test node -- --test-name-pattern 'selected name' scripts/example.test.mjs
node scripts/local-checks.mjs test moon -- --target js src/query_integration --filter '*selected name*'
```

Replace the example file/package/filter with the intended selection. `changed`
prints guarded commands for the affected test files and MoonBit packages.
The small reusable guard in `scripts/test-execution.mjs` also covers successful
Node selections in `test-acquired-effect-computation-probe.mjs`, the recovery
phase of `test-effect-capture-host-crash.mjs`, the focused Node/MoonBit checks in
`check-connector-addition.mjs`, and every MoonBit selection in
`test-native-publication-store-lock.mjs`.

The guard requires at least one passed executable case and no failed/cancelled
cases. Zero discovery, unmatched selections, skip-only and todo-only results
fail with the command/selection and observed counts. Mixed passed/skipped Node
cases can pass; suite headings and synthetic passing test-file records do not
count. Original nonzero process statuses remain failures; the local-checks
command preserves the exit code (or the usual 128 + signal number). Missing,
malformed or contradictory summaries fail closed with counts unavailable.

Node uses a TAP reporter that additionally retains structured `test:summary`
events. Only per-file case counts are added; the final process summary is
required for completeness but can falsely count an unmatched file as one pass.
This is tested with the CI Node 22.22.0 pin. Reporter overrides, watch mode and
nondefault isolation are unsupported by this focused path. Moon's pinned
0.1.20260904 tool emits `Total tests: N, passed: P, failed: F.` even with
`--output-json`; that complete line is the parsed format. It excludes `#skip`
cases, so skipped/cancelled/todo counts are unknown (`null`), never inferred as
zero. Each emitted target total must contain a pass. Recheck these fixtures and
live-tool tests when updating toolchains.

This does not wrap raw `node`/`moon` commands, every npm script, benchmarks,
compiled test executables, or all commands in `local-checks run`. Intentional
process-crash preparation remains an expected failure verified by its original
exit/custody assertions, not a passing-test claim. Existing optional CI jobs
retain their conditions: a sanctioned job/test skip is still a skip, not
successful execution. No general allow-empty switch or mandatory optional job
is introduced. Run the guard regressions with
`node --test scripts/test-execution.test.mjs` (the pinned MoonBit toolchain must
be on PATH).

### Retained command attempts

The focused wrapper retains each invocation under
`_build/focused-evidence/focused-test-*` and prints its exact directory. The
programmatic `evidenceScratch` option selects another parent directory. An
explicit rerun creates a new directory: a passing attempt cannot overwrite a
failure. No automatic retry or timeout increase is introduced.

Focused and packed verification share the existing `packed-query-evidence.mjs`
recorder and `actql-command-evidence/0.1` diagnostic format. `summary.json` is the
latest observation; numbered `*.summary.json` snapshots and per-command
`*.started.json` / `*.result.json` records retain earlier observations. Each
command records redacted arguments, canonical working-directory/device/inode
identity, actual Git HEAD and dirty indication, UTC start/end timestamps,
elapsed time, raw exit code or signal, and verification status separately.
Git source identity is read from the recorder's repository cwd; the child cwd
is recorded separately because packed consumers execute outside the source
checkout. Unavailable Git identity/dirty state remains `null`. The supplied packed
`revision` and GitHub event SHA do not replace the observed checkout SHA.

Streams are bounded by the existing limits: 8 MiB for packed commands and
64 MiB for focused commands. Buffer overflow remains a failed attempt with
`outputComplete: false`; persisted streams are bounded too. No environment is
serialized. Secret-labelled environment values and recognizable authorization,
credential URL/query and private-key forms are masked in diagnostics. These
helpers are for repository-owned test diagnostics, not arbitrary private buffers;
masking cannot prove arbitrary application output is free of secrets.

A failed, timed-out or interrupted invocation has `complete: false`; cleanup
errors also retain a failed/incomplete summary without changing the raw child exit. A command's
raw exit observation, its test-count verification, and invocation completeness
are independent fields. Evidence-write errors are reported and cannot turn a
failure green; a passing test with failed evidence persistence also exits
nonzero. The original nonzero status remains authoritative. Files/directories
replaced by links or different filesystem objects are not overwritten or cleaned.

The existing CI uploader retains only summaries, command receipts and bounded
stdout/stderr, for seven days. Names include GitHub run ID and attempt, while
summaries carry both event and observed checkout identities. Callers retain their
`always()` collection condition. Upload failure fails the collection step and
is reported separately; upload success establishes neither test success nor
completeness. Tarballs, installed dependencies and other scratch payloads are
never uploaded. Missing command result receipts remain missing.

A start record is persisted before each child. If the parent process is killed,
its last persisted snapshots remain partial, but `spawnSync`'s in-memory output
and unobserved child exit cannot be reconstructed. If the runner disappears,
the job is cancelled before collection, or GitHub terminates the entire job,
`always()` cannot guarantee an upload. A child timeout handled by the recorder
retains its observed output and failure normally. No fabricated receipt or
successful completion is substituted for any of these gaps.

The existing `packed_query_evidence_probe` CI dispatch option runs only tiny
nonzero, timeout, interrupted-parent and upload-failure probes (the last uses
a deliberately invalid artifact name). Every probe job
is intentionally failed; later assertions check that collection does not alter
that result. The regular `packed-query-evidence.test.mjs` gate exercises local
capture, partial selection, ownership guards and the action's exact upload-status
shell without rerunning packed product acceptance or a mutation campaign.

## PR checks and manual integration checkpoints

Normal CI runs on PR opened, synchronize, reopened, ready_for_review and
converted_to_draft events. There is no
main-push, scheduled, workflow-completion or merge-queue trigger. Advancing main
alone does not require updating an unchanged PR or rerunning its successful
checks. A changed PR head still needs its own applicable checks; missing,
failed or stale required evidence is not converted into a pass. The recorded
checkout may be the PR's synthetic merge at event time, not current main.

### Draft preparation and Ready verification

Draft pushes and reopen events run preparation checks, not merge verification.
The existing five jobs (`select-targets`, `preflight`, `lint`, `spec`, `check`)
are retained; no separate cheap-check workflow or duplicate push trigger is added.
The final `check` intentionally fails with “awaiting ready_for_review” even if
preparation passes. This is an incomplete verification state, not proof of a
product regression. Marking Ready triggers the existing normal coverage at that
event's exact checkout; later non-Draft pushes rerun it for the new head. Earlier
head results cannot satisfy the new plan's source identity.

Normal coverage still preserves the existing reviewed maintenance, declaration,
portable and owning-family exceptions. General product changes select full
coverage. Ready does not invent a new exemption or turn a narrow historic result
into a full campaign. Returning to Draft triggers preparation again; the shared
PR concurrency group cancels a superseded Ready/full attempt without a separate
run-cancellation API or sticky label.

The Draft command inventory is deliberately bounded:

- Preflight: retained-history validation; operation-support inventory regression;
  `npm ci`; synthetic pipeline artifact contracts; owned contract versions and
  metadata checks; pinned MoonBit setup and `moon fmt --check`; tracked-file
  cleanliness and the existing current-PR-head guard. Three-target API generation
  is deferred. Declaration provenance still passes actual-history validation.
- Lint: Node/root npm setup, public SDK/Client TypeScript declarations, and the
  existing preflight, focused-selection, target-selection and main-baseline
  fixtures. No native DuckDB setup, product build or dependency-isolation build.
- Spec: Node/root npm setup, document links, strict Local resource-boundary
  evidence validation and independently pinned execution-authorization vector
  freshness. No Python/MoonBit spec setup or compound `check:spec-after-preflight`.
- Only an exact existing reviewed fixed-request test family adds `focused-tests`:
  its owning JS package check and selected test files, through the existing
  nonzero wrapper. Ordinary Draft product changes do not automatically run their
  affected product tests; there is no complete dependency engine here.

Full Core matrices, Host/Client package builds and acceptance, native/macOS,
network, Worker, connector, DuckDB, session proof and pipeline proof campaigns
are deferred while Draft. The CI unit fixtures above are synthetic checks of
scheduling/evidence contracts, not execution of those product campaigns. Missing
or invalid Draft/event metadata fails closed. The five-job count (six for the
reviewed focused family) is a scheduling count, not a measured hosted runtime
or promise of zero preparation cost. Manual dispatch remains the explicit normal
full path and is not downgraded because a PR happens to be Draft.

Before a release or another meaningful integration milestone, explicitly run
`gh workflow run CI --ref main`. With the probe/performance flags left false,
this selects the existing full job families and JS/wasm/native matrix. Add
`-f native_macos=true` when the macOS checkpoint is required. Dispatching the
probe or performance-only modes is not a full integration checkpoint.

This intentionally delays detection of incompatibilities between independently
validated PRs until the chosen integration checkpoint. Review its exact source
SHA and actual required-job results before treating that checkpoint as verified.
No branch-protection settings or check obligations are relaxed by this policy.
Existing historical main-push baselines remain historical evidence only; stopping
automatic main runs neither creates a new trusted origin nor permits missing or
changed producer inputs to be reused. Reuse must still satisfy its existing
source, policy and artifact checks. Do not dispatch a replacement full run for
every merge or move the duplicate campaign to the PR merely because main moved.

## CI evidence by source revision

Use the read-only GitHub CLI helper to inspect this repository or another
GitHub.com repository, including `actql/actql-cloud`. It needs Node.js 22 or
newer and an installed `gh` with read access to the repository and Actions.
Policy inspection additionally needs access to classic branch protection;
if that policy is unavailable, required checks remain **unknown**.

```sh
node scripts/ci-evidence.mjs actql/actql --pr PR_NUMBER
node scripts/ci-evidence.mjs actql/actql --pr PR_NUMBER --integration main --dependencies 189,191
node scripts/ci-evidence.mjs actql/actql-cloud --sha FULL_40_CHARACTER_SHA --json
node scripts/ci-evidence.mjs actql/actql-cloud --sha FULL_40_CHARACTER_SHA --branch main
node --test scripts/ci-evidence.test.mjs
```

The text and JSON reports preserve each workflow run, event, source SHA and
attempt, including earlier failed attempts. Jobs retain their actual status
and conclusion: `queued`/`in_progress`, `failure`, `cancelled`, `skipped`,
`neutral` and `success` are different evidence. A conditional skip is not
successful execution. No successful jobs are combined across runs or attempts,
and a green push run never substitutes for a red or stale PR run.

PR inspection discovers exact-head runs and branch-history candidates, plus
runs associated with the current merge/test-ref SHA. Branch names can collide
across forks or be reused, so unassociated older branch runs are explicitly
labelled `stale-or-unrelated-branch-run`. GitHub's run-reported `head_sha`,
associated PR head/base SHAs and current `refs/pull/N/merge` are separate fields.
Today's PR merge SHA is not historical checkout evidence: the helper reports
the tested checkout SHA as unknown because jobs can customize checkout and
the run API does not prove it. Closed PRs have no current test-ref claim.
Commit check runs and status history are also shown by SHA, separately from
Actions evidence because those endpoints do not attribute a workflow event or
attempt. Absence of checks is reported as absence, not success.

PR reports also record draft/mergeability (including unknown), the current
merge-test tree and its ordered base/head parents, and reviews with their
original commit binding. Stale approvals remain stale observations; review
and code-owner policy is not inferred. The last API read re-reads the selected
PR after rechecking dependency PRs, the integration branch and merge/test ref.
Changed HEAD/base/state or an unavailable boundary makes the report incomplete;
`stable-observed` means only that those sequential reads agreed, not an atomic
snapshot or a guarantee that nothing can change afterward.

The intended integration branch defaults to the repository's reported default
branch; `--integration` overrides it explicitly. Dependencies are same-repository
PRs whose head branch matches the selected PR's current base, plus any explicit
`--dependencies` numbers. This is one-hop discovery, not a transitive stack
solver. Every subject reports full HEAD/base SHAs and a merged PR's destination.
Ancestry comparisons use the pinned integration SHA. Exact source ancestry,
whole-tree equality, and reachability of a recorded merge result are separate
facts. A squash can preserve a whole tree without preserving original commits;
different trees leave content correspondence unverified. A merge into a feature
branch whose result is absent from the integration branch identifies that
missing integration step. The tool never retargets, rebases, pushes or merges.

Each named requirement has separate HEAD and merge-test observations, including
missing/pending, cancelled, skipped and duplicate observations. A check is linked
to an Actions attempt only through its exact check-run URL, check-suite identity
and source SHA, never a matching job name. Older attempts stay visible and are
marked superseded; same-named jobs from other workflows, events or stale SHAs
remain separate. External checks or incomplete attribution keep the attempt
unknown. These are observations, not a GitHub requirement-satisfaction verdict:
status/check collisions, event eligibility and merge-ref precedence are not
collapsed into a green result. A conditional skip or neutral result can satisfy
GitHub policy but does not prove successful execution. See GitHub's
[required-check troubleshooting](https://docs.github.com/en/pull-requests/how-tos/merge-and-close-pull-requests/troubleshooting-required-status-checks).

Named required status checks come only from classic branch protection and
active repository/organization branch rules, retaining the expected app IDs.
An inaccessible, missing or ambiguous policy (including unsupported workflow,
scanning or quality rules) leaves the overall requirement set unknown. A bare SHA has no implied
target branch; supply `--branch` to inspect its policy. No merge, deployment
or real Preview acceptance verdict is produced, even when requirements are
known and all visible jobs passed.

Collection requests use `gh api --paginate --slurp`. The report marks missing
pages/counts, API/permission errors, identity mismatches and the filtered
workflow-run API's 1,000-result cap as incomplete. GitHub also bounds commit
check-run history to the latest 1,000 check suites; this API limit is disclosed
even when the returned collection fits on one page. It is a non-atomic snapshot;
runs may change during collection. Exit code `0` means retrieval completed
(failed or skipped CI is still data), `1` means incomplete retrieval, and `2`
means invalid arguments. Policy can intentionally remain unknown for a bare
SHA or unsupported policy even after retrieval. JSON output retains partial
evidence and diagnostics for automation. The helper only makes GET requests;
it never reruns jobs, updates PRs, merges, deploys or prints authentication
credentials or raw `gh` diagnostics. Offline tests use fixed response fixtures
and a temporary fake `gh`, with no live network or credentials required.

### Attempt-bound timing and explicit comparisons

The same report now includes job and step execution durations, raw timestamps,
runner labels and exact API endpoint/field boundaries in text and JSON. Run
`created_at`, `run_started_at` and `updated_at` remain separate observations:
`updated_at` is not a completion timestamp. Attempt execution is an **observed
job wall span**, from the earliest executed job start to the latest completion,
only when all non-skipped job intervals and the attempt are complete. Parallel
jobs are never summed into elapsed time; no dependency critical path is claimed.
The ten longest valid job and step execution intervals retain their source SHA,
workflow, event, run, attempt, runner labels and actual outcomes.

Job `created_at` to `started_at` and attempt start to job start are observed
pre-start intervals. They can include dependencies and other waits; neither is
proven runner queue time. Retry admission is unavailable, so the original run
creation time is not used for a retry's pre-start duration. Missing, malformed,
backwards, unfinished and skipped intervals are explicit unknowns, never zero.
Running durations are not extrapolated to observation time or counted as
completed samples. Missing steps and incomplete/API-denied evidence stay visible.
Timing does not change check conclusions, retrieval exit semantics or readiness
uncertainty, and cache state remains unknown.

Select fixed run IDs instead of a PR/SHA to avoid moving discovery results. All
attempts of those runs are still fetched; selecting a successful retry does not
hide the earlier failed attempt. Statistics are opt-in with exact run:attempt
pairs; unavailable selections are reported, not silently replaced:

```sh
node scripts/ci-evidence.mjs actql/actql --runs 36863741235,36874358135
node scripts/ci-evidence.mjs actql/actql --runs 36863741235,36874358135 --compare 36863741235:1,36874358135:1 --json
```

Each comparison group gives selected count, completed sample count, omitted
count/reasons, median and maximum seconds. Groups separate source SHA, workflow,
event, attempt number, run/job/step outcomes, evidence/timing completeness and
observed configuration (workflow identity, associated PR bases, job/step shape,
runner labels/groups). Missing configuration and unobserved dispatch inputs
isolate runs rather than pooling them. A matching observed group is not proof
of identical checkout, runner image, resolved actions/dependencies or cache hits.
Cross-revision results remain separate groups, with full source SHAs available
for deliberate inspection. Skips, failures and cancellations are never relabelled
as successful test evidence. `--compare` can also restrict a PR/SHA report's
statistics without narrowing the original evidence report.

The fixed OSS run IDs above are reproducible read-only examples, not speed
acceptance targets. They have different source SHAs and are intentionally not
pooled as equivalent samples. A full authenticated CLI fetch needs `gh` access;
a saved API observation can be projected with the exported `collectEvidence`
request adapter, but such a replay is not a fresh network/permission check.

## Updating specification metadata

For normative edits, preserve or explicitly assign `requirement-block` IDs.
Run `npm run check:metadata` to inspect added, changed and removed obligations
and document-import pins, then `npm run update:metadata` to apply reviewed
updates. Changed obligations become pending and do not inherit execution evidence.
Review the Git diff and run `npm run check:spec` before committing.

`npm run generate:requirements` regenerates only the combined registry from
owner-local records. It does not approve changed statements or produce evidence.

The metadata updater refreshes owner-local records and document references to
machine bodies. It does not rewrite machine contracts, internal registry
identities or external dependency pins. Those require their contract-specific
generation and identity rules; a matching hash alone is not approval.

`npm run generate:nest` regenerates nest expectations from the independent
reference lowering. Review identity preimages and graph changes before accepting
updated goldens; production output is not their source of truth.

## Versioning

Implementation packages start at `0.0.1` and advance through `0.0.x` during
development. The first formal release is `0.1.0`, after the release scope is
implemented and verified under the [conformance requirements](spec/conformance.md).

Language and machine-contract version identifiers remain independent of package
versions. The implementation targets `actql/0.1`; exact contract contents are
pinned by CID. Changing contract contents changes their CID. Package releases
do not rename contracts or imply compatibility between different pins.
Supported profiles and verification evidence are reported separately.

## Implementation materials

Before algebra implementation, resolve the normative bodies referenced by the
AoA contract: kernel, pipeline, scalar and primitive laws, pipeline registry and
target module contract. The portability/operation-semantics contract and bound
transfer laws also need resolvable bodies. CID pins alone are not those bodies.

For each dependency, record its role, exact version and CID, local path or pinned
retrieval location, hash preimage rule and required profiles. Verify the retrieved
body against its pin before using it; do not infer a replacement from an implementation.
The current document checks do not establish this transitive dependency closure.

The kernel law-name manifest is available locally with its existing CID verified.
See [JSON encoding](design/json-encoding.md) for its exact preimage, resolved scalar
spelling rules and Writer boundaries. `npm run generate:encoding` regenerates
MoonBit tests from fixed vectors; it does not replace expected text with product
output. Run the generated tests on all three targets to verify execution.

[Canonical JSON and CID](design/canonical-json.md) documents the normalization,
ordering, ownership and explicit budget contracts. `npm run generate:canonical`
regenerates identity tests from fixed corpus expectations and existing contract
pins. These tests hash supplied envelopes; they do not validate their domain meaning.

[Structural and scalar decoding helpers](design/decode-foundation.md) define
exact-key checks, primitive readers and their local failure ordering. They do
not replace a text parser, tree admission or caller-owned resource limits.

[JSON source parsing](design/json-source.md) adds strict UTF-8 and String inputs,
normalized values with original source spans, and explicit byte/node/depth limits.
Its tests do not establish YAML, Program or canonical-artifact conformance.

[YAML source parsing](design/yaml-source.md) adds explicit YAML text and byte
entry points with shared `ParseLimits`, normalized values and original spans.
Its structural parsing tests do not establish Program or execution conformance.

[Program and stage structure](design/stage-syntax.md) validates closed envelopes,
ordered predecessors and named cross-stage ports over owned source cursors.
Automatic JSON/YAML selection does not retry semantic or resource failures.
Local operation and type checking remain separate.

[Value contracts](design/value-contracts.md) admits distinct authored and checked
type grammars, expands fixed machine members and implements shared equality,
assignability, nullability join and key-domain compatibility. `generate:value-contracts`
regenerates tests from the fixed contract corpus. This is not Parameter binding,
runtime value admission or whole-Program type checking.

[Value admission](design/value-admission.md) checks normalized values against
admitted contracts with explicit whole-value budgets and source diagnostics.
`generate:value-admission` regenerates tests from fixed expectations. Reference
authorization, vector operation admission, Parameter binding and expression
execution remain separate.

[Parameter binding](design/parameter-binding.md) admits recursive declarations,
validates defaults and resolves supplied values to immutable `Ready` or
`NeedsBindings` results. `generate:parameters` regenerates fixed tests;
`generate:parameter-schemas` updates the embedded Parameter schemas and their
artifact pins. Parameter Values identity uses the same bounded emitter for
canonical text and incremental hashing. Whole-Program usage and Plan/Run integration
remain separate.

[Expression text admission](design/expression-text.md) decodes the common
Expression syntax into an owned Cursor and reports Parameter occurrences.
It does not yet perform expression type checking, evaluation or whole-Program
Parameter-use analysis.

[Owned tree decoding](design/decode-core.md) admits editable Nodes into bounded
opaque cursors, with exact-key checks, source spans and primitive readers.
It preserves raw values; canonical and domain validation remain separate.

Unicode 16.0.0 inputs for NFC, normalization cases and the Unicode license are pinned in
[vendor/unicode/16.0.0/manifest.json](../vendor/unicode/16.0.0/manifest.json).
`npm run check:unicode` verifies the input pins, both committed generated files,
and the generator regression tests without updating implementation files.
Run `python3 scripts/generate-unicode-tables.py` to regenerate the tables and NFC
tests; review the changes before committing. `--verify-inputs` checks only the
inputs, and `--output-dir <directory>` allows isolated generation.

The canonical-value tests separate pure NFC from ActQL's NFC-plus-LF normalization.
Pure NFC covers the listed normalization cases and assigned scalar values outside
Part1, using the pinned UCD ranges rather than the host's Unicode database.
CI runs these tests on JS, Wasm and native. Input verification and generation alone
are not NFC execution conformance. Generated files are excluded from formatting;
their exact contents are checked by the generator. Preserve the Unicode license
in distributions that include the derived tables.

Add foundational packages in dependency order: SHA-256, canonical values,
encoding, canonical JSON, then structural and scalar decoding. Each addition
includes its tests and public interfaces, with JS, Wasm and native checks.
Code dependency isolation does not remove normative dependencies. Before canonical
JSON, resolve the kernel laws for canonical bytes and CID computation, and test
against pinned identities and independent number-spelling vectors. Before
canonical values, derive identity and normalization vectors from the current
specification. Resolve other contracts before their consuming packages; do not
update specification pins merely to match implementation output.

Remaining independent corpora are still implementation inputs to supply.
README operation excerpts need typed fixture contexts before
compiler conformance checks; parsing complete Programs does not validate excerpts.

The [pure operation checking scope](design/pure-operation-checking.md) lists
the remaining 48 operations, shared Carrier/evidence work and completion gates.
`check:aoa` also checks fixed pure-operation law examples with independent small
oracles. Those examples and their law pins are specification checks, not proof
that the product executes graph, vector or temporal profiles.


## Read-only worktree inventory

Run this opt-in development command with every worktree whose borrowed
links should be considered, using explicit paths (quote paths with spaces):

```sh
npm run inventory:worktrees -- -- "/path/to/owner tree" "/path/to/borrower tree"
node scripts/worktree-inventory.mjs --json -- "/path/to/owner tree" "/path/to/borrower tree"
```

It prints a timestamp, resolved roots, Git changes, largest generated-output
candidates, allocated bytes, dependency/symbolic-link real paths and reverse
references in the declared scope, and visible live file/cwd references. JSON
uses the same information as the readable report. It does not read credential
or other file contents, delete anything, change worktrees, terminate inspected
processes, make network requests, or install dependencies. Git optional locks
and fsmonitor are disabled. The supported live-process interface is `lsof` on
Linux/macOS, with name/port lookups and device-cache writes disabled; `ps` is
never used. Missing `lsof`, warnings, permissions, command failure, timeouts,
and unsupported platforms are recorded as failed checks with unknown visibility.

No absence of observed references certifies a path unused. Other users,
containers/namespaces, closed files that will be opened later, concurrent
changes, undeclared worktrees, and excluded paths remain outside that evidence.
A present live reference is `active`; otherwise usage remains `unknown`.
A borrowed link is independently reported even when its borrower is not running.
The report is evidence for review, never global deletion authorization.

Tracked source and dirty/untracked paths are separate from candidates. Known
credential, database/WAL, evidence, runtime-journal and recovery names are
protected without traversing their contents. Generated-looking directories
containing such paths move to `protectedOutputs`. Compiler source modules
named `journal` are classified as source rather than runtime data. These are
conservative metadata/name classifications, not a complete data-type detector.
A failed Git check leaves protection knowledge explicitly unknown.

Defaults bound the scan to 20,000 entries, depth 6, dependency depth 2, and
10 seconds/4 MiB per child command. `node_modules` package contents are not
fully traversed by default. Nested and scoped links are resolved, including
links through other links; cycles and broken links are reported as unknown.
Targets are never traversed through a link; declare their worktree separately
to inventory them. Increase only the needed bound with `--max-depth N`,
`--max-entries N`, `--dependency-depth N`, or `--timeout-ms N`. Excluded paths,
partial measurements and failed checks are part of both output formats.
Allocated bytes use filesystem block counts with hardlinks deduplicated within
each candidate. Partial sizes are lower bounds. Even complete observed sizes
are not guaranteed reclaimable bytes (shared blocks, other hardlinks and races
are not ruled out). Roots may overlap; totals must not be added together.

CI runs only synthetic regression fixtures, not a scan of CI worktrees:

```sh
node --test scripts/worktree-inventory.test.mjs
```

