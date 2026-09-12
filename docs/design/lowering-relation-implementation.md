# Relation lowering implementation

## Scope and decisions

Work is isolated on `work/lowering-rel`. It began at `92b9d45` and was then
restacked onto `design/host-authorization` (`c387a26`) at the user's request.
Only the three lowering commits were replayed; the main-side capacity/evidence
commits were not duplicated. The intended integration order is finalized main,
authorization design changes, then this lowering implementation. This changes
the history base, not the agreed implementation scope. The first delivery
is values, derive, filter and select, with field/literal/bound-parameter,
arithmetic, comparison, boolean and conditional expressions. This is a minimum
delivery, not an authoring allowlist. Additional expressions that the common
implementation correctly supports need not be rejected merely for being outside
that minimum.

The implementation consumes public checked APIs. It must not reparse source,
infer types or order independently, or recursively replace parameter-looking
business data. Retained checked payloads are preparation metadata, not another
semantic IR. Executable computation must use the normative AoA representation.

These packages are intended as production building blocks. There is no separate
test evaluator, arbitrary-AoA-JSON execute API, public SDK export, or Program
execution authorization in this increment. Explicit supplied relations and
existing validated parameter bindings are in scope; Connector acquisition is not.

Host authorization, Checkpoints, durable Runs, Effects, Result publication,
final Plan identity, static capacity completion and DuckDB dispatch remain out
of scope. Local physical limits do not become language restrictions. Runtime
limits are explicit, enforced, and separate from static capacity evidence.
No implicit truncation, partial-success output or engine fallback is allowed.

Internal implementation decisions proceed locally. Changes to accepted language
behavior, evaluated meaning or canonical contracts require coordination and an
explicit decision. Main's shared typing, evidence, schemas and pins are not
edited here. Main synchronization is needed at integration/API boundaries,
not after every upstream commit.

## Authority and reference material

