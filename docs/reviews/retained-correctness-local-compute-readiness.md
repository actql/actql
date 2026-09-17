# Retained correctness baseline and Local Compute readiness

Date: 2026-09-17

Implementation baseline: `a6654531e078d712a477060f898273cb0340b20a`

This instruction closes the correctness foundation of managed retained
execution and freezes the connection boundary that Local Compute may depend on.
It does not require the retained path to meet its final performance targets.

The work is complete only when the four boundaries below are connected through
the standard Host entry and enforced by regression tests. Passing isolated
constructors or connector fixtures is not sufficient.

## Scope and stopping point

Finish these items now:

1. derive the exact managed obligations owned by the Host before candidate
   comparison;
2. select only implementations that can satisfy those obligations, without
   execution-time fallback;
3. pass and complete a representation-neutral producer/consumer contract that
   Local Compute can implement without frontend traversal;
4. close cancellation, stopping, retention and cleanup responsibility through
   the standard Host path.

After these four items pass, freeze the boundary and begin Local Compute. Keep
the following work in the retained-performance track:

- resident DuckDB relation reuse;
- hard-bounded native direct output;
- compact range/chunk measurement indexes;
- elimination of all avoidable controller-side cell materialization;
- the registered 27-case alternating equivalent-obligation performance
  assessment;
- general Coordinator/Execution Site transport, durable remote execution and
  Cloud deployment.

Do not use a performance TODO to keep changing the correctness boundary. Do not
claim a performance pass from the correctness milestone.

## Adopted decisions for this milestone

The following decisions are normative for this implementation increment.

1. The Host derives a checked named Result requirement as
   `LogicalRelation + NamedResult + BeforePublication`. It never substitutes
   `OrderedRows`. A checked Result occurrence is owned by the checked Program
   and exact ResultPort; a name alone is not identity. Two names that publish
   the same output may share a compatible computed content CID, but their
   authorization, publication obligation and completion remain distinct.
   Acquisition-origin publication is not implemented by this increment and is
   rejected before execution.
2. The conformance reference implementation supports only
   `OrderedRows + TaskOutput`, with the admitted `BeforeCidOperation` and
   `BeforeDiscard` deadlines. It is explicitly installed in a conformance
   bundle and uses the normal registration, admission, scoped issuer,
   lifecycle and completion paths. It does not claim named Result publication.
3. Identity establishment uses a Host-issued scoped capability. Registration
   records an implementation's finite issuance support; an execution attempt
   receives authority for an admitted requirement; only after the exact output
   generation exists may a trusted registered identity implementation run the
   existing canonical encoder over that bound material and establish the CID.
   There is no API that approves an arbitrary caller-supplied CID string.
   Consumer, publication and discard boundaries enforce their deadlines.
4. Managed implementations are collected and compared by the common Host,
   independently of an implementation selected for the legacy path. Support
   and preparation are bounded planning work and may not start execution I/O,
   pin material or reserve execution/retention resources. Dispatch,
   reservation, settlement, completion and cleanup continue to use the existing
   common task lifecycle; this is not a second execution manager.
5. Local Compute contributes a small product implementation that performs one
   checked projection through the existing Local meaning/evaluation code. It
   creates a new owned in-memory material generation and completes through the
   common managed boundary. The identity reference implementation and Local
   connection fixture remain separate contributions.
6. The stable boundary is the machine-contract meaning and the explicitly
   named SDK surface used by Local. Compatible API additions remain possible.
   A change to required meaning, mandatory conditions or state transitions
   requires a new contract version. The API-difference gate detects changes for
   compatibility review; it does not permanently freeze the entire SDK.
7. Checked minimum requirements, mandatory Host policy and caller-added
   strengthening are distinct inputs. The Host takes their union. Only a
   Host-side registered authority may supply mandatory policy. Contradictory or
   unrealizable requirements are rejected explicitly.
8. Local retained storage accounting is a declared safe physical holding upper
   bound unless the existing field specifically requires an actual measurement.
   Actual use and charged/reserved bounds remain distinct when their meanings
   differ. The bound includes owned buffers, strings, indexes, necessary
   management space, shared backing storage and the input/output overlap during
   generation. A representation without a trustworthy finite bound is not
   eligible. RSS equality is not required.
