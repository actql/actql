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

`createWorkersHost(hashSeed)` from `host.mjs` creates a Local-only runtime.
`withCapturedStrategy(setup, consume, signal)` allows scoped consumption of
verified outputs and always closes them and attempts recovery before returning.
A recovery error retains an explicit `cleanupHandle`; it is not a successful
response or permission to store handles for a later request. The generated
composition supplies implementations, not caller-provided verifier callbacks.
The test-only `conformance.mjs` prepares fixtures; product callers do not import it.

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

Local workerd tests do not establish deployed CPU/memory limits, large-input
capacity, cross-request persistence, Workers Wasm conformance or production
Cloudflare compatibility. Persistent capture and Store are separate increments.
