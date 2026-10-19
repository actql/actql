# Resumable expression frames

Expression scheduling and scalar semantics have different responsibilities.
A package-private expression frame retains the continuation stack, active
checked expression and temporary-root lease across semantic transitions.
Advancing it performs the same entry, operand, result and lifetime actions as
the synchronous expression evaluator. The synchronous wrapper advances the
frame until completion; it does not define a second evaluator.

The ordinary synchronous path drains that same transition loop within one
call. A suspended caller takes one transition per call. Draining does not defer
charges until the end: each transition checks control, logical work and root
lifetimes in the same order before advancing. Both modes share terminal result
detachment and cleanup. Binary events consume the left then right operand and
release left then right roots without requiring temporary iteration arrays.

Suspension is not completion and is not permission to reorder logical rows,
bindings or expression children. The enclosing Relation operation still owns
that ordering and complete-input admission. A different evaluator must also
preserve logical-limit failures, not just choose the smallest value failure
after speculative evaluation.

## Ownership and termination

Input snapshots and preceding slots are borrowed for a frame's lifetime.
Temporary expression roots belong to its scope. A successful terminal
transition detaches exactly one result root for the caller; closing the frame
does not release that result. Failure closes temporary roots and poisons the
shared logical budget. Explicit cancellation closes temporary roots without
refunding accumulated work or releasing borrowed input/slot roots.

A closed frame cannot advance again. This prevents replaying a scalar result
or handing out its root twice. Closing is idempotent; the continuation stack
and temporary result reference are cleared. Control/workspace limits remain
the caller's budgets and do not reset across suspension.

## Physical execution boundary

This frame boundary is not a vectorized kernel, a typed-column input API or a
chunked Relation implementation. In particular, the synchronous row path still
uses value snapshots. Merely calling it once per chunk cannot demonstrate
typed-batch support. A typed-batch strategy must establish its own supported
operation range before evaluation, reuse demand and lifetime rules, and must
not fall back after an execution error or exhausted budget.

Frames carry no wire identity and do not change checked expressions, semantic
contracts, Program admission or publication. The enclosing operation retains
failure atomicity regardless of whether its private computation is suspended.

## Shared semantic events

Frame transitions and a bounded alternative kernel can share entry charging,
operand consumption, scalar binary operations, condition selection, result-root
retention and release through package-private expression events. These events
run before the corresponding construction or selection; they are not a replay
of accounting after computation. Condition selection consumes and releases its
condition before the chosen child is evaluated. Forwarding a chosen result
preserves its root and the existing consumption charges.

The enclosing row lifetime has a separate shared event: retain the complete
output root, release produced slots, then release the input root. A physical
output builder follows this event. Replacing the builder or typed slot storage
does not move the logical release boundary or make pending output public.

An alternative strategy must declare its complete supported operation before
running it. Unsupported shapes select the ordinary evaluator before input
evaluation. Neither a value error nor a resource error permits retry through
another strategy. Typed slot storage and branch masks do not imply speculative
or parallel evaluation: retaining canonical row/slot scheduling is a valid
bounded implementation and avoids choosing failures after the fact.

## Fixed-unit temporal differences

`date_diff` retains its three original ordered children in the ordinary
expression node and eager frame, including the admitted literal unit. NULL
propagation does not skip a demanded peer or its failure. The frame holds all
operand values and root leases until the result is computed, charges their
original bytes, and releases them through the existing expression lifetime.
Its child views and three value/lease pairs use the same workspace accounting
as other eager operations; no alternate evaluator or Host time source is used.

Date operands use whole days only. Timestamp operands use the existing Value
owner's canonical UTC seconds and nanosecond remainder. Subtraction normalizes
that pair before dividing by the fixed authored unit, truncating the quotient
toward zero. It never forms an epoch-nanosecond Int64 or converts an input
instant through binary64. The admitted calendar bounds the final integral
quotient below 2^53, so conversion to the existing Number result is exact.

An instant one nanosecond before the epoch therefore has a zero public
millisecond difference while still being earlier under exact comparison and
internal event-clock classification. This public result does not replace the
exact event-clock projection or broaden trusted-now, expiry, rollback or
cleanup clocks. Civil/offset domains and dynamic clock material remain separate
existing implementation responsibilities.


Fixed `date_trunc` uses the existing eager binary event path with the original
unit and temporal value roots. Both are consumed once and retained through
conversion, then released by that same event. The existing Value owner reads
and formats bounded UTC seconds/nanoseconds, and checks the generated value
against the original typed result contract's non-null refinement before normal
expression output admission. Date day-only truncation preserves its value.
Negative instants use the containing fixed UTC bucket; no binary64 timestamp,
epoch-nanosecond Int64, Host Date or operational clock is introduced. Formatter
workspace, contract/value records and input/output aliases overlap; logical
root retirement is not physical cleanup acknowledgement or phase funding.

### Exact fixed-unit temporal addition

DATE_ADD shares the existing eager three-child temporal frame with DATE_DIFF.
The frame retains the original timestamp/date, evaluated Number and unit roots
through the result and charges their existing logical/control owners. Amount
expressions still round under ordinary Number laws. The resulting bits select
an exact signed significand/exponent duration; conversion does not multiply the
unit in binary64 or reinterpret a shortest decimal spelling. Nonintegral
nanoseconds and calendar overflow fail through ArithmeticFailure.

A loose calendar-width guard bounds all integer scratch before allocation.
The significand/unit product stays below 100 bits; divisibility is checked with
trailing-zero count before a right shift, so tiny subnormals do not allocate an
unbounded denominator. Whole seconds and a signed nanosecond remainder preserve
the full calendar without an epoch-nanosecond Int64. Fixed structural workspace
is reserved before integer and formatting scratch; those slots are not physical
byte capacity. Generated calendar values return through the original Value
owner and the original result contract. Timestamp/Date value identities, Run
clocks, ordinary DATE_DIFF and physical authority remain separate.

### Nullable exact Decimal conversion

TRY_DECIMAL uses one existing child frame and a dedicated continuation with the
same expression/child references as CAST. The original checked nullable Decimal
contract supplies precision and scale. It reuses CAST conversion work, variable
operand preflight, logical charges and original-root release; only the final
unrepresentable-conversion result becomes NULL. Child, control, logical and
workspace failures leave through their original errors before this boundary.
No general error catch or frontend conversion is introduced. Cancellation
retains caller input and releases only the frame's temporary holdings. Conversion
scratch and original operand/result aliases overlap under the existing phase;
a slot bound or logical release is not physical byte capacity or cleanup ACK.
