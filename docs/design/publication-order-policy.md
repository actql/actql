# Shared publication-order policy

`publication_order_policy.decide` contains the existing priority algorithm for
authored order, inherited total stable order, eligible candidate-key completion
and canonical projected-field fallback. It is independent of pipeline and Result
owner types, allowing the owning checkers to reuse one decision algorithm.

Its `Decision[T]` is a conditional calculation result, not a checked-order token,
an executable Plan or evidence that the supplied facts belong together. The
generic inherited value is passed through without interpreting or authenticating
it. Input schemas, selected fields, authored terms, keys and inherited evidence
must come from the owning checker's admitted state. Public policy data cannot
be used to construct a `PublicationOrder`, `ResultPort` or pipeline order witness.
No checker accepts a caller-supplied Decision as proof.

The `relation_results` wrapper continues to select an actual checked definition,
obtain its exact pipeline's keys and logical order, call the shared algorithm,
and retain that owner in its opaque `PublicationOrder`. It copies the decision's
term array into the checked result so mutable policy data is not exposed as an
alias to protected evidence. This refactor changes neither the accepted Result
grammar nor its conditional execution obligations.

The algorithm retains repeated authored terms, uses field provenance when deciding
whether a candidate-key component is already covered, prefers inherited order
only when authored order is absent, and uses existing stable input order to break
authored ties only when no eligible candidate key is available. Projected-field
fallback does not repair an unresolved authored order. Hidden source ordering
fields and canonical reference-type completion keep their existing treatment.

Work and UTF-8 text accounting are moved with the algorithm. Previously admitted
source/schema bounds still apply to the wrapper's term-handle conversion; these
logical budgets are not process-memory or CPU-time quotas. Missing field lookups
in inconsistent policy inputs reject rather than panic. The policy does not
replace grammar admission or verify a caller's inherited token.

Existing Result tests remain the governing regression for source-bound strategies,
keys, aliases, qualified columns, combined producer closure and exact budgets.
Policy tests separately cover inherited-token passthrough, authored priority,
unresolved ties, projected fallback, missing field rejection and budget boundaries.
The consumer-side Result import adapter remains unfinished.
