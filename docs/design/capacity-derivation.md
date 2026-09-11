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

Source authentication and law validation remain mandatory work. A wire witness
adapter must verify canonical bodies/CIDs, resolve each reference into this
graph, check the complete declared dependency set, validate role/source pairs
and the governing law, and bind each leaf to its actual source body. An
`enforced_ceiling` becomes numerically available only through a separately
validated resolved-limit/enforcement dependency; it is not represented here as
a public proof constructor. Likewise, a program proof cannot be established
merely by copying its claimed value into a leaf.

Inspection found bound-witness and resolved-limit shapes in the protocol
schemas and normative references to a closed law registry, but no corresponding
closed bound-law registry body in this repository. The fixed Sketch
`src/actql-bounds.ts` supplies implementation material, including law IDs,
role/source checks and arithmetic derivations. Its optional dependency-map
validation and global created-witness cache are not imported as trust rules.
The missing registry and its operation-specific semantics must be resolved
before claiming validated capacity evidence. They are not grounds to skip law
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
