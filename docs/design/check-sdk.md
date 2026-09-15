# Check SDK boundary

The standard check interface accepts a Program document or an admitted parsed
Program, supplied Parameter values, an environment of available inputs and
contracts, and compile limits. It constructs the
[CheckedProgram](checked-program.md) without requiring the caller to reproduce
compiler phases, contextual producer visits, or derivable capacity proofs.
Checking does not perform source I/O, authorize execution, select a physical
backend, or claim that runtime validation has completed.

## Inputs and outcomes

Document and parsed-Program entry points use the same semantic checking body.
Only the parser's admitted representation is reusable; an arbitrary internal AST
is not a checked input. Reuse avoids charging parsing that is not performed,
but retained document size, structure and depth must still satisfy the limits
of the current call. Source locations survive both paths. File and URL readers
belong to Host conveniences, not to Core checking.

The reusable Program owns measurements from its original parse and immutable
tree admission. Raw input bytes include a BOM, trailing whitespace and YAML
comments; a root span is not a substitute for document size. Parser node/depth
measurements and admitted-tree node/depth/text measurements remain distinct.
Admitted text bytes include field names, with both a largest-string limit and
an aggregate string limit. These measurements describe retained input, not
CPU work repeated by reading them. A child cursor's admission measurements
describe its whole owned tree, not the child subtree.

Reuse checks each current retention limit without reparsing, rebuilding the
tree or repeating structural stage validation. An exceeded retention dimension
is a diagnostic, not an external evidence request. It retains the source name
without fabricating a source span for an aggregate size failure. Semantic
checking and its current environment, bindings and compile budget still apply;
successful retention validation alone does not construct a CheckedProgram.

The document and parsed entry points take the same checking environment, values
and limits. Their explicit-evidence variants use the same semantic checking
body; ordinary callers need not manufacture an empty evidence inventory.
The environment retains admitted wire definitions, complete checker profile
declarations and selected numeric/Calendar/text contracts. Constructing that
configuration does not admit a Program, authorize I/O or assert backend
capability. Exact selected-handle applicability is checked during construction.

Input admission and semantic compilation are separate budget domains.
`CheckLimits.input` bounds the original source bytes/nodes/depth and admitted
tree/text/stage structure. `CheckLimits.compilation` applies to semantic
preparation after admission, including evidence binding and artifact emission.
The document entry actually performs the bounded source admission; the parsed
entry only checks retained admission measurements before semantic preparation.
Neither entry estimates parser CPU work from a source span or charges an
imaginary repeated parse. Source syntax and retention failures keep their
original typed details, rather than becoming evidence requests.

The checker distinguishes three outcomes:

- A complete opaque CheckedProgram, constructed only after static closure.
- Typed requests for missing external facts or explicit contract selections.
- Diagnostics for invalid or contradictory input, unsupported implementation
  paths, exhausted budgets, and other failures.

A request identifies its target, the needed fact or selection, admission
conditions and available original diagnostic locations. It is not a successful
check, permission to execute, or a guarantee that the unvisited remainder of the
Program is valid. Only requests established at the current checking frontier
need be returned; exhaustive recovery and complete multi-error enumeration are
not part of this interface.

The caller supplies additional environment or evidence inputs and invokes check
again. Responses are untrusted inputs, not `fulfilled` flags. The checker must
validate their applicability to the current Program, bindings and contracts;
it must not silently reuse a response after a changed source position points to
another operation. No suspended checker state or general resume protocol is
required. Implementation gaps, contradictions and exhausted search budgets are
not external evidence requests.

For missing Parameter values, the request inventory retains the exact admitted
declarations and their owner rather than collecting names and searching the
Program again. Indexed readers expose the name, full Parameter type (including
constraints), original declaration cursor and the admitted Program to which the
request belongs. Reading a request does not copy the entire inventory or
re-admit its contract. No partially bound value set is exposed.

Binding validates supplied values even when another Parameter is missing:
an invalid supplied value is a rejection, not a request response that can be
accepted later. Additional values are ordinary untrusted inputs to a new check;
there is no fulfillment flag, retained execution permission or resume position.
A changed declaration is checked afresh, so a value valid for an earlier
request does not bypass the current type or constraints. Rejected outcomes
retain the original typed failure independently of request interpretation.

