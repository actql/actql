# Capacity derivation consistency

`capacity_derivation` checks the numerical dependency graph underlying
[bound witnesses](../spec/language.md#resolved-limits). Its opaque
`CheckedArithmetic` result is deliberately not a validated witness, external
fact, resolved limit or permission to run. There is no pipeline input variant
that accepts this result as proof.

## Checked properties

Nodes contain a unit, claimed nonnegative safe-integer value, and one closed
numerical operation: leaf, preserve, minimum, addition, multiplication or clamp.
Dependencies are graph indices. Forward references and shared dependencies are
allowed. Every supplied node is checked, including nodes not reachable from a
prospective consumer. Missing indices, cycles, empty minima, invalid numbers,
overflow and incorrect claimed values fail atomically.

Preserve, minimum, addition and input-bearing clamp require matching units.
Multiplication can change units: the existing witness algebra permits an
operation-specific output unit (for example, an input cardinality multiplied
by an expansion bound). This package does **not** establish that a particular
conversion is authorized by a governing law. A clamp without an input returns
its maximum numerically, not evidence that enforcement took place.

Repeated dependency occurrences count separately. In particular, adding the
same dependency twice doubles its numeric contribution. Minimum repeats do not
change the numeric minimum; canonical CID-reference ordering/deduplication in
the wire format belongs to witness admission, not to this index graph.

The checker uses iterative dependency scheduling. `max_nodes` and `max_edges`
bound graph size before the corresponding allocations; edge limits count
occurrences, not distinct pairs. Work and storage are O(nodes + edges), including
minimum reduction. No recursion or global witness cache is used. Returned
values, units and leaf indices are detached from the caller's graph and its
dependency arrays. Inspection is indexed and bounds-checked.

The empty graph is numerically consistent but supplies no finite candidate.
A resolved-limit constructor must independently require at least one applicable
validated candidate. Multiplication by zero and clamp-to-zero do not bypass
dependency validation or make a cyclic graph valid.

## Required surrounding boundary

`link_references` resolves a complete CID-addressed numerical graph into the
same arithmetic checker. Identity strings must use canonical SHA-256 spelling
and be unique; forward references and repeated operand occurrences are retained.
All dependencies must be present, including those of unused nodes. No optional
dependency map or global created-witness cache can bypass resolution. Node and
edge-occurrence limits apply before array copying; fixed-size CID validation
precedes lookup, and the retained index and computed results are detached.

This API accepts **unauthenticated descriptions**, not wire witnesses. Checking
a CID's spelling does not recompute its preimage. Source leaves, source/role/law
relationships, wire dependency sets and enforced-ceiling applications still
require their own validated owners. `LinkedArithmetic` is not accepted as
pipeline evidence or permission to execute. An enforced ceiling is deliberately
not exposed as a reference operation that could turn an arbitrary limit CID
into a proven bound. The later wire adapter must connect its validated sources
and enforcement dependencies to this numerical closure.

`select_candidate_minimum` adds the common numeric limit-selection rule over an
already checked graph. Candidates retain their graph indices and supplied roles;
all must exist and match the requested unit. The minimum includes every supplied
candidate. Author guards must be positive; they are binding only when their
minimum is strictly below every non-author candidate. Equal ceilings make them
currently non-binding, but do not remove them. With only guards they are binding;
with no guards the status is absent. This matches the normative resolved-limit
rule and `resolveActqlLimit` in the fixed Sketch reference.

Selection is iterative O(candidates), with an inclusive candidate-count bound
before copying. Equal values and repeated candidates remain distinct entries;
even after finding zero, later invalid candidates fail. The opaque result retains
the graph and detached entries. It is an arithmetic result, **not** a resolved
limit or authenticated witness set: roles remain supplied classifications, source
applicability/completeness is unproven, and CID ordering and enforcement binding
are not performed. No pipeline evidence input accepts this result as a proof.

Source authentication and law validation remain mandatory work. A wire witness
adapter must verify canonical bodies/CIDs, resolve each reference into this
graph, check the complete declared dependency set, validate role/source pairs
and the governing law, and bind each leaf to its actual source body. An
`enforced_ceiling` becomes numerically available only through a separately
validated resolved-limit/enforcement dependency; it is not represented here as
a public proof constructor. Likewise, a program proof cannot be established
merely by copying its claimed value into a leaf.

The [closed law-name registry](capacity-law-registry.md) is now pinned and
generated into an exact-membership boundary. Membership is not validation of
an individual law application or source. The fixed Sketch
`src/actql-bounds.ts` supplies implementation material, including law IDs,
role/source checks and arithmetic derivations. Its optional dependency-map
validation and global created-witness cache are not imported as trust rules.
The remaining operation-specific application semantics must be validated
before claiming capacity evidence. They are not grounds to skip law
checks or to accept any caller-provided law string.

This implements a component of the original shared-capacity scope. Canonical
wire admission, source/law validation, enforcement binding, resolved-limit
generation and whole-pipeline discharge remain open in the
[completion audit](pure-operation-audit.md).

## Tests

Regression cases cover every numerical operation, forward/shared/repeated
references, missing references, self/mutual/unused cycles, invalid numeric
parameters, all derived-value mismatch branches, unit mismatches, overflow,
exact graph budgets and detached results. A 10,000-node chain checks iterative
handling. Three hundred permuted graphs use independent exact-integer formulas
for accepted claims and deliberately corrupted output claims. These tests prove
numerical graph consistency only, not external provenance or execution.

CID-reference regressions additionally exercise every reference operation,
forward/shared/repeated operands, malformed and duplicate identities, missing
dependencies, unused cycles, numeric mismatch, exact allocation budgets and a
reversed 10,000-node chain. Synthetic IDs in these tests are labels, not a claim
that a wire witness with that content hash has been authenticated.
