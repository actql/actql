# Ordered derive execution

The normative owner is [derive](../spec/language.md#derive). The execution
alternative is `actql-aoa.json#/execution_contracts/REL.derive.ordered`, selected
by `REL.derive.execution_extensions.ordered_bindings` in the pipeline registry.
It does not change the primitive's unary Relation signature or replace legacy
snapshot-map parameters. Supporting the signature alone is insufficient to
execute this alternative.

## References and identity

The source request and machine graph have different params. Ordered source
params are exactly `{bindings: [{name, expr}]}` with normalized source
Expressions, including unresolved source Parameter references whose values are
retained in `request.parameters`. Only the graph params add
`row_kernel_contract_cid` and `references` and replace RHSs with lowered nodes.
The contract schemas expose these as `schemas.source_params` and `schemas.params`.
This follows the existing snapshot-map fragment boundary in Sketch `87dc7144`
(`src/actql-expression-fragment-v2.ts`): source RHSs are normalized separately
from lowered graph RHSs. That revision has no ordered alternative. Ordered
source layout is an explicit shared-contract decision, not an imported format.

`derive_binding.aoa_node_cid` hashes the complete lowered graph step
`{id, in, op, params}`. `schemas.node_preimage` fixes the shape; the normative
derive section fixes canonicalization and the absence of wrappers/omissions.
This selects the concrete AoA pipeline step representation (also used in AoA
`dbab4fe8c1d624d81ed967f90e2abe742163f84f`), not a separate scalar node identity.
It binds the actual graph input edge and step ID as well as the ordered params.
Those are canonical fragment names, not the compiler's process-local handles.
The previous extension contract specified pin inclusion and evidence exclusion
but left this exact preimage and source params ambiguous; both are now explicit.

Bindings retain authored order. Each field occurrence identifies either the
original input or a preceding binding slot. An explicit occurrence table makes
shadowing inspectable without turning expression-shaped literal business data
into executable references. Root metadata remains canonically pointer-sorted;
that order is not the order of binding evaluation.

The lowerer's occurrence index retains its originating checked kernel. It walks
the typed machine expression rather than parsing emitted JSON or resolving
names again. CASE visits conditions and their results before the fallback,
regardless of the wire object's key order; lazy branches still contribute their
static field occurrences. Literal payloads never contribute occurrences.
Continuation frames bound traversal storage independently of expression width.
Reference count, retained pointer bytes and cumulative traversal work have
separate construction limits. These are preparation limits, not the row-kernel's
runtime logical-work evidence. Emitting an occurrence array does not establish
the enclosing fragment's evidence closure or execution permission.

The params builder consumes an admitted selected-extension body and this opaque
occurrence index. It obtains bindings exclusively from the index's originating
kernel, rather than accepting a second kernel or caller-authored table. The
extension body is hashed under explicit construction limits and compared with
the selected registry's pin. Generated consumer constants follow the shared
registry; they do not define an independent registration. Complete params are
still only one part of the fragment: producing them does not discharge context,
root, limit or backend-capability obligations.

The row shape, prior-slot context and limits are separate self-identified
bodies. This is an explicit definition of their preimages, not a serialization
of internal checker handles. Shapes retain required but untyped fields and the
possibility of additional fields; converting them to closed object contracts
would discard evidence. Contexts retain the exact checked prefix. Limits are
selected by the request for the same graph step, rather than trusted merely
because an artifact supplies a self-consistent digest.

The graph node pins the registered execution contract. Derived evidence names
the node but is not embedded back into its parameters, avoiding an identity
cycle. Registration pins the complete expression contract, including these
evidence schemas, without making that contract recursively pin the registry.

## Logical resources

The limits distinguish input row occurrences, individual wire value size,
simultaneously live logical value roots and cumulative logical work. These
measures are new explicit contract choices: allocation counts or interpreter
instruction counts would depend on the backend and its optimizations.

Canonical typed wire bytes provide a portable size measure, including exact
decimal strings. Work additionally counts value occurrences and raw string/key
octets, so escaping overhead is not mistaken for semantic work. Caching does
not reduce logical charges. Lazy branches retain their existing demand rules;
an unselected branch is not evaluated or charged as evaluated work.

Value measurement uses the same typed wire projection as lowering with a
measurement-only writer, avoiding a JSON output buffer. Logical weight is
counted separately: decimal weight includes the fixed-scale wire string, and
string/key weight counts raw UTF-8 rather than JSON escapes. Every occurrence
is measured even when backing storage is shared. The allowance uses checked
Int64 arithmetic within the contract's safe-integer range; host node/depth and
writer limits independently bound the measuring machinery. Per-value measures
must be charged by a shared row-kernel budget at the input, operand, production
and retention boundaries; computing them alone does not enforce cumulative
work or live-root lifetimes.

Logical live roots may share physical storage. Conversely, logical byte limits
do not cap physical heap overhead or algorithmic cost. Host resource controls
remain necessary. Input validation precedes shadowing, and an eventual select
cannot excuse evaluating an invalid binding or charging the retained output.

## Validation boundaries

JSON Schema checks closed bodies, required members, scalar ranges and the
exclusive input-field/prior-slot reference alternatives. Semantic admission
must additionally regenerate exact references, verify checked types and prefix
ownership, resolve all self-CIDs, and bind limits to the request and selected
Host policy. Neither shape validation nor a matching hash proves these facts.

`portability/corpus/ordered-derive-fragment.json` pairs a canonical source step
with its fixed lowered graph step, selected extension pin and
`expected_aoa_node_cid`. It is a binding/preimage vector, not an executable
fragment without the remaining checked roots, context, limits and shape evidence.
Its bytes and digests are fixed independently of a product lowerer; tests also
distinguish params-only, source-step, wrapper and whole-pipeline hashes.

The fixed corpus separates reference tables, identity preimages, resource
measurements and expected execution outcomes. Checking the first three does
not demonstrate that a backend executes the fourth. A backend unable to
implement the registered alternative, its expression demands or resource
measures must reject executable-plan construction. This contract does not
authorize a Program or replace the whole-Program integration boundary.