An absent `host_policy_profile.capacity` yields a `HostCapacityPolicy` selection
request. Its acceptance condition is admission of the selected complete
`actql-capacity-host-policy/0.1` body under
`spec/contracts/actql-capacity-host-policy.json#/schema`, followed by the ordinary
Program checks. Compilation limits neither select this policy nor synthesize its
execution ceilings. A present but invalid body, a mismatched contract or exhausted
checking budget remains a rejection, not a request to replace it.

Requests retain the exact checking environment as well as the admitted Program.
Parameter paths refer to the Program; the Host capacity path refers to the Check
Environment. A missing capacity property has no source cursor or byte span: its
parent object's location is not presented as the missing property's location.
The caller supplies a newly admitted environment and rechecks; the old request
is immutable. A Parameter frontier may reveal a later policy frontier only after
the supplied Parameter passes admission.

Existing runtime obligations remain runtime obligations when their contracts
permit that phase. A statically required fact cannot instead be deferred to
execution. Runtime checks retain their subjects, phases, dependencies and
atomic failure behavior.

## Evidence supply and derivation

Explicit evidence is an advanced input, not the center of ordinary SDK use.
Three dimensions remain separate:

| Dimension | Meaning |
| --- | --- |
| Authored location | Stage ID, original step ordinal, input or Result name, and where needed aggregate output or operand role |
| Purpose | The typed quantity and use, such as output rows, a right-input bound, or aggregate array items |
| Applicability | The exact Program/Unit, bindings, contracts and checked owner under which the evidence may be used |

An authored location locates a target; it is neither permission to apply a
proof nor a persistent identity. Definition-level facts, application to a named
consumer input/import path, and completed observations or execution attempts
are distinct. Repeated imports can share an applicable definition fact without
collapsing their input occurrences or equating separate observations. Evidence
body CID equality does not establish checked-owner equality. Existing bound
wire bodies are not rewritten merely to simplify target lookup.

Definition-level capacity evidence is selected by an authored Stage name and
typed limit uses at source step ordinals. A use refers to the exact admitted
limit handle in its supplied inventory, not a numeric position in a mixed
claim table. Binding copies mutable caller selections and ties the result to
the exact admitted Program. Equal source text or equal limit CIDs do not
substitute for that ownership.

The compiler expands definition evidence over the actual checked producer
occurrences. Repeated imports retain every application, while unspecified
definitions have no externally supplied claims. Empty evidence is not a proof
of completeness: subsequent application and closure checks still determine
whether the Program can be checked. Binding, owner lookup and occurrence
expansion contribute their own incremental work. Definition evidence cannot
assert consumer-specific observations or completed execution attempts.

For supported Programs, the compiler constructs the facts necessary for formal
check completion that follow from existing inference rules and admitted
premises. It preserves existing candidate collection and selection rules; this
does not require enumerating every derivable proof. Host-supplied facts and
selected runtime capacity contracts are not invented. Failure to finish a
derivation within the compilation budget is a budget failure, not absence of a
key, proof or external fact.

The input-responsibility split for the supported formal-check domain is:

