# ActQL Client–Host wire shapes

`@actql/client-wire` is the structural request boundary for the public
Client–Host HTTP protocol. It validates exact operation envelopes, connection
selection, scoped Run references and bounded text before Host authorization.
The Node Host uses this package directly; other Hosts can use the same
versioned shapes without importing Node, local kernels or provider code.

These functions do not authenticate callers, grant movement or execution,
admit Program intent, interpret Run state, or validate a Remote Site message.
The Host must use the common MoonBit owners and current authorization after
structural validation. A JSON Run reference is an identifier for an authorized
lookup, never a capability by itself.
