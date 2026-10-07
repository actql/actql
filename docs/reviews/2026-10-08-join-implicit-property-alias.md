# Single-JOIN implicit property aliases

Base: main `654b2d49f1f5d2af22a1641169b474d0313c070f`.
Branch: `fix/frontend-join-property-implicit-alias`; merge target: main.
No unmerged parent dependency or common execution change.

## Counterexample and existing contract

```sql
SELECT (l.payload).score, l.id
FROM objects AS l JOIN keys AS r ON l.id = r.k
ORDER BY score NULLS LAST, id
```

The selected GoogleSQL reference
`d82db99a923a46571f543a13899dc791a7b6f743`, `docs/query-syntax.md`,
"Implicit aliases", names a dot-member expression after its field, including
computed receivers. The [official query syntax reference](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#implicit_aliases)
states the same naming rule. This fixes a connection within ActQL's existing
closed-object/property subset, not a claim of complete GoogleSQL STRUCT support.

Ordinary/scoped projections and `joined_projection` already recognize the
Property AST. `join_order_projection` instead accepted only Reference ASTs when
collecting implicit output names, so `(l.payload).score` failed before reaching
the existing receiver/property lowerer. It now uses the Property leaf name too.
No receiver resolution, value evaluation, typing, nullability, key, JOIN bound,
order evidence, execution owner, wire or grammar contract is changed.

The complete independent machine Program in
`src/query_program/join_implicit_property_test.mbt` passes normal checking before
the fix. The equivalent text fails the pre-fix selection (0/2,
`run-V3oPDs`, `focused-test-7IPZOR`). The positive assertion is reached only after
checking that independent control. The first draft of the expected internal
names started allocation at zero; inspection of `pipe_physical_name` established
that allocation starts at the five reserved output/input names. The expectation
was corrected to slots 5/6 without changing expressions, values or public fields.

## Independent public obligations

`scripts/fixtures/join-property-source-input.mjs` retains its original cases and
adds a complete JSON control plus CTE SQL, CTE Pipe with quoted field names,
computed IF receiver, and typed-empty result cases. All are included in the
normal corpus as well as `--join-property-only`.

The independent sorted rows, including multiplicity, are:

```json
[{"score":10,"id":2},{"score":10,"id":2},{"score":20,"id":1},{"score":null,"id":3}]
```

Columns are `score` (nullable number), then `id` (nonnullable number). The NULL
receiver produces SQL NULL through existing property evaluation; no property
value is inferred from rows. JOIN keys remain ID/ID and its explicit ceiling is
12. Duplicate outputs, unknown receivers, missing properties and scalar
receivers are refusal cases. The unchanged consumer compares describe contracts,
column order, complete streams, rows and absence of internal columns; checks
pre-admission refusals have zero accepted Runs/provider reads; and uses the same
epoch-bound submission reference for repeat, lookup and attach/read controls.

## Existing ORDER assertion correction

The existing `JOIN property ORDER reuses only the same resolved receiver` test
also fails on the unchanged main compiler (`run-QR0eX5`, 0/1). It incorrectly
requires a second property evaluation both when the ORDER receiver is rebound
and when it is unchanged. In `SELECT payload.score AS original_score, ...`,
bare input payload and qualified `ORDER BY l.payload.score` resolve to the same
input. Sorting must reuse `original_score`, with one property evaluation and no
hidden sort field. Unqualified `ORDER BY payload.score` instead uses the output
payload alias, bound to right.other: this requires a different evaluation and
removal of the hidden sort field. The test now distinguishes those independent
resolution obligations, retaining the existing public rows and contracts.

## Verification and remaining work

Pinned MoonBit `0.10.12+1634b282e` and Node `22.22.0` are used.

- `node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js src/query_program --filter 'JOIN *property*'`: 12/12, `run-LijNsf`, `focused-test-EdS7aK`, working-tree source before publication.
- `node scripts/local-checks.mjs test node --timeout-seconds 120 -- scripts/analytic-offset-profiles.test.mjs scripts/public-query-profiles.test.mjs`: 12/12, `run-mXxlfW`, `focused-test-rCuz9o`. The extended JOIN corpus contains 15 successes and 9 pre-admission refusals on the unchanged standard Host profile.
- Fresh normal five-package production and external Local/HTTPS execution on the clean submitted revision remain required. No earlier tarballs or old client-wire are used as a fallback.

Full Core, Wasm/native, CI and broader compatibility are not established by
these focused checks. Scalar execution gaps recorded in the separate
scalar-contract-boundaries handoff and correlated-UNNEST capacity remain separate
common-owner dependencies; this connection neither resolves nor bypasses them.