| Rule family | Compiler-owned derivation | External premise | Explicit selection / remaining boundary |
| --- | --- | --- | --- |
| Stage topology and Parameters | Named imports, producer occurrences, effective bindings and typed uses | Program and supplied values; available input declarations | No caller-provided visit order; unavailable values may require a request |
| Local input and SourceView interpretation | Reconcile declarations, select applicable type/request contracts and retain source policy dependencies | Admitted environment, Local snapshot assertions, Catalog bodies and source contracts | Selected policy remains authoritative; checking does not acquire data |
| Relation keys and logical order | Existing exact-copy/projection/key-transfer rules and operation-specific order completion | Declared or otherwise admitted keys/order facts with their required validations | Runtime uniqueness is not statically asserted; unsupported inference is not added |
| Values and generated sources | Bound-cell admission, known row counts, typed-wire/recursive measurements and their existing proof forms | Parameter values and the declared value contracts | Host ceilings and selected numeric/calendar contracts are not inferred from compile limits |
| Capacity composition | Apply existing transfer/count laws to the actual input occurrences; collect applicable candidates and select prescribed limits | Applicable admitted external bounds and their owners when needed | Preserve author guards and selected capacity policy; retain atomic enforcement |
| Numeric, Calendar and lexical interpretation | Bind the selected profile and retain operation/slot identities and dependencies | Admitted profile data and contracts | A missing explicit profile is not permission to choose another meaning |
| Aggregate, nest, window and search limits | Existing producer-bound candidate selection and quantity-specific obligations | Required input bounds and selected ceilings | Rows, items, memberships and search work remain distinct; not all are output-row bounds |
| Policy, publication and incoming requirements | Existing dependency transfer, Result/import interfaces, Unit identity and runtime-check linkage | Admitted policies, source assertions and applicable evidence | No completed observation or authorization is fabricated; effect/receipt paths outside the supported domain remain unsupported |

This table assigns responsibility, not conformance by operation name. Carrier
alternatives and operation-specific prerequisites still govern each rule. In
particular, the existence of a wire grammar for a path does not make that path
supported by the formal checker. An implementation gap must remain a diagnostic,
not a request for the caller to manufacture a successful checker result.

## Owned information and preparation

Operation consumers depend on the owned pipelines, effective bindings, selected
policies, capacity context and retained resolutions they actually need. They do
not traverse unrelated Calendar, lexical, expression or identity preparation
wrappers to recover that information. Phase-specific checked types still record
what was validated; retaining a narrow shared reference does not make an earlier
phase a later successful one.

Shared information is immutable within a construction. No mutable universal
Context or generic proof constructor replaces operation-specific validation.
Public boundaries that accept independently built handles reject foreign
combinations with typed errors. Internal sharing does not replace ownership
checks with CID comparisons or assertion failures.

Each preparation contributes incremental usage to the construction's remaining
budget. Callers and collectors must not independently reconstruct cumulative
shared prefixes. Compilation-wide proof conversion reuses an already converted
node only for its exact checked owner and Unit binding. Repeated operand edges,
proof uses and publication candidates remain present even when the immutable
converted object is shared. Actual lookups and reference retention are charged;
hashing and construction are charged when performed. Failed attempt state is
not reusable by a later construction.

## Limits and diagnostics

Public compile limits describe document size and structure, traversal work,
generated or retained artifacts, and canonicalization/identity preparation.
They do not expose package preparation order. Existing metering scopes remain
distinct: payload bytes are not interchangeable with metadata/hash bytes,
additive work is not a depth maximum, and source size alone does not bound
generated aliases, combinations or proof graphs.

Compile effort, Program guards and selected capacity contracts, and Host/backend
physical limits are separate configurations. Changing a compile limit cannot
change a selected runtime contract. Removing unnecessary computation may reduce
charged work; it does not waive work actually performed or change the meaning
of a meter.

Compilation controls are grouped by the things measured, not by preparation
phases:

| Control | Scope |
| --- | --- |
| Work | The construction's aggregate logical work; subordinate traversals are additionally bounded by remaining work |
| Artifacts | The existing aggregate byte/node accounting for generated and admitted Program artifacts; depth is a traversal maximum |
| Structure | Stage, step, Result, Parameter, Binding, slot, reference, requirement and token counts |
| Traversal | Structural nodes/depth, text and individual strings, names, pointer units and comparison pairs |
| Values | Value-admission nodes, depth and text; distinct existing source-value and Local-input counters retain their scopes |
| Policy | Policy bytes, nodes and depth, independent of the selected policy's runtime ceilings |
| Patterns | Constructed pattern bytes/nodes and pattern nesting depth |

The compiler maps these controls to each checker that consumes them. Selecting
the same ceiling for two existing meters does not merge those meters into a
single total, recharge shared work, or exempt either traversal. Per-pass caps
remain separate from the aggregate work and artifact budget. Input-document
retention measurements are also separate from these generated/preparation
quantities. No internal phase configuration is a runtime capacity selection.

