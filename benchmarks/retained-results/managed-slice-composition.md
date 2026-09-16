# Bounded composition of managed selection chains

The managed take compiler now accepts consecutive checked projection/rename
and take steps, with at least one take, instead of exactly one take followed
by one projection. It composes the finite column-origin mapping through the
existing managed view plan and reduces contiguous row selections to one
interval. Unsupported operations and candidate-key order completion remain
explicitly outside this realization; no operation is silently omitted.

Composition spends bounded step/entry and name inspection budgets. Count and
offset stay in Int64, and addition saturates beyond the exact managed input's
Int-sized row domain. An already empty selection stays empty. Expected row-map
allocation and copied index size are still bounded separately. The SQL source
columns refer to the original receiving view, not intermediate aliases.

Per-step `(limit, offset)` is retained as conditional slice metadata. It is not
an exact output row count, an executed predicate, or discharge of intermediate
guards or logical charges. Compilation is only an implementation plan. An
installed Host must still establish applicable per-step obligations, source
order/physical binding, current use authority, retention and common completion.
Fusion is not permission to erase obligations or reset a remaining ledger.

The native through-Host fixture now includes four checked steps: rename by
projection, take three, rename back, take two. The generated SQL preserves
duplicate/NULL values and exact occurrences. Its output has zero repeated value
admission, an independent occurrence index and the same full input/final-output
measurement as the existing prefix-selection path. After the original physical
material is reclaimed, two downstream consumers reuse the resulting evidence.
All selected rows satisfy the fixture's bounded per-step requirements; this is
not a universal intermediate-diagnostic resolver.

Independent real DuckDB vectors also cover composed offsets, truncation before
a later skip, take followed by projection, huge safe-integer offsets, and empty
input. Projection-only and filter-containing paths remain rejected by this
compiler, not by the language or the complete planner. The ordinary validated,
single-selection and computed-column regression paths remain in the same test.

General filter/sort/derive composition, production obligation resolution, Local
and delegated lifecycle, physical metadata accounting and formal paired large
measurements remain required. No new profile capability, legacy identity,
1 GiB resource ceiling or performance acceptance threshold is changed here.

Verification: native Compute/manifest tests passed six cases, including the
four-step complete/retain/reuse path and composed SQL vectors. Adapter tests
passed 23 on each of JS, Wasm and Native. Strict JS, three-target API generation,
documentation and format checks passed. No timing acceptance claim is made.
