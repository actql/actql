# REL.values execution contract

The normative owner is [REL.values execution parameters](../spec/language.md#rel-values-execution).
The complete contract is `actql-aoa.json#/execution_contracts/REL.values`;
its params schema is at `/execution_contracts/REL.values/params_schema`.
The registry pins the whole contract, including semantic rules and dependencies,
not merely the schema or zero-input/Relation-output signature.

## Authoring and execution representations

The Program authoring schema reserves cell-root `$param` and `literal` syntax
and accepts author type declarations. It is not the execution params schema.
Executable params contain complete checked field contracts and already-bound
typed wire cells. Execution does not repeat author defaulting or interpret
source quotation.

This choice preserves type evidence for empty rows and prevents business objects
from becoming executable syntax. Decimal cells use the existing fixed-scale
wire strings, not the tagged projection used for Parameter identity. Row order
and repeated rows are preserved; object-key order follows canonical JSON.

## Validation boundaries

Compile the extracted params schema as its own schema resource so local
`#/$defs` references resolve against that resource, not the enclosing registry.
JSON Schema checks the closed params envelope, nonempty field schema, recursive
constructible checked types, row-object shape and JSON wire structure.
Exact row field sets and per-type values require separate semantic validation.
In particular, `{x: null}` differs from `{}` even if x is nullable.

An object such as `{$param: "business"}` can be valid data when its declared
type admits that field. The executor cannot identify unresolved source holes by
rejecting these keys: binding and quotation processing belong to compilation.
The fixed [execution vectors](../../portability/corpus/rel-values-execution.json)
separate source conversion expectations from executable params and their
admission outcomes. Fixture params CIDs are not Program, node or Relation CIDs.

## Publication resources

`ResolvePublicationResources` is a request to resolve execution limits, not an
execution check that can be discharged by retaining the selected Host policy.
The [resolved-limit rules](../spec/language.md#resolved-limits) require each
runnable capacity limit to retain its measured scope, exact operation target,
applicable candidate witnesses and enforcement boundary. A future enforcement
check is valid only after that static selection has been made. The existing
`actql.bound.values` proof establishes the authored row occurrence count; it
does not establish byte size, recursive-value limits or completed enforcement.

Compilation budgets, wire byte limits and physical memory budgets are separate.
Counting raw text in an admitted value tree does not measure canonical typed
wire bytes: decimal coefficients, escaping, field names and structural syntax
have different representations. Artifact publication ceilings cannot be applied
to an intermediate Relation merely because their units are also rows or bytes.
Similarly, the nested-output scopes specified for `nest` do not implicitly
define a whole-Relation byte scope for `values`.

The Program constructor must retain an unresolved resource requirement when a
required scope or its applicable evidence has not been selected. It must not
substitute parser limits, a backend capture budget or a row-count proof for that
selection. Lowering consumes the selected limits and checks whether it can
enforce them; it does not choose their semantic scopes or complete missing
static resource decisions.

## Registry and backend capability

`actql-aoa.json` selects the shared registry through `pipeline_registry_file`
and `pipeline_registry_cid`. The `/REL.values` entry includes
`inputs: []`, `output: relation` and an `execution_contract: {file, pointer, cid}`
reference. The file is repository-root-relative; the pointer resolves within it.
Consumers hash the complete registry body, including reference metadata.

Historical registries retain their original CIDs. An absent registration or
unsupported contract prevents executable-plan admission; it does not narrow the
source language. Registration is separate from implementing runtime validation,
whole-Program admission and execution authority. The
[expression-fragment binding](expression-fragment-registration.md) follows the
same distinction between registration and semantic admission.
