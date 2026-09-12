# Resumable expression frames

Expression scheduling and scalar semantics have different responsibilities.
A package-private expression frame retains the continuation stack, active
checked expression and temporary-root lease across semantic transitions.
Advancing it performs the same entry, operand, result and lifetime actions as
the synchronous expression evaluator. The synchronous wrapper advances the
frame until completion; it does not define a second evaluator.

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
