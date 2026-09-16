# Checked filter occurrence SQL

`managed_fixed_selection_sql` adds a source-occurrence output to the existing
managed filter/select query. It shares the original checked predicate, scalar
parameter and binary64 comparison compiler; it does not parse or splice an
already emitted SQL string. The existing query parameter/demand/completion
contracts still apply.

The Host must bind the hidden ordinal to the exact input's unique zero-based
logical occurrence order. Generated SQL qualifies input references and orders
by that ordinal. Input-field/ordinal and output-field/occurrence-name collisions
are rejected using DuckDB identifier comparison rules. Identifier and metadata
inspection are bounded; count/group queries are not accepted by this entry.
An integer returned by this SQL is not itself execution or retention evidence.

The existing real DuckDB preserved-filter path now uses this SQL and checks its
returned occurrence. Its zero/one-row scope is unchanged: the preceding count
creates one input row and the filter retains zero or one. The original demand
test still rejects a five-byte false predicate under a four-byte ceiling even
when output is empty. Alias collision and malformed-identifier cases are added.

This supplies the compiler entry needed for arbitrary selected occurrences; it
does **not** claim that the singleton aggregate-facts issuer has been replaced
with a multirow indexed issuer. That connection, input-index retention for newly
generated count/group results, full chains and large paired benchmarks remain
unfinished. Legacy filter SQL is unchanged when no occurrence output is requested.

Verification: adapter tests passed 23/23 on JS, Wasm and Native; strict JS and
all six managed DuckDB/manifest Node tests passed. Interface generation and
format/diff, documentation and cross-target public API checks passed. No logical identity definition or resource ceiling
was changed.
