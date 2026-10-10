# Grouped Graph macro binding arguments

## Requirement and counterexample

The query AST preserves grouping parentheses and ordinary expression lowering
passes their child's value through unchanged. Grouping a Graph binding must
likewise preserve its binding role. This changes neither the installed macro
namespace nor the Graph model, checker, execution owner or identity contract.

Baseline: `584b3a6144d4a8053ca4a541ef042a6e17c674e9`.

```aql
DATA g = PROPERTY GRAPH (
  NODE TABLES (objects AS N KEY (id) LABEL Person PROPERTIES (id, payload))
);
FROM GRAPH g
|> MATCH WALK (a:Person)
|> WHERE NODE_ID((a)) IS NOT NULL AND a.payload.score > 10
|> SELECT a.id AS id, a.payload.score AS score
```

The independent Values input contains scores 10, 20, a NULL object and a NULL
score. The complete handwritten Program passes the ordinary checker. Before
the product change, `NODE_ID(a)` matched that Program, but `NODE_ID((a))`
failed with `UnknownReference`. This was a compiler reproduction, not an
executed public Run failure.

Pre-fix focused check: `run-DUcku4`, `focused-test-c3LWk4`, 0/1 passed. Evidence
is retained under this worktree's `_build/local-checks/attempts` and
`_build/focused-evidence`.

## Change and independent obligations

`query_expression/lower.mbt::append_resolved` classifies a Reference and its
grouping-only parents in one linear postorder pass. A one-argument macro
receives the original Reference path, and the existing callback still owns
binding/name/kind resolution. The existing node-count admission bounds this
pass. There is no repeated traversal of nested arguments, new evaluator or
change to logical execution work.

The existing lowering pass retains all AST nodes for its work limit. An exact
node-count budget succeeds and one less rejects with `WorkLimit`. Ordinary
property, parameter and scalar expression lowering remains unchanged.

Independent controls cover:

- Bare, grouped, multiply grouped and quoted binding names resolving to the
  same complete Program; a typed identity predicate and nullable property
  predicate remain separate expressions.
- PATH_LENGTH on two independently keyed parallel self-loops: two one-hop
  WALK rows, both `{depth: 1}`, with a nonnullable Number column.
- An empty filtered result retaining its declared column order and types.
- Property/compound arguments, wrong binding kind, wrong arity and expired
  post-projection bindings remaining rejected before durable Run admission
  and Source I/O. No property value is treated as an element binding.

Public fixtures use full submitted text and independently authored ordinary
JSON Programs. They are in the existing normal Graph member acceptance cohort,
also selectable with `--graph-projection-property-only`. No Program is patched
after text lowering. The JSON identity control continues on the filtered current
row rather than reopening the original matched producer.

## Focused verification at the source commit

```sh
node scripts/local-checks.mjs test moon -- --target js \
  src/query_expression/grouped_macro_test.mbt \
  src/query_expression/lower_test.mbt \
  src/query_program/grouped_graph_macro_test.mbt \
  src/query_program/graph_projection_property_test.mbt \
  src/query_program/keyed_graph_program_wbtest.mbt
node scripts/local-checks.mjs test node -- scripts/graph-member-source-input.test.mjs
```

- JS: 24/24, `run-Il6VPI`, `focused-test-acNik3`.
- Node fixture checks: 5/5, `run-020vtU`, `focused-test-wP8aB5`.
- Changed MoonBit files formatted with the pinned formatter; `git diff --check`.

An initial test-only callback failed compilation because it used a raising
assertion in a non-raising resolver. It was replaced with callback observation;
that attempt (`run-7rGN2c`) is not counted as test execution or product failure.

The exact source SHA, normally packed five-package digests and actual
Local/HTTPS result are recorded in the PR after the source commit. They are
pending at this document's source commit. No all-Core, Wasm/native, full packed,
performance or hosted CI success is claimed here. Quoted *function names* are
the separate #1207 change, not a dependency or a claim of this unit.

The first packed attempt at `c2b4cf40d3eed856b0c192f81309fa7b9d16723a`
passed all 22 Local normal cases, then stopped on the refusal fixture's generic
input-code whitelist. `NODE_ID((a.payload))` resolves an ordinary property,
then fails as an unsupported function rather than an unknown reference. The
existing public check owner maps `UnsupportedFunction` to an implementation
limit. The fixture now explicitly expects `ClientProgramImplementationLimit`;
no product diagnostics or expected normal rows were changed. Typed lowerer
refusals are also asserted directly. That failed attempt is retained separately
as `run-Pazrm6` / `public-query-evidence-xkupzX`; it is not HTTPS evidence.
After adding the explicit refusal code and typed refusal cases, the changed
Program test file passed 2/2 (`run-GHoJKK`, `focused-test-H6vbhz`) and the Node
fixture checks passed 5/5 (`run-4ndRRl`, `focused-test-Ut7EBA`). The product
lowerer is unchanged from the earlier 24/24 JS check.
