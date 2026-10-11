# Retained asynchronous Model response custody

The asynchronous physical port is an internal extension of the existing Model
execution Owner. It is not a public installed capability, a new scheduler,
Ledger or response Store. An installed adapter must fund all physical records,
closures, response backing, metadata and codec workspace before using it in a
public Host. A response profile declaration does not provide that funding.

## Original entry and fixed start

No-I/O preflight binds the exact prepared Model request, generation Task,
response profile and installation facts. It retains the same transport start
closure. The original durable Entry supplies its one-shot send gate. The
`BeforeInvoke` diagnostic runs before the final current/stop/authority checks;
the consumed gate is followed immediately by the fixed start, with no await or
user diagnostic between them.

The physical start registers an opaque call under that original Entry before
starting transport. A returned foreign view cannot replace a registered call.
Registration itself is neither send permission nor a transmission fact. The
adapter must not defer another request construction or permission claim into
its Promise callback. Transport exceptions and lost responses retain entered
responsibility; they do not permit a second start.

## Poll, observations and settlement

Pending polls return `AwaitIo` without synthetic logical work. The first
terminal observation is immutable, and its poll closure retires. Optional
provider identifiers, finish reason, usage and opaque metadata remain absent
when unobserved. Empty metadata means an actually observed empty object. Actual
codec completeness is separate from these optional fields and from the
declared profile CID. The common bounded output and metadata checks precede
the common evidence issuer; adapters do not assemble evidence JSON.

The existing settlement ACK records only the original custody fact. It invokes
no physical callback. A later advance retries physical cleanup; failed cleanup
keeps the same call, backing and retry closure and blocks the next call.
Successful cleanup clears the escaped view's original Entry and closures.

Cancellation stops unsent calls and requests local transport cancellation once.
It does not prove remote stop. An entered late response can still be checked
and saved by the original settlement Owner, without publishing partial output
or granting another call. Unknown remains Unknown. Partial usage is retained;
missing usage is never synthesized as zero. If the bounded kernel stops before
physical usage arrives, immutable accounting is unavailable until the original
terminal poll has been observed. Cleanup drains that same retained call.

The physical cleanup callback receives whether the original settlement was
acknowledged. `false` is not authorization to drop unknown custody: the trusted
adapter must retain or durably transfer that responsibility before reporting
release. Cleanup success is not remote success or reconciliation.

## Scope

The synchronous API and historical observation lift remain unchanged. This
sequential response cursor does not implement four-slot scheduling, SDK parsing
CPU bounds, Store ACK, real network transport or public installation. Those
connections must use the same original resource preparation and Ledger, not a
fresh budget or a profile-derived allowance.
