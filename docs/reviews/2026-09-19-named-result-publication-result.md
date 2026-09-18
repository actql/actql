# Run-Bound Named Result Publication Result

Date: 2026-09-19

Owner: common execution engine

Verified implementation SHA: `4a0dc78ae40a7a5bd197dcd166941b2074918c20`

Plan: [Run-Bound Named Result Publication Implementation][plan]

## 1. Result

The ordinary Effect-free Program path now executes a checked Program through
the standard Host, publishes every declared Named Result as one durable
Run-bound chain, and delivers authorized Results as bounded JSON, JSONL, or
CSV. The same publication layer is exercised by real Local and DuckDB
realizations. It has no operation-specific publication branch.

The completed path includes:

- publication capability and capacity preflight before Compute;
- exact checked Result occurrence and view binding;
- ordered LogicalRelation identity and Result evidence issuance;
- bounded durable payload creation;
- admitted Result Artifacts, Manifest, final Effect-free Run Receipt, and
  Captured Run;
- one conflict-excluded durable public-index commit per Run Definition;
- same-Run late publication from retained exact Results without recompute;
- authorized Manifest, Run-state, and individual-Result access;
- bounded JSON, JSONL, and CSV delivery with durable attempt records;
- retention extension, expiry, deletion, and metadata deletion;
- restart lookup and delivery with fresh authorization; and
- retryable cleanup for prepared, losing, expired, and deleted material.

Publication success, delivery success, current availability, and physical
cleanup remain separate facts. A publication failure never rewrites an
already valid internal completion. A delivery failure never revokes a durable
publication.

## 2. Contract versions and semantic ownership

The portable `run_publication` MoonBit package is the only product owner for
publication contract admission, canonical preimages, logical identities,
reference checks, Result inventory, state transitions, delivery
serialization, and commit eligibility. JavaScript adapters sequence effects
and report typed observations; they do not admit caller-supplied CIDs or
reimplement canonical publication meaning.

The completed path admits these corrected or new 0.1 contracts:

- `actql-compiled-plan/0.1`
- `actql-run-definition/0.1`
- `actql-run-invocation/0.1`
- `actql-result-definition/0.1`
- `actql-result-retention-policy/0.1`
- `actql-durable-result-binding/0.1`
- the corrected 12-field `actql-result-artifact/0.1`
- `actql-result-manifest/0.1`
- the corrected `actql-run-receipt/0.1`
- `actql-captured-run/0.1`
- `actql-publication-request/0.1`
- `actql-publication-attempt/0.1`
- `actql-publication-record/0.1`
- `actql-public-index-entry/0.1`
- `actql-manifest-read-grant/0.1`
- `actql-result-read-grant/0.1`
- `actql-delivery-attempt/0.1`
- `actql-delivery-record/0.1`
- `actql-result-delivery-receipt/0.1`
- the corrected `actql-run-state/0.1`

The normative schemas, embedded schemas, protocol registry, reference roles,
pins, and independent vectors are checked together by `check:contracts` and
the full documentation gate. Nine-field Result Artifacts are rejected; no
defaulting or silent CID reuse is performed.

## 3. Supported Program and representation matrix

| Dimension | Completed support |
| --- | --- |
| Program | Checked, finite, Effect-free Programs accepted by the standard Host |
| Compute | Local and DuckDB standard realizations |
| Results | Every declared Named Result, including multiple producers and shared content |
| Result view | Exact checked projection, field order, row order, duplicates, and NULLs |
| Publication timing | Before Compute and same-Run late publication from retained exact Results |
| Durable payload | Framed canonical typed rows through a bounded batch or stream provider |
| Delivery | Canonical JSON, JSONL, and CSV |
| Store | Node local-filesystem durable publication Store |
| Restart | Committed publication lookup and delivery with fresh authorization |

The durable representation API accepts a verified logical view and an opaque
provider. It is not a permanent JavaScript row-object ABI. Existing conforming
durable material can be adopted, while batch and column providers can feed the
bounded writer without constructing a whole-Result array.

