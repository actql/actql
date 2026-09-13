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
