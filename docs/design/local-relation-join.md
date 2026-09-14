# Local Relation inner join

## Checked preparation and execution

An inner join is a binary `PreparedStep`, not a unary expression kernel.
Its owner and ordered input occurrences come from the same checked pipeline.
Two occurrences may name the same predecessor without becoming one logical
input. The prepared profile retains every authored equality pair and projection
alias, the null-key rule, the cardinality assertion and the bound output guard.
It does not infer uniqueness from observed row counts or construct new proof.

The emitted operation is `REL.join` followed by the checked `REL.select`
projection. The internal execution can construct the projected payload directly,
but still checks the joined row-count guard before any following aggregation.
Direct key comparisons are not invented expression-demand roots.

The sequence driver resolves both retained input slots and passes immutable
readers to the join implementation. The implementation verifies exact checked
ownership and both input identifiers. A stable right-side index and per-left-row
lookup preserve left-major/right-minor output order, including duplicate pairs.
Scalar equality reuses the engine comparator, including exact decimal comparison;
serialized keys and content CIDs are not equality substitutes.

## Validation and resources

The `fail` null-key rule inspects both inputs even when the other is empty.
Cardinality assertions inspect the required side independently of whether its
keys match the other side. Under `no_match`, null-containing tuples do not join
and are excluded from match-key uniqueness checks. Comparison failures preserve
the scalar diagnostic. These physical checks do not replace source admission or
the validation of upstream candidate-key evidence.

Key indexes, coordinate pairs and projected rows use the existing operation
workspace. Allocations are bounded before construction; failure releases this
operation's scratch without refunding spent work. Every projected output value
passes the existing retained-value accounting. Successful tables pass through the
same store commit and final sequence-completion boundary as unary results.

The captured DAG can bind two exact producer/target/input ports to this Local
binary step and retain both parents' allocations until their last retained
descendant closes. A self join has two logical ports but only one parent token.
Join and subsequent count remain separate completed Computes. The
[DuckDB adapter](duckdb-relation-execution.md) supplies fresh-import and resident
realizations of this checked profile. The
[physical strategy](physical-strategy-execution.md) accounts for both input
ports, potential pairs, transfers and retained results; resident reuse discounts
only shared physical imports, not logical input validation.

## Fixed producer input ports

The fixed-input execution boundary accepts producer reads in checked input-port
order. Every read retains its exact receiving owner and port; repeating a binding
for one port cannot satisfy another port. Two distinct bindings may share the same
completed backing storage without copying or re-admitting it during preparation.
Execution still uses ordinary producer admission and checks upstream liveness.

The common row ceiling applies independently to each input and the retained
output. Value measurement uses one cumulative physical measurement budget across
all input occurrences and output. Shared physical storage does not discount
logical input occurrences. The existing single-input entry points delegate to
this execution path; they do not maintain a separate evaluator or guard ledger.

`FixedComputeRequest` snapshots these handles in checked port order and retains
the exact receiving preparation and selected common capacity. Missing, duplicate,
reordered, foreign-owner or unavailable inputs cannot create a request. The
registered Local candidate passes the full input inventory to guarded execution;
candidate recovery does not bypass liveness checks at execution time. A backend
whose compiler does not yet support the input shape rejects it before cost
comparison, rather than proposing a candidate that fails after selection.

For the captured DAG, the join output limit is the exact existing capacity
application owned by the CheckedProgram's stage context. The execution boundary
retains that claim and narrows only the corresponding join output. It does not
replace the selected claim with a caller-supplied execution limit, reduce either
input's row allowance, or postpone fanout checks until a downstream count. An
additional execution ceiling can only tighten an existing ceiling. This is a
physical enforcement attachment, not a rewrite of the authored operation or CID.
