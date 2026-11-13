# Development

## Setup and verification

With Node.js 22 or newer, Python 3.11 or newer, a C compiler and `make`:

```sh
npm ci
```

Node.js is used for documentation and toolchain setup. Product implementation
is developed in MoonBit; see the [implementation guide](design/implementation-port.md).
Specification checks also verify generated connector code using the pinned
MoonBit formatter. Complete the MoonBit setup below before running `check:spec`.

### Checkpoint journal layout

The Node Checkpoint journal uses the current private layout
`actql-checkpoint-journal/0.1;model-call-provenance=1;effect-settlement=1;model-current-cut-link=1;model-current-cut-invalidation=1`.
The [settlement design](design/effect-refusal-settlement.md) explains its
observation-only claim and authority boundary.

Historical saved-Run layouts are not supported. Use a fresh journal for the
current implementation; there is no offline upgrade command. Startup refuses
an unsupported layout with `UnsupportedCheckpointJournal` before schema writes.
It never migrates, recreates, or deletes an existing journal automatically.
Do not rewrite a layout marker or drop evidence tables to bypass this refusal.
Current-layout restart preserves the same Run, Checkpoint, Resolution, resume
intent and cleanup records; it does not grant new execution authority.

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

The Native CLI release declaration selects `-O2` for its generated command C.
Qualify an artifact using its actual compiler commands; support objects may
have independently selected flags. `scripts/native-cli-artifact.mjs` accepts
an explicit finite `--compile-seconds` budget without changing that profile.

For the selected Linux x64/glibc Local package profile, the normal producer is
`scripts/produce-native-cli-linux-local.mjs`. It requires an exact clean source,
an explicit package version, the real compiler and the original SQLite and
Ubuntu Crypto archives pinned by the existing component recipes. It runs those
component producers and the ordinary Native artifact producer sequentially.
It never substitutes a Remote-only artifact when Local production fails.
Run it under the existing bounded guard with sufficient compiler time; the
ordinary release build retains `-O2` and `-j 1`.

```sh
node scripts/produce-native-cli-linux-local.mjs \
  --source "$(git rev-parse HEAD)" --package-version "$VERSION" \
  --output "$PRODUCTION" --clang "$REAL_CLANG" \
  --sqlite-archive "$SQLITE_ARCHIVE" \
  --openssl-package-archive "$LIBSSL_DEV_ARCHIVE" \
  --openssl-package-archive "$LIBSSL_RUNTIME_ARCHIVE" \
  --component-seconds 300 --compile-seconds 1800
node scripts/native-cli-release.mjs prepare-local "$COHORT" "$COHORT_JSON" "$PRODUCTION/artifact"
node scripts/test-native-cli-source-free-install.mjs "$COHORT"
```

Use new absolute output directories and original absolute input paths. The
explicit cohort JSON must select the same package version. The optional
`--system-header-root /usr/lib/linux/uapi` selects that separate kernel-header
layout when actually needed; `/usr/include` remains the default and there is
no automatic widening. The selected `prepare-local` path requires a real
Linux Local payload before writing packages. General `prepare` and historical
Remote-only verification keep their separate scope.

The mandatory full-integration `native-cli-linux-local` job uses this profile
and verifies a fresh private npm installation, plain initialization, check,
explain, source-free Run execution and separate-process saved Results after
the source file is removed. Its large-input representative submits a JSON
Program larger than one MiB containing 100,000 Values rows under an explicitly
selected finite operator Host policy, checks every row of the complete first
Result, removes the Program file, and checks the same stored Result in fresh
CLI processes. The operator uses the same installed launcher, libraries and
contract assets through the existing explicit configuration/adoption path;
packaged defaults remain unchanged. A distinct low-policy Host must refuse a
Program exceeding its selected row ceiling. Successful command replies remain
gated by the Native entry's actual cleanup; this is not independent FD inspection.
The consumer writes provisional observations only.
Success evidence is written by its parent after registry close, zero child exit
and verified removal of the original consumer scratch directory.
This profile does not qualify Mock Source/Model/Effect bindings, live connectors,
other platforms or public-registry publication. A Remote/no-runtime acceptance
job cannot replace this positive Local job, and this selection does not change
historical release policy or authorize publication.

For an opt-in command measurement, set `ACTQL_NATIVE_TIMINGS=1`. The launcher
and Native foundation emit bounded, best-effort timing diagnostics on stderr;
successful payloads and receipts on stdout retain their existing format.
These diagnostics are not a stable wire protocol or a cleanup acknowledgment.
They describe selected preparation, execution, Journal, publication, Result
and cleanup boundaries, with selected hash, parse, current, authorization and
SQLite call counts. Counts are invocation attempts at the annotated Native
callsites, rather than a complete census of internal library operations.

Compare an uninstrumented correctness run with a separate instrumented fresh
Run from the same package. Measure separate-process saved Result reads using
their original Run identity. Keep launcher preparation, Native argument
startup, external elapsed time and unassigned time distinct. Nested inclusive
phases cannot be summed as disjoint wall time; parallel, overflow, unmatched
or incomplete diagnostic records cannot establish a complete partition.
Timings do not change authorization, Run state, delivery status or pending
physical cleanup.

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

Full Core and selected `platform_native/remote_journal` diagnostics also compile
an owned, small C fixture executable. The WAL fixture runs it through
`posix_spawn`, using the same configured SQLite library in a fresh process. It
commits the independent version-3/old-Coordinator fixture and exits without
SQLite close; the existing non-mutation and cleanup-retry assertions remain
required. SQLite is never called between fork and exec. Compilation or fixture
failure is a failure, with input/DB evidence retained in that invocation's
namespace. `cc` and the SQLite development headers are required for this test
fixture; no install-time download or product execution path is added.

Full Core and selected `platform_native/host_bootstrap` diagnostics prepare the
existing process-region and channel cases' private 64-page backing files and
C/Rust handler leaf. The wrapper uses the pre-root builder's pinned Rust tools
and a digest-verified libc source, caching the compiler archives under
`.toolchains`. The child and Rust leaf link one shared original C provider.
Preparation or compilation failure fails the command; a retained handler panic
or aborted process does not count as physical cleanup. This test fixture is
separate from the Engine, VM and installed runtime supplier.

