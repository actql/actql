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
