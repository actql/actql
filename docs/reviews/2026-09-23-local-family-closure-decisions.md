# Local Compute family closure: agreed decisions

Baseline: `8cae50b6c6c3d9ae5c5cf215e5820358d94b59fe`.

This document records agreed implementation semantics and acceptance scope.
It is not evidence that the implementation, tests, or Linux CI have passed.
Later changes on `main` do not silently change this baseline or inventory.

## Meaning decisions

1. Window membership is computed exactly. Decimal and large timestamps are
   not rejected as classes. If a boundary that the language requires in the
   output cannot be represented exactly in binary64, report the existing
   arithmetic error. Rounding a boundary must not change the window width or
   membership. An internal intermediate outside binary64 is not by itself a
   reason to reject a representable result.
2. Shortest path minimizes depth among eligible simple paths. Apply the
   predicate and hop conditions before minimizing. Finding an ineligible
   shorter path must not terminate the search for an eligible longer path.
   `emit: nodes` and `emit: paths` use the same eligibility rule; existing
   tie-breaking remains in force.
3. Relation and Events grouping use the canonical typed group-key order.
   Compare compound keys component by component, with the specified NULL
   placement and type-specific comparison. Neither CID order nor JSON text
   order is a substitute. Representative-row and tie rules remain unchanged.
   Carrier-to-Relation Bridge paths must preserve this meaning.
4. Structural pairwise `number_mean` computes the exact mathematical average
   of its two finite binary64 operands, then rounds once to binary64 using
   round-to-nearest, ties-to-even. Apply the existing zero-normalization rule.
   Independent vectors cover large magnitudes, opposite signs, subnormals,
   and halfway cases. This does not change `number_sum` overflow or the
   meaning of a multi-input mean.

For each changed meaning, update the language specification, applicable
machine contract and dependency pins, independent vectors, product code, and
regressions together. Do not introduce a narrower domain merely to satisfy
existing tests.

## Closure scope

- Close RelA, SGA, VecA, TEA, and formal Bridges through ordinary Program and
  standard Host paths, not just isolated kernels.
- Reconcile historical review findings against the fixed baseline. Record
  resolved, unresolved, and normative-decision cases with evidence; do not
  reimplement resolved fixes.
- Cover typed Graph ordering, nullable labels, compatible values, diff/apply,
  mean demand and numeric rules; VecA empty-side admission; TEA identity,
  windows, and ordering; mixed Carrier/Relation Stages, including prefixes
  without a standalone provider; in-flight cancellation; nested cleanup;
  per-operation resource evidence; and shipping family composition.
- Use the existing MoonBit Engine accounting and execution-control
  primitives. Do not duplicate the scheduler, ledger, retry state machine, or
  storage engine in Local code.
- Verify JS, Wasm, and native semantics; principal variants with real
  consumers and formal Bridge consumers; mixed-Stage Host execution;
  Relation publication; failure, cancellation, stop, cleanup, and final
  reclamation. Release evidence must link product entrypoints, independent
  expectations, executed suites, and an exact SHA.
- Keep source comments, new documentation, and commit messages in English.
  Commit-message lines must be at most 72 characters.

## Authority and completion

Local implementation and local tests may proceed in the dedicated worktree.
Push has not been authorized. Do not claim origin/main publication or Linux
CI success for the new SHA until independently observed. A local feature
implementation and an integrated merge-ready result are separate states.
