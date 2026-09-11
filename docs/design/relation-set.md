# Complete-row set operation checking

`relation_set.check` implements the static boundary for
[`except` and `intersect`](../spec/language.md#row-set-operations). Both consume
two complete Relation schemas and the closed body `{with, duplicates}`.
`duplicates` is the required literal `distinct` or `all`; it cannot be a
Parameter or an inferred default. Pipeline resolution retains both operand
occurrences, even for the same input, and validates forward/self references.

The schema alignment algorithm is shared with `relation_append.align_schemas`:
exact provenance-aware field sets, recursive compatible domains, and joined
nullability/extents. Missing fields and incompatible recursive contracts fail
at the right-operand reference, retaining the mismatch's field and child path.
No implicit casts or field inference occur. Empty closed schemas are supported;
neither this nor self-input permits deleting the authored operation.

The immutable result retains the operation, multiplicity mode, source, operand
schemas, detached field alignment and output schema. Comparison of complete
typed rows is a separate execution obligation: arrays are ordered, objects use
recursive exact fields, JSON uses canonical value equality and references use
semantic identity. Decimal equality is the common numeric decimal law, not a
precision-tagged hash. This checker does not compute row hashes or execute sets.

`except all` retains the earliest `max(m-n,0)` left occurrences and `intersect
all` the earliest `min(m,n)`. Distinct variants retain the first qualifying left
occurrence. Output order follows the left input and the output bound cannot
exceed its bound. Comparison resources and the right capture's observation scope
remain explicit obligations; absence in that capture is not external absence.
The checker does not promote these obligations to proven keys, order or bounds.

The pipeline evidence layer preserves existing left keys for both multiplicity
policies. For `distinct`, it additionally retains a whole-row uniqueness witness
backed by the exact checked set operation, even without an input key. This follows
the normative one-occurrence-per-equivalence-class rule; it does not discharge
the producer's row-comparison or resource obligations. Joined output contracts
describe this new tuple, while retained left witnesses keep their original,
possibly narrower contracts. Nullable and structural components remain subject
to the separate key-use eligibility rules. Empty rows do not invent a field ID;
their at-most-one property belongs to cardinality evidence. Exact projections
transfer all aliases of each component; losing a component invalidates the tuple.

Work/text/nodes are charged cumulatively across body admission, both input
schemas, recursive alignment and output construction. Deep contract traversal
is iterative. Exact limit tests, recursive extent/nullability cases, provenance,
closed-body failures, detached arrays and pipeline/Result connections run across
all three targets. These are static checking tests, not execution conformance.

`scripts/set-schema.mjs` installs both closed bodies in embedded Program schemas
and updates artifact pins. `check:relation-set` verifies those bodies and pins;
it runs as part of the documentation gate. The surrounding Program schema does
not replace the pipeline checker's exact-one-operation and name-resolution rules.
