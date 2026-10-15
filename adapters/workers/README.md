# Workers boundary verification

This directory owns a thin generated-profile connection and the Node-side
workerd test harness, not Core I/O or a deployed Cloudflare service. The product
connection uses generic JS, not Cloudflare APIs. Runtime-startup tests are separate
from the public-checker/Local-DAG execution tests; passing startup alone does not
establish ActQL Workers conformance.

Install the pinned tools with `npm ci --prefix adapters/workers`. Run the runtime
checks with `node --test adapters/workers/runtime.test.mjs` from the repository
root. Missing tools or failed runtime startup fail the checks; neither is a skip.

The lockfile pins Miniflare `5.20260911.1-alpha`, workerd `1.20260911.1` and
esbuild `0.28.2`. Miniflare is test tooling only. The selected release includes
the dependency security fixes missing from the last published 4.x release;
the harness uses its official `convertV4MiniflareOptions` API. This selection
does not fix a future production Host's deployment tooling.

Compatibility date `2026-09-11` explicitly disables both `nodejs_compat` and
`nodejs_compat_v2`. The runtime tests also reject a `node:fs` import and confirm
the absence of Node globals. See the [Cloudflare compatibility flag rules](https://developers.cloudflare.com/workers/configuration/compatibility-flags/#nodejs-compatibility-flag).
An outbound service denies every external request, including unknown URLs;
the host process does not forward failed requests to the real network.
The Host harness explicitly sets Miniflare `cf: false`, disabling its optional
external Request.cf metadata fetch before startup. These local tests use the
built-in placeholder and do not establish production Request.cf behavior.
Every runtime records outbound attempts and its common `dispose()` finalizer
requires zero by default. Worker-side error handling cannot suppress this audit.
Intentional network probes declare an exact `expectedOutbound` count; an observer
callback alone does not exempt a test. The real-fetch injection tests deliberately
bypass the phase spies and require finalization to reject the attempt.

Local Compute composition is generated separately with the pinned MoonBit:

```sh
node scripts/workers-composition.mjs --write
node scripts/workers-composition.mjs
node --test scripts/portable-core.test.mjs
node scripts/check-core-without-connectors.mjs
```

The explicit manifest subset excludes unselected connectors before reading
their declarations or resolving dependencies. It does not depend on tree shaking
or on merely declining to call a statically imported provider's factory.

With the pinned MoonBit on `PATH` and `MOON_HOME` set, run the complete current
Workers verification command from the repository root:

```sh
npm ci --prefix adapters/workers --ignore-scripts
npm test --prefix adapters/workers
```

It checks generated composition and fixture freshness, builds the product bridge
and conformance entry, adapts the pinned physical hash seed, inspects the resolved
bundle graph, and executes the runtime and conformance tests. Fixture helpers are
projected from existing integration builders; expected result CIDs are computed
independently from literal expected rows, never from product results.

### Product Host and initialization

Generic JS composition lives in `adapters/host-common/local-js-host.mjs`;
invocation-scoped consumption, cancellation and cleanup ownership live in
`adapters/host-common/scoped-strategy.mjs`. Both reuse the existing common
runtime/strategy owner. `host.mjs` supplies the generated runtime and selected
contributions. Product and conformance callers import the scoped helper directly
from the common module; the Workers-specific `invocation.mjs` forwarding entry
has been removed. Old imports fail rather than selecting another lifecycle.

The public Workers Host entry names and historical diagnostic messages are preserved.
Workerd compatibility flags, Miniflare, transport/audit fixtures and environment
verification remain here. This extraction does not establish support for any
additional environment: Node/workerd evidence below is limited to the tested
profiles, not a claim of a deployed Cloudflare service or another runtime.

`bindWorkersHost(runtime)` from `host.mjs` binds the generated Local-only Host
operations to a trusted, invocation-created MoonBit runtime. Application
preparation and Host operations must be linked into that **same** runtime:
MoonBit's generated exception tags are link-unit-local. Do not pass handles or
errors between separately linked instances. The fixture generator projects the
ordinary generated Host operations into its application link unit for this
reason; it does not supply a replacement planner or evaluator.

`createWorkersHost(hashSeed)` instantiates the standalone dispatch-only bridge.
It is a composition primitive, not an API for importing setup handles from
another runtime. Applications that also prepare checked requests use
`bindWorkersHost` with their combined application/Host build. This trusted
assembly is not supplied by Program JSON or by an HTTP request.

`withCapturedStrategy(setup, consume, signal)` allows scoped consumption of
verified outputs and always closes them and attempts recovery before returning.
A recovery error retains an explicit `cleanupHandle`; it is not a successful
response or permission to store handles for a later request. The generated
composition supplies implementations, not caller-provided verifier callbacks.
The test-only `conformance.mjs` prepares fixtures; product callers do not import it.

### Finite source-free entry

The production npm subpath `@actql/run-host-core/workers-finite` exposes
`createWorkersFiniteRuntime(hashSeed, configuration)`. It links the finite
preparation/material owner, common Host controls and Account gate into one
runtime and returns `{host, core, createAuthorizationGate}`. `core` is the exact
control object used by `host`; copying the runtime into another control facade
would split wrapper custody. The physical hash seed is explicit and confers no
identity or authority. The production payload excludes conformance fixtures.

Create this assembly within the invocation driving one original Run. Do not
cache the returned Host/runtime in module globals or a long-lived Durable Object
instance for later requests. This follows the existing invocation-created linked
runtime contract; importing the factory itself does not create a Host. Preserve
the exact assembly, original Ledger and pending cleanup handle within that
invocation until cleanup is confirmed. An unresolved cleanup handle is retained
responsibility, not permission to return success or replay the Run elsewhere.

`workersFiniteArtifact.componentCid` and `componentBytes` identify the audited
production payload module bytes in the same package. The generated entry wrapper
is separate from the payload so its SHA-256 has no self-reference. These fields
can be compared with the existing RuntimeBundle `runtime_executable` component;
they are content metadata, not a new bundle format, issuer capability or proof
of physical retention. The package cohort/provenance and the Bundle owner still
establish which bytes were installed and retained.

`bindWorkersFiniteHost(runtime, configuration)` is an explicit trusted assembly
for one effect-free, source-free task and one Named Result. The installation
supplies its checked environment, registry/manifests, capacity, execution/search
bounds and a known finite duration estimate. Unknown or incompatible inputs
refuse through the existing owners. These are installation limits, not language
restrictions or a new placement policy.

`prepare(document)` uses the common JSON Program checker/lowerer and returns its
original compilation, template and Plan. The accepting request Owner supplies
its original nominal `admission`, `definition` and `ledger` to `open`. They must
belong to this same runtime/link unit. For original serialized materials,
`admitMaterials(body, expectedRunDefinitionCid)` delegates to the existing
`admit_client_values_run_materials` owner and returns `{preparation, admission,
definition}` in this link unit. It checks the expected original Run identity and
reuses received authorization evidence without issuing authority or extending
its lifetime. It does not accept handles copied from another runtime.

The installation supplies the exact physical `ledger` bounds (`planning_work`,
`attempts`, `holdings`, `transfer_bytes`, `retained_bytes`, `execution_bytes`).
`createLedger()` creates that original owner without per-request capacity
arguments. The caller owns the durable association between its accepted request
and Ledger and retains that custody. Re-admitting the same material cannot open
the same Run twice within one binding; the durable accepting owner enforces the
same no-reexecution rule across bindings and restarts.

The binding keeps only its first original Run Definition CID, including after
an unsuccessful open. Reopening that Run refuses with
`WorkersFiniteRunAlreadyOpened`; opening a different original Run in this same
invocation binding refuses with `InvalidWorkersFiniteInstallation`. Preparation
metadata alone does not select the Run. This one-shot invocation latch is neither
a durable claim nor a process-wide deduplication service. The accepting durable
request Owner must decide replay, restoration and retirement across invocations;
creating a fresh runtime does not prove that a Run was never executed.

`withExecution(setup, authorization, consume, signal)` requires the same protected
Account gate as `open`, checks current activation through the common strategy,
and uses its existing completion and scoped cleanup protocol. The gate must
protect `in-process-default`. A definition can be opened once per binding and a
setup executed once; a refusal never causes fallback, a new Run or a retry.
The accepting Owner must enforce the same invariant across bindings and requests.
Outputs remain borrowed only during `consume`. The caller remains responsible
for the existing Named Result publication/Store protocol before releasing them;
physical task completion alone is not durable publication or Cloud Run completion.

The invocation lifetime fixes where this adapter retains its original CID latch,
prepared metadata, setup/gate associations and cleanup closure. Their physical
representation and overlap still belong in the existing installation resource
inventory. This entry does not establish a complete normal numeric resource
profile or a deployed CPU/memory limit; finite per-Run Ledger limits do not prove
capacity for an arbitrary number of long-lived Host instances.

`core.outputExportControl.measurement(exported)` projects the exact column
measurements established by the live canonical Result export. The same export's
identity supplies ordered rows, logical Relation, schema and codec CIDs. These
measurements establish no physical custody or evidence-issuer authority.
`core.remoteSiteControl` exposes the existing durable admission, transition and
record JSON owners for asynchronous storage adapters. Persist the original JSON
and expected revision before committing a transition with durable confirmation;
restoration never authorizes physical replay. The common runtime success actions
and custody tokens remain responsible for progression.

This entry adds no Set candidate list, Worker/Native ranking, retained-input
conversion, cross-request recovery or deployed Worker route. Connecting it to
ordinary Cloud public Client placement remains a separate integration step.

The reference-only asynchronous test profile is separate from the Local product
profile. Its Connector waits at reservation and computation boundaries, then
reports stop confirmation before common completion. Cancellation and failed
cleanup retain the common reservation until a later cleanup confirmation within
the same invocation. Tests cover cancellation before and after computation,
cleanup failure and recovery, and interleaved independent Runs. Phase spies
reject acquire/store/transfer/provision/execute calls during checking, lowering,
and pure comparison; they observe rather than replace Core admission.
Unimplemented acquisition/store ports are spy-unit-test coverage, not evidence
of real Store conformance. Core code bypassing these spies is checked separately
by the runtime-wide outbound audit. Node comparisons use the same seed-adapted
runtime as workerd, not an unmodified Node compilation.

The common coordinator checks cancellation before and after each preparation
callback and immediately before dispatch. Cancellation stops remaining normal
preparation and fresh attempts; stop/finalization and recovery still run. This
does not preempt an already-running synchronous Local computation.

The command also checks `scripts/fixtures/portable-stdlib.json`, an explicit
inventory of the pinned standard-library production closure, including implicit
prelude and builtin dependencies. Package names, source digests, toolchain pins
and reasons are reviewed individually. This is not a blanket claim that every
standard-library API is pure: Core printing is prohibited, and reachable
generated code must independently pass the artifact and runtime gates.

Build reports separate `host` (dispatch-only composition) and `conformance`
(checker, preparation, execution and test probes) sizes, both raw and gzip.
Neither measurement is a deployment capacity guarantee. The execution fixtures
use a three-row relation and verify exact failure row, slot and expression span,
not just matching success values.

Pinned MoonBit's implicit builtin otherwise initializes its physical hash table
seed through ambient entropy during module loading. `moon-runtime.mjs` accepts
only the exact audited generated declaration (SHA-256 pinned in that script),
replaces that one source of entropy with the explicit signed-32-bit Host input,
and exposes an invocation-created module instance. It does not patch global
`crypto`, `Math.random`, the installed standard library, or canonical hashing.
Changed generated builtin code fails closed and requires a new audit. An AST
inspection rejects additional runtime imports and ambient I/O paths.

The seed controls physical hash layout, not identity, authorization, or canonical
SHA-256. A Host may obtain it through its own allowed entropy port. It must not
claim that a public fixed seed provides hash-flood protection. Tests vary seeds
and compare logical order, result CIDs and ledger accounting. This explicit
generated-runtime adaptation is a narrow toolchain-specific portability rule,
not permission for arbitrary Core FFI.

The `workers` CI job records the revision and pinned tools and runs this command
on Linux without credentials or deployment. A workflow definition is not evidence
of a successful GitHub Actions run.
The separate `connector-addition` CI job runs the committed-source, isolated
addition proof with pinned MoonBit and DuckDB dependencies. It retains common-file
digests and phase logs as artifacts, including available failure logs. This
expensive integration check is deliberately not part of `check:spec`.

Local workerd tests do not establish deployed CPU/memory limits, large-input
capacity, cross-request persistence, Workers Wasm conformance or production
Cloudflare compatibility. Persistent capture and Store are separate increments.
