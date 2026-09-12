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

Program construction can use `resolve_values_wire_limit` to derive the proof,
witness and selected limit from the owned cell resolutions instead of requiring
a caller to manufacture those intermediate claims. The payload is measured
once under its traversal budget; proof and limit metadata use separate bounded
encodings and the normal integrity admission. The resulting bound retains the
exact resource occurrence and bindings. Metadata budgets apply per encoding and
admission; the enclosing Program constructor must also account for aggregate
preparation work. This path has the same byte-scope contract as externally
supplied proofs and does not discharge row or recursive-value requirements.

`resolve_values_row_limit` retains that same wire-limit owner and selects the
row scope separately. It constructs and applies the existing
`actql.bound.values` proof to the actual checked generator: the quantity is the
authored row count, including repetitions and zero. Both this proof and the
selected policy's `max_relation_output_rows` ceiling are retained as candidates,
even when one cannot tighten the minimum. No byte, Artifact or unrelated input
ceiling is substituted for the row ceiling. The canonical limit's owner-relative
subject is `values:checked-step:<index>:rows`, with absent author guard, atomic
engine enforcement and failure on breach. Metadata encoding/admission is bounded
per pass, independently of aggregate Program preparation work.

A resolved row limit is not a successful publication check: an exact count can
exceed the selected Host ceiling. That case must fail at the enforcing boundary,
not truncate rows or discard the tighter candidate. Empty rows select zero while
retaining the declared schema and both candidates. Recursive-value applicability
and enforcement are separate from both the row and complete-wire byte scopes.

The [values recursive-resource scope](../spec/language.md#values) makes the
previously unspecified scope explicit rather than importing `nest`'s child-array
scope. It selects declared array/object/vector cells, including null occurrences,
and sums their typed-wire bytes. The declared type supplies depth independently
of data, so empty rows cannot bypass a deep type check. Vector contributes one
wire-array level. This is a values-specific clarification: the reference Sketch
compiler's nest depth calculation and fragment-wide value ceilings do not define
this generator's contract. It does not make scalar cells subject to a nested
byte ceiling or turn either logical measure into a heap bound.

`check_values_recursive_resources` checks these scopes from the exact owner of
the row and wire limits. It walks declared contracts with continuation frames,
including for empty data, then measures selected cells using the shared owned
binding resolver and canonical typed-wire emitter. The preparation-work ceiling
is cumulative across type frames, field/row/cell visits and emitted value nodes;
cell encoding never resets the remaining byte or node allowance. The admitted
result retains the selected Host byte/depth ceilings, measured usage and row
owner. It is a static resource admission, not a substitute for a canonical
execution-limit binding or a receipt that a backend enforced it.

`resolve_program_values_resources` closes the resource occurrences of one exact
operation-resolution index. It internally derives row/wire limits, performs
recursive admission and binds the selected recursive-byte Host witness into a
canonical limit for the selected field indices. No complete-wire proof is
relabelled as a recursive-cell proof. An already-known row excess is rejected,
not deferred as if resource preparation succeeded. The result retains typed
`ValuesPublication` checks with the exact occurrence, limits, fields and policy;
their phase is before operation output and failure rejects that output.
Operation closure accepts these as future checks, not enforcement receipts.

The resolver copies its resolution index only after reserving traversal work;
all occurrences share payload byte/node ceilings. Failure at any occurrence
leaves the original index unchanged and exposes no partially resolved result.
Aggregate measurement usage is readable for enclosing construction budgets.
Metadata has per-artifact pass ceilings and the number of values constructions
is separately capped. These are bounded preparation scopes, not a heap ceiling
or an implicit claim of backend compatibility or complete Program identity.

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
