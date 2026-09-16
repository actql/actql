# Native file conversion: evidence before scan reuse

The fixed-SHA matrix at `46c5b033` showed that fresh-file Compute inputs still
perform complete typed validation and ordered logical hashing after native import.
This probe checks the finite `read_json` conversion that a future adopted
preservation rule would have to cover. It does **not** enable that rule or remove
the existing validation/hash pass.

Run:

```sh
node --test adapters/duckdb-node/test/native-file-values.test.mjs adapters/duckdb-node/test/session.test.mjs
```

All 25 tests passed with the installed pinned DuckDB Node `1.5.5-r.4` and Node
`v22.23.2`. The five added tests use the product `withComputeDatabase` path, exact
file grants, disabled general external access, one thread, bounded native vector
transport, and explicit DOUBLE/VARCHAR/BOOLEAN columns. They use the same native
SQL conversion shape, not the MoonBit SQL-generation entry point. They do not
issue ActQL completion or replace the existing schema eligibility tests.

## Independent positive evidence

- Thirteen literal decimal/IEEE-754 binary64 pairs, including positive/negative
  minimum subnormal, maximum subnormal, minimum normal, maximum finite value,
  neighboring values around one, and the exact integer precision boundary.
  Expected physical bits are fixed literals, not hashes or values obtained from
  the ActQL serializer or DuckDB output.
- Escaped control characters including NUL, quote and backslash; literal and
  escaped accented/supplementary Unicode; empty strings; Boolean and NULL.
- Duplicate occurrences and insertion order through native import followed by
  `ORDER BY rowid`.
- A 4,097-row sequence crossing both native-vector and bounded-transport chunk
  boundaries, and an empty explicitly typed relation.

These finite checks support testing an adopted implementation; they are not a
mechanized proof or exhaustive parser validation. They do not cover every codec,
colliding/case-folded column name, user `rowid`, or source-file generation change.
The existing bounded schema eligibility and Store integrity checks remain.

## Negative boundary: import success is not value admission

`[{"n":"1"}]` imported with `n: DOUBLE` succeeds and returns the binary64 value
one. Its source value is a JSON string, not an admitted ActQL Number. Therefore
native success alone cannot attest typed source validity. A physical byte hash
also says nothing about that distinction.

Any future no-rescan rule must be restricted to the exact immutable
representation already bound to successful complete typed admission and required
identity evidence. It must additionally bind the actual conversion, receiving
port, private table/session/attempt, row order and lifetime. It cannot be granted
to arbitrary `read_json` output, reconstructed from a path/digest alone, or used
to waive consumer-specific demands, guards or budgets. Unsupported paths retain
ordinary validation before execution, not a retry after confirmed violation.

No production scan was removed in this increment. No performance ratio or
new-profile completion claim follows from these conformance probes.
