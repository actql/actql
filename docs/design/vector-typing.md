# Vector operation checking

The checker supports `normalize_vectors` and `score_vectors` on Vectors,
retaining semantic identity, dimensions and partial payload contracts. The
normative owner is [vector bridges](../spec/language.md#vector-bridges).
The explicit `vectors` bridge exposes the resulting fields to Relation consumers.

Query arrays are owned; accessors return copies. Parameter queries retain their
name and any declared exact length, never a default value. Binding, dimension
validation, component arithmetic, uniqueness, profile/resource resolution and
score ordering are separate pending obligations, not execution permission.
The checker does not quantize, normalize, score or sort actual vectors.

Source traversal and output construction consume shared work, node and text
budgets; pipeline consumers debit the reported usage. Diagnostic paths and spans
survive pipeline wrapping. No recursive traversal of payload contracts is needed
inside this checker: those contracts enter through validated Carrier boundaries.

## Fresh score decision

The reference score adapter overwrites a payload field named `score`. The
language now explicitly requires a fresh field, consistent with generated-column
collision checks elsewhere. This is a new acceptance decision, not a claim that
the old adapter enforced it. It prevents data loss and requires proof of absence,
so an open or opaque record cannot be scored by this static boundary. An unknown
payload type in a closed field set is still retained without inventing `json`.
Repeated scoring requires an explicit bridge/reshape rather than silent overwrite.

Normalization preserves an existing score as payload, but does not refresh its
meaning. Score provenance and order proofs must not be inferred from a field name.
No evaluator or lowering adapter is implemented by this package.
