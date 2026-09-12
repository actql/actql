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

Source and graph step artifacts are projected from the same opaque ordered
params owner. Source bindings use the retained normalized expressions, including
Parameter references; graph bindings use the already-bound machine expressions
and indexed references. Both rebase the fragment-local input to `input` without
changing the original checked kernel. The graph artifact hashes the complete
`{id, in, op, params}` step, not only its params. Construction bounds cover the
combined retained bytes and nodes of both artifacts. These steps alone do not
establish the enclosing request, derive-binding evidence or fragment admission.

The binding-record builder derives the graph step from its owned links rather
than accepting a caller-supplied node CID. It records the complete step identity,
input/output shape identities, exact limits identity, and authored-order pairs
of expression-root and prefix-context identities. The self-CID excludes only
`self_cid`. A detached slot array keeps later emission consistent with the
generated artifact. The single-step evidence projection emits the binding,
contexts, limits and shapes in their required closure order; it does not yet
establish their enclosing request or admit a complete fragment.

Ordered source requests use the same per-kernel request builder as maps and
filters. They require explicit row limits for that exact step; non-ordered
requests reject an extraneous row-limits member. Request and runtime share the
same immutable quantities, safe-integer validation and canonical body emitter.
The row/value ceilings cannot exceed the enclosing request ceilings. The request
emits the limits self-CID under its generated step ID, while its source pipeline
contains only authored-order bindings with normalized source expressions.
Preparing this source request does not bypass the registered machine-node and
evidence checks required by complete fragment construction.

Complete fragment construction accepts the selected registered ordered contract
alongside that request. It regenerates occurrence references, row shapes,
prefix contexts, limits, binding record and graph node from the request's checked
kernel. The candidate includes `row_kernel_evidence` only for ordered kernels.
Missing or extraneous extension selection is an explicit construction error.
Generated-node and binding artifacts retained alongside the graph and roots
consume the construction allowance as well; the final candidate has its own
bounded serialization. Fragment checking repeats this construction and compares
the complete canonical candidate, including the evidence closure, before keeping
regenerated material. This is integrity checking, not Program permission or, by
itself, runtime input admission and resource enforcement.

The checked-fragment driver uses the same context path for maps, filters and
ordered bindings. Ordered runtime limits cannot exceed any of the four quantities
declared by the checked request, although explicit tighter execution limits may
be supplied. The driver requires one context for every expression kernel before
input capture, creates fresh counters, and feeds the sole row evaluator. In this
mode it does not accept an additional component-level ordered configuration;
there is no precedence rule between two competing sources of enforcement data.
The older component-only invocation remains distinct and does not claim checked
fragment admission. These internal paths still are not a Program/Run API.

An internal generated-sequence handle owns the prepared sequence, its complete
checked context set and the selected retained outputs. Construction checks
ownership and wiring with explicit work and metadata bounds before publishing
the handle, and copies the caller's context and selection containers. Invocation
takes immutable limit quantities and supplied inputs; it creates fresh counters
and always selects checked-fragment execution, with no component-only fallback.
The common driver still checks input obligations on every invocation. This
composition handle does not certify Program capacity or authorize external work.

Runtime preparation consumes the lowering package's opaque typed request and
the selected registered contracts. It constructs the complete candidate,
regenerates it for integrity admission, and only then creates an enforcement
context. These steps are one internal constructor; callers cannot opt out of
admission or provide a substitute graph. Failures preserve the material,
candidate, admission or runtime stage. The physical construction ceilings apply
to each bounded artifact construction, not to process-wide heap usage or total
preparation work across all calls.

The repository-internal package surface exposes opaque registered contracts,
runtime contexts, generated sequences, completed outputs and producer bindings.
It exposes immutable limit quantities and indexed output readers, not table
containers, mutable counters or constructors for completion evidence. A consumer
can prepare and execute generated fragments without private access. This is not
a stable SDK surface or a Program/Run API. Preparation failures expose their
stage; sequence failures expose their category and relevant input/step index.
The complete typed failure tree is also readable, including resource limits,
incomplete implementation or evidence, and row/slot/expression diagnostics.
Expression failures retain their checked source location. Error values do not
grant access to mutable execution state and are not a versioned wire protocol.
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

The runtime budget separates monotonically consumed work from releasable live
bytes. Each retained logical root owns a budget-bound lifetime handle. Aliases
receive separate handles; a transfer retains the original handle. Releasing
twice or against another budget is invalid and cannot reduce a counter below
zero. Exhaustion invalidates further charging, while cleanup of existing roots
remains possible without restoring work or reviving execution. Input row
occurrences are admitted before evaluation; row, binding and expression-entry
charges are separate events. These helpers must be attached to the actual
evaluator's continuations and row lifetimes, not merely exercised by a host.

The evaluator's `logical_work` hook charges at its existing `Enter` state and
at semantic operand consumption and result production. Lazy branches do not
add work; eager boolean operands do. Selection nodes retain a forwarding
continuation so the chosen child is consumed and the parent's result counted
without inventing a second expression evaluation. Boolean implementation seeds
and accumulator folds do not introduce additional semantic operands or results.
Comparisons charge complete operand weights even if comparison itself stops
early. Reuse across calls does not reset work, and any evaluation failure
invalidates further use of that budget. Failures retain the checked expression
at which the charge was refused.

Expression continuations also retain their live operand handles. A left binary
operand remains live during right-side evaluation; a condition is released
before evaluating its selected branch. Forwarding a selected value transfers
the existing root without adding an alias. Boolean accumulator storage has a
temporary root but does not create an extra semantic work event. A bounded,
reusable slot pool tracks only this expression evaluation's roots, allowing
failure cleanup without touching borrowed input or slot roots. The retained
evaluation entry detaches its final handle for transfer to a row slot; the
value-only entry releases it.

Ordered row execution uses this same evaluator and a row-operation root scope.
It admits every input row's complete shape and logical weight before any RHS,
then charges each row and binding entry without resetting the budget. The
operation-start snapshot remains separate from authored slots; output shadowing
is materialized only after all bindings succeed. Slot handles transfer from
expression evaluation into the row scope. A complete retained-output row is
measured before releasing its input and slot handles, and pending outputs remain
live until the operation finishes. Failure cleans operation-owned roots and
returns no partial table. The value-only row entry ends that operation's scope;
it is not yet a whole-fragment artifact-delivery or evidence-admission boundary.
The generic sequence driver must supply the correct same-step resource context
before it can use ordered execution; runtime helper success does not synthesize
the request's limit CID or discharge the surrounding fragment's obligations.
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