Full Native Core runs every `platform_native/http_client` case with the existing
HTTP harness's actual mTLS and bearer peers. This separate profile preserves the
compiler-selected case count and original strict flags. Its environment is not
enabled for unrelated Core packages; transport failure still fails Full Core.

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

## Quickstart

This checkout provides source-built `@actql/*` development packages
(`0.0.0-development`). The commands below test those artifacts; they do not
install an npm release or require an `actql` CLI. Use Node.js 22.22.0 (the CI
version), Git, and the pinned MoonBit toolchain from
[MoonBit](#moonbit). Consumers of the packed artifacts
need only Node.js; MoonBit is needed to build them.

From a clean checkout, prepare one package set:

```bash
npm ci
npm ci --prefix adapters/connectors/duckdb/node --ignore-scripts
node scripts/packed-client-packages.mjs "$PWD/_build/client-packages"
export ACTQL_PACKED_CLIENT_PACKAGES="$PWD/_build/client-packages"
```

Create a new empty directory outside the checkout, switch to it, and install
the package set:

```bash
npm init -y >/dev/null
npm install --ignore-scripts --no-save "$ACTQL_PACKED_CLIENT_PACKAGES"/*.tgz
```

### Run a query

Save this program as `query.aql`. Its three orders are explicit Values, so
this example needs no Connector account or external input registration:

```yaml
version: actql/0.1
id: customer.open_orders
stages:
  - id: main
    inputs: {}
    steps:
      - values:
          schema:
            id: { type: string, nullable: false }
            customer_id: { type: string, nullable: false }
            status: { type: string, nullable: false }
            amount: { type: number, nullable: false }
          rows:
            - { id: o1, customer_id: c1, status: open, amount: 120 }
            - { id: o2, customer_id: c1, status: closed, amount: 30 }
            - { id: o3, customer_id: c2, status: open, amount: 80 }
        as: orders
      - filter: "status = 'open'"
      - group:
          by: [ customer_id ]
          aggregates:
            order_count: { fn: count }
            total_amount: { fn: sum, field: amount }
        as: customer_totals
    results:
      main:
        from: customer_totals
        fields: [ customer_id, order_count, total_amount ]
        order_by: [ { total_amount: desc }, { customer_id: asc } ]
results:
  main:
    from: { stage: main, result: main }
```

Save this Client as `quickstart.mjs`:

```js
import {readFile, writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {connect} from '@actql/node';

const client = await connect({mode: 'local', owner: 'local',
  durability: 'durable', installation: {directory: resolve('actql-state')}});
try {
  const submissionRef = client.newSubmission({nonce: 'customer-open-orders'});
  await writeFile('submission.json', JSON.stringify(submissionRef) + '\n');
  const execution = await client.startSource(await readFile('query.aql', 'utf8'),
    {format: 'yaml', submissionRef});
  const state = await execution.wait({signal: AbortSignal.timeout(60_000)});
  if (state.status !== 'succeeded') throw new Error(JSON.stringify(state));
  const rows = await execution.result('main').all();
  await writeFile('answer.jsonl', rows.map(row => JSON.stringify(row)).join('\n') + '\n');
  await writeFile('run.json', JSON.stringify(execution.ref) + '\n');
} finally {
  await client.close();
}
```

Run it:

```bash
node quickstart.mjs
cat answer.jsonl
```

`answer.jsonl` contains, in this order:

```jsonl
{"customer_id":"c1","order_count":1,"total_amount":120}
{"customer_id":"c2","order_count":1,"total_amount":80}
```

Submission checks the Program; `wait()` follows it to termination and
`result('main').all()` reads the named Result. `run.json` saves the Run
reference for `client.attach()`. Reusing the same request ID and Program
returns that Run rather than executing it again. Keep `actql-state` while
using its retained Results. The consumer directory belongs to this
example and can be removed when you no longer need its files or Results.

For two independently bound local databases, run the executable
[two-source DuckDB JOIN example](../examples/two-source-join/README.md).
It uses one JSON Program and returns a Named Result through the same public Client.

## Program model examples

The canonical Program model (YAML or JSON) for the operations beyond tables.
The Graph excerpt is checked against an independent fixture.

Event sequences, graph traversal, vector search, and model tasks return
relations, so `filter`, `join`, and Effects work on their results like any other
step. Examples:

**Event sequences.** Detect an alert followed by a remediation, per incident,
within two hours:

```yaml
  - sequence:
      by: [incident_id]
      time: occurred_at
      id: event_id
      pattern:
        - as: opened
          where: {eq: [{field: kind}, {literal: alert_opened}]}
        - as: remediation
          where: {eq: [{field: kind}, {literal: remediation_started}]}
      within: 2h
      contiguity: subsequence
      overlap: disallow
    as: detected_sequences
```

**Graph.** Build definition-keyed nodes and edges, then select edge
properties. Distinct edge keys preserve parallel edges with the same endpoints:

```yaml
  - graph:
      version: actql-graph-constructor/0.1
      nodes:
        - name: N
          from: nodes
          key: [tenant, id]
          labels:
            - {name: Node, properties: {mode: all_columns}}
            - {name: Person, properties: {mode: no_properties}}
      edges:
        - name: E
          from: edges
          key: [tenant, key]
          source: {definition: N, key: [tenant, src]}
          target: {definition: N, key: [tenant, dst]}
          labels:
            - {name: R, properties: {mode: all_columns}}
            - {name: Link, properties: {mode: no_properties}}
    as: g

  - match_edges:
      definition: E
      label: R
      where: key > 0
      fields: [key]
    as: matched
```

The [complete Program](../scripts/fixtures/graph-parallel.program.json)
declares the `nodes` and `edges` Relations. Submit it with the public Client
above using `format: 'json'`; its `answer` Result contains `{key: 10}` and
`{key: 11}`. The retired `graph` constructor is refused. Other Graph consumers
without a current keyed implementation are also refused before Run acceptance;
see the [current Graph contract](design/graph-contract.md#definition-keyed-graph-profile).

**Vector search.** Rank active runbooks against the original alert embedding:

```yaml
  - from: active_runbooks
    nearest:
      queries: incident_queries
      query_id: alert_event_id
      query_vector: embedding
      candidate_id: runbook_id
      candidate_vector: embedding
      metric: cosine
      k: 3
    as: runbook_rankings
```

All three return relations, so they join together in one program: which
incidents went from alert to remediation, what those services touch downstream,
and which runbook fits the original alert.

**LLM structuring.** Turn ticket text into typed rows under a versioned
model-task contract:

```yaml
  - infer:
      contract: model-task:ticket-triage.v1
      input:
        subject: {field: subject}
        body: {field: body}
    as: ticket_triage
```

The contract fixes the prompt, model selector, input and output schemas, and
data-handling policy. Its result is a separate relation keyed by the input
identity, so source fields return only through an explicit join.

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

The public Node facade resolves the selected Local provider before loading its
existing private compile-cache helper, then imports that same resolved provider.
The helper's declared `@actql/local-node/_internal/compile-cache` delivery edge
uses the same facade's package resolution context; it is no public SDK API.
Missing or invalid private delivery exports fail without a replacement helper.
This places the optional V8 cache call before Local's static Host graph without
selecting Local for Remote connections. Coverage exclusion and an unavailable
or declined Node cache keep the existing helper policy. This is no ActQL
checking cache, funding evidence, admission result, or runtime identity claim.

### Local Files native delivery

The ordinary Local package producer builds the Local Files descriptor binding
on the pinned Node 22.22.0 toolchain for Darwin arm64/x64 and Linux x64. Linux
uses the same reader, writer, bounds, currentness and cleanup implementation;
only timestamp field access and atomic rename calls differ. Its private image
exports the complete Local Files read/write interface, not the separate
Darwin/APFS HostJournal directory inspector. File STORE installation and
approval/claim ownership do not change by platform.

Creation requires the filesystem's atomic no-replace rename operation; there
is no existence-check or link/unlink fallback. Replacement swaps the directory
entry without following its symlink and is not compare-and-swap. File fsync
precedes rename, and directory fsync follows it. Failed or ambiguous publication
never supplies a success observation or permission to replay. A successful
local filesystem test does not establish arbitrary network filesystem behavior
or power-loss durability. Unsupported operations fail without weakening these
requirements.

The normal build records the original source, compiler, Node headers and binary
identities. Linux records its actual compiler/system header inputs, not an Apple
SDK identity. Installed consumers use the package's ordinary platform-selected
image; copying another build's native module into an installation is not normal
delivery or acceptance evidence.

### Source-free Local scalar capacity

Pure source-free Local preparation can use a smaller scalar value-node envelope
when every original checked input and intermediate relation schema consists of
Number or Boolean fields (including nullable fields). The bound is the prepared
row ceiling times the larger cumulative input or output row-node envelope.
Each row container counts separately from its scalar fields; input occurrences
include every original prepared node port (also Step targets and duplicate
ports), and output occurrences include every original node plus possible
external producer projections. This conservatively covers shared multi-step
sequence budgets rather than assuming one kernel per task. It is
never larger than the general 20,000-node envelope. Missing schemas, nested or
other value contracts, and out-of-range products retain the general envelope.
This is an implementation capacity derivation, not a language restriction.

For source-free Request preparation, the configured Plan's complete execution
and retention requirements must fit the same original initial admission before
its module body completes or its custody transfers to a Run. A known byte
refusal is reported as `ClientProgramRejected` / `operation_failed`, not as an
invalid or unsupported Program. A failed original Result metadata quote is also
an operation refusal before provider construction, without invented numeric
capacity amounts. Missing optional specialization or a legitimate absent Result
envelope is not that failure. The existing bounded Host diagnostic observer
can receive the best-effort event `preparation_capacity_refused` with immutable phase, dimension, and decimal
required/available byte quantities. These diagnostic facts neither increase
capacity nor authorize a retry. The public submission wire retains its existing
coarse Problem shape; saved older failed Runs keep their original terminal
projection. Unclassified, foreign, currentness and cleanup failures remain
uncertain rather than becoming capacity refusals.

The pre-admission inventory and configured providers/imports/exports use the
same checked-sequence derivation. Text, expression/intermediate execution,
serialized-value measurement, row, work, and the 512 MiB retained-store ceilings
remain unchanged. Values are not sampled, truncated, or replaced to fit a quote;
retained input ports and task outputs still count separately. Source acquisition
and Effect paths retain their original envelopes.

### Checkpoint Resolution and Effect continuation

`@actql/run-host-core/checkpoints` supplies the existing portable Checkpoint
Owner without a physical Store or Node execution runtime. The Host seals and
persists a Checkpoint before committing its waiting Run projection.

For a Resolution, obtain `resolutionProofPreimage` and authenticate it using
Host-trusted reviewer keys and current authority. Pass those authenticated
facts to `resolutionAdmit`, sign its attestation preimage, then use
`resolutionDecide` with the closure read inside the durable transaction.
Commit the Resolution, Checkpoint closure, unique resume intent and same Run
transition atomically. Admission alone does not authorize continuation: check
`checkpointExpiredAt` again at commit time after asynchronous authentication
or signing, and check `resumedApprovalAt` for the approval's own lifetime.

`effectResumeClaimDecide` selects continuation or settlement using the current
authorization/environment binding. Persist its generation, then use
`resumeFenceDecide` before a protected operation or intent mutation. Settlement
does not authorize unknown Effect replay. Run lifecycle projections and allowed
transitions do not prove execution, physical cleanup or reservation release.

### Effect Run Host preparation and restoration

`@actql/run-host-core` exposes `prepareEffect` and `compileEffect` for the
existing checked Effect computation Owner. These return opaque handles separate
from an Effect-free Program. `effectExecutionShape` projects checked task,
acquisition and Effect counts; it does not select or schedule tasks.

After the Host has checked current authorization, `issueAllowedEffectRun` and
`issueEffectRunDefinition` bind the original policy evidence and Run identity.
`issueEffectRunMaterials` serializes the retained JSON Program, environment and
separately supplied parameters using the existing bounded materials codec.
`admitEffectRunMaterials` reconstructs that same Owner from the saved evidence
and the expected Run definition CID. It does not issue fresh authorization or
extend the saved lifetime. `effectRunStartCurrent` checks the original policy
and Run lifetime; the Host must independently recheck current authority.

For the finite completion-free Resident Effect profile,
`issuePreparedEffectRunMaterials(allowed, definition, request)` uses the original
checked preparation retained by the allowed Run. It accepts no replacement
Program, environment or parameters and performs no re-preparation or compilation.
It returns an opaque `IssuedEffectRunMaterials` with the original `wire`. The
private Owner reference remains process-local. Pass that same object as the
fourth `admitEffectRunMaterials` argument when restoring journal-bearing bytes.
An object copied from its visible fields or a wire without original custody is
refused. No serializable remote proof or transport signature is implied.
The original preparation Owner issues its inventory-backed journal before the
material projection; actual completions and unsupported profiles refuse rather
than falling back to a fabricated empty journal.

For an initial live Run, `bindPreparedEffectRunMaterials(allowed, definition,
issued, request)` binds those exact nominal originals through the same Common
material Owner without re-preparation or compilation. It retains the original
prepared/compiled handles and accepts no replacement inputs or serialized proof.
Cold restoration continues through `admitEffectRunMaterials`.

`restoreEffectRunNormalization` accepts only the exact object returned by
`admitEffectRunMaterials` or `bindPreparedEffectRunMaterials`. It reuses saved
original journal bytes through the material Owner without journal issuance. Copying its visible fields does not
recreate that custody. Initial execution-material admission still reconstructs
execution ownership once on cold restoration; the normalization inverse does not
repeat it.
Neither a journal nor a material content digest supplies current authority,
Provider permission, approval or physical cleanup evidence.

These APIs perform no Source acquisition, Preview, approval or physical Effect.
Run admission is not Effect approval. Dispatch, retained input custody,
Checkpoint/Resolution and physical apply remain responsibilities of their
existing Owners and consuming adapters.

The MoonBit `prepare_client_effect_source_dispatch` projects the initial
Source task from the original retained Effect compilation. Its initial scope
is one acquisition, two checked computation tasks and one Named Result on the
consumer. `bind_client_effect_source_dispatch` checks the received Run/task and
logical Source input against reconstructed Effect materials; it never treats
the Program as Effect-free. Native
`admit_resident_effect_source_dispatch` additionally checks trusted delegation,
the current Site generation, original lifetime and configured Source identity
before acquisition. Admission does not grant a journal start claim or Effect
approval. The existing runtime must recheck current authority and lifetime at
physical start. The polled holder/Checkpoint/approval connection remains a
separate integration boundary.

For the initial acquired Effect composition,
`prepare_client_effect_retained_input_edge` and
`prepare_client_effect_retained_task_dispatch` use the original Effect Run
and the existing independently committed Transfer destination. Native
`open_resident_effect_retained_compute` consumes that receiver holding through
the same decoder, borrow and cleanup Owners as the ordinary consumer. Its
typed Effect projection preserves both original task coordinates and Effect
dependency pins. An Effect pin retains the consumer allocation after ordinary
Result export closes. Returning that pin does not reclaim the destination
holding or producer capture; their own cleanup remains necessary. These are
physical custody APIs, not a journal start claim, approval or public Cloud
integration.

The formal `@actql/run-host-core` facade also supplies `prepareEffectRequest`,
`effectSourceInputBinding`, `issueEffectSourceDispatch`,
`prepareEffectRetainedTaskInputEdge` and `issueEffectRetainedTaskDispatch`.
Their Effect handles remain opaque and cannot enter the Effect-free facade.
The retained edge feeds the existing producer/Transfer/current-input APIs;
consumer issuance re-admits the durable destination before and after current
authorization callbacks. Original materials can reconstruct the same caller,
Run and Source dispatch. Hosts still own persistence-before-send, current
permission, start claims, approval and physical execution.

`effectTaskKeys`, `effectResultDefinitions`, `effectResultSchema` and
`effectSourceEvidenceFacts` expose the original checked Effect computation's
dispatch coordinates, declared Result contracts, schema and Catalog facts.
They require the matching opaque preparation and compilation, including after
original Run-material reconstruction. A Host need not parse the Compiled Plan
or prepare the Program again as Effect-free to obtain this inventory. Effect
members are not public Result declarations. Catalog evidence grants neither
Source read permission nor Effect approval, and an inventory is not proof of
execution, publication, a waiting Run transition or cleanup.

`inspectEffectTaskProgress` admits the trusted Coordinator's saved bytes against
the original allowed Effect Run and its checked task graph. It exposes
`computationComplete` and `taskCleanupComplete`, not a public Run state, Effect
outcome or permission to publish. Task cleanup does not discharge Checkpoint,
Effect Ledger, Transfer, borrower or rereadable Result custody. The opaque Effect
progress cannot enter the Pure unpublished Run/cancellation projection.

`prepareEffectTaskPhysicalStart` derives the original Effect request identity
and uses the same saved-intent/start decision as ordinary checked tasks. A
persisted but unobserved intent remains the original attempt; historical
Accepted, Running or Unknown evidence never authorizes a second start. The Host
still must commit the exclusive claim, recheck current Source/retained-input
custody and authority, and use the existing dispatch sender. The decision is
not Effect approval and does not perform a Provider operation. Resolution,
waiting Run commit and physical apply remain separate Owner connections.

### Installed Connector distribution inputs

The standard Local package resolves provider runtimes, installation adapter
entries and static declarations from the same checked `host-bundle.json`
manifests that generate its installed connector table. The resolved inventory
in `scripts/local-node-package-inputs.mjs` is shared by runtime compilation,
asset copying and adapter packaging. A stale generated table is refused.

An installation can list connector-owned JSON declarations and physical I/O
assets in `assets`. JSON declarations must be below that connector's source
directory. Physical Python workers, requirement pins and documentation must be
below its adapter directory and use the admitted `.py`, `.in`, `.lock` or `.md`
suffixes. All assets must be existing regular files in their declared owner;
absolute paths, traversal, aliases to outside files and duplicate entries are
refused. These files retain their package-relative locations for the installed
adapter's URL reads. The package contains these declared data files, not the
connector's MoonBit sources. Adapter imports are followed by the existing
module graph builder.

The generated `packages/local-node/src/connectors` directory is ignored by
Git. Packing and freshness checks refuse old undeclared files or symbolic links
there; remove stale generated output before rebuilding after an asset removal.
Adapter destinations also refuse symbolic links before any copy. A Host
installation implemented in JS or Python may omit `providerBundle`; it still
declares its real Source/Effect roles, registration and revision, and does not
receive a dummy MoonBit provider runtime. Local Table I/O uses this declared
installation and finite asset inventory, not a handwritten Host entry or worker
list. Python dependencies remain optional installation dependencies.
`test-packed-installed-connectors.mjs` creates an empty producer from source,
uses normal prepack, and checks all registered provider bundles in an external
consumer, including GitHub Source/Effect startup without provider I/O.

Distribution resolution adds no external package resolver or another
execution/authorization owner. The Host's
built-in DuckDB JS bridge remains available without installing its optional
native transport; selecting an acquired DuckDB source still requires that peer.

### Connector role selection

Rebuild-time `names` selects Connectors from the union of their declared
Compute, Node-strategy and Host manifests. Omission discovers them in stable
name order; an explicit empty array selects none. Unknown, undeclared and
duplicate names are refused. Unselected manifest contents are not read.

The generators project that selection independently into real contributions.
A Read-only or Effect-only Connector needs no dummy Compute declaration;
a Compute-only Connector needs no Host installation. A Node strategy still
requires its own Compute declaration. A Host manifest declares `source`,
`effect`, or both, and every declared section must be valid. An installation
with neither role is refused; absent roles never acquire loaders or profile
entries. Runtime role tables validate complete entries before projection and
retain their existing per-role duplicate-profile checks.

This removes generator restrictions that were stronger than the independent
entrypoints in `connector_sdk/CapabilityBundle`. It changes no registration,
authorization, identity or dispatch owner. Empty or Host-only projections are
valid for neutral compositions; the standard Local Host keeps the genuine
Local Compute dependency used by its handwritten carrier and Program bridges.

### Focused Connector source checks

From a prepared development checkout, select the Connector and the affected
test files in one command:

```sh
node scripts/check-connector.mjs notion --stage source \
  --test adapters/connectors/notion/test/users-catalog.test.mjs \
  --test src/connectors/notion/catalog/users_wbtest.mbt
```

The command reads the existing manifest selection, checks the complete normal
Node and RelA generated assemblies without writing them, then runs exactly the
selected files through the existing nonzero-execution guard. A provider subset
must not replace the shared normal assembly. Node files end in `.test.mjs`;
MoonBit files end in `_test.mbt` or `_wbtest.mbt` and run on JS. Each file is
selected once. Shared regression files can also be selected explicitly.

The whole sequence has one bounded local execution Owner and defaults to the
lint workflow's time budget; `--timeout-seconds N` sets an explicit duration.
A failed generation or test step stops the sequence. Missing dependencies,
stale generated output and zero/skip-only test execution remain failures.
Prepare the selected tests' ordinary dependencies first; this command does not
build a runtime, pack a distribution, install dependencies or require a clean
working tree. It supports editing an unfinished change.

This first author entry implements `source` only. `installed` is refused rather
than redirected to source checks. Standard-loader, authentication, capacity,
public read/write and restart acceptance still require the actual family suite
and matching ordinary distribution. Source success does not register an
unfinished role or establish provider availability.

### Trusted external Compute builds

`resolveConnectorBuildInputs` in `scripts/connector-build-inputs.mjs` accepts
explicit, already verified package roots, exact MoonBit module names/versions,
a Host composition module, and selected Connector manifest directories. It
reads the existing `moon.mod`, `compute-bundle.json` and `node-bundle.json`
declarations and supplies immutable inputs to the existing Compute/Node
generators through their `buildInputs` option. That option fixes selection;
it cannot be combined with a second `names` list.

The Host module imports both Core and the selected Connector modules. Core
does not import the external implementation. Generated Compute imports use
the external module namespace, and the Node bridge imports the generated
assembly through the Host module namespace. The current external profile is
JS with static Node contribution loading and a generated Compute bridge.
Handwritten product Client bridge extensions are refused explicitly. External
Read/Effect installations use the installed Host composition below.

Package acquisition, normal package integrity verification and stable input
placement remain with the trusted build harness. This resolver downloads and
installs nothing, imports no Connector code and grants no execution authority.
Package roots are never taken from a Program or connection profile. It rejects
unknown namespaces, mismatched module/dependency pins, dependency cycles,
unsupported JS targets, escaping paths and symbolic links, including generated
output paths. Ordinary compiler parsing and type checking still apply.

The metadata reader supports an audited subset of text `moon.mod` and
`moon.pkg` declarations; unsupported syntax is reported explicitly as a build
profile limitation, not an ActQL language rule. Compute-only contributions do
not acquire an invented Connector revision. Existing Host registrations and
revisions retain their meaning. Build receipts and npm integrity are package
input evidence; executable component identity, signature, activation and
retention remain with the existing runtime bundle owner.

### Trusted external installed Host builds

The same resolved input snapshot includes checked `hostEntries` for Read-only,
Effect-only and combined Host contributions. External modules use the existing
`src/connectors/<registration>` and `adapters/connectors/<registration>/host`
manifest layout. A provider's qualified MoonBit package belongs to its module;
its `providerBundle` remains the safe package-local
`connectors/<registration>/<bundle>` key. This key grants no execution authority.

Generate with `checkNodeAssembly(hostRoot, true, {buildInputs,
installations: true})`, then pass
`localNodePackageInputs(hostRoot, {buildInputs})` to the existing builders.
`buildExternalLocalNodeRuntime({inputs, destination, compiledDirectory})`
compiles only the inventory's exact module-owned targets into fresh output.
`buildLocalNodeAdapters({root: hostRoot, inputs, destination})` copies the same
inventory's finite adapter graph and static declarations. The destination and
compiled directory stay inside the Host root. The harness supplies the local
MoonBit workspace; these functions never download or install dependencies.

The inventory separates physical source paths from distribution destinations,
rejects ownership collisions, and places the selected installation table at
the ordinary `adapters/connectors-builtin/installations.generated.mjs` path.
The adapter graph stays within verified module roots. External helper modules
stay beneath their registration's adapter directory; declared assets stay in
its source directory. Supported external imports are Node built-ins and the
existing ActQL package boundaries; the Host's optional DuckDB package remains
optional. Unsupported dependency shapes are explicit build-profile limits.

Authored Node installation adapters reuse
`@actql/local-node/connector-installation`, a direct export of the common row,
credential invocation and initialization-cleanup helpers. Common runtime
handles and separately compiled provider handles keep their respective owners;
the provider boundary exchanges the existing serializable values. Host profile
validation, authorization, capture, publication, Effect claims, recovery and
cleanup remain unchanged. See `scripts/fixtures/external-installed/README.md`
and `scripts/test-packed-external-installed.mjs` for normal prepack and an
external application consuming the resulting package set.

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
execution. Classified-heavy work additionally reserves one of at most four
shared slots across this user's worktrees on this host. Admission checks the new
job's memory estimate against current available memory, and the sum of all
memory estimates against physical RAM. Running jobs already affect current
availability, so their estimates are not subtracted from it again. Disk space
and available CPUs are checked against still-held verification reservations.
The default estimate is 2 GiB memory, 2 GiB disk and two CPU threads
per job, with 256 MiB memory and 128 MiB disk headroom. A `runLocalCheck` caller
may supply positive integer `heavyResources: {memoryBytes, diskBytes, cpuThreads}`
estimates for its actual workload; these do not alter product fuel, capacity or
authorization and are not an OS quota or a cold-build peak guarantee. Preserve
each recipe's additional preparation/runtime and minimum-free-space conditions.
Memory availability is read from Linux `MemAvailable` or Darwin's read-only
`memory_pressure -Q` percentage of physical memory; raw free pages alone omit
reclaimable cache. Missing or malformed availability measurements refuse admission.
If resources or all slots are occupied, report concrete queue/resource pressure
and retry admission only after the relevant resource or Owner state changes.
State is beneath the canonical home directory
at `.cache/actql/local-checks/<host-hash>/`, independent of `TMPDIR` and
`RUNNER_TEMP`. Other users or containers with separate homes/state are outside
this cooperative lock scope. Existing state-directory symlinks or foreign
ownership are refused; the wrapper does not change permissions or user config.

A lock records a random owner token, supervisor PID, user/host, worktree and
evidence path. Acquisition is exclusive; release checks file identity and the
same token. `summary.json` lists the invocation's worktree and reservation locks;
`heavyAdmission` separately records its estimate, resource snapshot, slot and
shared compatibility barrier. Other admitted jobs may still hold that barrier
after this invocation has released its own locks. A failed acquisition releases
only locks it acquired before starting any command. A busy worktree, legacy or
incomplete lock is refused. Pool admission/release uses a checked short mutex
with at most one second of bounded contention waiting; it never reclaims a stale
mutex. PID liveness is diagnostic only: PID reuse, missing PIDs,
reboots, incomplete metadata and surviving descendants never authorize removal.
There is no automatic stale-lock recovery or generic cleanup command. Inspect
the exact reported owner/evidence and confirm its processes have stopped
before manually recovering that lock. Never remove another active worker's
lock or use a broad process-kill command.

The existing `heavy.lock` is retained as an immutable compatibility barrier
for the complete pooled lifetime. A live old singleton prevents pooled admission;
an old checkout also refuses a pooled barrier rather than overlapping its jobs.
Each reservation retains its own supervisor identity and token and must match
its still-held exclusive worktree lock. Missing or changed worktree custody
refuses both admission and release. The barrier's initial Owner may already have completed while other slots remain live: inspect
all member Owners, not only the barrier PID. The last member removes the checked
barrier. A missing/replaced barrier, malformed member, orphan slot or unknown
ownership is refused without automatic cleanup. Worktrees must normally adopt
the integrated guard before participating; never bypass a live legacy lock.

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
keep each running worktree exclusive and honor all existing live locks.
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

## Pull request checks and main integration

Normal CI runs on pull requests (`opened`, `synchronize`, `reopened`,
`ready_for_review`, and `converted_to_draft`), pushes to `main`, weekly Monday
03:23 UTC deep validation, and explicit manual dispatch. The repository must be public. No repository activation
variable is required: enable or disable the workflow through GitHub Actions.
This workflow does not change repository visibility, permissions, branch
protection, or release authorization.

Pull request jobs use the event's synthetic merge checkout. Its tested SHA is
kept distinct from the PR head SHA. Target selection compares that checkout
with the event's base SHA, and admission rejects a superseded PR head. Fork
pull requests use the same read-only `pull_request` workflow: no secrets,
write permissions, or `pull_request_target` execution are introduced.

### Draft preparation and Ready verification

Drafts run preparation (`select-targets`, `preflight`, `lint`, `spec`, and the
aggregate `check`). An exact registered fixed-request test family adds
its focused JS tests. Changes to normal Python packages, producers, acceptance
fixtures, or their CI/toolchain inputs also run the genuine macOS wheel lane
automatically, including in Draft. Unrelated Draft changes do not start that
lane; this targeted exception is not complete Draft product coverage. The
source-bound selection drives both scheduling and required-job checks. These
checks are not full product verification: the aggregate
intentionally fails with “awaiting ready_for_review”. Marking Ready triggers
the normal applicable coverage; subsequent non-Draft pushes rerun it. Returning
to Draft cancels the superseded PR run through the existing concurrency group.

General product changes select full coverage. Reviewed maintenance, portable,
and focused-test selections remain explicit, bounded exceptions. Missing or
invalid selection, failed or cancelled required jobs, and unexpected skips
cannot satisfy the final `check`. Inspect the jobs actually executed; a narrow
PR run does not establish a full integration or release checkpoint.

CI passes the complete selection and aggregate job results through quoted JSON
files in the runner's temporary directory (`CI_PLAN_PATH` and `RESULTS_PATH`).
Source inventories can exceed Linux's per-environment-string execution limit.
File transport preserves the original SHA, event, paths and compiler evidence;
the same consumers validate them without truncating or reselecting coverage.
Direct callers may still supply the existing inline inputs, but conflicting
inline/file inputs refuse rather than silently choosing one. Local full-Core
execution excludes both hosted plan transports and retains complete coverage.

The Native HTTP and Remote Query harnesses select their existing owned files
through the Query packages' transitive imports and literal FFI includes. Separate
CLI/conformance packages do not widen this closure. Unknown imported environment
readers, unresolved FFI inputs and changed required cases retain full fallback;
Core remains unfiltered. A repository regression requires the normal subset to
work, alongside the refusal tests. Selection and fallback reasons appear in the
job summary. The focused fixed-request lane similarly checks actual Git fixture
pins, not just synthetic fixtures; changed shared inputs require re-review.

Linux and macOS each prepare the original Native commands/components once in
one workload runner. Background command groups use that SAME physical
preparation and toolchain. Resident Effect/Site remain inline, retaining the
original immediate summary upload, bounded failure-only diagnosis and fallback.
Two background slots run the other independently owned cases; final join checks
the complete original inventory, preserves failures and forwards original packed
artifact outputs. HTTP integration remains an independent job with its original
stock-library fixture. Both workload and HTTP results are strict dependencies.
The original retained-product command runs after the background join: its long
global Moon build must not hold the build lock during bounded npm prepack.

On macOS the complete remote-runtime command follows Resident controls in the
second existing background slot, while the complete HTTP command keeps its
original package and case order in the runtime slot. The remote invocation owns
one verified private Moon/Core installation and separate generated roots for its
stripped Native tests and default-profile Query tests. Its compiler environment
changes only the tool home and PATH; signed fixtures, private Stores, dynamically
allocated peers and original child cleanup remain per invocation. Shared project
`_build` and installed Core caches are not writable compiler outputs for that
remote lane. Linux group assignment and the two-slot bound remain unchanged.

HTTP, remote-runtime and bundle-CLI consumers verify the existing same-job
portable preparation before importing its returned original module path. A
foreign or changed explicit preparation refuses without rebuilding it. Without
an offered preparation, the original standalone builder is retained; focused
HTTP review builders keep their original explicit compiler scheduling. This
keeps concurrent CI consumers from rewriting the prepared shared JS artifact.

The macOS HTTP harness assigns its original complete package/Query loop and
its subsequent CLI control sequence to the existing two background workers.
Each phase owns its peers, Stores, pinned compiler copy and Native output tree;
only completed verified preparation inputs are shared. Nested test wrappers use
the same phase-local compiler entrance. The joined HTTP result requires both
phases, retaining the original parent deadline, flags, assertions and cleanup.
The complete standalone/Linux entrance still executes both phases in order.

No Native preparation is transplanted across runners: existing descriptors bind
physical compiler aliases and generated toolchain inputs. A mismatched original
still refuses; there is no metadata rewrite or implicit rebuild fallback.
Explicit compiled-command inputs use a separate inert-data path for the two
closed bundle/Resident entries. Export preserves the original successful build,
command and complete selected-input receipts. Receive rechecks the same Source,
target, compiler profile and current source/tool/SDK bytes, then publishes a new
receiver file and physical descriptor. Generated producer inputs remain immutable
provenance data; they are not executed as receiver tools. Original paths and
inodes are never relabeled as local prepared originals. This path neither starts
a provider nor replaces the subsequent fresh runtime, currentness or cleanup
checks, and a refused explicit input never triggers a rebuild fallback.
The macOS workload explicitly selects `--lanes 2` inside that same preparation
owner. Closed command compilation runs alongside the existing sequential
libraries, HTTP and portable preparation. The command lane uses one verified
private copy of the pinned tool installation and Core bundles; shared tool-home
aliases refuse as output destinations. Build/cache roots stay separate. Both
lanes must finish before the single complete index and consumer environment are
published, including when either lane fails. Original command budgets also cover
export and receive; component profiles, TLS jobs and consumer deadlines remain.
The default CLI and Linux workload keep one lane.
A complete index may retain `received.json` for an explicitly received command.
Its exact immutable inputs are checked once per unchanged process scope, with
physical file identity, metadata and current tool selection checked on every
reuse. Changed inputs invalidate the scope and require full verification; a new
process starts empty. The real factory keeps its current Source, entry, target
and executable checks and never copies or rebuilds a reused received command.
Local `run native` retains one preparation and every original case serially.
Job and case deadlines stay unchanged. Parallelism is CI orchestration, not a
product lifetime, permission, capacity or successful cleanup claim.
Timeout and failed-command cleanup retains the known process group's TERM/KILL
grace after its leader closes. An unconfirmed group stop remains a failure;
a timed out leader exiting zero cannot turn the command into a success.

Native preparation logs each command/component interval as
`ACTQL_NATIVE_CI_PHASE` and writes small `phase-*.timing.json` or
`lane-*.timing.json` diagnostics into
its existing receipt artifact before later tests run. Each record identifies
the source, target, phase, elapsed milliseconds and producer outcome;
parallel lanes also record their actual start/end bounds;
it is not an artifact reuse or runtime acceptance receipt. Missing timing I/O
never replaces the producer's original result. The HTTP package loop separately logs build-only and
execution intervals using the same compiler inputs and fixture environment.
Execution includes Moon's incremental freshness check; it is not a pure test-CPU
measurement. Compare these intervals with Actions job start/queue observations;
case counts alone do not predict wall-time savings.

Hosted Native Core assigns complete compiler-owned ordinary package drivers to
four disjoint jobs. HTTP, Source and scoped physical profiles have independent
jobs with their original environments; the scoped profile retains the deliberate
second geometry configuration. The compiler metadata selection checks complete
case identities, unchanged driver inputs, nonempty partitions and no overlapping
ordinary drivers before C generation. Portable targets are not multiplied.
The original two-part local interface remains supported.

The migration toward Linux for exhaustive common Native coverage starts with
eight additional required Linux partitions in the same Core matrix. The pinned
compiler's complete source, whitebox and blackbox import graph identifies Native
command/platform packages, explicit C stubs and linker overrides, including all
their importers. Every remaining compiler-owned common case is assigned once,
keeping whole package drivers and the existing release/strip, strict warnings,
test-only generated-C optimization and serial test execution. Nested packages
use original compiler-selected file inputs rather than admitting an unrelated
child package. The actual executed case count must equal compiler discovery.
After actual execution of all eight Linux partitions, hosted Darwin Core uses
the complementary compiler-owned package scope. It retains FFI/allocator,
SQLite/crypto/linking and installed-consumer differences, complete HTTP/Source
and scoped profiles, and the deliberate repeated geometry. Local full Core
diagnostics remain unpartitioned and do not inherit the hosted platform scope.
This transition is
not a measured CI speedup or evidence that the complete workflow meets its
20–30-minute target including queue and setup time.

The hosted scoped job runs its two existing allocation profiles concurrently
on the same runner (`ACTQL_TEST_NATIVE_CORE_SCOPED_JOBS=2`). Checkpoint,
component and relation preparation still occur once, before both loops, and
each profile keeps its original separate compiler target and per-case files.
The original shared deadline and nonzero case checks remain. A failed profile
stops its own later cases; the other profile finishes within that deadline
before the original failure propagates or scratch cleanup is confirmed.
Local execution defaults to one serial profile at a time.
The existing scoped compiler wrapper records each original C compile/link/query
interval separately. These intervals exclude Moon lowering and test execution;
their sum is compiler activity, not elapsed job time when profiles overlap.

The ordinary Native child measures `--build-only` and subsequent execution
separately in the same build tree, with identical arguments and environment.
Both phases share the original absolute timeout. Execution still uses the
nonzero/full-count guard and includes Moon's incremental freshness check.
Neither successful compilation nor a timing record establishes test success.

The preparation helper reuses the verified OpenSSL source archive from the
compatible Darwin Crypto producer for HTTP TLS acquisition. TLS rechecks the
original digest and builds its own patched source/libraries; Homebrew and Linux
profiles do not assume that Darwin archive exists. An explicit original archive
continues to take precedence. `--http-jobs 1|2` bounds only the build-time TLS
compiler parallelism and records it in the TLS receipt; the local default remains
one. Linux and macOS full Native CI explicitly select two after a bounded actual
Mac TLS/HTTP component build. Existing time windows, compiler flags, cleanup and
deployment settings stay intact. Local measurements do not establish CI speedup;
runtime resource limits and the component lifetime profile are unchanged.

Session input/origin rejection tests run in the independent `session-controls`
job, with the same pinned toolchain, Lean and complete test-file inventory.
Every selected file must report executed tests, with no failure, cancellation,
skip or todo. The `session-evidence` collector, mutation/final campaigns and
artifact identities remain unchanged. Both jobs are required for deep proof
coverage; local `run session-evidence` retains both sequences serially.

### Full integration and release evidence

Every main push selects full runtime coverage, including all three Core
backends and macOS. Complete Session and pipeline mutation/search campaigns run
when their actual source snapshot or safety/orchestration inputs change. Their
snapshot includes all Core source and vendor files; ownership, resource,
platform, build and unknown inputs conservatively select deep coverage. Other
reviewed integration-tree changes retain runtime/package acceptance without
repeating unrelated proof campaigns. Cheap pipeline contract/negative checks
remain independently mandatory even when deep assembly is not selected.

Only the current push event's exact `before` and tested `after` endpoints are
compared for deep scheduling, with both sides of renames and deletions retained.
An absent, invalid or unavailable base selects deep coverage. This is not the
removed prior-success API/history traversal: no previous successful run or
ancestor search chooses ordinary CI jobs. Current checkout SHA, source,
toolchain, artifact, and execution identity checks remain required.

Main also records performance from the same run's normal Client artifacts
using the existing measurement tools. Timing regression thresholds are not
blocking in record-only mode; malformed measurements, setup and correctness
failures still fail the required main aggregate. No measured speedup is claimed
from scheduling alone.

The normal main concurrency group keeps one running integration and at most
one pending run; newer arrivals replace pending work. This does not promise
FIFO or test every intermediate merge. An active main run validates its
immutable event SHA and may finish after main advances. PR and working-branch
runs still reject superseded heads. Performance/probe runs have separate groups.

Weekly scheduled validation runs complete runtime and deep campaigns on its
authenticated main event SHA. Manual normal dispatch also selects all deep
campaigns, with optional `native_macos=true`. Scheduled receipt authentication
retains the same source/run/attempt checks; it does not authorize new cross-run
proof reuse.
Performance and intentionally failing evidence probes are separate opt-in modes,
not full integration checkpoints. The Python wheel acceptance job runs on its
supported product platform independently of the optional native diagnostic job.
No package publication or deployment is performed by ordinary CI.

Before release, require the exact main SHA's successful full integration
`check` with complete deep campaigns and macOS from the same attempt (use normal
manual dispatch with `native_macos=true` if the push selected shallow proofs). Local tests, an
ancestor's green run, a Draft preparation, skipped checks, and performance
results are not substitutes. Configure required branch checks separately under
owner-approved repository rules; this workflow does not modify those rules.
Explicit historical artifact reuse or comparison commands retain their own
source/policy/provenance validation; they are not normal main target selection.

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

### Native holder Review installation availability

The current holder has no production issuer for the mapped Review preparation
profile. Account/current checks do not supply that funding or create a Review
installation. The holder preserves the ordered root-selection and currentness
checks, then refuses installation without opening Catalog resources. The former
unreachable installation/publication branch is not a supported alternative.

Existing restored Review cleanup and resume remain owned by their original
runtime objects. Lower-level mapped Read/FD acquisition and cleanup tests remain
component ownership evidence; they do not establish a production Review issuer.

### Original Request preparation and historical probes

Ordinary Local and HTTP execution require the installed original Request
preparation owner. Missing that owner is an invalid installation, never a
selection of raw serialization, standalone preparation or a second diagnostic
check. Independent checker/compiler APIs still accept raw inputs for their
separate purposes; a compiled value cannot substitute for an admitted Request.
The private legacy `installNodeClientEffectProgramPreparation` export and the
old `measure-local-preparation.mjs` standalone-Run probe have been retired.
Historical reports retain their original source qualification. Use the existing
`health:quick` or `health:release` collectors for current ordinary preparation
measurement; do not compare their whole-operation observations to that old
compiler/Plan probe as if the methodologies matched.
