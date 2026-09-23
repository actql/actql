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
and digest. The Host still authorizes lookup against tenant, scope and grant;
those private grant facts are not present in this public response.

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
