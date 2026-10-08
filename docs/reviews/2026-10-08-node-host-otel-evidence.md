# Node Host OTel acceptance evidence

## Source and completion unit

Base: `db1bcddd793ad9a1e2e1d9fe452a984dc35254ac`.
Verified implementation: `4b7cdbd83d92266afc73ff225e4d370c723cb2bc`.
Subsequent evidence-only documentation does not extend that execution claim.

This is the initial single-scope Node Host O1/O2 unit, not all-Host
observability, O3 evaluation, Cloud ingestion or empirical CBO. The optional
`@actql/otel-node` adapter exports managed metadata-only OTLP/HTTP protobuf.
Public Local and HTTPS acceptance uses actual prepare, submit, Owner execution,
Store-backed Named Result reads, approval resolution and process restart.
Fixtures supply providers and TLS/authentication; no external collector or SaaS
was used.

See the [Owner mapping and boundaries](../design/node-host-observability.md)
and [configuration and registration example](../../packages/otel-node/README.md).

## Executed acceptance

| Boundary | Executed fixture and independent assertion |
| --- | --- |
| Public Local / HTTPS | `packages/otel-node/public-host.test.mjs`: caller trace reaches final protobuf; Named Result equals two explicitly authored rows |
| Pre-Run failure | Invalid SQL returns the checker verdict; request journal has zero Runs; projection has no invented Run/Program identity |
| Waiting / restart | `packages/otel-node/recovery.test.mjs`: persisted approval wait sends zero Model calls; a new process approves and reads the expected Result with one call |
| Repeated recovery | A further process reads the same Result without another Model call; saved context becomes a link to the new trace, not a resumed lifetime span |
| Cancellation | Public Local cancellation while waiting returns the Owner-confirmed cancelled state; zero Model dispatch and no Named Result |
| Custody loss | Delete only optional observation custody after completion; another process still reads the Result with one total Model call, reports unavailable budget and does not recreate custody |
| Disclosure | Final trace/metric/log protobuf packets contain none of the sentinel supplied as query text, data value, credential or baggage; metric packets contain no Run/CID dimensions |
| Independent signals | Generic endpoint sends traces only; sampling off retains enabled metrics/logs; trace export failure does not suppress the other signals or Result |
| Overflow / disable | Queue overflow is explicitly counted without changing Result; complete disable sends nothing and creates no optional custody table |
| Resource limits | Component tests cover exact record/byte caps, bounded response, timeout through physical close, no retries, finite journal rows and corrupt context |
| Embedded guarantee | Application callback is deferred, original execution exceptions remain original, providers are not shut down, unresolved delivery retains its slot |
| Owner lifecycle | Existing strategy and request-journal regressions retain activation, cancellation, cleanup retry, independent outputs and durable request semantics |

Task durations reuse the existing driver's timing. Model entry/observation
receipts are instant facts, not a claim of measured physical Model latency.
No new terminal-state inference or authority is implemented by OTel.

## Local commands and retained receipts

At the verified implementation SHA:

- Focused Node selection: **46/46 passed**. Receipt:
  `_build/local-checks/attempts/run-7dT8wD/summary.json`;
  detailed cases: `_build/focused-evidence/focused-test-igZGGs`.
- Existing strategy and request journal: **169/169 passed** (43 and 126).
  Receipt: `_build/local-checks/attempts/run-TOBm0N/summary.json`;
  detailed cases: `_build/focused-evidence/focused-test-aNVBN2`.
- Selected declarations passed strict TypeScript compilation.
- Generated Local adapter graph passed its existing read-only freshness check.
- `git diff --check` and new commit-message lines of at most 72 characters passed.

The first receipt contains these nine real test files:

```sh
node scripts/local-checks.mjs test node --timeout-seconds 150 -- \
  packages/sdk/trace-context.test.mjs \
  adapters/host-common/observation.test.mjs \
  adapters/host-node/client-observation-journal.test.mjs \
  packages/otel-node/configuration.test.mjs \
  packages/otel-node/transport.test.mjs \
  packages/otel-node/index.test.mjs \
  packages/otel-node/public-host.test.mjs \
  packages/otel-node/recovery.test.mjs \
  adapters/host-node/embedded-local-lifecycle.test.mjs

node scripts/local-checks.mjs test node --timeout-seconds 60 -- \
  adapters/host-node/strategy.test.mjs \
  adapters/host-node/client-request-journal.test.mjs

node node_modules/typescript/bin/tsc --noEmit --strict \
  --module NodeNext --moduleResolution NodeNext --target ES2022 \
  packages/otel-node/index.d.ts packages/local-node/index.d.ts \
  packages/local-node/http-host.d.ts packages/local-node/observation.d.ts \
  packages/sdk/index.d.ts

node scripts/build-local-node-adapters.mjs --check
```

The first literal invocation also included a nonexistent
`adapters/host-common/strategy.test.mjs` path, which contributed zero tests.
Strategy coverage is attributed only to the second, correctly located selection.
An earlier unfiltered dispatch test selection exceeded its 180-second bound;
it is not a pass. A subsequent targeted 19-case diagnostic passed before the
fixed implementation SHA and is supplementary, not current-SHA acceptance.

## Runtime and distribution provenance

Tests import current source-package public exports through private package
aliases. Local adapters were assembled from this source and checked, not copied
from an older worktree. The compiled Node runtimes were built locally with the
pinned toolchain. No MoonBit source, contract or pin differs from the base; the
OTel changes are Node adapters, SDK propagation, declarations and documentation.

The retained primary compiled payloads have these SHA-256 digests:

- `packages/local-node/_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js`:
  `a68af597dda552e49774c12b42bd9aa52aebe3dde35518c4dfe8e2bbc2329a60`.
- `packages/run-host-core/dist/client_values_host_abi.js`:
  `4e4fec8f743548e498d2c228ec69dcc0ddabccbc9d564db5324c5c4f2e33c179`.

The optional adapter's exact dependency lock is committed. Runtime bundles,
private dependency aliases and raw test output remain ignored. These results
are **source-bound public acceptance**, not a pristine packed-package campaign.

## Not established by this evidence

Full integration CI, Core Wasm/Native execution, pristine external package
installation, other Hosts, multi-tenant isolation, hosted storage/search, live
disclosure reconfiguration and external Collector deployment were not run.
Application-owned provider additions and synchronous processing time remain
outside the managed payload/time guarantee.

No benchmark was executed. The existing benchmark contract informs only the
finite cold/warm proposal in the design document. Sidecar applicability is
design-only. Evaluation Evidence remains independent of OTel sampling/export;
O3 needs its own authorized capture-to-evaluator acceptance unit.