Late publication accepts only the original checked Result occurrence from the
same Run while its immutable generation, evidence, authority, retention, and
capacity remain admissible. It cannot introduce a new name or view, reacquire
inputs, or rerun Compute.

## 4. Field origins and reference graph

The exact closed fields live in the pinned schemas. This table records the
origin and admitting authority for every field group; self-identity fields are
always produced by the MoonBit canonical encoder after all non-self fields are
admitted.

| Object and fields | Source | Admission and persistence |
| --- | --- | --- |
| Compiled Plan: compiler and AoA IR versions, executable Plan, Program semantics, AoA contracts | Checked compilation provenance | MoonBit Run admission; durable contract object |
| Run Definition: scope, Run identifier, admitted Program, input Artifact set, creation and validity bounds | Checked Run admission and Host clock | MoonBit issuance; durable contract object |
| Bound Invocation Template and ObservationSet | Admitted invocation template and exact completed observations | MoonBit evidence admission; durable contract objects |
| Run Invocation: template and ObservationSet references | The two admitted values above | MoonBit issuance; durable contract object |
| Result Definition: Program Definition and exact Result name | Checked Program Result occurrence and port | MoonBit inventory projection; durable contract object |
| Retention policy: data policy, availability, deletion, extension ceiling, metadata policy, and clock | Host policy and publication request admission | MoonBit admission; durable contract object |
| Ordering and derivation evidence | Checked Result view, exact execution occurrence, and admitted dependencies | Registered MoonBit issuer; durable evidence objects |
| Durable binding: Run, Result, Invocation, logical CID, schema, ordering, codec, fields, material generation, Store authority, retention, counts, and physical digest | Verified Result view plus Store-sealed generation | MoonBit issuance after typed Store facts; durable contract object |
| Result Artifact: Run, Result, Invocation, logical CID, schema, ordering, retention, provenance, and durable binding | Admitted Result evidence and binding | MoonBit issuance; durable contract object |
| Manifest: Run, Invocation, complete Result Definition and Artifact inventory | Every declared checked Result exactly once | MoonBit issuance; durable contract object |
| Run Receipt: Manifest, Artifacts, admitted plan provenance, compiler and AoA IR versions, normalization and source evidence | Final Effect-free execution evidence | MoonBit issuance; durable contract object |
| Captured Run: Run, Invocation, Manifest, Receipt, snapshots, authoring, model, and source-state evidence | Final admitted Run evidence | MoonBit issuance; durable contract object |
| Publication Request: tenant, authority, Run, complete inventory, policy, target, and request time | Host publication admission | MoonBit issuance before attempt; durable contract object |
| Publication Attempt: request, Run, attempt identifier, fence, optional external key, and start time | Host attempt admission | MoonBit issuance; append-only Store owner |
| Publication Record: attempt, prior record, sequence, state, time, index or failure, and cleanup owners | MoonBit transition from the prior admitted record | Store CAS append |
| Public index: tenant, authority, Run, Invocation, Manifest, Receipt, Captured Run, bindings, request, and winning attempt | Complete admitted chain | MoonBit commit verdict followed by exclusive durable Store install |
| Read grants: principal, exact committed target, Result set, format, purpose, ceilings, uses, and expiry | Current authorization and egress admission | MoonBit issuance; durable Store use counter |
| Delivery Attempt: exact grant, Result, format, target, request, and unique attempt | Fresh delivery admission | MoonBit issuance; durable append-only owner |
| Delivery Record and receipt: prior record, confirmed bytes, exposure range, outcome, byte digest, and receipt reference | Sink observations and MoonBit transition rules | Store CAS append; receipt on confirmed completion |
| Run state: immutable outcome, per-Result availability observations, aggregate, and eligible next action | Committed chain, current Store query, trusted clock, and policy | MoonBit validation before authorized response serialization |

The dependency direction is acyclic:

```text
Program and Run admission
  -> Run Definition
  -> Run-bound Invocation
  -> Result Definitions
  -> evidence and durable payload bindings
  -> Result Artifacts
  -> complete Manifest
  -> final Run Receipt
  -> Captured Run
  -> exclusive public-index commit
  -> fresh read grants
  -> Delivery Attempts and terminal records
```

