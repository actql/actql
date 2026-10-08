# Node Host OTel acceptance evidence

## Source and completion unit

Base: `db1bcddd793ad9a1e2e1d9fe452a984dc35254ac`.
Initial verified implementation: `4b7cdbd83d92266afc73ff225e4d370c723cb2bc`.
Sampling verification: `8ae7f09b21555c2bc5266d0eb6723942fb23e1ab`.
Current production implementation: `52aac792323eeab3d6cf4670e2615ab2e123fb71`.
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

At the initial verified implementation SHA:

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

## Completion audit and sampling correction

The completion audit found that the initial adapter used root ratio sampling
without preserving a parent's decision, contrary to the adopted parent-based
profile. The correction uses the pinned SDK's `ParentBasedSampler` with a
`TraceIdRatioBasedSampler` root. Its profile name is included in the optional
configuration revision. Existing custody cannot silently adopt the changed
profile; a mismatch stops additional observations rather than resetting usage.

On an isolated copy of the original adapter, the new four-case matrix failed:
root ratio 1 incorrectly exported an unsampled parent, and root ratio 0 dropped a
sampled parent. The other two cases rejected its inaccurate effective sampler
description. Original failure evidence:
`_build/focused-evidence/focused-test-yVBWey`.

At `8ae7f09b21555c2bc5266d0eb6723942fb23e1ab`, the nine-file focused command
above (without the nonexistent extra path) passed **52/52**:
`_build/local-checks/attempts/run-SOKHch/summary.json` and
`_build/focused-evidence/focused-test-LfIsaX`. Strict selected declarations
also compiled successfully. Added assertions cover:

- Both parent flags against root ratios zero and one, with logs/metrics
  independent of the trace decision.
- A real public HTTPS request from an unsampled caller still produces the
  independently expected Named Result without trace export.
- Every actual exported Gauge/Sum/Histogram data point is inspected for absence
  of Exemplar fields, not merely absence of one trace ID.
- Fixed HTTP route span names, SERVER kind, unset error status for 422 and ERROR
  status for 503.

The same fresh-process Model fixture also has a dedicated unsampled-caller
acceptance: approval wait has zero dispatches, approval stores a successful
capture with one dispatch, and subsequent process replay reads the identical
independent Result with no extra call and no trace packets. Missing optional
custody still does not prevent replay. The initial targeted diagnostic passed
one case (`_build/focused-evidence/focused-test-EQJJgg`, dirty test/documentation
tree); it is not reattributed to a clean SHA. This case is part of the ordinary
OTel selection. The final clean-source receipt and submitted SHA are recorded
in PR #971 rather than guessed in this document.

## Common projection, physical measurement and final scoped verification

The implementation at `52aac792323eeab3d6cf4670e2615ab2e123fb71`
move Run observation equivalence into `run_publication.run_observation_key`.
The optional SQLite custody stores its bounded key with cumulative count/bytes;
unchanged polling is suppressed without resetting consumption on restart.
Independent revision, cleanup and physical-stop facts remain distinct.

The same change adds a metadata-only physical observer to the existing
MoonBit Model execution. It surrounds both provider invoke and the selected
preflight invoke, after actual durable entry and cancellation checks. Node
measures elapsed time and matches the Owner-issued attempt to its existing
journal receipt. Approval waits, response saving and replay are not physical
invocation durations. Source measurements cover the selected adapter's entire
acquisition `open`, not an unobserved individual transport request.

Regressions were added for saved duplicate suppression, exact exhausted
allowance, foreign/damaged custody, public repeated Local/HTTPS status, actual
Model CLIENT spans and absence of another interval during fresh-process replay.
The scoped verification completed as follows. Pre-commit results are attributed
to the tested source subsequently committed unchanged in the implementation
SHA, not to older passing receipts. A later test-only addition uses public SQL
checking with an invalid number parameter and creates no Run; its two Local/
HTTPS cases passed separately. Evidence and that fixture addition do not change
the production implementation or compiled runtime inputs.

| Check | Result | Retained receipt |
| --- | --- | --- |
| Canonical interfaces for four changed packages | Passed | `run-xEKssK` |
| New common Run key / physical metadata tests, JS | 2/2 and 1/1 | `run-wyzL8w`, `focused-test-5ZydYl`, `focused-test-BWQIZc` |
| Projection, journal, configuration, SDK and bounded transport | 49/49 | `run-uAvplC`, `focused-test-a0GiGI` |
| Public Local/HTTPS, Model approval/restart/replay and waiting cancellation | 11/11 | `run-lWvxck`, `focused-test-0HHhSW` |
| Existing common preflight / replay callers, JS, at the implementation SHA | 5/5 and 4/4 | `run-C5oM5Q`, `focused-test-ObyGYY`, `focused-test-hMjp95` |
| Public pre-Run type failure, Local/HTTPS | 2/2 | `run-CCl8Su`, `focused-test-eaVPuq` |
| Public HTTPS Effect approval/restart/lost reply | 1/1 | `run-CCl8Su`, `focused-test-4ry93t` |
| Selected public TypeScript declarations / generated adapter freshness | Passed | `run-CCl8Su` |
| Preserved original timeout Run: same identity, expected Result, one total call | 1/1 | `run-c3eu4s`, `focused-test-vPkNZI` |

