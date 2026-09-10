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
fail statically. No arithmetic, search algorithm or provider
dispatch is implemented.

`NearestSource.KeySource` supplies a retained candidate-key collection bound to
its own Relation contract. The pipeline uses that boundary for both sides.
An omitted ID is completed only when exactly one distinct non-null string
singleton-key field remains. Repeated witnesses for the same field count once;
multiple aliases count as different available fields and require an explicit
authored ID. Numeric and composite keys cannot supply this specific implicit
role, although an explicitly selected numeric identity remains valid. This is
the existing nearest completion rule, not pooling's preferred-key selection.
Sketch `87dc7144` uses the same singleton/string filter and distinct-field count.

The completed identity retains its declaration, original fields and admission
obligations, plus a side-specific typed-field completion journal requirement.
Explicit IDs bypass inference and are never replaced by an available key.
Existing Vectors roles remain authoritative. Options, both input completions and
output construction consume one cumulative budget; repeated declarations and
every alias visit are accounted for even when completion proves ambiguous.
The single-Carrier APIs remain available and cannot invent key evidence.

## Grouped vector pooling

The source reader preserves grouping order, method and optional component/identity
output names. Repeated grouping references are rejected because they restore
duplicate output columns, unlike repeated predicate conditions. The closed body
and singleton-only output_id rule are now explicit in Language. This is a
clarification of the output contract, not permission to deduplicate authored
group keys or fabricate a member ID.

The pinned Sketch decoder has the same four source keys; its semantic checker
adds physical id/vector fields and can invent nullable json for missing groups.
Those behaviors are not imported. AoA's grouped pooling requires string record
and group IDs; adapter encoding must preserve the language's semantic identities
and specified numeric law rather than changing source acceptance.

`check_pool_vectors` checks the Vectors alternative and retains member identity
separately from output grouping identity. Group contracts must be known non-null
KeyComparable values, matching the output Carrier invariant; this newly explicit
acceptance rule is narrower than arbitrary nullable Relation grouping. Output
contains group fields, the same component field, member_count and any distinct
singleton output_id alias. Collisions are tested only among actual output fields,
not dropped payload. The constructor shares owned contracts and budgets new work.

Actual global member uniqueness, quantization/fold arithmetic, output count and
order remain obligations. `check_pool_relation` consumes the opaque keyed Relation
from the [key declaration boundary](relation-evidence.md), not a separate schema
and an unverified name list. It retains every input-admission obligation. Single
string keys use their values directly; other scalar keys use the specified
length-prefixed member encoding, including singleton non-string keys. Language
now closes that singleton case explicitly. Reference keys are not silently
stringified, and unknown key types cannot satisfy scalar completion.

`check_pool_keys` accepts multiple independent witnesses and selects the eligible
scalar tuple using deterministic completion. The single-key entry delegates to
the same selection, so both paths sort tuple fields in UTF-16 order and retain
the original declaration separately. A singleton string key has no preference
over an earlier eligible numeric key. No eligible tuple yields
`MissingEligiblePoolKey`, including when all available key types remain unknown.

This resolves the older pooling wording "declared key order" in favor of the
general completion rule. It changes the generated member preimage for a tuple
whose declaration order differs from canonical order; declarations and authored
source are not rewritten. At Sketch `87dc7144`, `completeVectorRecordIdentity`
also selects a preferred key before encoding, but validates scalar eligibility
only after that selection. ActQL filters eligibility first, as its completion
rule requires, so an ineligible preferred key cannot hide a usable alternative.
The original admission tuple order remains available for input validation.

Typed checking retains both the selected tuple and original declaration with an encoding obligation rather than
materializing the reserved physical field in authored row knowledge. Its absence
must be provable before admitting encoded completion; open unknown fields are
insufficient. Member ordering is by completed identity for Relation pooling, not
the original numeric/tuple order, whereas Vectors pooling retains its intrinsic
identity order. The encoded field never appears in the pooled output.

