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

### Original query invocation time

The zero-child CurrentTimestamp expression retains its authored operation.
An optional opaque QueryEvaluationTime belongs to the original expression
frame and carries the existing Run owner's checked Timestamp; the evaluator
does not accept a timestamp String or a sampler callback. A demanded leaf
without that context refuses. An undemanded lazy branch performs no clock
read. The shared result event accounts for the borrowed checked value and its
result root, and frame closure drops its context reference separately from
escaped values and physical cleanup.

The checked typing traversal records whether any declared expression node
requires query time, including lazy branches. The bounded preparation getter
uses the existing typed expression-slot inventory across all Carrier consumers;
it does not scan text or JSON keys, and budget exhaustion never means false.
Static compilation can retain that declared dependency, while actual Source
binding and dispatch still require the same original preparation and admitted
Run. No scope, clock authority or resource grant follows from the flag.

### Exact Decimal quantization

QUANTIZE retains one checked Decimal child and the original closed rounding
mode in the existing expression frame. Its result contract supplies precision
and scale. Bounded integer coefficient division selects an exact quotient and
remainder; half-even tests quotient parity, half-up selects magnitude ties
away from zero, and directed modes respect the original sign. Coefficient
zero is canonical and result overflow fails before Value publication. No
binary64 conversion or altered Decimal identity is involved.

The admitted 38-digit/scale bounds limit integer scratch to at most 128 bits.
Upscale overflow is rejected before multiplying, and smaller target scales use
an exact power of ten. The fixed transform preflight covers representation
passes and bounded arithmetic; 32 structural scratch entries are reserved
before allocation and released on both conversion outcomes. Those entries are
not a physical byte grant. Original operand/root, mode String, integer records
and limbs, coefficient String, formatter and result overlap under the existing
phase. Child/current/cancel, logical charging and original-root release remain
owned by the original evaluator; NULL propagation does not catch those errors.

### Explicit exact Decimal division

DECIMAL_DIVIDE reuses the existing eager binary child order, consume events and
root-release protocol. The private binary event receives the original frame's
workspace only for the typed Decimal ratio branch; all previous operator paths
retain their original behavior. The left is an admitted Decimal, the right an
admitted Decimal or an exactly read safe-integer Number. Both child failures
remain demanded before NULL propagation, and zero division fails without
publishing a value. Shared private quotient/remainder rounding preserves the
same five modes as QUANTIZE; neither operation passes through binary64.

For scales 0..38, the target adjustment exponent is -38..76. The numerator is
less than 10^114 (at most 379 bits), and the denominator less than 10^76. The
rounded quotient is compared to 10^precision before formatting, so an overflow
never constructs a 114-digit public coefficient. Parse/power/ratio/rounding,
mode and contract references, both operand roots, integer limbs and loop
temporaries, formatter and final value overlap under the existing phase.
The 64 structural scratch entries and bounded control preflight are not a
physical byte grant; logical retirement and GC are not cleanup ACKs. Original
Value identity, wire schemas, clock domains and authority are unchanged.

### Existing Decimal addition, subtraction and multiplication

The checked binary expression's existing Decimal result contract supplies the
precision and scale for these operations. The eager frame still demands both
original children, charges their consumption and releases their individual
roots. Only the typed Decimal branch uses exact signed integer coefficients;
the context-free Number evaluator, SAFE operations and mixed-domain refusals
retain their meanings. NULL propagation does not suppress child failures.

Addition and subtraction align coefficients at the original maximum scale;
multiplication keeps the sum of the original scales. Neither operation rounds.
Admitted coefficients have at most 38 digits and alignment adds at most 38
places. Aligned magnitudes and products are below 10^76; a sum's magnitude is
below 2*10^76. The result is checked against the original precision before its
coefficient is formatted. Zero is canonical. The existing structural workspace
reserves 64 scratch entries and a bounded control preflight before integer
work; these are not physical byte admission. Both operands, temporary integer
limbs and powers, formatter output, result and root aliases can overlap under
the existing phase. Scratch release is distinct from logical-root retirement
and physical cleanup acknowledgement.

### Original String TRY_NUMBER occurrence

The ordinary checked Program preparation binds its local Stage's opaque
expression closure to the same prepared pipeline and original Parameter binding.
An equal source document, contract, profile CID or separately checked binding
cannot replace that original. Empty closures retain the previous preparation
path. Lowering discharges only the String TRY_NUMBER envelope occurrence it can
find at the same typed node and semantic step; unsupported envelope operations
remain pending at their existing boundary.

The lowered expression retains its original text bound and policy. Fragment
construction projects every such occurrence from those same typed roots, with
source and machine-node pointers, argument and input-evidence CIDs, semantic
step and original demand path. It emits the existing closed envelope and its
self-CID, sorted by UTF-16 source pointer. Admission regenerates the complete
array; a matching digest or omitted envelope cannot supply another occurrence.
The retained request includes that same complete policy, without issuing Host
capacity or operation authority.

The existing expression frame demands the original child once. A demanded
String first receives a complete scalar/UTF-8 extent check against its retained
input bound, including text that is invalid at its first character. It then
uses the existing Number lexeme and finite Number reader. Only conversion-domain
failure becomes NULL; child, control, input-bound, engine and root failures keep
their original error paths. An undemanded lazy branch does no input preflight.
The admitted Number identity branch remains an ordinary scalar operation and
needs no String parsing envelope.

The closure and selected pipeline/Parameter aliases, node-resolution map,
policy/input/output bound chain, canonical root and argument trees, envelope
writers/hash/cursors and emitted artifact overlap under the existing preparation
and execution phases. String operands, parser workspace, result and root aliases
remain subject to those owners' logical and physical limits. Dropping these
references is neither a physical cleanup acknowledgment nor numerical funding.