The normative owners are [algebra lowering](../spec/language.md#algebra-lowering)
and [generated identifiers](../spec/language.md#generated-identifiers), together
with the pinned [AoA contract](../../spec/contracts/actql-aoa.json).

`src/lowering_relation/registry-preimages.json` preserves the exact registry and
module preimages recovered from sketch. Construction follows sketch's
`src/actql-aoa-contract.ts`: registry input/output signatures from
`AOA_PIPELINE_OPS`, and the core/rela/sga/veca/tea module subset from
`ACTQL_MODULES`. The registry distribution matched the archived dependency
`smoothhq-aoa-pipeline-0.12.0-integration.20260906.2.tgz` whose SHA-256 is
`be37097b180634e6fbb3e5c1b026661b70f314fb7babead507dc4798ba18fcf4`.
That dependency version is provenance, not an ActQL contract version.

`node --test scripts/lowering-registry.test.mjs` independently verifies the
selected shared registry and the historical registry as distinct identities,
plus the module preimage. It checks all four preparation signatures against
actual entries in the selected body, without using target requirements as a
substitute for registration. `REL.values` is absent from the historical base
but registered in the shared registry supplied by main at `a728bda`.
These signatures do not prove operation-parameter or expression admission.
Historical module descriptions are not substituted for newer normative rules.

sketch MoonBit's relation evaluator informs ownership and budget design. AoA
informs node/parameter representation. Smooth Cloud's local lowering and DuckDB
fragment compiler inform the engine boundary. Their restrictions (for example
discarding empty transforms or rejecting empty derive) are not imported as laws.

## Wiring preparation (first increment)

`lowering_relation.prepare` retains one CheckedPipeline and checked operation
payloads, allocates ASCII `input_<index>` and `<preferred-operation>_<step-index>`
identifiers, checks collisions, preserves resolved input occurrence order, and
retains diagnostic cursors. These namespaces are disjoint. Author aliases never
become node identifiers; explicit branch references resolve to their original
producer rather than the immediately preceding step.

The allocator implements document-order/preferred-name identifiers; it does not
claim identity parity with a historical compiler. Generated identifier bytes,
nodes (including input handles), reference occurrences and work have explicit
overflow-safe limits. Returned reference arrays are copies. A late unsupported
operation returns an error and no partially prepared pipeline.

Preparation alone is not executable-fragment or Plan admission. The execution
package consumes typed fragment requests, constructs complete canonical
candidates and regenerates them before creating runtime contexts. Preparation
does not itself discharge expression obligations, parameter binding,
operation-parameter contracts, serialized size or Program authorization.

## Execution boundaries

| Area | Execution responsibility | Boundary not implied by success |
| --- | --- | --- |
| Contract selection | Hash the selected registry and execution-contract bodies; consume the registered expression-fragment and ordered row-kernel contracts | Registry membership alone does not establish backend support |
| Typed fragment admission | Generate request, machine graph, roots and evidence from the same checked owner; regenerate the complete candidate before runtime preparation | No arbitrary saved AoA JSON execution and no final Program Plan identity |
| Parameters and explicit inputs | Reuse bound parameter ownership; admit supplied values and keys; distinguish exact completed producer bindings from raw captures | Computation success does not authenticate unrelated inherited metadata |
| Four-operation execution | One driver executes values, map/ordered derive, filter and select, including unused branches and expressions | Retained output selection cannot prune required operations |
| Ordered derive | Use registered row-kernel params, source params and complete graph-step identity; enforce authored slot order and explicit logical limits | No split into relation-wide derives or unregistered replacement opcode |
| Runtime resources | Explicit cumulative value/control budgets, operation workspace, live table slots and per-fragment logical budgets | Runtime counters are not static capacity evidence; container-entry accounting is not a process-heap meter |
| Internal package API | Opaque generated sequences, runtime contexts, completed outputs and producer bindings; immutable output readers and detailed typed failures | Not a stable SDK, Run protocol, Host authorization or Result publication API |

The API and evidence flow are described in
[ordered derive execution](ordered-derive-execution.md), including its shared
map/filter path. Increment sections below are historical descriptions and
verification counts, not the current capability table or release evidence.

The [row-kernel integration proposal](row-kernel-integration-request.md) and
[earlier closure audit](lowering-fragment-closure.md) record the origin of the
shared-contract requirements. Their historical handoff requests do not override
the selected shared contracts or mean that those registrations remain absent.

### Unsupported cases and extension conditions

These are implementation boundaries, not additional language prohibitions.

| Case | Normative owner | Missing support and condition for extension |
| --- | --- | --- |
| Expressions outside the implemented typed variants | [Common expression contract](../spec/language.md#common-expression-contract) | Add the exact typed lowering and scalar semantics with independent vectors; `ExpressionNotImplemented` must not be read as invalid source |
| Pending profile/pattern/other expression validation | Same common expression contract and its selected dependencies | Discharge the particular typed obligation and bind its evidence; do not erase `PendingValidation` to force admission |
| Structured captured-value comparison | Pinned expression contract's comparison domains | Supply exact domain semantics and bounded comparison; runtime preparation rejects unsupported domains with a located capability error |
| Qualified/scoped supplied rows | Checked relation schema and resolved field references | Add a lossless scoped row representation; `ScopedInputNotImplemented` must not flatten qualified names |
| Unsupported candidate-key domains or nullable witnesses | Checked candidate-key evidence | Implement the required equality/null evidence and bounded validation before removing `UnsupportedKeyDomain` or `NullableWitnessPending` |
| Other operation handlers | [Algebra lowering](../spec/language.md#algebra-lowering) and selected operation contracts | Add normative lowering and execution rather than treating `OperationNotImplemented` as a permanent authoring restriction |

Unsupported-operation tests describe implementation coverage, not permanent
language rejection. Implemented common paths must not grow a separate restrictive
allowlist. Evaluation failures must not expose partial results.

Completion requires the entire agreed four-operation path, the minimum expression
set, supplied inputs/parameters, independent lowering and execution vectors,
ownership and budget cases, JS/Wasm/native, API equality, formatting and relevant
documentation checks. Commit lowering and execution in functional units, report
known failures and remaining integration requirements, then stop rather than
expanding into more operators or Host implementation.

## Preparation verification

On the initial preparation increment, the five fixed preparation tests passed
on JS, Wasm and native (5/5 on each). The two independent registry tests passed.
`moon info` produced identical package interfaces on all three targets (SHA-256
`501534a8608460d83bbc4cdc88cb7b356737410dd3c68969632c84cb0c9a258e`).
Package format checks and `npm run check:docs` passed (839 local links and
19 parsed example programs). These are preparation/documentation checks, not
evidence of expression execution or full Program conformance. No full repository
MoonBit test-suite result is claimed for this increment.

## Parameter association increment

`bind_parameters` consumes existing opaque `BoundValues`; it does not bind raw
JSON again. Like main's bound-guard implementation, it checks physical identity
of the retained declarations before associating values with the prepared
pipeline. Equal-looking declarations created independently are not accepted as
the same checked owner. Missing environments, foreign environments and local
indexing limits have distinct typed failures. Parameter counts and cumulative
UTF-8 name bytes are bounded before retaining the index. Nested admitted values
remain frozen and are not rewritten or interpreted as parameter syntax.

Eight package tests now pass on each of JS, Wasm and native. This proves owner
association and bounded indexing, not yet expression substitution or evaluation.

## Expression increment and theory review

The implementation now consumes retained typed expression nodes and checked
field references, including InputField/PriorSlot distinctions. Implemented
nodes cover field, literal, bound parameter, negate, arithmetic, comparisons,
boolean/null tests, eager boolean composition, coalesce, nullif, if and case.
Missing CASE ELSE uses the checker's ImplicitElse contract. The typed expression
body follows actql-expression-node/0.1; source locations and resolved references
are non-wire sidecars. No constant evaluation or branch hoisting occurs here.
Emission preserves canonical tags (including `neq`, not historical `ne`), and
is bounded by the existing writer's bytes, nodes and depth. Both lowering and
encoding use explicit traversal stacks. Literal objects remain opaque.

Expression-level unimplemented handlers and pending validation obligations are
implementation gaps, not language restrictions. Adding a correct common handler
does not require expanding a separate product allowlist. Full Relation-fragment
admission and pure execution remain unfinished.

Theory sources inspected at fixed revisions:

- aoa-mechanized `26139fa908b49d14509aa0c211ecea25b8efb119`:
  RelA/Core.lean, Where.lean and Select.lean. The model proves selected-field
  retention and filter membership/predicate facts. Its rows are functions into
  Option String and predicates are total Bool functions. It is not a proof of
  our binary64 arithmetic, nullable expression evaluation or failure ordering.
- smooth-mechanized `a8424bed8066466aeb2677a6858361fef97a090a`:
  ACC/LoweredIR.lean, ACC/LoweredExec.lean and AoA canonical-lowering contracts
  and lowered-execution derivation. These relate native/lowered execution for
  the modeled LoweredRowsPlan cases. The model's unresolved-case empty-list
  fallback must not become successful empty output in ActQL. Source-order
  projection there also does not override ActQL's authored projection order.

Neither theorem tree was modified or rebuilt during this review. No Lean proof
of the MoonBit implementation is claimed. The relevant preservation properties
guide independent execution tests, while current ActQL remains authoritative.

## Scalar execution increment

`execution_relation` now contains pure scalar operator implementations to be
used by the row evaluator, not a second reference runtime. Binary64 comparison
does not round or serialize operands. Arithmetic rejects non-finite results and
division/modulo by zero. Primitive boolean combination follows the complete
three-valued truth tables. Eager/lazy child evaluation and row-major failure
ordering remain the evaluator's responsibility, not a guarantee of these
already-evaluated-operand helpers. Captured immutable values are retained for
pass-through. Checked-fragment runtime preparation examines the retained operand
contracts for all comparison operators, including `nullif`, across every root
and every branch. Unsupported domains produce a typed capability failure with
the root step/parameter pointer and expression source location, before input
rows are read. Empty input or an unselected lazy branch cannot hide a backend
implementation gap. This does not restrict language typing, scalar passthrough
or null inspection, and does not evaluate expressions during preparation.
Division by zero remains a runtime failure only when its expression is evaluated.

The nonrecursive readiness walk uses one `max_body_nodes` construction allowance
for root queue entries, expression visits, copied child views and queued edges
across the complete kernel. It is separate from runtime logical-work counters;
exhaustion returns a located preparation-limit failure. The raw scalar helper
retains `ComparisonDomainNotImplemented` as a defensive guard for component-level
calls, not as the generated execution API's capability-admission mechanism.

## Expression control increment

The private `execution_relation` evaluator consumes lowerer-created expressions
using a typed continuation stack, not recursion or re-parsed source. Fixed tests
exercise actual checked/lowered expressions: lazy IF/CASE/coalesce, eager AND,
left-before-right failure, missing-field rejection, exact control-work and stack
boundaries, shared counters across roots, fresh execution after failure, and
512 nested unary operations. JS, Wasm and native each pass 8 execution-package
tests (3 scalar plus 5 control tests).

This is deliberately not a public execution entry point. Its row frame must
eventually come from the admitted fragment executor. The current input map and
slot array are internal borrowed inputs, not evidence of public ownership
admission. Private code currently has only whitebox-test callers, so ordinary
builds report unused-code warnings; these are not suppressed or represented as
completed integration.

Control transitions and continuation depth are bounded here, but this is not
complete resource enforcement: runtime text work, nested-value sizes,
defensive-copy child arrays, retained output and physical live-value accounting
remain to be connected. A bounded lowering tree is not a replacement for those
execution limits. The four-operation fragment, registry-bound node emission,
input/schema ownership admission, map row loop and ordered-kernel integration
remain open. No ordered derive executable wire form or shared pin changed.

## Captured values and logical value accounting

`capture_values` accepts an exact bound preparation and values-node index, not
an unrelated CheckedValues object. It reads the existing checker-owned row cells
and already admitted Parameter values, retaining their immutable backing values.
The result is opaque input material carrying that owner/node/schema; indexed
access never exposes mutable row arrays. It does not discharge the values
checker's publication-resource obligation or confer executable Plan authority.

Capture enforces a row ceiling and cumulative logical value limits across the
whole captured node. Each row contributes one object node; each nested value or
vector component contributes one node. Root row depth is one. Text bytes include
field names and string/date/timestamp content in UTF-8, and decimal coefficient
text. Work is logical node count plus those text bytes. These are explicit local
implementation counters, not replacements for pinned capacity measures, encoded
output bytes or a complete heap-size accounting model.

The meter traverses frozen arrays/objects by index with O(depth) auxiliary space,
does not copy entire child arrays or encode strings just to count their size,
checks capacity before retaining cells, and counts repeated logical occurrences
even when backing storage is shared. A failed capture returns no row prefix;
its local counters cannot contaminate a later invocation. Tests cover exact and
one-under limits, multibyte text, nested literal opacity, defensive access and
wrong-node/owner identity. Physical live-value accounting remains to be integrated
before a fragment execution API.

## Explicit supplied input

`capture_input` selects the input schema from the exact bound checked owner,
then reuses `value_admission.admit` for explicitly supplied data cursors. It does
not parse expressions, acquire Connector data, coerce values or repair text.
Data has an explicit `SuppliedInput(index)` origin, distinct from
`ValuesNode(index)`. The caller's mutable cursor array is not retained.

The same logical capture limits apply cumulatively across input rows. Admission
receives remaining node/text limits before constructing each immutable row;
measurement enforces their combined work bound before retaining it. This work
counter is a logical size measure, not a claim that schema traversal or Unicode
normalization CPU time is fully metered. Physical temporary allocations and
schema-processing work remain part of the final execution budget integration.

Current input support covers schemas with an existing ordinary object Value
Contract. Qualified/scoped schemas without that representation return the
implementation-gap error `ScopedInputNotImplemented`, not a language rejection.
Exit condition: a lossless supplied row representation for scoped fields, using
their existing contracts, with the same ownership and resource checks.

This establishes row value admission, not validity of supplied candidate-key,
order or capacity claims. Those obligations must be checked before final
fragment execution admission. Tests include source-parser normalization versus
noncanonical supplied data, non-null/type/closed-field constraints, empty input,
cumulative limits, alias/index separation and post-capture caller mutation.

## Checked operation kernels

`prepare_kernel` groups already checked map/ordered bindings, predicates and projections
with their exact bound owner, step and input ID. Expressions remain the normative
typed expression representation. This is a non-wire preparation object, not a
new execution language, registered AoA fragment or final Plan admission token.
The binding and projection arrays are defensively copied at access boundaries.

Expression-lowering node/work/literal limits are consumed cumulatively across
all bindings rather than reset for each RHS. Separate binding/name limits bound
the operation container. Canonical map binding order and authored projection
order come from the existing checked APIs; preparation does not infer either.
Empty maps retain a real preparation object. Ordered arrays preserve authored
bindings and checked input-field/prior-slot targets in `OrderedBindings`.
Their root pointers are sorted independently without changing evaluation order
or the association with each checked expression. Preparation does not establish
the occurrence table, evidence closure or logical resource accounting required
for execution. Until those are connected, fragment preparation reports
`NeedsOrderedEncoding` and the row evaluator reports
`MissingOrderedResourceContext` without explicit runtime limits. The existence of a shared execution
contract alone is not a backend capability.

Fixed tests cover map payloads/order, retained no-op, projection order, defensive
access, whole-operation cumulative failure and separate execution admission.
Connecting these objects through registry-bound fragment construction and the
row evaluator remains open; this increment alone does not authorize execution.

## Row evaluation connection

The package-private row evaluator now consumes prepared map/filter/select kernels
and captured tables. It rejects owner or input-ID mismatches before evaluating
rows. Map bindings see a single operation-start snapshot, preserve all original
fields, and execute in checked canonical name order inside each row. Filter
retains only true (not null); select resolves its input ordinals before the row
loop and emits authored projection order. Input tables are not mutated.

Fixed tests execute a real checked/lowered values → derive → filter → select
chain, check independent scalar results, competing row/binding failures, foreign
owner/wrong-branch rejection, retained no-op identity and a derive-output limit
that cannot be bypassed by later select. Operation failure exposes no row prefix.
Logical output counters and expression-control counters can span kernels.

The final fragment driver remains absent. Whitebox tests explicitly connect
these production-intended pieces; there is no arbitrary-JSON run API or ordered
derive workaround. Remaining work includes registry-bound fragment construction,
input proof obligations and complete preallocation admission/physical live-value
tracking. Schema/field setup work is now charged as described below.
The current retained-output check is not a claim that temporary allocations are
already bounded by the output limit. Ordinary builds retain unused private-code
warnings until the fragment driver connects this path.

Control-work accounting now includes column-index setup, projection metadata,
snapshot name hashing, per-row field copies, expression field lookups and both
operands' UTF-8 size before text comparison. Select uses pre-resolved ordinals
without constructing a snapshot map. Exact fixed budgets cover empty-input
setup and multibyte comparisons. These are logical work charges, not measured
CPU instructions; physical live memory and allocation admission remain open.

## Existing Relation node wire

`emit_kernel_node` emits complete `id`, `in`, `op`, `params` steps, not just
expression bodies. Map uses `params.exprs`, filter `params.expr`, and select
`params.columns`; the existing column rename form uses `{from,to}` when needed.
Generated IDs and input references come from the prepared checked owner. Map
bindings retain canonical order, select retains authored order, and an empty
map remains a node. The writer enforces whole-step bytes/nodes/depth.

Reference shape inspection used AoA `dbab4fe8c1d624d81ed967f90e2abe742163f84f`,
`packages/pipeline/src/index.ts` and `packages/rela/src/core-steps.ts`. The latter's
nonempty-map restriction is not imported: the current ActQL no-op law wins.
Current expression nodes use the pinned ActQL expression contract, not the
reference adapter's historical expression type. This inspection is not evidence
that that adapter can execute these emitted nodes without integration work.

Independent full-string tests cover all three operations, branch wiring and
exact whole-node byte limits. Registry parameter validation, expression-root
evidence, runtime-obligation binding and the whole pipeline envelope remain
open. Values-node emission is now described below. No emitted individual node
is an execution permit.

The private row tests now also run supplied-input → map → filter → select,
check branching back to the pre-filter producer, and enforce one cumulative
output budget across operations. A filter that emits no rows does not change
which earlier table a later explicit branch consumes. These tests still wire
the kernels explicitly, so they do not prove automatic fragment execution.
Main/integration has accepted ownership of the missing values execution-params
contract, as recorded in the shared-contract request. Delivery subsequently
arrived in main `dab50b1` (incorporated as `d38d2ad`); values wire lowering now
consumes it, while backend/registry admission remains open. No local shape was invented.

Parameterized four-operation vectors now bind the same checked preparation to
two different values, use each Parameter in both values cells and derive RHSs,
and compare fixed results. Mixing a table from one binding with the other's
kernel fails before evaluation. A separate nullable-input vector verifies lazy
conditional selection and that a NULL filter predicate excludes the row. These
close private-kernel coverage gaps, not the still-open fragment admission gate.

Defensive-copy expression/kernel views now expose O(1), allocation-free entry
counts. Execution reserves their copy work before constructing the array view,
rather than relying only on lowering limits. A lazy coalesce test distinguishes
copying child references from evaluating unselected children. This bounds
cumulative view-copy work; separate peak live-memory accounting is still open.

## Per-operation row workspace

The private row evaluator now requires a fresh, explicit `RowWorkspace` limit.
Before inserting container entries it reserves structural slots for the borrowed
input layout, copied kernel view, column ordinals, projection metadata, snapshot
maps, output cells and retained row references. Snapshots are released logically
at the end of each row, including a false/NULL filter result. Retained rows remain
charged for the operation. Failure returns no partial table; a partly consumed
workspace cannot be reused for another operation.

Independent fixed boundary tests count a two-column/two-row projection at 22
slots (21 fails), a fully rejecting filter at peak 15/live 12 (including its
binary-expression continuation), and an empty map
at peak 20/live 18. They also check unchanged borrowed input and a successful
fresh invocation after resource failure. The whitebox convenience wrapper only
supplies an explicit generous limit to this sole evaluator; it adds no alternate
execution semantics or production default.

Slots are structural entries, **not bytes, allocator capacity or RSS**. Empty
container headers and hash-map capacity are not modeled. This is not a claim of
complete physical memory admission: retained tables across a fragment,
nested immutable payload bytes and actual allocator/GC behavior
still need an integrated budget. Logical output and cumulative work remain
separate counters, and none replace main's static capacity evidence.

Validation for this unit: execution tests 27/27 and lowering tests 25/25 on each
of JS, Wasm and native; both package interfaces match across all three targets
and are unchanged by this unit. Registry checks 2/2, document tests 11/11 and
865 local links pass. Formatting and whitespace checks pass. The ordinary build
still reports 14 unused private-code warnings while the fragment driver is not
connected. The full repository suite and production execution are not claimed.

Capture-to-table conversion now also requires an explicit fresh structural
workspace and the caller's cumulative control budget. It reserves both borrowed
capture row entries and the new table layout, checks each row width, and charges
field-name bytes and cell-copy work before allocating copied arrays. Nested
admitted values remain immutable shared payloads. There is no unbounded
production-private conversion helper; the whitebox helper delegates with stated
limits. Independent vectors require 14 slots and 10 work units for a two-column,
two-row capture, reject one-unit deficits, and verify that modifying copied row
containers cannot mutate captured input. Conversion followed by projection uses
one 28-unit work budget (27 fails), not fresh per-step work budgets. Structural
workspace lifetime across the complete fragment still needs integration; these
per-operation checks do not authorize resetting a future fragment-wide limit.

Conversion-unit validation: execution tests 29/29 on JS, Wasm and native;
unchanged matching public interfaces across those targets; format, whitespace
and 865-link checks pass. The 14 unconnected-private-code warnings remain.

Expression evaluation now shares the row workspace, reserving copied child-view
entries before copying and continuation slots before pushing. Parent views stay
charged during descendant evaluation. Completed unary/binary/conditional frames
and completed or short-circuited Many/Case views release their logical slots;
moving a binary or multi-child continuation forward retains its reservation.
Workspace failure carries its expression position separately from work/depth
failure. Two nested two-child coalesces require six slots above the caller's
existing live count; one fewer fails. Success restores the caller's live count,
including CASE's selected and fallback paths. This changes resource accounting,
not demanded expressions or result semantics. Counts describe logical container
entries and frames, not the allocator size of a frame, tuple, object or array.

Expression-workspace validation: execution 31/31 on each of JS, Wasm and native,
unchanged matching public API, format/whitespace and 865 links pass. Existing
private-code warnings remain; fragment-wide retention and shared-contract
admission are still open, not inferred from these component tests.

## Retention wiring preparation

Private `prepare_wiring` consumes the bound prepared owner's generated input
IDs and checked occurrence counts. It resolves ordered references to physical
slots, preserving branch edges, and records each table's last consumer. Sources
are registered before steps and a step only after resolving its references;
forward/foreign IDs cannot be repaired by a global name lookup. Authored input
names are not confused with generated step IDs. No expression or source is
parsed or retyped here.

Every prepared step remains in the schedule. An unconsumed output expires after
its producer runs, not before: unused derive failures and no-op operations must
still occur. The future fragment driver supplies retained output IDs; this is
not Program Result selection, root pruning or Result publication. Unknown
retained IDs fail atomically and duplicates do not duplicate retained storage.

Metadata construction precharges structural entries, copied reference views,
work and identifier lengths. Its lookup map is released logically after
construction. A fixed four-step branch vector has routes `[], [0], [1], [1]`,
last-use positions `1, 3, 2, 3`, 23 peak slots / 19 retained slots and 71 work
units; one-unit deficits fail. This remains retention metadata, **not an
executable fragment**: actual table release, registry/params admission, input
proof obligations and complete fragment budgeting still need connection.

Retention-preparation validation: execution tests 34/34 on each target, matching
unchanged public API, formatting/whitespace and 865 links pass. Ordinary builds
now report 25 unused-private-code warnings, including the unconnected retention
metadata. No public execution entry or runtime-conformance claim is added.

Private table storage now adopts successful operation outputs in prepared step
order. It verifies owner, producer ID and availability of every input before
updating retained tables. Source/output overlap is charged before releasing the
last-consumed sources; retained branch outputs remain available. Release visits
the current input edges, not all historical tables. A four-step branch vector
retains 12, 15, 15 and 9 structural entries after successive commits, with a
23-entry peak. Failed adoption keeps the previous tables and step cursor intact;
its partially spent budget is not a fresh retry budget. This is not durable
commit or execution authorization, and tests still wire row kernels explicitly.
Fragment-wide nested-value accounting and simultaneous computation/store
workspace accounting remain open; this store alone is not a heap bound.

Storage-unit validation: execution tests 36/36 on each target, unchanged
matching API, format/whitespace and 865 links pass. Ordinary builds report 27
unused-private-code warnings until the driver is connected.

## Bound values node wire

`prepare_values_node` retains the exact bound owner and checked values node,
enforces explicit row/cell ceilings, and checks that each Parameter reference
has its admitted binding before constructing opaque emission material.
`emit_values_params` follows main's `dab50b1` execution contract: complete checked
field contracts and ordinary typed wire rows, preserving empty schema evidence,
row order and duplicates. `emit_values_node` adds the generated ID, zero inputs
and `REL.values` operation. Quotation is already removed by checking; only typed
Parameter cells resolve bindings. Nested business keys are never interpreted.

The expression and values emitters share the same iterative admitted-value wire
writer, including exact fixed-scale decimal strings. Output limits belong to the
bounded writer; a node is only observable after successful writer completion.
This material is not registry/backend admission or a runnable Plan.

`scripts/lowering-values-vectors.mjs` generates 18 normal vectors from main's
fixed expected canonical params, without recomputing expected bytes from product
output. These exercise the quoted-literal source route; a separate real Parameter
test checks binding ownership and full node output. Author source contracts omit
checked-only `additional_properties` and `element_type`; emission restores them
from checked contracts. Invalid-wire admission remains a separate executor
obligation, and these successful emission tests do not close that obligation.

Validation: lowering 45/45 and execution 36/36 on JS, Wasm and native; matching
public interfaces, formatting, generator drift, five registry/contract tests and
867 links pass. No shared schema/pin was independently revised by lowering.

## Atomic sequence preparation

`prepare_sequence` prepares every operation under one bound owner, returning an
opaque `PreparedSequence` only after all steps succeed. It preserves no-op and
unused operations. Node count, values rows/cells, binding count, field-name bytes
and expression work/node/literal totals span the sequence rather than reset per
operation; expression depth remains a depth limit. Kernel preparation exposes
its residual budget privately so the sequence does not rewalk/reinfer expressions.

The sequence is not an execution permit. Registry/params admission, input proofs
and runtime obligations must still be discharged before a fragment execution
entry exists. Ordered derive can be prepared after a supported prefix without
becoming encodable or executable. `emit_sequence_steps` emits the normative
steps array only; it does not invent a fragment envelope or final Plan identity.
Independent tests fix the complete four-operation array and verify late failures
from cumulative expression, binding, name and values-row/cell budgets.
Failure exposes no partly prepared sequence; an encoding failure exposes no
complete serialized step array.

Sequence-unit validation: lowering 49/49 and execution 36/36 on each target;
matching interfaces, format, generator drift, whitespace and 867-link checks
pass. Execution admission is still open; the 27 unused-private-code warnings
are retained rather than disguised as a completed driver.

### Execution-admission handoff audit

At lowering `f78ce03`, main's `dab50b1` REL.values params contract is incorporated
and its accepted conversion vectors pass. The selected `pipeline_registry_cid`
still identifies the recovered base registry whose 57 signatures do not include
`REL.values`. `target_registry_requirements.REL.values.execution_contract` is a
requirement for a supporting registry, not proof that the old registry implements
it. The exact preimage remains in `registry-preimages.json` and is checked by
`scripts/lowering-registry.test.mjs`; do not relabel it or combine a new body with
the old CID. Main at `9e60528` has no later committed replacement in the inspected
handoff. Integration has been asked whether main will supply the supporting
registry/pin or authorize lowering to construct it. No shared mutation is made
while that boundary is unresolved.

Existing public input APIs expose `candidate_keys`, `logical_order`,
`input_producer` and carrier/schema information on the checked owner. The current
capture boundary validates row values only; the internal driver's successful
execution does not discharge key/order/provenance claims. These must be consumed
and checked, not independently inferred or silently dropped. Whole-Program
capacity/admission remains main's boundary per the agreed scope. Ordered derive
still independently needs the shared executable row-kernel contract. Thus there
is useful completed calculation below admission, but no basis yet to label the
sequence a conformant, runnable registry-bound fragment.

The admission audit reran the entire repository, not only the two new packages:
`moon test --target js`, `wasm`, and `native` each passed 2,149/2,149 tests at
`f78ce03` with MoonBit `0.10.12+1634b282e`. `npm run check:docs` also completed
successfully after the audit text update. No product source or contract changed
during those checks. This regression evidence does not establish missing
registry support, input-claim verification or ordered-derive conformance.

## Internal sequence component driver

The package-private `evaluate_sequence_components` now drives capture, conversion,
row evaluation and retention automatically from `PreparedSequence`. It checks
the complete supplied-input owner/origin set before computation, resolves each
operation's checked branch from retention slots, and adopts outputs in original
step order. Only the completed store is returned. Errors expose no prefix store,
and unused failing operations are not pruned by retained output selection.

Control work spans metadata, capture conversion, evaluation and adoption. Input
rows and logical input values accumulate across supplied and inline inputs;
logical output allocation accumulates across all row operations. Separate
explicit ceilings bound metadata entries, store entries and per-operation
workspace. These scopes are not a single measured heap budget; nested retained
payloads are bounded by cumulative logical input/output limits, and allocator
capacity/GC timing is not claimed. The driver does not reset cumulative budgets
when an intermediate table is dropped.

Fixed vectors run all four operations with branch retention, supplied-input
owner rejection, two Parameter bindings, unused RHS failure, exact cumulative
output limits and a second values node exceeding the total input-row limit.
They no longer manually invoke a different kernel for each operation. This
driver remains internal: registry/params admission, input key/order/capacity
proofs and runtime obligations are not discharged by component execution and
must precede any exposed fragment-run API. Ordered derive remains pending.

Driver-unit validation: execution 41/41 on JS, Wasm and native; unchanged
matching API, format/whitespace and 867 links pass. Ordinary builds report 29
unused-private-code warnings while the admission entry remains unconnected.

## Supplied input candidate-key verification

The internal sequence driver now consumes the checked owner's candidate-key
witnesses before evaluating any operation. For currently admitted non-null scalar
key domains it verifies each complete tuple with a typed structural hash key;
map collision resolution uses complete equality, not a concatenated string or
digest alone. Individual component duplicates are allowed when the tuple remains
unique. No duplicate normalization, row reordering or output pruning is introduced.

Key ordinals are resolved once per witness. Ordinal slots, retained tuple atoms
and map entries consume the operation workspace; traversal and UTF-8 text lengths
consume the shared control budget. Successful verification releases its workspace.
This is logical accounting, not a measured allocator/RSS or worst-case hash-table
CPU guarantee. Failed execution returns no partial store and must not reuse the
partially consumed budget as a fresh retry.

Four independent tests cover duplicate rejection through the sequence driver,
compound keys and input order, exact workspace/control limits with Unicode text,
and empty input/invalid limits. Nullable generated witnesses remain explicitly
pending rather than being silently treated as a non-null declared primary key;
opaque reference input admission and its identity semantics also remain pending.
Order and provenance claims are not discharged by this check. Consequently this
does not open an admitted fragment-run API or alter the shared registry/pin.

Validation: execution package 45/45 on each of JS, Wasm and native; generated
public API is unchanged and identical across the three targets. Format,
whitespace and 867 document links pass. Ordinary info builds have 37 warnings
from private components not yet connected to a production entry, with zero
errors. The full-repository suite was not rerun for this input-key change.

## Fixed values corpus through the four-operation driver

`scripts/lowering-values-vectors.mjs` now also generates 18 execution tests from
the accepted main-owned params vectors. Each uses quoted source values followed
by empty map derive, `filter(true)` and a reversed field-list select. Assertions
check exact field order, row order/multiplicity, nulls, nested object/array values,
decimal coefficient/precision/scale, temporal values and vector components. Empty
rows still preserve the selected schema. Business `$param` and `literal` keys
remain data. Expectations are generated structurally from the fixed corpus, not
by decoding the evaluator's own output or regenerating golden values.

These tests complement nonempty derive, failure-order and actual Parameter-owner
tests; corpus labels such as `bound-parameter` here test the already-bound value,
not the binding mechanism. They exercise the single private sequence driver,
not a second evaluator. They do not validate arbitrary incoming execution params
or discharge registry support, ordering/provenance or ordered-derive obligations.

Execution package: 63/63 on JS, Wasm and native. Generator freshness and format
checks pass; this increment changes only tests, their generator and this guide.
No runtime or public API is changed. The first generated sources omitted the
required values alias and failed checking; the source generator now includes
`as: seed`. No product acceptance rule was relaxed to pass the vectors.

## Shared registry handoff (a728bda)

Main's complete 58-operation registry is imported unchanged at
`spec/dependencies/aoa-pipeline-registry.json`, selected by
`sha256:b97a22de3664c1dafe3bc1e6791f1f8bcfb70324a1fcc1087450fe057e0f2311`.
The REL.values execution contract remains
`sha256:c95bc0d474fd6fbe62d3182bdefe6af412070f6ad2c8e102c5279d7a8b3eed17`.
The earlier admission audit's missing-registration finding is closed. Its
historical 57-operation body/CID are not rewritten or accepted as values support.
Lowering's registry checks consume the shared registration instead of falling
back to a target requirement. Main's negative resolver vectors cover old
selection, changed signatures/references and changed contract bodies.

Cherry-pick `a52b2e2` reconciles generated requirement hashes and four language
document references because this branch retains an earlier specification
baseline. They were regenerated from the merged document; no other main changes
were imported and the supplied registry/contract identities are unchanged.

This closes the registry handoff, not runtime fragment admission. Ordered derive
still awaits the separately owned row-kernel contract. Backend capability,
remaining input obligations and the typed fragment execution entry are not
established by registry tests. No arbitrary JSON execution entry is introduced.

Handoff verification: the whole repository passes 2,173/2,173 tests on each of
JS, Wasm and native. Shared/lowering registry checks pass 7/7, `check:docs` passes,
metadata reports no changes, and fixed values generator freshness/whitespace
checks pass. This branch's smaller count than main reflects its isolated baseline,
not a claim to have run main's staged compiler suite. Linux CI was not run.

## Runtime registry identity admission

`execution_relation.admit_relation_registry` accepts immutable canonical registry
and REL.values execution-contract bodies, not caller-asserted CID strings. It
hashes both through the common canonical encoder under explicit per-body byte,
node and depth limits. Only the exact selected identities generate the opaque
`RegisteredRelationContracts` value. Exact registry identity binds the operation
signatures and contract file/pointer; exact execution-contract identity binds
its schema, semantics and dependency references. This implementation supports
the current selected contract set, not arbitrary registry negotiation.

Pins and test bodies are generated from main-owned files by
`scripts/lowering-registry-vectors.mjs`; the existing independent registry tests
continue checking those files and historical identities. No new shared registry
or contract is defined. Raw artifact parsing and noncanonical-input rejection
remain the loader's preceding responsibility: this function neither parses nor
normalizes a wire artifact.

The single private sequence driver now requires this opaque value. All existing
driver vectors, including the 18 fixed values cases, obtain it by validating the
actual shared bodies; there is no unchecked replacement driver or fabricated
test permit. This discharges registration identity only, not backend support,
input provenance/order, ordered derive or Program authorization. The general
fragment entry remains unexposed until its remaining obligations are connected.

Validation: execution tests 65/65 on JS, Wasm and native; public API identical
across targets (SHA-256
`5174c383f9d9aa2d19c23055ff1cd941b4d06be4575144491ac2591a72253f29`).
New negative tests reject the historical body, wrong execution body, invalid
limits and byte/node/depth exhaustion at either hashing stage. Formatting and
both owned vector generators pass. Ordinary info builds retain 39 private-code
warnings and no errors; the whole-repository suite is not rerun for this unit.

## Conditional producer evidence is not raw input admission

`pipeline_typing.ProducedInput` and its `LogicalOrder` explicitly describe the
conditional successful output of a retained checked producer, not measured data.
The current `capture_input` establishes schema/value ownership only. The driver
therefore returns `InputExecutionEvidencePending(input_index)` for a captured
input with `input_producer`, before row evaluation. Equal counts, unique keys or
apparently sorted rows cannot substitute for successful execution of that exact
producer, its obligations and bindings. Normal explicitly supplied schema/key
inputs remain supported and their existing driver tests still pass.

This is an implementation gap, not a language prohibition. Closing it requires
an immutable successful fragment output handle tied to the exact producer and
target (plus any checked projection), then adopting that handle into the receiving
owner. Do not silently strip producer evidence, rerun a potentially different
producer, or treat arbitrary matching JSON as its output. Program publication,
Host authority and whole-Program capacity are still outside this increment.

Regression checks use a values producer with established order and test genuine
expected rows, reversed rows and empty replacement. All pass value capture but
none fabricates successful producer execution evidence. Execution package passes
66/66 on JS, Wasm and native; this unit does not claim producer adoption complete.

## Successful sequence output identity

The internal driver's success type is now `CompletedSequence`, separate from its
mutable in-progress `TableStore`. Its sole production constructor is after the
last operation succeeds. It retains the selected registry contracts and the exact
`PreparedSequence`/`BoundPrepared`, including Parameter bindings. `completed_output`
selects an existing retained Input/Step target from that completion and preserves
the parent alongside the table; absent, released and out-of-range targets return
None without recomputing or substituting data. No arrays or constructors are
exposed outside this package.

This supplies the origin side of producer adoption. The receiving side still
must match the checked producer owner, target, binding context and any explicit
projection before accepting it; raw capture remains insufficient. The handle
proves this component sequence completed, not whole-Program obligations or
publication. Existing component failures return no handle, even when an earlier
retained table was successfully computed.

Execution tests pass 68/68 on JS, Wasm and native. New vectors cover exact target
and bound-owner retention, unavailable output rejection, and later failure after
a retained prefix. All existing sequence vectors use the same completion type.
Formatting, generator freshness and whitespace checks pass. Public API is
unchanged; these are private execution types, not an SDK expansion.

## Receiving producer identity binding

`bind_completed_input` matches a successful output against one receiving
`ProducedInput`: exact checked producer pipeline, exact selected `BoundPrepared`
and exact Input/Step target. The expected bound producer is explicit because
`ProducedInput` retains an unbound checked pipeline, not an invocation's Parameter
values. Matching source text or equal schema/data does not identify that binding.
The resulting private `BoundProducerInput` preserves receiver/input/output owners.

This is identity binding only. It does not install rows, waive input budgets or
authorize a Program. The driver still refuses raw captures for produced inputs.
At this checkpoint, checked producer projections returned
`ProjectionExecutionPending`. The projection adoption increment below supersedes
that temporary gap. No shared API/schema/pin is modified.

Regression cases check exact matching, wrong target, foreign producer pipeline,
wrong input, ordinary input with no producer, and a separately bound handle of
the same checked pipeline. Execution tests pass 69/69 on each target. Existing
Parameter tests cover binding values; this new test specifically checks owner
identity even for an empty binding environment.

## Completed producer row adoption

The same private driver now accepts `produced` bindings alongside raw captures.
Each input is assigned by its exact receiving ordinal; counts, duplicate slots,
receiver identity and selected registry identities are checked before operations.
An input must have exactly one source. Raw captures still cannot satisfy a
ProducedInput. Validated unprojected producer output does not round-trip through
JSON or re-resolve column names/types. Its private immutable row storage is shared
under a new receiving-owner table wrapper.

The receiver charges all adopted rows and nested values to its own cumulative
input budget, including names, text, depth and work. Raw and producer inputs share
the total row limit. Retained table slots are charged on installation even when
their backing data is shared. Input dispatch and retained producer-binding arrays
are charged against the same metadata workspace used by wiring; completion copies
the binding list under that budget and retains the exact successful dependency.
Failure returns no receiving completion and neither mutates nor re-executes the
upstream output. At this checkpoint explicit producer projection remained pending;
the following increment connects it rather than bypassing it.

These per-fragment logical budgets do not claim to bound the complete ancestor
graph's physical RSS: completed dependency handles retain their parents. A future
invocation-level retention policy must account for that graph without dropping
the provenance needed to distinguish executions. No such Host/Run policy is
introduced in this increment.

Execution tests pass 71/71 on JS, Wasm and native. New cases cover successful
producer-to-receiver execution, exact input budget boundaries, raw/producer mixed
inputs, duplicate producer slots, foreign receiver rejection and immutable retry
after receiver budget failure. Existing fixed vectors remain unchanged in meaning.
Formatting, both generator checks and whitespace checks pass; public API remains
unchanged. This closes unprojected component adoption, not the full fragment entry.

## Checked producer projection adoption

The receiver now retains the exact checked projection from `ProducedInput` along
with its bound producer, target and successful output. After charging the complete
unprojected input to the receiver's cumulative input budget, the driver applies
that projection through the same row-major evaluator as authored select. It does
not infer a new schema, invent an authored node or recompute the producer. The
private transient dispatch view is neither a wire format nor an executable
fragment API.

Projection preserves row order, duplicates, selected column order and aliases.
The receiver-owned projected table is installed under its existing input ID.
Projection metadata is reserved before obtaining the checked API's defensive
array copy. Input layout, ordinals, output arrays and cells use the existing
operation workspace, including for empty input. Projection output consumes the
same cumulative output value budget as subsequent authored operations; dropping
columns cannot evade input accounting. Failed projection or later operations
produce no completion and leave the upstream result available unchanged.

Independent tests cover reordered/aliased columns, a dropped column, empty rows,
exact empty-layout workspace (10 entries, 9 rejected), cumulative input/output
limits and retry after receiver failure. Execution tests pass 74/74 on JS, Wasm
and native. Public interfaces match across targets and remain unchanged; format,
both fixed-vector generators, links (869), documentation tests (11) and examples
pass. Full-repository and Linux CI tests were not rerun for this increment.
This closes checked projection adoption within the internal driver;
ordered derive still awaits the shared row-kernel handoff. The complete fragment
entry's outstanding input obligations and capacity integration remain separate
from this component success. No Program/Run execution permission is claimed.

## Expression root positions

`prepare_roots` consumes an opaque `PreparedSequence`, not source JSON. Each
read-only root entry retains the exact lowered expression used by that sequence's
AoA emitter, together with the generated step ID, step index and parameter pointer.
The index retains the sequence itself; callers cannot replace entries or detach
their owner. Values, select and empty derive have no invented expression root,
but their operation nodes remain present and executable.

Map pointers are `/exprs/<RFC6901-escaped-name>` and filter uses `/expr`. Root
ordering follows graph step order, then UTF-16 pointer order, independently of
row evaluation order. For example the map evaluates `/`, `a`, `~` in that name
order, while its root pointers sort as `/exprs/a`, `/exprs/~0`, `/exprs/~1`.
Generated `derive_10` does not sort ahead of `derive_2`: graph position wins.

Explicit limits bound root count, cumulative UTF-8 pointer bytes and work.
Pointer capacity is checked before escaped-string construction. Bottom-up merge
sort checks its work budget before comparisons and output writes, including
pointer-comparison lengths; at most two root-reference arrays coexist. Overflow
safe range arithmetic avoids unchecked doubling at the final merge. Budget
failure publishes no index and leaves sequence/evaluation order unchanged.

The root index is location preparation, not the complete machine root record.
Canonical source regeneration, demand paths, fragment witnesses, shared outer
registration and final re-admission remain open. It does not supply dummy demand
evidence or claim a fragment CID. The API is an internal core package surface,
not a public SDK or an arbitrary wire execution entry.

Independent tests cover escaped pointer order, exact expression identity, empty
map retention, graph order beyond nine steps, UTF-16 versus UTF-8 Unicode cases,
and exact/one-below cumulative budgets. Lowering tests pass 53/53 on each of JS,
Wasm and native. Shared schemas/pins and execution/Host APIs are unchanged.
The added lowering-package API matches across targets; formatting, both fixed
vector generators and 872 local links pass. Full-repository and Linux CI tests
were not rerun for this increment.

## Shared expression demand integration

### Source values and machine nodes

The expression-fragment request is not the outer four-operation composition.
Values and projection operations remain outside this binding. A kernel-scoped
root index retains the original prepared sequence and half-open step range,
including for an empty snapshot map. Root numbers are local to that index;
original step IDs and checked expression owners do not change. This permits
independent fragments to each use `/roots/0/source` without mixing evaluation
frames or constructing a shortened sequence that pretends other operations did
not exist. A single-kernel fragment is a composition strategy, not a language
requirement to persist or execute every operation separately; compatible fusion
still requires its own complete request and root reconstruction.

Source and machine pipeline projections share one opaque kernel-fragment owner.
Both preserve the original step ID and output target, and name the single local
Relation source `input`. The outer upstream ID remains attached to that owner
for composition; projection does not mutate the prepared kernel's wiring.
Empty snapshot maps retain an actual derive node even though their root table
is empty. The machine projection reuses the existing kernel node emitter with
only its local input rebased. The source projection uses the same bindings but
emits retained normalized syntax. Neither projection alone is an executable
artifact: request schema/Parameter bindings, ceiling witnesses, root evidence,
canonical identity and sealed-fragment admission remain separate obligations.

The request projection retains that same owner, supplies its checked input
schema and bound Parameter contracts/values, and carries explicit positive
request ceilings. Its canonical identity is formed by the shared canonical
codec, through a bounded private adapter used only for generated typed output.
Root evidence uses that same adapter. Object enumeration differences disappear
from identity; array order, Parameter values and request ceilings do not.
Canonical identity does not discharge resource witnesses or sealed admission,
and these internal adapters do not accept externally supplied artifact JSON.

The local request's row and value-byte ceilings are projected into the
expression fragment's registered `contract_ceiling` witness form. Each witness
binds the complete canonical request CID as its sole dependency and its exact
request pointer as the source field. Resolved limits retain that pointer and
use `engine_atomic` enforcement with `fail` on breach. They are sorted by
request pointer, not by CID. These generated bodies are declarations of the
selected bounds, not applications of Program cardinality-inference laws, and
do not by themselves admit the fragment or discharge input obligations.

Fragment generation material is prepared from one opaque request. Its local
machine graph and complete root list are derived from the request's retained
pipeline owner; callers cannot substitute independently prepared roots or a
different graph. Root order follows the shared index, including an empty list
for a snapshot map that still retains its graph node. The aggregate generated
value bytes and nodes consume one budget across request, graph and roots.
Temporary representations have their own bounded preparation paths; this
accounting is not a process-heap ceiling. Material preparation is atomic and
does not itself supply the enclosing contract admission or execution permit.

The generated candidate closes the map/filter fragment envelope with request,
graph, roots, limits, checked output schema and expression-contract identity.
Its execution-contract body is hash-checked against the selected registry's
pin. This checks registration, not an individual fragment's runtime suitability.
The candidate hashes the entire canonical envelope without `fragment_cid`,
then emits that identity in the complete body. The current closed-schema,
profile-free expression kernels produce `output_open: false` and no profile
evaluations; admitting open schemas or profile nodes requires their retained
evidence rather than silently inheriting these projections. The candidate is
still separate from sealed admission, backend obligations and Program permission.

Generated-fragment checking rebuilds request material and the complete candidate
from its retained checked request. It compares both the canonical stored body
and the material used by the emitter with the rebuilt body, in addition to the
claimed CID and selected contracts. A correctly hashed unrelated graph or root
cannot replace part of that request. Successful checking retains regenerated
material rather than preparation arrays owned by the caller. This typed check
does not admit arbitrary saved JSON, reparse author source, or discharge runtime
input/key/order/value-limit obligations. The execution boundary must still
enforce those obligations before using the retained checked kernel.

The shared row evaluator accepts logical accounting for snapshot maps and
filters as well as ordered bindings. Map results remain leased until the
complete output row is accounted; filter predicates use the same expression
evaluator and release both the predicate and rejected input roots. Input
admission precedes expression evaluation, and errors clean up all logical
roots without publishing a partial table. This internal accounting hook does
not yet choose request/Host limits or establish input evidence on its own.

An immutable fragment runtime context binds explicitly supplied enforcement
limits to the regenerated fragment and its exact checked kernel. Row and value
ceilings cannot exceed that fragment's request; tighter supplied bounds remain
explicit. Live/work and physical encoder limits are supplied separately, not
inferred from static capacity facts. Fresh counters are created for each
execution, and cannot be requested for an independently prepared kernel even
when its source is identical. This connects bounds to the common row evaluator,
but is not itself evidence for input keys, ordering or producer completion.

The existing sequence driver can consume the exact set of checked map/filter
runtime contexts. Before capture or RHS evaluation it checks owner, registry,
duplicate steps and missing contexts, then supplies their fresh budgets to the
same row evaluator. Ordered contexts retain their separate extension checks.
An explicitly empty set does not silently fall back to unchecked map/filter
execution. The absent option remains only for component-level verification;
neither option constitutes Program permission, and full input evidence and
ordered-fragment closure remain separate integration obligations.

Each expression root retains its exact typed owner. Source projection reads the
normalized syntax of that owner; machine-node projection reads the bound lowered
expression. A Parameter remains a reference in source while becoming a literal
in the machine node. An omitted CASE ELSE remains absent in source even when the
checked machine expression carries a typed-null ELSE. Literal objects are data,
not nested author instructions.

Source projection streams indexed cursor children into a bounded Writer using
one continuation per open container. It does not copy a complete sibling array,
reparse JSON or infer expression meaning. Object enumeration is preserved by
this projection, just as with the generic Writer's JSON adapter. Consequently
its bytes are not themselves a canonical artifact or CID preimage: enclosing
artifact serialization must impose canonical object ordering. Writer limits
are cumulative across all embedded roots, and only successful finish publishes
the completed document.

Main's standalone API handoff `06742b9` is imported as `df75931`.
The duplicate conditional-rule traversal introduced in `b3680f2` is removed.
`prepare_demand` delegates directly to `expression_typing.derive_demands`
using each root's exact retained `TypedExpression`. No source reparse, type
inference, private topology copy or runtime reevaluation is introduced.

The root-scoped index retains opaque shared `DemandPaths`. Node indices and
condition tests belong to that root's typed expression, not a global numbering
scheme. Shared bounded accessors expose source-relative RFC6901 pointers and
detached test lists. An implicit CASE ELSE retains its conditional demand but has
no source occurrence (`None`); the adapter never invents an ELSE pointer.

One preparation budget spans all roots: root count, typed node count, work,
address text bytes and retained links. Each shared call receives only the
remaining resources, and its reported usage is accumulated without resetting.
Root traversal/storage is charged before allocation. Negative limits and
exhaustion return typed errors without publishing a partial index. Pointer/test
expansion has its own explicit accessor limits, not an implicit unlimited copy.

Five independent vectors assert nested IF/coalesce source paths, CASE demand,
implicit ELSE absence, eager AND/OR, opaque literal data, exact owner identity,
root/frame separation, detached test lists and exact/one-below resource limits.
Expectations use semantic pointers rather than the retired traversal's incidental
node numbering. Exact-cost tests use measured usage only for resource boundaries,
not to derive semantic expectations.

This remains an internal preparation API. Binding source-relative pointers into
the final `/roots/i/source/...` envelope, canonical source emission, registered
outer-fragment admission and ordered derive are separate integration work.
The existing evaluator remains the only computation engine.

Verification after the shared-API migration: full repository JS/Wasm/native
2,200/2,200 each, including lowering 58/58; API equality, format, fixed-vector
freshness, two registry checks, 872 document links and 11 document tests pass.
Existing unused private-component warnings remain; this is not a global
`--deny-warn` pass. Linux CI was not run.
