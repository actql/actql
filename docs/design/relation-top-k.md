# Top-k type checking

`relation_typing` checks the closed [top-k](../spec/language.md#top-k) bodies
against a complete Relation schema. These are Relation ranking operations,
not vector-scoring functions. Their checked enum variants remain distinct,
including `top_k_by` with an empty global partition key.

The existing OrderKey and equality-key readers validate all references and
applicable types. Repeated partition and authored order keys are retained;
accessor arrays are detached. Input field contracts and qualified provenance
pass through unchanged. No expressions or provider calls run at this boundary.

Counts are exact positive safe-integer literals or symbolic number Parameters.
`BoundInteger` retains bound-value validation, and `SortOrderCompletion` retains
the requirement to establish a total order without treating repeated keys as
evidence. `TopKPartitioning` retains canonical partition enumeration; empty
input has no representative row. `TopKSelectionEnvelope` retains bounded atomic
selection and publication validation. No checked count is silently turned into
a proven cardinality or permission to truncate input admission.

The common pipeline owns from/as/current resolution and shared budgets. Results
still need their own publication-order evidence. Existing reference paths can
guide lowering, but the AoA partitioned adapter currently rejects empty keys;
it must implement the admitted global-partition behavior without rewriting the
authored operation identity. Execution and AoA adapter changes are not part of
this static checking layer.
