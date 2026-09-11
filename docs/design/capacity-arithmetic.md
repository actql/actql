# Capacity arithmetic

`capacity_arithmetic` implements the numerical domain shared by conditional
count inference and the pending bound-witness verifier. The normative owner is
[resolved limits](../spec/language.md#resolved-limits). This package does not
produce a bound witness, authenticate a source, resolve a policy or authorize
execution.

`Value` is opaque and immutable. `read` admits exactly the nonnegative integers
through 9,007,199,254,740,991. Zero is valid for data bounds; the independent
positive-value requirement for author guards belongs to guard admission.
Addition and multiplication reject overflow before performing the operation.
They use integer subtraction and integer quotient tests, not rounded binary64
arithmetic. Minimum and clamp return only a numeric result. In particular,
minimum does not deduplicate equally valued witnesses, and clamp does not
claim its maximum was enforced. Each call has constant work and storage.

Pipeline sum/product count transfer uses this arithmetic and preserves its
existing source-local `RowBoundOverflow` diagnostic. Unknown counts remain
unknown; a proven zero factor still yields a zero conditional output count.
No ceiling becomes a data bound through this connection.

The fixed Sketch reference `src/actql-bounds.ts` separates safe-bound arithmetic
from witness and resolved-limit construction. The same separation is retained
here; the reference's global created-witness cache and optional dependency-map
validation are not a validated external-evidence boundary to copy. This is an
implementation choice under the existing contract, not a change in acceptance.

## Remaining witness integration

The [derivation consistency checker](capacity-derivation.md) now recomputes a
bounded nonrecursive dependency graph using this arithmetic. Its result remains
numerical consistency, not authenticated bound evidence.

The next boundary must resolve source bodies and derivation dependencies,
validate their identities, units, role/source pairs and governing laws, and
recompute the closed derivation. Checking an arithmetic result alone cannot
establish those properties. Source admission and an enforced-ceiling derivation
need their own validated evidence; neither can be manufactured from a number.
Candidate selection must retain distinct evidence even when values coincide,
record author-guard binding, and bind enforcement to the exact consumer.
Dependency traversal and candidate collection require cumulative work/size
limits even though each arithmetic operation is constant-time.

Full witness closure, external fact admission, resolved-limit serialization and
whole-pipeline discharge remain open in the
[completion audit](pure-operation-audit.md). Passing the arithmetic tests does
not establish those boundaries.

## Regression evidence

All targets execute exact small-integer addition/multiplication, safe-integer
addition endpoints and 4,095 integer-quotient multiplication boundaries in both
operand orders. Tests also cover invalid signed 64-bit endpoints, zero products,
overflow, minimum and absent-input clamp. Existing pipeline tests independently
cover count propagation and source-local overflow diagnostics. Expected values
use exact integer arithmetic, not the product's output or a floating-point
oracle.
