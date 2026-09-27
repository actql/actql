# Workers boundary verification

This directory owns a thin Workers Host and the Node-side workerd test harness,
not Core I/O or a deployed Cloudflare service. Runtime-startup tests are separate
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