Prepared objects and reconciliation metadata are not public references. The
public index becomes visible only after the complete chain is persisted and
the index directory is durably synchronized.

## 5. Store and device assumptions

The first Store implementation uses the local Node filesystem. Its durability
claim is limited to the selected filesystem and device guarantees. It does not
claim survival of media loss or loss of the only local copy.

The Store requires:

- exclusive ownership of one Store directory by one live Store instance;
- bounded object and total-capacity reservation before copying input bytes;
- streamed writes without a whole-payload Buffer requirement;
- file and required-directory synchronization;
- physical SHA-256 and exact stored-byte verification;
- conflict exclusion independent of atomic rename;
- an exclusive public-index install for the Run Definition key;
- a trusted-clock high-water mark that survives restart;
- exact generation checks on reopen and every committed read; and
- retained reservations and cleanup owners until physical recovery is
  confirmed.

A second process cannot open the same live directory and split capacity
authority. A dead owner can be recovered under the Store's ownership rules.
Physical mutation, generation substitution, incomplete chains, and conflicting
commits are rejected.

## 6. Public Host usage

The ordinary Node Host entry is
`runPublishedCapturedStrategy(setup, publication, options, signal, observer)`.
`publication` contains the durable Store and the Run-bound publication plan.
The entry performs immutable preflight before Compute, then returns one owner
containing the internal execution and formal publication result.

Late publication uses the same completed execution owner:

```js
const published = await execution.publishEffectFreeRun(
  store,
  publicationPlan,
  signal,
);
```

It is not a separate weaker publication contract.

Result access installs a current authority and a Node delivery service:

```js
const service = installNodeResultAccessService({
  store,
  control,
  authority,
  now,
  limits,
  frameLimits,
});

const delivered = await deliverAuthorizedResult(
  service,
  {
    indexKey,
    principalId,
    purpose,
    resultName,
    format: 'json', // or 'jsonl' or 'csv'
    attemptId,
  },
  sink,
  signal,
);
```

The sink implements bounded `write(bytes, signal)` and
`finish(signal)` operations. Each write confirms its exact accepted byte
count. `finish` must return `{confirmed: true}` before the Host can issue a
successful delivery receipt. This terminal confirmation is required even for
zero-byte JSONL. A failed or unknown terminal confirmation produces no
success receipt.

Delivery-record visibility is not durability. If synchronizing the record
directory fails after the exact immutable record becomes visible, the caller
receives a pending cleanup handle. Its retry synchronizes that same record;
it does not serialize or send the Result again.

Manifest access, Run-state access, Result retention extension, Result
retirement, and metadata retirement use their separate installed authorities.
Individual Result access does not require permission to inspect the Manifest.
The Result request authority runs before Store resolution so denied callers
cannot distinguish a missing, expired, deleted, or malformed internal target.
After asynchronous authorization, the Host rechecks MoonBit-owned grant and
retention rules immediately before starting each new sink write.

## 7. Acceptance evidence

| Area | Fixed evidence |
| --- | --- |
| Program path | Real Local and DuckDB standard Host publication in `standard-host.test.mjs` |
| Inventory | MoonBit inventory tests and multi-Result standard Host fixtures |
| Atomicity | Invisible precommit index, durable commit, partial-export cleanup, and complete-chain validation tests |
| Identity | Independent Result Definition, ordering, Artifact, binding, payload, and delivery fixtures |
| Evidence | Negative MoonBit chain, Receipt, Captured Run, ordering, policy, and provenance tests |
| Publication retry | Lost response, same-intent idempotency, conflict, and concurrent-race tests |
| Publication unknown | Failed reconciliation remains unknown; fenced noncommit and cancellation tests |
| Crash | Prepared payload, failed writer seal, semantic pre-link, index durability, shared custody, and unpublished metadata restart tests |
| Availability | Available, partial, unavailable, expired, policy-unavailable, deleted, and Store-unknown tests |
| Authorization | Request-stage denial, Manifest-only, Result-only, revoked, expiry races, wrong binding, use limit, and hidden state tests |
| Retention | Extension, forbidden extension, trusted-clock rollback, active readers, deletion retry, and metadata deletion tests |
| Formats | MoonBit fixed JSON, JSONL, and CSV vectors plus real standard Host delivery |
| Delivery | Success, idempotency, empty-stream finish, byte-zero retry, known prefix, unknown exposure, record durability retry, sink failure, and corruption tests |
| Late publication | Real completed Local and DuckDB execution, exact success, authority, evidence, policy, and capacity rejection |
| Cleanup | Primitive failures, unconfirmed readers, retry, shared allocations, losing attempts, and reservation return |
| Restart | Freshly authorized committed delivery, integrity recheck, stale-handle rejection, and incomplete cleanup recovery |
| Compatibility | Corrected pins and explicit rejection of stale closed shapes |

