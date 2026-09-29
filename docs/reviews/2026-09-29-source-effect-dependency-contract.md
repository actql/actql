# Captured Effect dependency closure: agreed 0.1 delta

Implementation branch: `feat/source-effect-run`.
This is the implementation contract, not a completion or CI claim.

## Contents and references

Extend the existing Captured Run evidence, not the public Result namespace
and not a new recovery database. The checked Effect computation selects the
acquired input and preceding Stage local Results required to validate its
Effect inputs, together with their transitive typed dependencies. Unrelated
Stages, arbitrary provider history, and unused Results are not independent
inventory roots. A referenced local Manifest still contains all Results
required by its existing contract.

Retain canonical dependency bodies, their declared contract kind and identity,
and existing Store holdings for required relation payloads. References are
derived from the admitted contract and checked dependency graph, not accepted
from a caller-authored edge list. Shared dependencies occur once in the
inventory. Audit authentication and physical custody remain outside local
semantic preimages. A Run-bound Invocation or Manifest cannot substitute for
its local semantic counterpart.

The existing checked owner issues the closure. Recovery admits the complete
closure before using any saved local Invocation or Artifact. It rejects missing
bodies, duplicate identities, wrong kinds, altered bodies, foreign checked
owners, dangling references, cycles, and dependencies outside the selected
closure. A CID is not a capability or an attestation. Typed relation values
terminate the graph only after validation against their retained payload and
schema. Recovery does not fetch Source or rerun Compute to fill a hole.

## Bounds

The initial installation ceiling is 4,096 distinct dependency entries,
16 MiB of total canonical evidence bytes, 65,536 references, and 64 dependency
edges on a path.
Existing stricter wire, node, JSON-depth, Store-capacity and relation-payload
limits also apply; these ceilings never increase an existing admission budget.
The evidence-byte ceiling includes the inventory envelope and embedded bodies.
Payload bytes remain charged to existing Store holdings and reservations,
not exempted by keeping them outside the evidence envelope.

Issuance measures before serialization/storage allocation. Recovery checks the
bounded envelope before body admission, checks count and aggregate bytes before
building indexes, and walks the typed graph with explicit depth/work bounds.
Neither cyclic references nor repeated sharing can bypass accounting. Test the
exact limits and one-over cases independently of the production issuer.

## CID and compatibility impact

| Contract/body | Impact |
| --- | --- |
| Captured Run Effect context | Required dependency inventory changes its body and CID. |
| Captured Run | Its containing body and CID change with the Effect context. |
| Final Receipt and other exact capture references | Reissue from the new capture; never retain a stale referenced CID. |
| Local Invocation, Artifact, Manifest | Existing preimage rules remain; actual observation/upstream dependencies affect their CIDs. |
| Captured Run schema and registry | Regenerate schema pins, embedded schemas and public/generated bindings. |
| Independent vectors and fixtures | Update complete bodies and independently calculated identities together. |
| Existing Program and checked Unit definitions | No identity change merely to add durable custody metadata. |

Keep version 0.1 by explicit agreement. This is an incompatible coordinated
development change, not wire compatibility. New writers always emit the required
inventory, including an explicit empty inventory when no upstream dependency is
required. Readers reject a missing inventory, old or mixed shapes, and claims of
empty inventory when typed references require dependencies. Do not supplement
old records, rewrite their bytes, replace old signed fields before validation,
or infer permission to retry from a format rejection.

## Durable point and ownership

Before capture is complete, acquisition and Compute owners retain responsibility
for partial physical work. A crash with incomplete inputs is not a completed
captured Run. The no-reacquisition/no-recomputation boundary begins only when
all required input/result payloads, dependency bodies, holdings, the Captured
Run, and the matching Preview are durable through the existing Store path.
Publish commit approval wait only after that boundary.

A failed persistence operation retains existing cleanup responsibility and must
not expose an answerable continuation claiming successful persistence. Resume
uses the saved approval target and verifies current commit permission, Site
generation, installation, Mapping and target state. Target confirmation reads
are separately counted from Source reads. A missing or invalid dependency never
authorizes substitute input or a new computation.

Cancellation or rejection before mutation retires unpublished holdings through
existing cleanup owners. Failed deletion retains a retry handle. If a write may
have occurred, keep the exact dispatch, response or unknown correlation and all
evidence required for reconciliation. Cleanup, status, repeated answers and
restart never resend that write.

## Acceptance and handoff

Use an independently authored expected inventory. Cover upstream-body deletion,
mutation, foreign replacement, duplicate entries, cycles, unknown kinds and
bounds. From public approval wait, restart and approve the same Run with Source
acquisition and Compute counters unchanged. Count target confirmation reads
separately. Exercise persistence failure before wait, cleanup failure and unknown
write recovery without evidence loss or resend.

D received the agreed delta in PR #53 before executable handoff. C owns schema,
compiler, checked owner, Store connection and Host changes. D owns provider
adaptation. A pushed executable SHA, commands and explicitly unconnected parts
will follow; this document does not claim the acquired Effect path is complete.