Diagnostics retain a stable classification and typed details, applicable target,
origin domain, path, source span, decoded-expression range and related causes
or locations. Origin domains distinguish Program, environment, supplied values,
evidence and check configuration. A decoded-expression range is not a raw
document byte range. Missing location information stays explicitly absent; it
is not fabricated as the Program root. Normative failure order is preserved,
without requiring clients to unpack a preparation-phase wrapper tree.

Location readers preserve the original coordinate representation: a source
span, a byte offset, a UTF-16 offset or explicit unavailability. Retained-input
limit failures can identify a source document without identifying an offending
token. Such failures have no invented root path or zero-length span. Auto-format
parse alternatives remain separately ordered JSON and YAML locations; neither
is promoted to a primary failure. Request origins distinguish Parameter
declarations in the Program from selections in the Check Environment, even if
both documents have the same source-path label. Reading a location does not
reparse input; returned paths are caller-owned copies of retained provenance.

Operation obligation owners provide their retained source through a common
reader, including selected graph endpoints and individual union folds. An
indexed requirement uses its finer source when one is retained (for example an
aggregate call); otherwise its owner's body is the available location. Invalid
indices have no location. A diagnostic for an unresolved operation uses this
owned provenance, not a fresh search through the Program or a guessed step span.
Reading provenance neither establishes evidence applicability nor discharges
the requirement.

Parameter binding records the selected input origin before validation or
preflight can fail. Supplied-map shape errors belong to supplied values;
failures while charging or reading a retained default belong to the Program.
The original typed cause and its nested path/span are retained within the
origin-bearing binding failure. Declaration/default admission failures retain
their Program origin before binding begins. File labels and path spelling are
not used to infer these domains. Invalid binding-limit configuration remains a
configuration error rather than a default or supplied-value failure.

## Consumers and responsibility boundaries

Operation-bound construction belongs with operation-law application, not with
the SDK's graph traversal. `capacity_program_step.derive_bound` uses the same
operand-edge validation and arithmetic rules as supplied-proof admission. It
accepts already checked inputs in data-edge order and returns an owned bound;
it neither searches for candidates nor selects a capacity policy. Sorted proof
inputs retain repetitions, unique dependency sets do not replace those input
occurrences, and arithmetic derivations preserve left/right roles. Metadata is
reserved per complete artifact. Input traversal, operand preparation and bounded
CID ordering have separate usage scopes; caller-owned input arrays are not
retained. Construction establishes no completed observation or execution permit.

`BoundDerivation` retains the operation rule, bindings and admissible operand
arities. Its constant-time operand reader identifies the exact input target,
measurement and edge role before inputs are assembled. A retained derivation
is a request for premises, not a proof. Both constructing a new bound and
checking a supplied claim still validate the actual owned input occurrences.

The construction entry also accepts an aggregate work ceiling. It reserves
input/operand work and reference processing from the same remaining amount,
then bounds complete-artifact node preparation by what remains. Per-scope caps
still apply independently. Its reported work is the sum of those scopes, not
an observed CPU cost; a scope cannot reuse work already spent by another one.
The values-specific preparation adapter retains its complete-artifact scope:
with no input operands, its sole self-dependency visit is already represented
in the artifact nodes and is not charged again by that adapter.

Count Parameter preparation separates immutable value interpretation from
pipeline applicability. One admitted bound-value collection owns its name
lookup and parsed duration values. Attaching that lookup to a pipeline requires
the exact declaration owner and retains that pipeline as a separate authority;
equal values or equal declaration text do not authorize another owner.

A capacity construction shares this value lookup and memoizes attachments by
exact checked pipeline, including repeated imported visits. Each lookup and
new attachment is charged, while value scanning and duration parsing are
charged only when performed. The independently usable combined binding entry
reports its full preparation usage; attaching already prepared values reports
no repeated value-preparation usage. A failed construction does not publish its
session or reuse it in a subsequent Program check.

Values row-count evidence is prepared once per checked Stage definition before
capacity applications are expanded across imports. An applicable supplied proof
is retained; otherwise the compiler constructs the existing count law from the
checked operation. Other supplied claims are not replaced merely because they
share a local source ordinal. Their actual producer applicability remains a
separate owner-aware check.

