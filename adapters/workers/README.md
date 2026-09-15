# Workers boundary verification

This directory owns the Node-side workerd test harness, not Core I/O and not a
deployed Cloudflare service. The product execution acceptance path is separate
from runtime-startup tests; passing the latter alone does not establish ActQL
Workers conformance.

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

Local workerd tests do not establish deployed CPU/memory limits, large-input
capacity, cross-request persistence, Workers Wasm conformance or production
Cloudflare compatibility. Persistent capture and Store are separate increments.
