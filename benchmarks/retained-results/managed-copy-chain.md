# Exact-copy derive in checked managed slice chains

The managed take compiler now accepts checked snapshot/ordered bindings when
every expression is an exact input-field or prior-slot copy. The existing finite
view plan resolves these copies through intervening projections and slices.
SQL reads the resolved original source column; unchanged values do not need
another value-admission pass simply because a derive added a copy.

Every binding is inspected, including fields later dropped by projection.
An arithmetic expression such as `1 + 1` or `1 / 0` still rejects this candidate:
the compiler must not silently eliminate a demanded computation or failure.
This is not a general derive compiler. Expression inspection is charged against
the existing bounded metadata allowance. Input validation, per-step obligations,
execution verification and common completion remain separate requirements.

The real DuckDB conformance chain is now derive-copy → take → projection → take.
Its derive fragment is admitted through the existing registry/runtime-fragment
boundary, rather than removing that requirement because the SQL looks trivial.
The fixture verifies retained output and repeated downstream use after upstream
cleanup as before, for empty and nonempty input. Additional independent SQL
vectors check copies between slices and two consecutive derive copies, including
NULL and duplicate values. Negative vectors keep dropped computations rejected.

An initial vector attempted to derive into an existing input field and failed
the existing input-collision rule before compilation. It was corrected to create
a fresh second copy and project it under the desired output name. No language
collision rule was relaxed. This exposed a second fixture integration issue:
the new first-step derive needed a runtime-fragment context, which is now
prepared at step zero for that chain.

Filter/sort integration, general computed expressions, full production Host
selection, metadata reservation and the original large paired performance gates
remain unfinished. This increment demonstrates the exact-copy chain, not those
broader claims. It does not change identity preimages, resource ceilings, or
the adopted managed-profile contract.

Verification: DuckDB adapter tests passed 23/23 on each of JS, Wasm and Native;
all six managed DuckDB/manifest Node integration tests passed. Strict JS and
cross-target public API checks passed, with no public API change. Documentation,
format and diff checks also passed.