9. The representation bridge is an explicit SDK capability, not a Local type in
   common code. Only an installed representation provider can open an admitted
   generation. Its ProducerRead is scoped and becomes unusable after the scope
   ends even if retained by connector code; its pin remains until the last
   actual read stops. Unsupported representations are excluded before start.
10. Equal-cost managed candidates use an existing registration-order-independent
    rule when one exists. Otherwise the common chooser uses the specified order
    of a unique stable registration key after cost comparison. Registration
    order, asynchronous completion order, object address and backend-name
    branches are forbidden tie-breaks.
11. A fixed SHA passing all local gates is implementation-complete. The same SHA
    passing Linux CI is merge-ready. Any CI-driven fix creates a new SHA and a
    new verification record.
12. An identity issuance permit is bound to one opaque execution-attempt token
    issued by common execution management, in addition to its checked
    preparation and requirement. The permit may bind exactly one retained
    generation. A retry or transfer needs a newly authorized permit, and a
    completion from one attempt cannot satisfy another attempt that shares the
    same preparation.
13. Memory representations obey the same actual-stop rule as file
    representations. A provider reporting pending cleanup keeps every acquired
    use until that cleanup is confirmed. Backing-release request, confirmation
    and failure are distinct states; one release failure cannot skip the other
    inputs, cannot be reported as confirmed, and is retried only through an
    explicit cleanup contract.
14. The standard-Host delayed-stop acceptance covers both the session-scope
    boundary and a real file-reading `session.command` whose Promise is still
    unsettled when outer cancellation returns. This proves the product lifetime
    connection without claiming observation of an arbitrary C++ instruction.
15. A Local or reference calculation may construct a provisional independent
    output while input pins are held, but it commits common task completion only
    after every input's final integrity report is accepted. The commit runs
    before those pins are released and after a current cancellation and use
    check. A failed final check never publishes and is not repaired by rolling
    back an already completed task.
16. Portable retained-boundary tests do not load an optional native backend SDK
    merely to obtain a shared error type. Representation codecs import that
    type from its dependency-neutral owner; real DuckDB loading remains in the
    dedicated DuckDB jobs.

## Status at the implementation baseline

Do not restart work that is already present at `a6654531`. Treat the remaining
work as closing integration gaps at the common Host boundary.

| Condition | Current status | Work remaining for this milestone |
| --- | --- | --- |
| 1. Host-owned obligations | The common scheduler derives opaque per-task managed obligations and passes them to the DuckDB driver. Caller policy is sealed before dispatch. | Prove that checked consumer and actual Result destinations form the mandatory floor, that optional policy only strengthens it, and that a terminal internal task is not mistaken for a named Result. |
| 2. Pre-start capability selection | CID-free DuckDB is excluded before execution for consumer/publication identity requirements. Process-local work still runs. | Add a positive identity-capable candidate through the common registry and prove alternate selection. A boundary that can only reject has not yet demonstrated usable capability negotiation. |
| 3. Representation-neutral completion | Common managed completion, holding, material binding and producer-use primitives exist; DuckDB uses the typed meaning contract without frontend traversal. | Connect one bounded Local implementation through the same request, completion and downstream-consumer path, without a backend branch in common code. |
| 4. Lifecycle closure | Product fixes retain pins until actual stop, retain unreported native files for cleanup and wrap arbitrary throwables. Component regressions cover two distinct inputs, filesystem cleanup retries and frozen abort failures. | Add one standard-Host integration case that combines delayed native stop, cancellation, all input pins, failure settlement and terminal cleanup. Keep the existing component regressions in the default gates. |

## Existing work to preserve

Do not redesign the following completed behavior:

- the managed profile keeps logical identity conditional on the selected
  obligations and keeps physical identity distinct from logical identity;
- exact immutable Store material is bound to a physical manifest;
- duplicate logical input occurrences can share one physical pin and integrity
  pass while retaining independent logical charges;
- output storage is hard-bounded through the Store writer;
- input files can be scanned through an authorized DuckDB view without a full
  parameter-INSERT import;
- native cancellation does not release input pins before actual stop;
- an unreported native-created file remains cleanup-owned until its exact
  generation is reclaimed;
- arbitrary JavaScript throwables are wrapped in Host-owned failure metadata;
- two distinct managed inputs remain pinned until an actual delayed DuckDB
  session stop;