Receipts named `run-*` are under `_build/local-checks/attempts`; detailed
`focused-test-*` receipts are under `_build/focused-evidence`. The original-Run
diagnostic is retained as `_build/resume-original-otel-run.test.mjs`. It uses the
ordinary public fixture and preserves the original timeout report byte-for-byte.
An earlier intermediate report with zero calls is not proof of no send: the
saved provider wire has one call and the replay reads its successful Result.

The successful commands use `scripts/local-checks.mjs test node` with the six
component files, the two public Host/recovery files, and the representative
Effect file. JS MoonBit selections are the two new files plus
`src/client_infer_host/physical_preflight_wbtest.mbt` and
`src/client_infer_host/replay_wbtest.mbt`. The existing bounded guard also
recorded canonical `moon info`, selected declarations and adapter freshness.
No full Core, all-target, packed or performance campaign was run.

The first component run used stale assembled adapters: 48/49 passed. Normal
runtime/adapter preparation (`run-CfLiIq`) corrected the copied source, not the
expectation; the unchanged case then passed. An aggregate caller/public run
exceeded 180 seconds (`run-C5oM5Q`); its two completed MoonBit selections remain
valid individually, but the aggregate is not a pass. Public cases were then
selected without compilation overhead. An initial type fixture used the
unsupported JSON check format (`run-Ri3paC`); it was corrected to the existing
public SQL parameter API, not a new Host interface. These failures remain intact.

The original timeout receipt `run-WhcMPS` is also unchanged. User-authorized
inspection found its wrapper, children, process group and worktree test
processes stopped. Recovery rechecked the exact owner/token and file identity
immediately before removing only that lock. Separate receipt:
`_build/local-checks/recovery-emjKkc/receipt.json`. No other lock or process was
removed. All subsequent completed guards released their own locks normally.

The current source-bound public runtime payload digests are:

- Local builtin Node runtime:
  `c12075f9a2ebfcbe69d25ba2b3829a6150ac6947d43d8f08799969e277e74d1a`.
- Run Host ABI runtime:
  `40c65dba00a9161dc151f0f09806fa2e12c570a537dea7bd6e282e69455f87d6`.

Unlike the initial historical unit above, this follow-up changes common
MoonBit and generated public interfaces. There is no new semantic contract,
pin, authority, replay decision or accounting rule. Source acquisition clock
hooks are compiled, but this selection does not claim a dedicated real-Source
latency acceptance or a pristine packed package campaign. Final submitted SHA
and exact CI status belong in the PR; local success is not CI success.

The existing 169-case Owner evidence is reused, not reattributed to a new run:
`git diff 4b7cdbd83d92266afc73ff225e4d370c723cb2bc..8ae7f09b21555c2bc5266d0eb6723942fb23e1ab`
has no changes in adapters, SDK, Local declarations, process fixtures, MoonBit
sources or contracts. Only the optional adapter and its sampling acceptance
changed. No runtime rebuild or performance measurement was needed.

| Required boundary | Completion evidence |
| --- | --- |
| Owner facts, distinct outcomes | Owner mapping, bounded projection, task hooks, actual approval/cancellation/recovery/publication/cleanup assertions; no new execution state machine |
| Caller linkage and finite restart segments | Local/HTTPS trace bytes, saved context links, current Run ref across fresh processes |
| Pre-Run check failure | Actual checker failure with zero journal Runs and no invented identity field |
| Pinned standard conventions | Exact SDK lock, parent-based matrix, independent HTTP protobuf assertions |
| Metadata-only disclosure | No content getter reads, fixed names/bodies/Resource, final sentinel checks, explicit no-Exemplar data-point checks and no dynamic metric IDs |
| Independent signals and disable | Configuration matrix, no implicit destination, sampling/export failure independence, no custody on disable |
| Managed resource isolation | Finite record/queue/Run/segment/transport limits, physical-close sender accounting, deadline/loss tests, real journal capacity and reopen tests |
| Optional journal failure | Original request/Run/scope/revision binding; failed/missing/corrupt custody never resets consumption or prevents Result retrieval |
| Application provider ownership | Deferred callback, no global replacement or application shutdown; downstream additions/time explicitly excluded |
| Semantic-boundary isolation | Queue-only internal hooks; delivery after a later event-loop turn; existing activation/completion/cleanup Owner evidence |
| Evidence independence | Capture/replay dispatch counts remain one across restart with telemetry present or missing; no sampler condition in capture authority |
| Measurement/sidecar limits | Existing benchmark contract, finite cold/warm proposal and design-only sidecar applicability; no measured-performance claim |
| Delivery | Dedicated branch, conventional commits, fixed-SHA evidence, public Draft PR and repository-accessible usage/mapping documents |

