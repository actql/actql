# Public Local and Remote Client acceptance

The OSS Client has one operation surface after `connect()` chooses the
transport. Embedded Local uses the installed in-process Host port; Remote
uses the HTTP Host. Neither connection option grants access by itself. The
Host admits the request under its authenticated namespace and authority
scope, and a returned RunRef carries both coordinates.

| Operation | Embedded Local | Remote HTTP | Evidence |
| --- | --- | --- | --- |
| `aql` / `start` | Same acceptance, held, known-refusal and unknown classes | Same | `adapters/host-node/client-http.test.mjs`; packed Values tests |
| `lookupRequest`, `attach`, `status`, `wait` | Durable request and Run ownership | Same | packed Embedded and Remote Checkpoint tests |
| `checkpoints`, `reviewCheckpoint`, `resolveCheckpoints` | Exact review and signed answer; restart resumes | Same | packed Embedded and Remote Checkpoint tests |
| `result(name).all()` | Typed in-process frames | JSONL over HTTP | Both packed tests use `packages/sdk/fixtures/values.json` and its independent rows |
| `cancelRequest`, `cancel` | Same public outcome families | Same | packed terminal and Remote held/Run cancellation tests |

The packed Embedded test installs published tarballs outside the checkout,
runs without a MoonBit toolchain, and uses a fresh process for submission,
review/answer, resume and recheck. It verifies one physical start and one
computation. The packed Remote test uses the same Values document, an HTTPS
Host in another process, and covers lost replies, expiry, cancellation,
crashes, reconciliation and unchanged accepted work. It now installs its
tarballs outside the checkout as well. These are local mock-Host tests, not
live Cloud validation.

An automatically generated request ID is made before submission. If its
acceptance is unknown, `SubmissionUnknown` retains that ID and the original
endpoint/scope lookup context. The SDK never switches connections or resends
on its own. Applications must retain the original input and connection
selection to inspect or intentionally resubmit the same request. The Host
journal keeps the exact accepted namespace, authority scope, request intent,
Run Definition and dispatch state; another namespace cannot claim the same
request. Losing current permission does not delete an unknown record or
authorize a replay. The original Host root remains the recovery boundary.

## Cloud adoption handoff

The OSS namespace correction is available at
`7fa9ace4857cbd48b1c067c230d6b56736b40653` (PR #47), with its
same-SHA Linux CI green. Cloud should consume tarballs regenerated from a
validated adoption SHA, then update its digest, lock and provenance rather
than only changing a pin string. `RunRef.namespaceId`, the signed grant's
`namespace_id`, publication index keys, Result access and Store bindings
change together. The logical request key still uses authority scope and
caller request ID; it is not globally deduplicated by namespace.

Cloud maps the selected Workspace to the OSS namespace at its adapter
boundary. It must retain the original Workspace/namespace, authority scope,
request ID and input for unknown requests across reconnects, and must not
redirect them after a Workspace switch. Cloud Organization, Workspace and
provider-owned tenant identifiers do not become OSS execution fields.
Cloud's existing stored records and package fixtures require their own
inventory before adoption. This OSS change neither rewrites nor discards
them. Old OSS Host/Store roots and old or mixed wire bodies are refused
without conversion; the contract stays at the unpublished 0.1 baseline.

Cloud package adoption, its boundary conversion, stored-data decision and
live Cloud validation belong to the Cloud integration task. No such result
is claimed by these OSS tests.
