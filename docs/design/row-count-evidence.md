# Conditional row counts

`pipeline_typing.row_count` reports a count summary for a checked step. `exact`
distinguishes a known successful-output count from an upper bound; an upper
bound of zero is exact. Unknown input counts and operations without an
implemented count-transfer rule return `None`, never an invented zero.
No API accepts an arbitrary summary as input evidence. Keep the originating
pipeline and target: its checked operands and operations retain the dependencies
and all validation, binding, ordering, profile and resource obligations.

These are static summaries conditional on successful validation and execution,
not observed row counts, source-completeness evidence, resolved capacity limits
or a standalone content-addressed Plan witness. An assertion that fails still
fails atomically; a zero summary does not skip its execution requirements.
Author guards and Host/Contract ceilings are not recast as data cardinality.
They require the separate enforcement and witness-resolution boundary defined
in [resolved limits](../spec/language.md#resolved-limits).

## Implemented transfer

`graph_count` reports separate node/edge summaries; Graph steps still return
`None` from `row_count`. Concise construction bounds distinct edges by its input
row count and endpoint-derived nodes by twice that bound. Explicit construction
bounds nodes and edges from their respective branches; an empty node universe
gives exactly zero edges because endpoint closure excludes them all. Equal-payload
duplicate collapse and explicit endpoint filtering mean nonempty construction
counts are upper bounds, not exact counts. Normalization retains these summaries.
Node/edge projection selects the corresponding extent, while degree/components
emit one row per node. Graph equality emits exactly one boolean row even for
empty inputs. Graph validation and profile obligations are not skipped.
Union and graft bound each extent by the sum of its two operand extents;
overlapping identities prevent claiming an exact sum. Subtraction and induced
subgraph retain input upper bounds rather than exact counts. Property matching
retains the relevant node/edge bound on its Relation output. None of these
rules treats a diagnostic threshold, selector or policy as observed data.

| Checked operation | Count rule |
| --- | --- |
| values | Exact authored row count, including Parameter cells awaiting binding |
| time_series | Its known literal count, otherwise unknown |
| calendar_series | Conservative finite Calendar count bound; equal literal endpoints give exact zero |
| calendar_bucket, derive, select, rename, drop, sort, json_pick, analytic, lag, assert_rows | Preserve count on success |
| filter, distinct, non-global dedupe/group/pivot, partitioned top_k_by, dropping watermark | Retain upper bound, not exact count |
| marking watermark | Preserve count |
| global group/pivot | Exact one, including empty input |
| global dedupe | Zero or one existing row; never synthesize a row for empty input |
| take, top_k, global top_k_by | Apply known offset and clamp to known literal count; unresolved Parameters lose exactness |
| unpivot | Multiply by authored column occurrences, including repetitions |
| unnest | Multiply by known element upper bound; outer expansion uses at least one; otherwise unknown |
| append | Add both operand occurrences, including a repeated target |
| cross_join | Multiply both counts; checked right_rows: one preserves the left count conditionally on that assertion |
| except | Left upper bound |
| intersect | Minimum of available operand upper bounds |
| nest, left asof_join | Preserve left count |
| inner asof_join | Left upper bound |
| inner join/interval_join | Operand product upper bound |
| left join/interval_join | L * max(1, R); preserve the left count exactly when the right upper bound is at most one |
| full join | max(L * R, L + R); an empty side preserves the other side's count |
| semi/anti join and interval_join | Left upper bound; empty right gives exact zero for semi and preserves left count for anti |
| to_events, events, to_vectors, vectors, normalize_vectors, score_vectors | Preserve record count |
| session | Preserve count: label events, do not aggregate sessions into rows |
| watermark_events | Mark preserves count; drop retains only the upper bound |
| dedupe_events | Retain upper bound |
| fixed row_window/window_events | Preserve count, independently of an explicitly supplied step |
| sliding row_window/window_events | Multiply by ceil(size / step) for literal size/step; exact multiplicity only when size is divisible by step |
| pool_vectors | Input upper bound; every nonempty group emits one vector |
| nearest | Query count times min(k, candidate count); exact when both factors are exact |
| text_rank | Query count times min(k, corpus count), upper bound only because zero-score documents are omitted |
| merge_rankings | Sum input-occurrence upper bounds, not exact; empty by additionally clamps the whole output to k |

Authored join cardinality assertions refine the successful-output bounds without
discharging `ValidateCardinality`. For inner joins, unique right keys bound output
by L, unique left keys by R, and both by the minimum of available bounds. Left
joins with unique right keys preserve L exactly; unique left keys alone give
L + max(0, R - 1) when both bounds are known (empty left remains empty). Full
joins with either side unique have upper bound L + R. Empty-side rules remain
stronger and preserve the surviving side's exactness. These are mathematical
consequences conditional on validating the assertion, not automatic uniqueness
inference from the data's size or a permission to skip a failed assertion.
The pipeline combines these per-side assertions with complete candidate-key
coverage of checked ordinary join keys. Its `join_evidence` retains selected
operand-bound witnesses and their original producer/admission requirements;
count transfer consumes the combined uniqueness without erasing either source.

Window multiplicity follows the integer lattice and closed-open membership rule
in [event windows](../spec/language.md#event-windows). When size is not divisible
by step, some times have fewer memberships (including zero when size < step),
so an exact input count becomes an upper bound. Offset shifts the lattice but
not this bound. Unbound size/step leaves the factor unknown; a Parameter default
is not a binding. Fixed windows do not use step for geometry, but still retain
all authored-step binding and validation obligations. Checked boundary arithmetic
and profile/resource resolution remain required even for exact or zero counts.

`relation_typing.row_count_rule` reads private checked metadata in constant time;
it does not copy the operation's field, order or aggregate arrays. Pipeline
derivation is one nonrecursive forward pass with one work-budget unit per step.
Ranking fusion additionally charges one unit per operand to inspect completeness
and, when all counts are known, another unit per operand to accumulate the bound.
Partition arity is read without copying its field list. Repeated ranking inputs
are included in the sum, although their repeated candidates need not emit repeated
rows. With nonempty by, k is per group, not a bound on the entire output. Empty by
is one global group: compute min(k, sum) without overflowing an unnecessary
unclamped intermediate. Unknown operand counts keep this global k bound, but do
not manufacture a finite union bound for partitioned fusion. Rank windows may
reduce participation further; these summaries do not claim the bound is tight.
It respects resolved operand edges and does not deduplicate repeated inputs.
Checked addition and multiplication reject safe-integer overflow with
`RowBoundOverflow` at the step source, rather than saturating or silently dropping
the fact. Zero products remain zero even when the other count is unknown, without
waiving that operand's validation requirements.

The fixed Sketch bound-transfer registry distinguishes preservation, clamping,
addition, multiplication, reduction and carrier-specific laws. This implementation
uses the same distinctions and additionally records exactness where warranted by
the current language. It does not adopt a Host ceiling or physical estimate as
an exact count. Join-key uniqueness can further tighten these conservative
matching bounds. Further Graph structural/query transfers,
validated external count facts and dependency-closed Plan witness
serialization remain shared-evidence work. No execution conformance is claimed.