- Store cleanup can retry after `lstat`, `open` and `unlink` failures without
  losing the tracked generation or reservation;
- a frozen abort reason and a cleanup failure retain both causes and remain
  retryable;
- the standard Host already excludes the current CID-free DuckDB realization
  before start when configured consumer or publication identity is required;
- connector code receives typed lowering/AoA meaning and does not traverse the
  frontend pipeline or source to reconstruct semantics;
- no logical CID preimage, existing Artifact wire or existing acquisition wire
  changes as part of this milestone.

The current `configure_captured_managed_identity_policy`,
`captured_next_managed_obligations` and opaque request plumbing are useful
parts of condition 1. Extend or correct them; do not replace them with a
connector-specific route.

## Condition 1 — Host-owned obligations are complete and immutable

The common Host must determine the minimum obligation set before comparing
implementations. The set is derived from:

- checked task meaning and output destination;
- known downstream consumers;
- the actual publication contract, if any;
- mandatory Host policy;
- optional caller requests that only strengthen the minimum.

Program text and connectors cannot lower this set. A caller passing `false`
must not erase a requirement already implied by a named Result, consumer or
Host policy.

The standard captured-Program entry requests its checked named Results and
therefore always includes that floor. A separate, explicitly named internal
task entry may omit Program publication; this is an execution target, not a
false publication-policy value. It returns internal task records only and does
not claim Result publication.

### Required implementation

1. Represent the prepared requirements as one opaque Host-owned value per task,
   or as an immutable per-task plan from which that value is produced. Global
   booleans may remain an internal input, but they must not be the only source
   of truth once concrete consumer and publication bindings are known.
2. Distinguish a terminal internal task from an actual named Result. A task with
   no graph consumer is not automatically a publication target.
3. Derive deadlines explicitly:
   - a CID-dependent consumer: `BeforeCidOperation`;
   - a named Result or CID-bearing publication: `BeforePublication`;
   - a Host retention policy that requires identity before loss of source:
     `BeforeDiscard`.
4. Seal the requirement plan before the first candidate is prepared. Reject a
   second configuration and any configuration after task start.
5. Pass the exact opaque `ManagedObligations` object through the common
   scheduler, generated bundle, connector driver, request and completion port.
   Connectors may inspect it and reject it. They cannot replace it with
   `process_managed_obligations()` or construct a weaker default.
6. Verify the exact checked owner at each handoff. Equal CIDs or structurally
   equal requirements do not replace owner identity.

### Required tests

- internal output plus material-binding consumer produces
  `UnestablishedRetained` and is eligible for the current CID-free DuckDB path;
- a known logical-identity consumer produces `EstablishedBy(BeforeCidOperation)`;
- an actual named Result produces `NamedResult` with
  `EstablishedBy(BeforePublication)`;
- a Host identity requirement produces `EstablishedBy(BeforeDiscard)` where
  applicable;
- optional caller policy can strengthen an otherwise process-local task;
- optional caller policy cannot weaken a checked or Host-mandated requirement;
- configuring policy twice, after selection, or after execution start fails;
- multi-task graphs derive requirements for the correct producer rather than
  applying a terminal-task flag to every task.

If formal Program Result publication is outside the current physical profile,
state that explicitly and reject that request before candidate execution. Do
not simulate publication by setting a generic terminal-task Boolean.

## Condition 2 — capability selection happens before execution

The common selection boundary must answer whether an implementation can satisfy
the complete request. A connector callback succeeding does not establish that
capability.

### Required implementation

1. Give each managed candidate a typed compatibility decision for the admitted
   identity domains, subjects and deadlines, plus the existing operation,
   capacity and representation requirements.
2. Exclude an incompatible candidate before resource reservation, native
   session creation, input pinning or task start.
3. Compare all eligible installed candidates through the common selection
   mechanism. Do not hard-code Local, DuckDB or reference implementation names
   in the common Host.
4. Add one positive reference candidate for the identity-required case before
   Local Compute depends on this API. It may be a bounded test implementation;
   it must issue identity through the real scoped issuer and completion port.
5. Prove that a rejected CID-free DuckDB candidate does not prevent selection of
   that capable candidate.
6. Once an implementation starts, its failure is the selected attempt's
   failure. Do not catch it and silently rerun the task in Local Compute.

