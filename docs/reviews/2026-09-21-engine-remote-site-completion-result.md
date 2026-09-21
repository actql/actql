# Engine and Remote Site completion result

Date: 2026-09-21

Validated implementation head: `04bac78f`

This result closes the Engine milestone defined by the three acceptance
milestones below. It does not claim production deployment across an arbitrary
Internet boundary, mid-Compute crash continuation, Effect execution, or the
separate formal performance milestone.

## Milestone result

| Milestone | Result | Product evidence |
| --- | --- | --- |
| MoonBit ownership | Complete | Common progression, retry, completion, retention, reconciliation, and reclaim decisions are owned by MoonBit packages. Local, reference, DuckDB, Transfer, publication, credential, bundle, and Remote Site callers enter those owners. Handwritten environment code performs physical I/O, waits for physical completion, and reports observations; it does not own a second ActQL success or reclaim decision. |
| Node-free native product path | Complete | Native executables run Local and real DuckDB tasks, durable filesystem and SQLite Stores, complete Run-bound Named Result publication, JSON, JSONL, and CSV delivery, restart retrieval, and cleanup without spawning Node. The test harness may coordinate the process, but the product path does not delegate execution or retrieval to a Node subprocess. |
| Authenticated Remote Site | Complete | Mutual-authenticated outbound HTTPS connects separate processes. Linux network namespaces prove the direct profile and the outbound-only Store profile with separate Site roots. The path includes durable dispatch, direct and Store Transfer, publication, signed scoped credential use, bundle operations, restart reconciliation, force loss, release, and cleanup. |

## Decision ownership

The following MoonBit packages are the product authorities for this
milestone:

- `physical_strategy` and `execution_site` own common task and Site progress;
- `remote_site_protocol` owns dispatch identity, transitions, and evidence
  admission;
- `remote_transfer` owns Transfer identity, integrity bindings, and lifecycle;
- `run_publication` and `publication_payload` own publication, delivery, and
  durable payload decisions;
- `remote_bundle` owns signed bundle identity and lifecycle plans;
- `remote_credential` owns signed grant identity, scope, claim, and use
  decisions.

Environment adapters retain only responsibilities that require an actual
environment:

- HTTPS and TLS transport, bounded streaming, and physical connection state;
- filesystem creation, synchronization, locking, and deletion;
- SQLite transactions and durable compare-and-set operations;
- OpenSSL verification and native library loading;
- native DuckDB calls, cancellation delivery, and stop observation;
- secret resolution and application inside one scoped HTTP operation.

Adapter state such as an open socket, multipart upload, buffer owner, or
physical cleanup retry is expected. The adapter reports those observations to
the MoonBit owner and cannot independently declare ActQL completion, authorize
re-execution, or refund capacity.

## Native and Remote Site profile

The completed profile has these properties:

- Coordinator intent and Site physical observations remain in separate
  durable journals; no distributed transaction is assumed.
- Dispatch retransmission, state query, cancellation, and a new task attempt
  are distinct operations.
- Site generation restart fences old execution authority while preserving
  historical terminal facts for reconciliation.
- Direct Transfer streams bounded chunks between reachable Sites without a
  Coordinator bulk relay.
- The outbound-only profile blocks host-to-Site inbound traffic and
  Site-to-Site traffic, then completes through the Transfer Store.
- Transfer physical manifests bind ordered chunks, lengths, digests, row
  counts, codec, schema, view, and exact material generations. Logical Result
  identity remains a separate obligation.
- Publication bytes stream from the Site to the Store; the Coordinator handles
  control and exact binding, not bulk payload bytes.
- Signed credential grants bind the exact Site generation, runtime,
  Connector, Run, task attempt, dispatch, origin, operation, expiry, and use
  limit. Claims and revocation are durable, and the provider secret is applied
  only inside the native HTTP adapter.
- Bundle operations cover install, signature verification, activation, drain,
  rollback, restart, and reclaim. Runtime registration is bound to the exact
  verified component loaded for the Site.
- Force loss quarantines the old generation and unresolved physical
  responsibility. It is not reported as ordinary cleanup or capacity reuse.

## Acceptance environments

The native smoke profile passed on macOS arm64. It exercised the native Local,
DuckDB, Store, publication, delivery, credential, bundle, restart, and cleanup
paths.

The separated-network profile passed in a clean Linux x86_64 container. It
used two network namespaces, separate Store roots, blocked inbound traffic and
cross-Site direct traffic for the outbound-only profile, and exercised both
direct and Store routes.

The validated implementation head also passed:

- MoonBit formatting and all-target checking;
- retained-boundary tests;
- publication runtime tests;
- Remote Site runtime tests, including the idle outbound-poll race;
- native Local and real DuckDB conformance, with 362 DuckDB tests;
- signed native credential call, restart query, duplicate rejection,
  revocation, and post-revocation rejection;
- native runtime bundle lifecycle and publication Store process locking.
- MoonBit tests on JS, Wasm, and native targets: 5,157, 5,157, and 5,211 tests;
- public-interface comparison, including explicit native-only package
  classification;
- independent Connector addition on JS, Wasm, native, and Node;
- the complete DuckDB Node suite: 132 tests and the 27-case smoke matrix;
- the Workers product and conformance suite: 24 tests;
- repository-wide documentation, generation, link, and example gates.

The generated Workers bridges and conformance host are checked artifacts of
the same common MoonBit template. Their product and workerd tests confirm that
the shared control surface adds no Node runtime dependency to the Workers
profile.

## Follow-on work

The following work is intentionally outside this completed milestone:

- arbitrary Internet deployment, provider-specific Cloud rollout, and fleet
  automation;
- resumable byte offsets for an interrupted direct Transfer;
- continuation of an in-flight Compute operation after process crash;
- Effect execution;
- resident-result performance optimization and the formal performance
  acceptance suite;
- additional language families and Connectors.

Those additions must reuse the completed owners and adapter boundaries. They
must not introduce another environment-specific completion or reclaim state
machine.
