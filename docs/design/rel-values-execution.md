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

`pipeline_check_context.measure_operation_values_rows` measures the execution
params' `/rows` value from an owned cell-resolution chain. It includes the outer
array, each row object, field names and typed wire cells; schema and the enclosing
params object are excluded. Empty rows therefore measure two bytes, one node and
one container level. Each Parameter occurrence resolves through its exact
requirement index, with the same producer, operation and cell coordinates, rather
than a caller-supplied value map. The index is built with cell resolution, so
measurement does not scan all bindings again for each cell. Limits apply to the
entire measured `/rows` value, without resetting at row or cell boundaries.
The returned byte/node/depth counts do not change an operation requirement's
resolution state and are not themselves a capacity proof or a publication limit.

`check_values_wire_bound` applies the separately pinned
`actql-bound-values-wire-law/0.1` to an integrity-admitted Program proof. It
checks the law, byte unit, local operation subject, source derivation and empty
input-quantity list, then recomputes `/rows` from the same owned cell resolutions.
The applied result retains that owner and the requirement occurrence together
with the proof and measured usage. Equal byte counts under different bindings
may validate the same numeric claim, but their applied results keep different
owners; a proof CID cannot substitute for that ownership. This bound still needs
scope-correct limit selection and enforcement before publication. It cannot
stand in for a recursive-depth ceiling or an Artifact byte bound.

`create_values_wire_limit` performs the pinned whole-wire candidate selection
and constructs a canonical `actql-resolved-limit/0.1`. It retains the applied
bound and the selected policy from that same owner. The fixed source grammar has
no byte guard, and the fixed Host policy has no whole-`/rows` byte ceiling;
the exact Program proof is therefore the sole applicable candidate. Its subject
is owner-relative `values:checked-step:<index>:wire`, its breach is failure and
its enforcement is engine-atomic. CI audits the source and policy field sets so
a new scope-compatible ceiling cannot be silently omitted by this selection.
Artifact and nested-value ceilings still require their own scoped checks.
Metadata serialization is bounded independently of the measured data and does
not materialize the payload. The returned limit is not a complete values resource
closure, an enforcement receipt or an executable-plan authorization.

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
