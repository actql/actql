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

`node --test scripts/lowering-registry.test.mjs` independently verifies both
full preimages against the existing pins. It also checks the four preparation
signatures against the registry plus normative target requirements. In
particular, `REL.values` is a target requirement, absent from the base registry.
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

There is deliberately no executable fragment or Plan emission yet. Preparation
does not discharge expression obligations, parameter binding, operation-parameter
contracts, final serialized size or any Program-level authorization.

## Remaining implementation and release conditions

| Area | Current state | Condition for closing |
| --- | --- | --- |
| Four-operation wiring | Implemented preparation | Keep tests as executable lowering is connected |
| AoA expression lowering | Typed scalar/conditional nodes and bounded encoding implemented | Connect roots to complete Relation nodes and evaluator |
| Bound parameters | Owner association, expression substitution and values-cell capture implemented | Add parameterized end-to-end fragment execution vectors |
| External rows | Object-schema input admission and immutable capture implemented | Connect to full fragment input obligations; scoped row representation remains unsupported |
| Map/filter/select row evaluation | Private evaluator connected; fixed four-operation values chain tested | Connect supplied input, branch and parameter cases through fragment driver |
| AoA fragment lowering | Complete map/filter/select step emission and expression wire implemented; values/pipeline envelope remain open | Bind registry contracts, roots and runtime obligations, then admit complete fragment |
| Runtime budgets | Cumulative expression/control/logical-value limits implemented | Close temporary/live allocations and complete work accounting before exposing fragment API |
| Ordered derive | Checked references available; executable contract pending main | Consume main's registered row-kernel extension without a substitute opcode |
| Additional expression obligations | Not implemented | Discharge the specific profile/pattern/other obligation before evaluation |
| Other operation handlers | Not implemented here | Add normative lowering and evaluator support, then replace coverage-status tests |
| Product Run/publication | Outside this increment | Separate integration with main's acceptance and capacity boundaries |

This table is the current status. Increment sections below retain historical
verification counts and describe what was established at each checkpoint, not
the latest total. Priority is closing the existing four-operation path, its AoA
contracts and runtime budgets, not adding more operations.

The ordered-derive wire/capability binding requires the
[shared row-kernel integration unit](row-kernel-integration-request.md).
This is not a reason to drop array-form derive from the agreed goal.

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
pass-through; unsupported comparison domains return a distinct implementation
gap instead of inventing stringified equality.

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

`prepare_kernel` groups already checked map bindings, predicates and projections
with their exact bound owner, step and input ID. Expressions remain the normative
typed expression representation. This is a non-wire preparation object, not a
new execution language, registered AoA fragment or final Plan admission token.
The map and projection arrays are defensively copied at access boundaries.

Expression-lowering node/work/literal limits are consumed cumulatively across
all bindings rather than reset for each RHS. Separate binding/name limits bound
the operation container. Canonical map binding order and authored projection
order come from the existing checked APIs; preparation does not infer either.
Empty maps retain a real preparation object. Ordered arrays return the temporary
`NeedsSharedRowKernelContract` gap until main supplies the registered extension.
Their individual checked expressions remain available for independent work.

Fixed tests cover map payloads/order, retained no-op, projection order, defensive
access, whole-operation cumulative failure and the explicit shared-contract gap.
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
input proof obligations, schema/field setup work accounting, and preallocation
admission/physical live-value tracking for row snapshots and output arrays.
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
evidence, runtime-obligation binding, values-node emission and the whole pipeline
envelope remain open. No emitted individual node is an execution permit.
