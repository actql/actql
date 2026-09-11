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

Main owns this contract, the shared registration and fixtures. Lowering owns
conversion, binding provenance, executable registry admission and implementation
of all runtime checks. No lowerer or evaluator is added here. Unsupported
backends reject runnable plans. Ordered derive's row-kernel contract and
whole-Program integration remain separate work.

## Selected shared registry

The selected body is [aoa-pipeline-registry.json](../../spec/dependencies/aoa-pipeline-registry.json),
at JSON Pointer `""`; REL.values is at `/REL.values`. Its canonical whole-body CID is
`sha256:b97a22de3664c1dafe3bc1e6791f1f8bcfb70324a1fcc1087450fe057e0f2311`.
`actql-aoa.json` selects it through `pipeline_registry_file` and
`pipeline_registry_cid`. The enclosing contract's family pin and its normative
document import pins consequently change. The execution-contract and params-schema
CIDs above do not change.

This body preserves all 57 previous signatures and adds only REL.values, with
`inputs: []`, `output: relation`, and `execution_contract: {file, pointer, cid}`.
The file is repository-root-relative; the pointer resolves inside that file.
The registry hash includes the reference and its CID, not only the signature.
Consumers must not strip registration metadata when verifying the registry CID.
The complete execution-contract pin transitively binds the checked-type schema
and semantic rules; equality of params-schema CIDs alone is insufficient.

The [historical body](../../portability/fixtures/pipeline-registry-base.json)
still hashes to
`sha256:00ac46baefe7fa34412ad83beb85cf1899b906e792d74fa89211a7c4972f0d5a`.
It was recovered from `src/lowering_relation/registry-preimages.json#/registry`
at `42e8a0bcff8fa816c44d163517372d130ecd3938` and independently hash-checked before
extension. It remains a negative registration fixture, not the current selected
registry. Historical lowering fixtures are not rewritten; after importing this
commit, lowering should resolve the shared file for current selection and keep
historical fixtures explicitly bound to their old CID rather than comparing
them to the new selection. The target-module contract pin is unchanged.

`scripts/pipeline-registry.test.mjs` tests registration-only resolution, including
old-body absence, body/CID mismatch, signature mismatch, wrong file/pointer/CID,
and a changed execution body or checked-type dependency. Its independent Node
oracle is a contract test, not a production resolver. Both registry body hashes
also run through MoonBit's canonical JSON/SHA-256 tests on all three targets.
Existing execution-params corpus tests remain separate. Other target requirements
are not automatically registered, and registration does not certify any backend
or close Program execution admission.