### Required tests

- CID-free DuckDB is rejected before start for consumer and publication
  identity requirements;
- the same request selects the positive identity-capable reference candidate;
- the process-local request still selects DuckDB;
- an implementation cannot claim support and then omit the required issuer or
  completed identity;
- registration order does not change the result when costs and capabilities
  are otherwise equal under the existing deterministic rules;
- no excluded implementation opens a DB, pins an input, reserves execution
  capacity or receives a dispatch callback.

This milestone need not implement general delayed CID generation in DuckDB.
Pre-start rejection is correct when no capable implementation exists. The
positive reference path is required to prove that the common API is usable and
does not merely reject every non-default request.

## Condition 3 — completion and input use are representation-neutral

Local Compute must be able to join the existing Host without depending on a
DuckDB file, Node callback, frontend object or connector-specific enum.

### Required common boundary

A completed managed output must retain:

- exact producer, task, attempt, output target and input bindings;
- the admitted meaning and demanded-failure obligations;
- exact material generation and logical-view interpretation;
- current holding, availability and authorization;
- physical manifest or equivalent owned generation evidence appropriate to the
  representation;
- identity requirements and their established/unestablished plus
  retained/unavailable state;
- the scoped issuer used for any later establishment.

The common layer treats the material as opaque. Its representation may be:

- Local in-memory typed rows or columns;
- a Store-managed file;
- a DuckDB resident relation generation;
- a future admitted execution-site representation.

Do not add a common `Local | DuckDB | File` enum. Representation-specific
opening, validation and disposal stay behind an installed typed contribution.

### Local Compute entry contract

Freeze the Local entry around the following rules before adding more kernels:

1. It accepts the same typed AoA/lowering contract and exact checked owner used
   by other Compute implementations. It must not inspect frontend pipelines or
   source text.
2. It accepts only exact bound producer inputs admitted by the common Host.
3. It declares whether it supports the admitted identity obligations. If the
   first Local increment supports only process-local material binding, it must
   reject CID-required requests before start.
4. If Local establishes a logical identity, it must use the existing canonical
   encoder and scoped issuer for the exact domain/subject. It must not relabel a
   physical digest as a logical CID.
5. Successful execution creates a common completion and owned holding. Failure
   or cancellation exposes no partial successful output.
6. Consumer-specific guards, demand, logical work and capacity are charged for
   each use even when physical measurements or material are reused.
7. The portable synchronous Local implementation performs no filesystem,
   network, clock, process or environment I/O. Host-specific asynchronous and
   I/O work remains outside the portable Core.

### Required tests

- a real two-task standard-Host path passes a completed output to another task
  without converting it to caller-authored JSON;
- two independent consumers obtain separate use authority and logical charges;
- closing one consumer does not revoke another or the completed producer;
- foreign owner, attempt, target, material generation and expired holding are
  rejected;
- Local in-memory and Store-file representations produce the same logical value
  and ordering for the same checked fixture;
- unsupported identity obligations exclude Local before execution;
- no Local package imports frontend checking internals, concrete DuckDB code,
  Node adapters or physical-strategy implementation packages outside the
  allowed SDK boundary.

The test implementation may cover a small operation set. Kernel breadth is the
next Local Compute track; this milestone proves the connection, ownership and
completion path.

## Condition 4 — stopping, cleanup and resource ownership close end to end

The standard Host must preserve the following distinctions:

```text
outer Promise settled
  != native or Local operation stopped
  != all input uses released
  != output generation resolved
  != output reclaimed
  != reservations returnable
```

### Required implementation and regression coverage

The component-level cases for two distinct inputs, filesystem cleanup retries,
arbitrary throwables and frozen failures already exist at the baseline. Keep
them; do not recreate them under new helper APIs. The remaining integration
work is to prove the same ownership chain through the standard Host entry.

1. Add a standard-Host test that aborts during native file use with an
   intentionally delayed actual stop. No later task starts, no output is
   published and every distinct input pin remains owned until retry confirms
   stop.
2. Preserve the existing coverage for duplicate logical inputs sharing one
   physical body and two distinct physical input bodies. The standard-Host
   integration case must use all pins returned by the selected task.