Pipeline `check_with_evidence` accepts `KeyedInput` alongside ordinary
`CarrierInput` values. The keyed wrapper supplies its own Relation contract,
preventing an unrelated schema from being paired with the assertion. Pooling
retains the declaration and its pending admission checks, shares the pipeline
budget, and composes with the explicit `vectors` projection. `check_carriers`
continues to accept Vectors pooling but supplies no candidate-key assertion for
Relation pooling. Keys survive supported unary operations through the checked
transfer boundary, including all surviving aliases of each component. The
single-declaration path is not the completed multiple-witness evidence model;
join cardinality propagation and operation-created keys remain separate work.

## Ranking fusion options

`read_ranking_options` separates max/weighted_sum from reciprocal-rank fusion.
It retains all input occurrences and authored ordering, including repeated RRF
input names and zero-weight occurrences. RRF weight count includes the current
input; its positive total is checked by the existence of a positive finite
weight, avoiding an unnecessary overflowing binary64 sum. Rank window and output
k are independent. Reading options establishes no input score-contract evidence
and does not validate any ranking rows.

The normative owner is [merge_rankings](../spec/language.md#merge-rankings).
The source-options paragraph closes previously unspecified boundaries: empty by
is global grouping, repeated by fields occur once in output, and empty business
tie-break still uses the mandatory final candidate identity. These follow the
existing partition and repeated-condition decisions, not a no-op rule. The fixed
higher-is-better law permits omission or explicit true, never false. Weighted
sum uses binary64 equality to one without the old adapter's epsilon tolerance.
These are explicit decisions; source spelling is retained rather than repaired.

Fixed Sketch `87dc7144138edfcba108cdc59dc485ac976ba976` decodes only two-input
max/weighted_sum, requires nonempty by/tie_break and explicit higher_is_better.
AoA `dbab4fe8c1d624d81ed967f90e2abe742163f84f` pipeline mapping also hashes
semantic IDs and carries a representative payload through score fusion. The
current Language instead preserves semantic identity domains, requires complete
input uniqueness, rejects conflicting business tie-break values and defines a
closed output with new ranks. Those older behaviors are not imported. Searches
of Smooth `55b83448ac44c66c992b2f1c33452b7849e6c3f8` Data Plane operator runtime
and container found no merge_rankings/RRF implementation; this is not evidence
of support elsewhere.

`RankingInput` separates ordinary Relation contracts from `nearest` outputs.
`ranking_from_nearest` binds the row contract, ordered composite identity domains
and producer obligations in one opaque value; a same-shaped ordinary object is
not thereby a semantic identity. The producer remains accessible for discharging
its obligations. `check_ranking_shape` requires complete row types, validates
query/candidate roles and non-null numeric score/rank roles, and checks business
tie-break fields against the authored ordering domain. Nullable query grouping
keys remain grouping values; candidate identity must be non-null. The constructor
does not certify actual rows, input uniqueness, contiguous ranks or score scale.
Checks share bounded work/name budgets and retain owned contracts without
constructing a second contract tree.

Generated machine schemas distinguish all three closed policy forms. Arithmetic
relations between values (weight sum, range endpoint ordering and weights length
versus input occurrences) remain semantic checks, not claims of JSON Schema
coverage.

`check_merge_rankings` consumes ordered `RankingInput` occurrences, aligns query,
candidate and business tie-break value domains, and creates only the specified
output fields. Contract joins widen admissible string bounds/nullability without
converting values; incompatible domains, including different decimal P/S, fail.
Composite identities require producer evidence on both sides in the same tuple
shape. Output tuples retain that evidence through `ranking_from_fusion`, allowing
another RRF stage without treating an arbitrary object as an identity.

For max/weighted_sum, `declare_ranking_score` represents a captured input's
semantic score assertion bound to its immutable row contract and score field.
It is not a normalization operation or a proof obtained by naming a range.
Both input assertions must exactly match the authored contract, and the checker
retains authentication and range-admission obligations. Ordinary Relation inputs
and nearest outputs do not acquire this declaration implicitly. Hosts must bind
the assertion to captured input evidence before execution, not use this boundary
to relabel newly computed scores. Producer handles and their obligations remain
reachable through indexed input accessors.

Whole-input uniqueness, contiguous input ranks, score arithmetic, business
tie-value agreement and output resource envelopes are explicit obligations.
Fusion emits fresh ranks; business payload is not copied. In particular a
weighted result can lie outside the original range because one-sided candidates
receive an absent-side zero. No input score declaration is reused as the output
score envelope; deriving and propagating that envelope remains shared evidence
work.

Pipeline fusion keeps the current ranking first and each authored with occurrence
after it, with separate `Sample(index)` edges even for repeated targets. Options
are admitted once; reference resolution and typed fusion debit the remaining
shared budget. `RankingInput` in `check_with_evidence` supplies captured score
declarations. Nearest and fusion producers supply their bound identity domains
directly, supporting repeated RRF composition. Ordinary input columns do not
silently acquire score declarations. Diagnostics retain the failing source path
and span.

`transfer_ranking_unary` preserves value-domain and declared-score annotations
through supported row-preserving/subsetting operations. Projection transfers all
aliases; dropping one alias does not erase another. Derive overwrites invalidate
the affected annotations even when the replacement has the same type. Whole-row
distinct preserves them. Other operations currently clear these annotations.
The checked operation must use the exact bound input schema, not an unrelated
equal schema. Maps distinguish qualification from an unqualified dotted spelling.
Score aliases point back to the original captured declaration, row contract and source field;
they do not rewrite that declaration or perform normalization.

Pipeline caches each step's transferred annotations once and charges the work
and names to its shared budget. A retained producer does not certify that the
current rows still have contiguous ranks: filtering may leave gaps, and RRF must
validate its complete current input before applying rank_window. Order/uniqueness
witnesses, cross-family transfers and derived output score envelopes remain
unfinished shared evidence work.

## Pure lexical ranking

`read_text_rank_options` admits the closed body specified by
[text_rank](../spec/language.md#text-rank); `check_text_rank_inputs` checks its
roles on the corpus and query Relations. Identity and text roles require known
non-null strings. Other payload fields may remain unknown: the language does not
require a complete payload schema for this operation. Role declarations impose
whole-input uniqueness checks; known string types alone do not prove uniqueness.
BM25 constants and k are explicit, with no tokenizer, scoring or ranking defaults.

Output consists only of typed query_id/candidate_id and non-null number score/rank.
Identity contracts are retained without encoding IDs as strings from other types
or hashing them. Contiguous positive ranks, canonical ordering and the bound
query_count * min(k, corpus_count) require their execution/resource checks.
Pipeline query edges retain their target separately from the current corpus;
`ranking_from_text` preserves the producer and its obligations for RRF. It does
not declare lexical scores comparable with arbitrary vector scores.

The checker records Unicode NFKC/full-fold/tokenization, actual-input corpus
statistics, correctly rounded logarithms, exact fold order, empty-input guards,
non-finite rejection and separate token/statistics/scoring/output ceilings as
obligations. This implements no tokenizer or BM25 evaluator. Resolving the pinned
text-rank profile and its numerical/tokenizer vectors remains shared profile work;
MoonBit type-check tests are not numerical conformance evidence.

Fixed-revision searches found no text_rank implementation in Sketch
`87dc7144138edfcba108cdc59dc485ac976ba976` (src and moonbit/src), no text_rank/BM25
in AoA `dbab4fe8c1d624d81ed967f90e2abe742163f84f` packages, and none in Smooth
`55b83448ac44c66c992b2f1c33452b7849e6c3f8` Data Plane operator-runtime/container.
This operation follows the current normative language rather than borrowing
external index statistics or a library-specific BM25 variant.

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
