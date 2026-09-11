# REL.values execution contract

The normative owner is [REL.values execution parameters](../spec/language.md#rel-values-execution).
The complete contract is `spec/contracts/actql-aoa.json#/execution_contracts/REL.values`;
its standalone schema is at `/execution_contracts/REL.values/params_schema`.
`/target_registry_requirements/REL.values/execution_contract` pins the whole
contract, including semantic rules and the checked-type dependency. The family
manifest additionally pins the enclosing AoA contract. Relative pointers in this
registration resolve against that AoA contract file.

The registered contract CID is
`sha256:c95bc0d474fd6fbe62d3182bdefe6af412070f6ad2c8e102c5279d7a8b3eed17`.
The schema subtree CID is
`sha256:14d6c5c90e14ba8b9da4a3da4ec342a1ee84d19ef2417bcb4ae99ce94120bcb6`;
it is covered by the complete contract pin, not a separate registry entry.
Compile the extracted `params_schema` as its own schema resource so its local
`#/$defs` references resolve against that resource, not the enclosing registry.
The enclosing AoA contract continues to bind the existing kernel/pipeline/scalar
law manifests; this extension neither replaces nor silently upgrades them.

## Investigation and decision

Before this addition, the target requirement declared only `inputs: []` and
`output: relation`. `scripts/values-schema.mjs` generates authoring schemas in
the embedded Program definitions; it reserves cell-root `$param` and `literal`
operators and uses author contracts. It is not an execution-params contract.
The language's values and canonical-binding sections already fixed order,
multiplicity, binding before lowering and decimal wire strings, but did not
close the type-schema form or the quoted-cell boundary of executable params.

Searches at Sketch `87dc7144` and AoA
`dbab4fe8c1d624d81ed967f90e2abe742163f84f` found no `REL.values` registration or
execution params schema. Smooth Cloud `55b83448ac44c66c992b2f1c33452b7849e6c3f8`
provides canonical row serialization, not this operation's typed params contract.
Those implementations do not supply a competing authoritative wire definition.

Two decisions close the gap: use complete checked field contracts rather than
repeat author defaulting during execution, and use ordinary typed wire cells
rather than carry source quotation or internal `Cell` variants into the plan.
This keeps schema evidence with empty rows and prevents business objects from
becoming executable syntax. It preserves the existing fixed-scale decimal
representation and does not reuse Parameter identity's tagged projection.

## Validation and handoff

The JSON Schema checks the closed params envelope, nonempty field schema,
recursive constructible checked types (including decimal scale <= precision),
row-object shape and JSON wire structure. Exact fields and per-type values are
dependent constraints checked separately. In particular `{x: null}` differs
from `{}`, and `{$param: "business"}` can be legitimate object data if its type
declares that field. An executor cannot detect unresolved source holes by
rejecting those keys; the compiler owns binding and quotation processing.

`portability/corpus/rel-values-execution.json` fixes execution params and
accept/reject expectations independently of a product lowerer. Binding cases
include source cells and selected supplied values only as explanatory input;
the fixed `params` is the handoff expectation for lowering tests. Canonical
params bytes/CIDs are fixture identities, not Program, node or Relation CIDs.
Generated MoonBit tests exercise checked schema/value admission and canonical
serialization, not REL.values evaluation. Node tests separately check the
standalone schema and pin/generator drift.

The schema test interpreter is intentionally limited to this schema's explicit
keyword subset and rejects unknown keywords. It is not a shipped validator or
a claim of general JSON Schema conformance. Runtime validation remains a backend
responsibility. All 35 fixed cases are schema-checked; 25 shape-valid cases add
MoonBit checked-type/row validation, and 18 accepted cases also fix canonical
bytes and SHA-256 identities. Binding/quotation examples are fixed conversion
expectations for the lowerer, not evidence that a conversion implementation
has already been added on main.

Main owns this contract, registration requirement and fixtures. Lowering owns
conversion, binding provenance, executable registry admission and implementation
of all runtime checks. No lowerer or evaluator is added here. The old registry
pin is not relabeled as supporting a new operation; supporting registries need
their own accurate registration/identity. Unsupported backends reject runnable
plans. Ordered derive's row-kernel contract and whole-Program integration remain
separate work, without a dependency on this definition.