3. Confirm each pin exactly once; repeated cleanup is idempotent.
4. A missing or throwing native cleanup status remains pending.
5. Keep the Store entry and reservation when native creation may have produced
   a file without a terminal report. Confirm absence or bind and reclaim the
   exact generation before release.
6. Keep the existing retry coverage for `lstat`, `open` and `unlink` failure in
   the default test path. A failed cleanup attempt must keep enough state and
   reservation for a later retry.
7. Preserve conservative unknown-write accounting separately from live storage
   reservation.
8. Preserve the existing arbitrary-throwable and frozen-Error coverage. Extend
   the standard-Host integration case only where needed to prove that the
   original value remains the primary cause while every independent finalizer
   runs.
9. Distinguish failure before native start from unconfirmed failure after
   start. Only the former may use confirmed-zero settlement.
10. At terminal cleanup, require zero live task reservations, retention
    reservations, Store bytes, input readers and unresolved cleanup owners.
11. Apply the same rules to memory providers. Pending or unknown provider
    cleanup retains the exact use count. A backing-release failure keeps the
    generation cleanup-owned, and all independently acquired inputs receive a
    release attempt even when another release fails.
12. Exercise a real file-reading session command that has started but remains
    unsettled across the outer cancellation deadline. Assert that every input
    pin remains held until the command and composed cleanup settle. Retain the
    separate session-scope delayed-stop case as well.
13. Keep calculation/output generation provisional until all input integrity
    reports have passed. Run the one-shot common completion while all exact
    pins are still held. Cover same-size mutation after initial verification,
    failure of the last confirmation among multiple inputs, and cancellation
    before the commit boundary; none may notify completion or dispatch a
    descendant.
14. Track backing-release failure independently from its throwable payload.
    `undefined`, `null`, booleans, numbers and strings are still failures and
    must terminate `close()` with Host-owned cleanup responsibility. Keep
    retry diagnostics separate from current cleanup ownership so a later
    confirmed stop can release every use and clear `pending`.

The old native-COPY output route is not part of the current bounded product
path. Keep its Store/session regression because the API still exists, but mark
the standard managed-COPY cancellation case as not applicable unless that
route is reintroduced.

## Implementation order

Use small reviewable commits in this order.

### Increment 1 — obligation floor and task derivation

- audit the obligation plumbing introduced by `94ae2916` against condition 1;
- bind real consumer/publication destinations rather than assuming every sink
  is a named Result;
- separate mandatory requirements from optional strengthening policy;
- add exact multi-task derivation tests.

### Increment 2 — positive capability selection

- add the bounded identity-capable reference candidate;
- collect eligible candidates through the common registry;
- prove rejection, alternate selection and no-start behavior;
- keep connector names out of common code.

### Increment 3 — Local connection fixture

- make one small Local operation use the frozen request/completion boundary;
- exercise process-local completion and a downstream consumer through the
  standard Host;
- reject unsupported identity requirements before start;
- add dependency/API boundary tests.

This is a connection fixture, not the broad Local kernel implementation.

### Increment 4 — lifecycle integration

- add the standard-Host delayed-stop test using every selected-task input pin;
- retain the `a6654531` component regressions for distinct inputs, retriable
  filesystem cleanup and frozen/arbitrary throwables;
- run the combined cancellation, settlement and cleanup path through the
  standard Host;
- confirm all reservations and handles close.

### Increment 5 — freeze and document

- document the exact Local candidate support matrix;
- document that managed task completion is not formal Program publication;
- record deferred performance work without calling it a correctness blocker;
- regenerate APIs and generated connector bundles;
- make every default gate pass on a clean worktree.

Do not combine these increments with Coordinator/Execution Site extraction,
Cloud RPC, durable Run recovery, dynamic connector loading or new ActQL
operations. Those changes make the boundary harder to assess and are not needed
to begin Local Compute.

## Implemented support matrix

This milestone fixes the following finite product surface. It does not imply
general managed execution or named-Result publication support.

| Contribution | Admitted input | Identity support | Output and lifetime |
| --- | --- | --- | --- |
| DuckDB managed | Registered managed column/Parquet files | CID-free managed use only | Store-owned generation and the existing common lifecycle |
| Reference numeric managed | One registered row-readable managed generation | `OrderedRows + TaskOutput`, established by the registered canonical encoder before `BeforeCidOperation` or `BeforeDiscard` | New owned memory generation; no named-Result publication |
| Local managed | Registered row-readable managed generations for the checked projection-only sequence | CID-free managed use only | Existing Local evaluator, independent owned memory copy, schema re-admission and common managed completion |

