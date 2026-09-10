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
| to_events, events, to_vectors, vectors, normalize_vectors, score_vectors | Preserve record count |
| session | Preserve count: label events, do not aggregate sessions into rows |
| watermark_events | Mark preserves count; drop retains only the upper bound |
| dedupe_events | Retain upper bound |
| fixed row_window/window_events | Preserve count, independently of an explicitly supplied step |
| sliding row_window/window_events | Multiply by ceil(size / step) for literal size/step; exact multiplicity only when size is divisible by step |

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
It respects resolved operand edges and does not deduplicate repeated inputs.
Checked addition and multiplication reject safe-integer overflow with
`RowBoundOverflow` at the step source, rather than saturating or silently dropping
the fact. Zero products remain zero even when the other count is unknown, without
waiving that operand's validation requirements.

The fixed Sketch bound-transfer registry distinguishes preservation, clamping,
addition, multiplication, reduction and carrier-specific laws. This implementation
uses the same distinctions and additionally records exactness where warranted by
the current language. It does not adopt a Host ceiling or physical estimate as
an exact count. General join cardinality, ranking and Graph transfers,
validated external count facts and dependency-closed Plan witness
serialization remain shared-evidence work. No execution conformance is claimed.
