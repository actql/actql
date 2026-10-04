# Graph MATCH output: nested property expressions

## Completion unit and baseline

Base: `7e32faa5a455dc4beafa02a8cd06313e83772d50` (main, including #388).
This is independent of #400's node-pattern predicate change. No property
predicate is added inside MATCH by this unit.

Given nullable `payload` with nullable numeric `score`, the ordinary Program
can project `property("score", field("payload"))`. The public source entry
instead rejected this corresponding tail with `UnknownReference`:

```aql
FROM GRAPH g
|> MATCH WALK (a:Person)
|> SELECT a.id AS id, a.payload.score AS score
```

The test context supplies independently authored Values, followed by the pure
Property Graph mapping. The handwritten complete expected Program passes the
ordinary checker. Before the product change, the two selected tests executed:
the checker control passed and source lowering failed (1/2). Evidence suffixes:
`run-Vk35uB`, `focused-test-ar0tJt`.

## Implementation and scope

`query_program/compile.mbt::append_expression` already chose the shared macro
entry for Graph bindings. That entry disabled ordinary object-prefix resolution.
`query_expression.append_with_macros` now accepts an optional property-resolution
flag, defaulting to false; the Graph SELECT/WHERE caller enables it. Graph macros
and property expressions use the same bounded AST pass and source owner.
NODE_ID still references the full checked identity slot. No expression is
converted back into text, evaluated by the Frontend or assigned guessed types.

The existing column resolver selects the longest visible receiver prefix;
ordinary property nodes preserve the remaining member names. The common checker
owns member lookup, closed-object types and nullable propagation. Existing Pipe
projection boundaries continue to reject removed columns/range variables and
same-SELECT aliases. The generated MoonBit interface was regenerated with the
pinned `moon info src/query_expression`, not edited by hand.

This changes an internal MoonBit function signature, with unchanged defaults
for existing callers. Public source grammar, wire/schema contracts, contract
versions, identity pins, runtime owners and stored data are unchanged. It does
not claim broad Graph/Frontend completion. Nested ORDER expression reuse (#374),
implicit property output names (#389), node-pattern predicates (#400), and
unadapted edge/path property bindings remain separate completion units.

## Independent expectations and local verification

- [Lowering fixture](../../src/query_program/graph_projection_property_test.mbt):
  complete expected Programs retain static Person membership, the nullable
  object receiver, the member name, selected column order and NODE_ID slot.
- [Shared expression fixture](../../src/query_expression/lower_test.mbt):
  handwritten expression with both a macro and property access, default-off
  compatibility, source locations and prefix-work exhaustion.
- [Public cases](../../scripts/fixtures/graph-projection-property-source-input.mjs):
  one handwritten JSON control, seven authored source cases and five refusals.
  Independent rows are id/score `(1,20),(2,10),(3,NULL),(4,NULL)`. The last two
  distinguish a NULL object from an object with a NULL member. Cases cover
  local/qualified/backtick receivers, a macro plus typed parameter, typed empty
  output, and a projected object's new current scope.

Focused JS tests: 16/16 (six new Program tests plus ten shared expression tests),
`run-qydawN` / `focused-test-oKdBJJ`. Existing keyed Graph callers: 5/5,
`run-ZA1wfa` / `focused-test-TmhOmv`. These compile affected shared API consumers
and execute NODE_ID/path macros; they are not all-Core or backend conformance.
Changed MoonBit formatting, Node syntax and `git diff --check` are checked.

The cases are registered in the normal packed public corpus. For the changed
boundary alone, use the pinned toolchain and normal package prepack:

```sh
node scripts/test-packed-public-query.mjs --graph-projection-property-only
```

The existing external consumer checks Named Result rows, full ordered column
contracts through describe(), stream completion, absence of internal fields,
same-request retry/lookup/attach without extra source reads, and typed refusals
before Run admission/provider I/O. No generated Program is repaired by tests.
Packed Local/HTTP execution has not yet been recorded for this change.
Full required hosted CI, Wasm/native and unrelated packed corpora are not locally
rerun. Billing-blocked CI is not product failure or verification success.

## References

- [Query text and Graph construction contract](../spec/query-text.md#logical-data-and-pure-property-graph-construction)
- [Selected Graph profile](../design/frontend-standard-profiles.md#property-graph-mapping-and-element-identity)
- [Nullable object semantics](../design/semantic-decisions.md)
- [Local verification policy](../development.md#focused-test-execution)
