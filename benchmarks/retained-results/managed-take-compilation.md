# Checked managed take/projection SQL

The native take/projection fixture now uses a product compiler instead of its
handwritten SELECT. The compiler accepts an exact managed receiving use and
checks a consecutive, single-input take/projection path. Count and offset come
from bound checked kernels, projected names come from checked column mappings,
and identifiers are quoted with bounded UTF-8 SQL construction. Preparation
retains the exact input binding; another use of the same material is not the
same binding and revocation invalidates eligibility.

The Host must bind the hidden physical ordinal to the **existing proven
logical input order**, with one distinct zero-based occurrence per row. SQL
compilation does not establish that binding, pin, authority or execution.
An authored field cannot shadow the hidden ordinal, and the output occurrence
alias cannot shadow a projected field. A take requiring candidate-key order
completion is unsupported by this realization rather than silently using
physical order. Another suitable implementation may fulfill that contract.

Identifier collision checks use DuckDB's ASCII case folding. ORDER BY qualifies
the physical ordinal through a private table alias, so renaming a projected
value to `rowid` cannot redirect ordering to that output value. A native
rename vector verifies this distinction rather than rejecting the valid rename.

Expected selection metadata is derived from the checked count/offset and exact
input row count, bounded before row-map allocation and independent index
construction. Large safe-integer offsets/counts are compared in Int64 before
narrowing to the available Int row count. Expected occurrences are not proof
that the native query executed them; the adopted verifier still compares the
actual execution to the required mapping.

The real DuckDB vectors cover prefix selection, one row after offset one,
maximum-safe-integer count after offset two, and an offset beyond the input.
They compare fixed expected contents and occurrences, including duplicate text,
NULL and empty input. Identifier quoting, NUL rejection, alias/ordinal shadowing,
SQL capacity and selection metadata limits are checked separately. The existing
through-Host path still retains output independently, reclaims the ancestor,
and admits two downstream consumers from the new receipt/index.

This closes the handwritten SQL gap for this finite take/projection shape, not
the whole managed pipeline. The derive SQL remains fixture-specific. General
operation composition, production representation-order binding, demanded
expression/diagnostic integration, Local and delegated lifecycle, physical
metadata reservations and original paired large-case gates remain outstanding.
No legacy identity, contract pin, 1 GiB limit or performance criterion changed.

Verification: the adapter passed 23 tests on each of JS, Wasm and Native;
query_integration passed 275 on each target. All six native Compute/manifest
tests passed, including the generated SQL vectors and ancestor-reclamation
path. Strict JS check, three-target API generation, documentation and formatting
checks passed. This is correctness/integration evidence, not a large-case timing
or final acceptance result.