## 8. Structural counters and resource invariants

The publication path adds work only for an explicit publication or delivery:

- Result export is bounded by row, byte, node, depth, and object limits.
- Canonical batches stream into one durable object without a whole-Result
  array or whole-payload Buffer.
- Logical Result identity, physical payload digest, and delivery-byte digest
  remain separate even when produced during one traversal.
- Existing retained input reuse still reports zero logical-CID passes where
  the managed process-local profile does not require publication identity.
- Publication preflight rejection starts no Compute attempt and leaves zero
  Store objects and reservations.
- Closing successful Local and DuckDB publication owners returns execution
  held and reserved bytes to zero.
- Failed cleanup retains exact Store bytes, object count, and owner until a
  retry confirms physical recovery.
- A losing concurrent publication retains neither a second Manifest holding
  nor untracked metadata after terminal cleanup.

No new wall-clock performance target was introduced. The existing retained
benchmark fixture gate remains green; explicit publication copying is not
misreported as a zero-copy optimization.

## 9. Local verification

All commands below passed against the verified implementation SHA. The only
untracked workspace file during verification was the user-owned Local Compute
plan, which is unrelated to this branch and was not staged or modified.

| Gate | Result |
| --- | --- |
| `moon fmt --check` | pass |
| `moon check --target js --deny-warn` | pass |
| `moon test --target js --deny-warn` | 4,592 passed |
| `moon check --target wasm --deny-warn` | pass |
| `moon test --target wasm --deny-warn` | 4,591 passed |
| `moon check --target native --deny-warn` | pass |
| `moon test --target native --deny-warn` | 4,591 passed |
| `node scripts/check-moonbit-api.mjs` | pass |
| `node --test scripts/moonbit-environment.test.mjs` | 3 passed |
| `npm run check:retained-boundary` | 223 passed |
| `npm run check:publication-runtime` | 16 passed |
| retained benchmark fixture tests | 26 passed |
| `npm run check:process-capacity` | 15 passed |
| `node --test scripts/portable-core.test.mjs` | 9 passed |
| `node scripts/check-node-without-duckdb.mjs` | 58 passed |
| `npm run check:docs` | pass |
| `node scripts/check-core-without-connectors.mjs` | pass |
| `npm test --prefix adapters/workers` | 24 passed |
| `npm run check:connector-addition` | pass on JS, Wasm, native, and Node |
| `npm test --prefix adapters/duckdb-node` | 127 passed |
| DuckDB Host release builds | pass |

Linux CI must pass on the report-bearing final SHA before this branch is
merge-ready. A CI correction creates a new fixed SHA and requires the affected
and mandatory gates to be rerun.

## 10. Explicit deferrals

This result does not claim:

- remote Site placement, remote credentials, or a Cloud deployment;
- Effect execution or Effect reconciliation;
- resumption of an unfinished Compute Run after process or machine crash;
- survival of local-media loss from a single Store copy;
- midstream delivery resume or exactly-once delivery;
- timing noninterference for unauthorized existence probes;
- resident-result publication optimization;
- compressed retained measurement indexes;
- the deferred native direct-output optimization; or
- final 27-case retained-performance acceptance.

These deferrals do not weaken the completed ordinary Effect-free publication,
authorized delivery, restart lookup, retention, or cleanup contracts.

[plan]: 2026-09-18-named-result-publication-implementation.md