Integration is separate from this implementation handoff. PR #971 targets
`main`. A read-only merge simulation against
`9ac1f5520135f640794dc76d0ed05bb6d56486a4` found one conflict in
`packages/local-node/package.json`: preserve both the new
`connector-installation` exports/files from main and `observation` exports/files
from this branch. Integration-owner conflict resolution, final Ready coverage
and user merge remain outside this handoff. No CI success is claimed.

## Public wire acceptance follow-up

The public Local/HTTPS fixtures now decode actual OTLP log records independently
of the product serializer. They assert that pre-Run checker records have no Run
or Program identity, that successful Owner observations carry the admitted Run
identity, and that actual metric data points contain no Exemplars. The same
decoder serves the adapter-level assertions rather than a second expectation
implementation. HTTPS waiting cancellation also uses the existing public Model
process fixture: zero dispatch, Owner-confirmed cancellation and no Result.

The combined three-file diagnostic reached its 120-second bound and is not a
pass (`run-OJdWoy`). Narrowed selections passed: adapter/public Host 17/17
(`run-JxqXAU`, `focused-test-KtUX6U`) and HTTPS cancellation 1/1
(`run-bKk2xJ`, `focused-test-KKOkDQ`). These are dirty-source diagnostics;
fixed-source verification is recorded separately in PR #971.

## Adopted Node configuration follow-up

An additional design comparison found that the initial explicit-only options
did not expose the adopted measurement, attribute and correlation selectors or
the standalone standard environment mechanism. These are connected without
adding an execution Owner or changing semantic contracts. Only duration is
available from the current hooks; selecting other registered groups does not
fabricate usage. Intrinsic span intervals remain unchanged when optional
duration metrics are disabled. Explicit Resource/authentication configuration
is bounded, filtered and omitted from inspection values.

The affected five-file diagnostic passed 38/38 (`run-zqLu7m`,
`focused-test-U9aqeq`), covering selector validation and actual exported wire,
environment precedence, disable, missing destinations, credentials and bounded
standard-setting diagnostics. This was a dirty-source diagnostic, not a claim
against a submitted clean SHA. The environment fixture is included in the
ordinary OTel CI selection; final verification is recorded in PR #971.

## Effect receipt and delivery follow-up

The existing HTTPS Effect fixture now has a narrow observability selection:
one successful independently approved Set, waiting cancellation without send,
and an applied request whose reply is lost. The original full inventory
selection is unchanged. Both completed and unknown recovery retain original
Run references, exact independent rows/transcripts, and no additional sends.
The expected physical sends are one to each installed provider.

An initial 90-second inventory diagnostic timed out (`run-1iXxLX`); it does not
establish a product failure or a pass. The narrowed diagnostic completed with
15 projection cases passing and its public Effect case failing on missing
`application_observed` records (`run-dsLGD8`, `focused-test-jjjXYI`). Execution,
approval, independent Results and unknown non-resend had passed before that
assertion. This caught a projection defect: recovered background dispatch is
not guaranteed to inherit an ingress AsyncLocalStorage context.

The first explicit-ref correction was insufficient (`run-e9u1Dw`,
`focused-test-gFYJUn`: 40 passed, 2 failed). The wire-kind assertion also
compared a protobuf integer decoded as BigInt with Number; it now uses `3n`.
A later diagnostic (`run-tSev6n`, `focused-test-N6BTXG`: 29 passed, 2 failed)
confirmed waiting/unknown facts on the explicit Owner hook but showed the
log export window exhausted by polling interval records before publication.
It also exposed a managed export deadline under concurrently running public
and unit fixtures. Neither run is a successful acceptance claim.

The correction projects the common receipt/publication Owner result through
the installed Host's explicit original Run reference. It adds no outcome
inference, replay authority or execution state machine. Rejected adapters do
not invent a semantic Effect outcome. Source/Model attempt receipt facts use
CLIENT span kind; Effect disposition remains an INTERNAL fact without an
invented transport interval. Logs replace duplicate span events when enabled.
Managed close aborts in-flight delivery and suppresses remaining signals and
queued records; external data already sent cannot be recalled.
Interval boundaries now use spans only, leaving discrete lifecycle logs for
Owner facts without increasing the finite export caps. The OTel selection runs
test files sequentially, including public fixtures, under a finite total budget.

Selected public declarations passed strict TypeScript checking, and Node
adapter assembly/freshness and whitespace checks passed after the correction.
These diagnostics are not final clean-SHA acceptance. The final command,
counts, receipt directories and SHA are recorded in PR #971. No additional
full Core, packed, Native or performance campaign was run for this follow-up.
