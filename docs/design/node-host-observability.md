# Node Host observation boundary

The optional Node adapter is the initial O1/O2 implementation: metadata-only
Owner projections on public Embedded Local and HTTPS. It is not a new execution
Owner. Evaluation Evidence and empirical CBO have independent exits and controls.
Native, Workers and hosted multi-tenant export are not supported by this adapter.

## Owner facts and identities

| Observation | Existing source | Projection boundary |
| --- | --- | --- |
| Pre-Run check verdict | Common checker through `prepareSource` | After check returns; no invented Run or valid Program CID |
| Run admission | `client-request-journal.acceptDefinition` | After semantic admission commit; only a new admission initializes optional consumption |
| Task activation/completion | `strategy` activation and checked completion | Bounded internal hook after the confirmed operation; no output handle passed to exporters |
| Model physical attempt | `installed-model-continuation` / Checkpoint journal | After entry/observation receipt; actual task, slot, attempt and attempt CID |
| Effect application | Common Set receipt / publication disposition through the installed Effect Site | Confirmed application fact with the original Run ref; interrupted adapters cannot supply a semantic outcome |
| Approval waiting | Dispatch owner with retained Checkpoint | Waiting event, not inferred permission or a long-lived span |
| Resolution | Installed Checkpoint owner | Committed resolution and original Run ref, not automatically resumed execution |
| Recovery | Existing journal/controller diagnostics and Run inspection | New finite ingress segment, saved caller link, actual observed state |
| Cancellation request | Installed cancellation owner | Accepted request is distinct from confirmed cancelled outcome |
| Run outcome / physical stop | Stable revision-checked `observeRun` | Copies Owner outcome/revision/physical close fact; no AbortSignal inference |
| Publication | Dispatch owner / committed Store index | `computed` maps to committed Result, not mere capture success |
| Cleanup | Dispatch `settleCleanup` | After retained execution/capture cleanup and required stop observation; distinct from semantic completion |

Task ordinals are not invented attempt IDs. Model attempts carry the existing
attempt identity. Other provider-specific attempt details are not inferred from
task ordering. Arbitrary Owner diagnostic details, resource usage objects,
locations and raw failures are discarded. Completed tasks reuse the existing
driver's measured elapsed time; ingress segments measure their own duration.
Other instant fact spans do not claim a physical duration, including Model
attempt receipts. Source/Model attempt facts use standard CLIENT span kind;
application/receipt facts remain INTERNAL, never inferred physical sends.
Logical work/accounting is not inferred from these clocks.

The common projection copies fixed fields into a bounded queue and delivers
after `setImmediate`. The Host does not import an OTel SDK. SDK/HTTP propagation
is a syntax-checked transport header outside canonical requests and authority.
The optional package uses private SDK providers and official protobuf serializers
with an explicitly bounded HTTP sender. Application-owned providers remain
application-owned and have the weaker contribution-only guarantee.

The observation projection's `actql-observation/0.1` version and private journal
`actql-client-observation-custody/0.1` marker do not change semantic preimages.
Configuration digest binds scope, limits, filters, correlation, sampler,
destinations and selected SDK revision. Destination URLs are not stored in the
journal. One observation connection is installed on one live Host at a time.

Selection and wire configuration remain observation-adapter concerns, not new
execution authority. The existing MoonBit Owners still decide admissibility,
attempt identity, accounting, cancellation, publication and cleanup. Operation,
measurement, correlation and attribute selectors only narrow copied facts.
Unavailable measurements stay unavailable; no exporter derives logical work or
usage from spans. Duration selection controls optional metric instruments, not
the truthful timestamps of the finite span being represented.

The optional Node package can explicitly select standard environment
configuration. It never overlays an application-owned provider. Generic
destinations enable traces only; signal-specific settings and exporter choices
resolve before SDK construction. Authentication headers are bounded transport
configuration, never observation fields. The managed Resource has a fixed
default and only three explicitly disclosed standard installation attributes
may replace or extend it. Read-only inspection reports keys and credential
presence, not their values. Unsupported configuration files, transports and
Hosts are explicitly reported instead of creating an implicit pipeline.

## Restart and missing observations

Optional custody is in the existing Client request database on a separate
SQLite connection/transaction. It references the original namespace, authority
scope, Run definition and caller request ID. Admission and telemetry are not a
mandatory atomic commit. Only a newly inserted Run may initialize consumption.
An idempotent submit, recovery or changed observation setting cannot replenish
it. Unconfirmed telemetry consumption disables further Run projection; Run
execution, capture, publication and cleanup continue under their existing Owners.

Caller SpanContext stores only fixed-size IDs and sampling flags. It is never
authority and contains no baggage/tracestate. Recovery starts a new finite
segment and links to that saved context. There is no durable span state or
promise. Loss counters identify unavailable budget, limit, queue overflow,
delivery failure and deadline discard. They are diagnostic, not completeness
certificates. Shutdown never reports physical settlement of a pending callback.

The first profile is immutable and metadata-only. Explicit adapter close
revokes queued and not-yet-sent owned delivery and aborts outstanding sends;
already-delivered data cannot be recalled. Live disclosure reconfiguration, content redaction,
tenant routing, hosted export and recall of downstream buffers are not offered.
Application providers are not a way to extend the guaranteed managed boundary.

## Evaluation and bounded measurement proposal

Evidence capture remains independent of OTel enablement, sampling and exporter
success. O3 can later connect an authorized INFER capture to an external
evaluator using existing capture/Result access; this unit adds neither content
export nor evaluation replay authority. Missing observation does not imply
missing capture; a captured successful execution does not prove answer quality.

The [existing Relation benchmark](../../benchmarks/local-relation/README.md)
uses seven paired repeats, alternating candidates, with a fresh process and one
warmup per candidate. Its prepared measurement reports operation time separately
from warmup and E2E. It must not be relabeled as cold Host latency.

For a future, separately authorized OTel overhead diagnostic, use seven fixed
pairs (off/on), alternate order, and freeze source, workload, artifacts and
capture mode. **Cold** is a fresh process/Host/empty process-local cache and the
first request with no warmup; it does not imply an empty OS cache. **Warm** is
one unmeasured request followed by seven fresh logical requests on the same
Host, not retransmission of one idempotent request. Keep operation time, public
request-to-Result E2E, capture time, telemetry delivery and shutdown separate.
Do not run this measurement during builds or use it as an implemented gate.

An empirical estimate sidecar is applicable only to an immutable admitted
candidate set and pending request, with authorized bounded disclosure and its
own deadline/volume cap. Unknown estimates remain unknown. It cannot relax
admission, reorder approved calls or authorize dispatch/retry. This unit does
not implement that sidecar or any CBO sampling/training pipeline.