Complete count-proof and witness artifacts consume aggregate preparation bytes,
nodes and work before subsequent identity construction. Their claim coordinates
are retained for later values resource selection, which reads the registered
application instead of rebuilding the count proof. Repeated imports retain
their input occurrences without repeating definition-level artifact generation.
Count evidence does not admit cells, imply uniqueness or discharge runtime
enforcement obligations.

Result row-bound demand and group, window-group and analytic array-envelope
input demands follow actual producer edges and existing non-expanding transfers.
An array envelope demands its input bound independently of the output's row
bound or publication target. Multiple array calls in one operation share a
single input demand; inspecting calls and retaining that demand are metered.
Nest demands its child input for grouped-array item bounds and its parent input
for attachment bounds, independently of the published target. Both demands use
the actual checked operands and share the same target memoization; repeated uses
do not create another proof or erase a parent/child occurrence.
Window membership envelopes independently demand their input row bounds.
Membership selection uses the owned closure's common target-candidate collector,
including applicable imported producer claims with their original coordinates.
The window-specific membership factor is applied after that applicability check;
physical input enumeration is not a count proof or an order witness.
As-of and interval search envelopes demand both checked operand row bounds,
including operands not needed by an output-count rule. Their existing search
calculation consumes those bounds without changing the separately selected join
output-capacity contract or treating a search bound as execution permission.
For an ordinary join whose right input is an admitted SourceView registration,
the compiler also demands the checked left target for keyed acquisition sizing.
Registration ownership is checked against the same Program and environment;
name lookup and retained input-role indexing consume preparation budgets.
This is only a dependency demand. The later keyed request, mode, correlation,
positive-bound and access-policy checks remain mandatory, and an ordinary Local
join is not classified as keyed merely because it has a right operand.
Source request construction retains the exact checked Stage context alongside
request-specific facts. Row-bound selection, source preparation and reference
construction depend directly on that immutable owner, not on the sequence of
reconciliation and wiring wrappers used to prepare it. The original reconciled
inputs remain available where their distinct correspondence checks are needed.
Construction reads the existing operation-bound plan,
including its exact row-operand arity and explicitly permitted fallback arity.
Only available premises or a rule's admitted premise-free case can produce a
bound. Graph entity measures are not substituted for missing row premises.
An already sufficient unary input bound is transferred without constructing a
redundant refinement; a stricter take or an expanding operation creates its own
bound. Count Parameter interpretation is shared with subsequent application
checking, and its incremental work/text is charged once.

Target memoization is scoped to exact Stage pipelines; repeated Result demands
share construction without deleting operand occurrences. Applicable supplied
claims are reused without emitting their metadata again. Closed claim bodies
may share a CID across producers, but their checked applications and eventual
Unit-bound references remain distinct. Missing premises are not fabricated as
Host evidence, and unused outputs do not trigger proof enumeration. The prepared
source prefix is reserved before generation and occurrence expansion; it is
included once in the integrated usage, not made available again as scratch work.

The standard path owns visit expansion, evidence applicability and preparation
order for every supported formal-check route. A parallel legacy Program
construction path is not a compatibility requirement. Independently useful
parsing, value admission and expression checking APIs can remain public; APIs
whose only purpose is assembling Program preparation phases need not be public.

Lowering reads retained input edges, effective values, order strategies, limits,
policy, identities and runtime obligations. It does not reconstruct checker
ownership or decide semantics again. Capability matching, candidate comparison,
placement, reservation, retention and recovery belong to the execution layer.
The fixed-input engine's completion, ownership and budget interfaces are shared
contracts; concrete Connector behavior stays in its Connector.

Acceptance includes public document/parsed equivalence; Local and values,
multiple stages, repeated Result imports and SourceView paths; evidence and
diagnostic ownership failures; budget boundaries and atomic later-stage failure;
and consumers that read decisions without inference. Shared-graph construction
counts and independent usage checks accompany identity, capacity and obligation
invariance. Operation expansion, new inference, general execution admission,
Workers support and durable capture are not implied by this checking boundary.
