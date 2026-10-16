# ActQL Client–Host wire shapes

`@actql/client-wire` is the structural request boundary for the public
Client–Host HTTP protocol. It validates exact operation envelopes, connection
selection, scoped Run references and bounded text before Host authorization.
The Node Host uses this package directly; other Hosts can use the same
versioned shapes without importing Node, local kernels or provider code.
The TypeScript `WireClientBodyByOperation` map describes the envelope accepted
by `validClientBody(operation, value)`. Its `parameters` and compiled Program
input remain `unknown` and `object`, respectively, until the Host performs
semantic validation; the structural guard does not authorize either value.
`validDeliveryAttemptLookup(value, expected)` checks the published attempt,
record and Host release receipt shapes and binds the reply to the requested
attempt ID, Run definition and Result name. It also checks the shared artifact
and serialization contract CIDs, record state, receipt reference, byte count
and digest. The Host still authorizes lookup against namespace, scope and grant;
those private grant facts are not present in this public response.
The request keys, Client–Host response shapes, and their TypeScript types are
generated from `spec/contracts/actql-client-host.json` with
`node scripts/generate-client-host-wire.mjs --write`. The publication artifact
guards and types are generated from the registered Run publication and protocol
schemas with `node scripts/generate-client-publication-wire.mjs --write`. The
same Client–Host generator projects the registered `run_state` artifact from
`spec/contracts/actql-protocol-schemas.json` into `validRunState` and
`WireRunState`. This guard checks structural wire shape only. It is a component
of the future Client snapshot; it does not express the separate publication,
cancellation, physical-stop or revision facts, and it does not replace the
MoonBit state validator. The normal distribution gate checks both
generated-file sets for freshness. The
small remaining
cross-artifact checks bind a reply to the requested Run and Result; they do
not decide publication or delivery transitions.
`validClientProfile`, `validClientAdmission` and
`validRequestLookup(value, expectedRequestId)` check
closed Host response shapes. Profile and admission validation bind the selected
connection and reject a durable downgrade. A found request lookup echoes and
matches the requested ID; lookup preserves distinct found, not-found and
observation-unknown results. These decoders do not make
an acceptance durable or prove that an absent request cannot be accepted
later.

These functions do not authenticate callers, grant movement or execution,
admit Program intent, interpret Run state, or validate a Remote Site message.
The Host must use the common MoonBit owners and current authorization after
structural validation. A JSON Run reference is an identifier for an authorized
lookup, never a capability by itself.

A local-owned Hybrid connection names an existing registered Cloud assistance
connection with `cloudConnectionRef` and a separate `movementPolicyRef`.
A Cloud-owned Hybrid connection names at least one selected Runner and its
movement policy instead. These references identify intended connections and
policy; the Host still checks current scope, grants and movement permission.

`snapshotClientRequest(value)` detaches a Client request through ordinary JSON
serialization. It throws if a number would become null or lose negative zero,
including boxed Numbers and numbers returned by `toJSON`. Boxed Numbers use
the same numeric conversion as JSON, exactly once, before number admission. It performs no query
checking or authorization and does not normalize text or keys. SDK and public
Local/HTTPS ingress use this owner before checking; SDK `start` and `aql` also
use it before credentials or exchange. `snapshotCheckRequest` remains the
existing check entry point, with its original TypeError spelling. Local takes the snapshot before
awaiting authentication. Parser/decode/binding limits still belong to the
existing checker. A serialization refusal is request admission, not a checker
verdict. No snapshot is retained beyond the caller's existing request custody.

## Exact pending Checkpoint lookup

The existing `checkpoints` request optionally selects `checkpointId`, using
the original Checkpoint-summary ID spelling from the machine contract. This
mode requires `after: ""` and `limit: 1`. The same Host/Journal returns zero
or one pending summary, with no `next`; IDs are exact, not CID fallbacks.
`validCheckpointLookup` checks the original requested ID against that closed
response. The old paged request is unchanged when the selection is absent.

This is safe metadata from the original Host scope, not permission, a signed
answer, a new Checkpoint, completed Effect or physical cleanup. The Journal
retains its ambiguity and lifetime checks; stale/foreign/fulfilled originals
do not become fresh attempts. Callers use the existing review and signed
resolution ports, with current authorization still checked by their Owners.

### Exact lookup ownership

| Attribute | Original boundary |
| --- | --- |
| responsibility | The registered optional selector and existing Checkpoint Journal select pending metadata; no approval is inferred from an ID. |
| inputsOutputs | One non-control ID, empty cursor and limit 1 produce zero or one summary, without a next cursor. |
| identity | The original ID must equal the same Journal row ID; CID fallback, copied/foreign identity and a fulfilled row cannot substitute. |
| ownership | The Host retains the original Journal, attestation and review custody. Consumers borrow the safe summary only. |
| synchronization | The same row is checked after asynchronous projection; closure during projection prevents publication of stale pending metadata. |
| failure | Invalid request/response, ambiguous ID and unauthorized principal remain existing refusals. Lookup loss does not authorize resolution or resend. |
| cancellation | Aborting metadata transport is not Run cancellation, signature acceptance or physical cleanup. |
| resources | Existing bounded ID, one-summary page and control-response budgets remain in force; no independent page search or cache is added. |
| extension | The same machine optional-field rule feeds generated JS/Python admission; ordinary absence preserves paged lookup. |
| verification | Independent request/response counters and original Account/encrypted SQLite Journal caller tests retain their source and runtime qualification. |
