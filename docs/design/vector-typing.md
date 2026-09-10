# Vector operation checking

## Exact nearest-neighbor checking

`read_nearest_options` admits the closed authored body and preserves optional
ID/vector references independently for the candidate and query sides. It does
not manufacture missing roles, a metric or an exactness flag. The corpus is the
pipeline's selected input, never a second body-level reference. Query names are
not sigil-stripped. The positive safe-integer literal k follows the fixed
reference checker and bounded rank contract; Parameter counts are not introduced
by this reader.

The pinned Sketch checker validates Relation/Vectors alternatives but restricts
Relation identities to string primary keys; AoA's knnJoin also requires nonempty
string IDs and returns no public rank. Those limitations cannot replace ActQL's
semantic identity restoration or contiguous one-based rank requirement. Candidate
key evidence is needed for permitted implicit ID completion, not a name heuristic.

`check_nearest_input` resolves explicit Relation roles without requiring a complete
payload schema. It can complete the vector role only from the sole known vector
field in a closed field set and retains that completion for journaling. An ID
cannot be guessed without candidate-key evidence. Vectors retain their existing
ordered identity tuple and component role; optional authored names may restate,
but not replace, those roles. This resolves an unspecified override boundary by
preserving the Carrier's semantic identity instead of silently changing it.

`check_nearest_pair` admits both sides under one cumulative source/work budget
and rejects a known dimension mismatch at the query vector option (or query
reference when that role is implicit). Relation/Relation, Relation/Vectors,
Vectors/Relation and Vectors/Vectors use this same boundary. Exact scoring,
quantized component admission, global ID uniqueness, semantic identity restoration,
contiguous rank and canonical query/candidate order remain separate obligations;
field completions retain side-specific journal obligations.

`check_nearest` adds the four-field output Relation. Scalar identity contracts
remain scalar. A composite ID becomes a closed record with position keys `0`,
`1`, etc. and separately typed component contracts. Language fixes this new
public representation: position keys avoid alias-dependent identity, support
heterogeneous and reference components without a new general tuple value type,
and do not stringify or hash the ID. Comparison must still use the retained
ordered Carrier identity components, never the record's JSON key order.
Ordinary object ordering is not broadened. Ranking consumers need this provenance
before claiming tuple comparability. Positive contiguous rank and exact scoring
remain explicit obligations rather than facts inferred from the number contract.

The pipeline retains corpus/query edges separately, resolves queries in the exact
available namespace and advances current to the ranking Relation. No second
corpus reference can replace the selected step input. Opaque Vectors preserve
unknown ID contracts as untyped known output fields, not json, and retain role
binding and dimension-match obligations before scoring. Known mismatches still
fail statically. Candidate-key-backed ID completion and ranking evidence
propagation remain to be connected. No arithmetic, search algorithm or provider
dispatch is implemented.

## Existing vector preparation and scoring

The checker supports `to_vectors` from Relation and `normalize_vectors` and `score_vectors` on Vectors,
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

## Explicit input bridge

The Relation bridge validates only the selected semantic roles and shares the
already-owned payload knowledge. Unknown payload types or an open field set do
not invalidate otherwise known roles. Unknown, nullable or incompatible role
types do fail at the specific source option. Qualified references preserve join
provenance instead of flattening the schema.

The reference bridge restricts IDs to strings and adds physical `id`/`vector`
columns. This implementation follows the semantic Carrier boundary instead:
non-null KeyComparable identity values and authored role names are retained.
The expanded identity domain is an explicit language decision; incompatible
backend adapters require work before execution support can be claimed.
