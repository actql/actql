# Immutable Review binding facts

The publication owner retains the parsed canonical value of an admitted public
Review. Its binding projection reads the original Preview, Authoring Context,
authority scope and approval claims from that value. It performs no wire parse,
hash, schema admission or current authorization. Returned claims do not expose
the retained value's mutable backing.

The Run Host facade accepts the same namespace's original evidence token and
forwards the projection. Caller-visible wire and identity fields cannot replace
that original. The observed fields are historical DATA, not approval, execution,
publication or cleanup acknowledgements.

A consuming persistence boundary joins the Preview, scope and claims to its
actual original Checkpoint and owner scope. The canonical Review identity stays
distinct from the full Store byte digest. That exact pinned Review identity
also retains the Authoring Context contained in the original Review; this
projection neither derives an independent expected context nor proves upstream
Review issuance. Current authority and the required durable mutation remain
with their existing owners.
