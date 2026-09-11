# Result publication order

`relation_results.check` still checks Result structure and types. The separate
`resolve_publication_order` chooses a conditional publication strategy for one
definition in those checked Results. It retains the original Results/pipeline,
definition index, selected key or inherited order, and an immutable indexed term
sequence. It does not emit a Plan, journal, validate data or publish anything.

The resolver follows Language's priority, without using a lower-priority rule
to repair an unresolved higher-priority choice:

1. Authored order retains every term, direction and null placement. An eligible
   candidate key closes ties; only missing components are appended ascending,
   nulls last. Existing aliases count as coverage of their original component.
   No selected key leaves the authored ties unresolved in this implementation;
   it does not authorize a replacement sort over projected fields.
2. Without authored order, inherited pipeline order is retained even if Result
   projection hides its original ordering fields.
3. Otherwise the canonical eligible candidate key orders the input before field
   projection, so its fields need not appear in the published result.
4. Otherwise all projected fields must be CanonicalOrderable. Their order is the
   Result's declared `fields` order, not the schema's canonical name order. Each
   term is ascending, nulls last; nullable scalar and reference contracts are
   allowed here. This does not declare them a non-null candidate key.
5. Otherwise resolution returns `UnresolvedOrder` at the Result definition.

Reference fields participate in internal canonical ordering; authored OrderKey
still permits only AuthorOrderable types. The source checker already enforces
that distinction. The resolver never manufactures a uniqueness assertion or
uses physical input arrival order. Retained key and generator obligations still
require their execution/admission checks. Successful resolution is a static
strategy conditional on those dependencies, not a runtime conformance claim.
The generic ResultDefinition's pending list stays context-independent; the
separate resolution object supplies its contextual order strategy.

Work and name-byte limits are explicit and inclusive. Key selection, alias and
authored-term scans share those limits. Projection fallback builds one field
lookup and then walks declared fields in linear time. Returned terms are indexed
read-only values, and failure exposes no partial successful resolution. Fixed
tests distinguish all four strategies, their precedence, hidden input keys,
nullable/reference fallback, rejection and exact/minus-one resource bounds.

`resolve_publication_orders` requires a successful strategy for every definition
in the checked Results, in their retained definition order. It shares one work
and name-byte budget across all resolutions and checks the Result-count ceiling
before beginning. A failure retains the failing definition's diagnostic and
returns no partially resolved collection. The opaque collection retains the
original checked Results and provides only indexed read-only access, so callers
cannot omit an inconvenient Result or splice a different pipeline into it.
Its usage is the sum of individual resolutions, not a fresh budget per Result.

Stage/root publication admission can require this complete collection, but still
needs to resolve execution, policy and resource dependencies. Additional
admissible proofs for authored ties and external order witnesses remain separate
work. A complete strategy collection is not permission to publish unvalidated data.