The common Host gathers all three offers without relying on the legacy selected
registration. It compares declared common cost first and then the unique stable
registration key. Known cost sorts before unknown cost. Registration order,
asynchronous completion order, object address and backend name do not decide a
tie.

Checked named Results produce distinct
`LogicalRelation + NamedResult + BeforePublication` occurrences even when two
names refer to the same ResultPort. No installed contribution in this milestone
publishes that contract, so it is rejected before task start. Acquisition-root
publication is also rejected while configuring the Host policy. Deriving these
requirements is not named-Result or acquisition publication support.

The Local representation bridge is provider-owned. It acquires exact memory
generations before an asynchronous read, keeps every acquired generation until
the provider's actual stop is confirmed, and revokes a captured reader when
its scope closes. A backing release is complete only after its callback or
explicit cleanup owner confirms completion; arbitrary throwable values and
transient retry diagnostics never stand in for that state.
Its `storage_bytes` value is the charged safe holding upper bound, including
generation-time input/output overlap; it is not observed RSS or serialized
size. The current Local path may encode and re-admit a bounded row while
creating its independent checked generation. Removing that work is deferred to
the retained-performance track.

Cancellation coverage distinguishes the session operation becoming unsettled
from the C++ engine's internal stop position. The product Store/session bridge
keeps all exact input pins until the real operation and cleanup owner report
stopped. The tests establish that ownership connection; they do not claim to
observe an arbitrary internal C++ instruction boundary.

The explicit Local SDK dependency surface is the managed request and
obligation value, managed producer read/bridge, independent checked output,
retention/completion port, selected common task lifecycle, and registered
representation provider. Compatible additions are allowed. Non-compatible
changes to their mandatory meaning or state transitions require a new contract
version and API review.

## Mandatory validation

Run at the final fixed SHA:

```sh
moon fmt --check
moon check --target js --deny-warn
moon check --target wasm --deny-warn
moon check --target native --deny-warn
moon test --target js --deny-warn
moon test --target wasm --deny-warn
moon test --target native --deny-warn
node scripts/check-moonbit-api.mjs
npm test --prefix adapters/duckdb-node
npm run check:retained-boundary
npm run check:connector-addition
npm run check:docs
npm run check:metadata
git diff --check
```

Also run the Workers and real DuckDB jobs already required by the repository.
Run Linux/GitHub Actions once before merging this boundary into `main`; local
Darwin success is not a substitute for the required Linux result.

## Definition of done

The correctness baseline and Local Compute connection boundary are complete
when all of the following are true:

- all four conditions above have standard-Host evidence;
- mandatory identity requirements cannot be weakened by caller or connector;
- at least one capable reference implementation proves positive selection for
  an identity-required request;
- a Local connection fixture executes and completes without frontend traversal
  or backend-specific common branches;
- incompatible candidates are rejected before any execution side effect;
- cancellation and cleanup preserve ownership until actual stop and confirmed
  reclamation;
- memory-provider cleanup and backing-release failures retain ownership, run
  all independent finalizers, and never convert a failed release into a
  confirmed one; arbitrary throwable payloads remain failures, while a later
  successful cleanup clears pending responsibility even if earlier retries
  failed;
- identity authority is bound to the exact common execution attempt and one
  retained generation, including rejection of same-preparation cross-attempt
  reuse;
- both session-scope and active file-reading-command cancellation tests retain
  all pins until actual settlement;
- Local and reference completions occur exactly once after all final input
  checks and before input-pin release; integrity failure or cancellation before
  that point leaves the task incomplete;
- dependency-neutral retained-boundary gates pass without installing the
  DuckDB Node SDK, while the dedicated real-DuckDB job remains green;
- the worktree is clean and every mandatory validation passes at one fixed SHA;
- the support matrix and remaining performance limitations are accurate;
- no Result, acquisition, wire or CID guarantee is silently weakened.

At that point, begin Local Compute kernel/storage work and the
Coordinator/Execution Site refactor as separate branches. Performance work may
continue in parallel against the frozen boundary.
