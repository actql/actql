# Engine Remote Site baseline

Date: 2026-09-19. Baseline: `0cf74029634485f017a21df0d7bc32ae55802451`.

This report fixes the starting evidence and migration inventory for the Engine
Remote Site milestone. It is not a completion report. Local Compute work that
is not integrated into the baseline is outside this branch.

## R0 through R6 status

| Area | Baseline evidence | Remaining work in this milestone |
| --- | --- | --- |
| R0: gates and reproducibility | The pinned MoonBit toolchain, generated bridge checks, public API check, retained-boundary suite, Node dependency-isolation suite, and existing Connector-addition gates are present. | Add Remote Site, native-runtime, separated-network, crash, credential, bundle, and full failure-matrix gates. Verify the final commit on Linux x86_64 and macOS arm64. |
| R1: dependency boundaries | Common MoonBit packages do not depend on concrete Connector adapters. Built-in Node composition is generated. | Make MoonBit the sole owner of common progression and list every remaining environment-specific adapter reason. Remove superseded product decisions from JavaScript. |
| R2: in-process Site Agent | Execution Site generation, admission, byte ceilings, operation and holding lifetimes, teardown, and revocation are implemented. | Preserve this authority across native and remote adapters. Add durable Agent identity, restart generation, and reconciliation. |
| R3: Site binding and dispatch | Standard Host placement compares registered Sites and rechecks exact generation, task, attempt, input authority, and capacity. | Persist Coordinator and Site dispatch facts, authenticate the exact remote binding, separate query/retransmit/reexecution, and handle split-journal crashes. |
| R4: managed completion | Local, reference, and DuckDB use common task completion and retained-output boundaries. | Accept only scoped Remote Site evidence and bind it to common completion without receiving or revalidating every row at the Coordinator. |
| R5: identity obligations | Managed obligations and formal Named Result publication are connected to checked Result occurrences. | Carry exact obligations and deadlines through remote admission and registered issuers. Keep historical evidence separate from current material authority. |
| R6: explicit Transfer | In-process memory Transfer has independent attempts, destination generations, Site accounting, cancellation, and cleanup. | Add bounded direct and Store-mediated remote routes, ordered physical manifests, credentials, restart reconciliation, and Site-to-publication streaming. |

## Baseline verification

The base branch already records the E0 through E3 local verification in
`2026-09-18-engine-site-implementation-result.md` and the Named Result
publication verification in `2026-09-19-named-result-publication-result.md`.
This branch additionally verified the dependency-free Node standard path and
the existing retained boundary before adding the first remote integration
slice.

The first slice introduces a portable canonical dispatch request and
independent execution, evidence, and cleanup states in MoonBit. It uses the
existing Execution Site authority rather than creating a second Site model. A
Node SQLite adapter demonstrates the required ordering:

```text
MoonBit prepares exact admission
  -> SQLite transaction persists or reconciles the request
  -> MoonBit commits admission
  -> physical provisioning and execution may begin
```

The slice is deliberately smaller than the milestone. It does not yet prove a
remote transport, native Host, durable transition recovery, direct or Store
Transfer, scoped credentials, bundle operation, or network separation.

## Non-MoonBit responsibility inventory

The following product areas contain environment code at the baseline. Entries
marked `migrate` still make application progression or lifecycle decisions.
Entries marked `adapter` may remain only for their physical operation and
observation responsibilities.

| Area | Current implementation | Classification | Required result |
| --- | --- | --- | --- |
| Standard Host loop | `adapters/host-common/strategy.mjs` | migrate | Move progression, retry, completion eligibility, and release decisions to MoonBit; retain only asynchronous environment calls and projections. |
| Managed Transfer orchestration | `adapters/host-common/managed-site-transfer.mjs` | migrate | Move admission, state transitions, accounting release, and retry eligibility to MoonBit; adapters retain streaming and resource-stop observation. |
| Local managed execution | `adapters/local-node/strategy-bundle.mjs` | migrate and adapter | Move common task progression and cleanup decisions; retain input/output bridging required by the environment. |
| DuckDB managed execution | `adapters/duckdb-node/managed-strategy-compute.mjs` | migrate and adapter | Move common progression and accounting decisions; retain native DuckDB session, file, and stream operations. |
| Publication coordination | `adapters/host-common/run-publication.mjs` and related modules | migrate and adapter | Keep contract and transition authority in MoonBit; retain bounded stream and Store calls. |
| Filesystem Stores | `adapters/store-local/*.mjs` | adapter | Keep filesystem, synchronization, conditional commit, descriptors, and physical cleanup. Consume MoonBit decisions rather than defining common success. |
| Native database session | `adapters/duckdb-node/session.mjs` | adapter | Retain native library calls, cancellation delivery, and stop observation. |
| Process and network channels | `adapters/host-node/*.mjs` | adapter | Retain process, stream, and transport state. Do not infer common execution success or cleanup from transport completion. |
| SQLite dispatch journal | `adapters/site-node/sqlite-dispatch-journal.mjs` | integration adapter | Persist exact transitions transactionally. MoonBit remains the application-state authority. Replace or supplement it for the Node-free native profile. |

Migration is not measured by lines of MoonBit or JavaScript. It is complete
when each common decision has one product owner, current product callers use
that owner, and environment adapters are limited to physical operation and
observation.

## Technology selection checkpoint

The first candidates are outbound HTTPS for control, SQLite for local durable
journals, existing object storage for staged Transfer, and OCI plus established
signing tools for bundles. These choices remain candidates until an integration
slice demonstrates their required semantics and target availability.

The selection evaluates dependency maintenance, license, native and Wasm
targets, distribution size, crash behavior, concurrency, cancellation, bounded
streaming, idle and dispatch latency, and security update practice. Alternative
implementations are compared only when the first candidate cannot meet a
requirement or creates a material distribution tradeoff.

The final profiles require:

- Linux x86_64 separated-network execution with inbound Site and direct
  Site-to-Site connectivity actually blocked for the outbound-only case;
- macOS arm64 native smoke coverage;
- distinct Site Store roots with no shared-memory or shared-path data channel;
- a Node-free standard Host path using Local, native DuckDB, a durable Store,
  Named Result publication, JSON, JSONL, and CSV delivery, restart retrieval,
  and cleanup; and
- authenticated loopback and separated-network Remote Site paths using direct
  and Store-mediated Transfer.

No existing test in this report is evidence that those final profiles are
already complete.
