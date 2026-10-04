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

An expression that requires a missing `host_policy_profile.text_time_evaluation`
component yields a `HostTextTimePolicy` request. The supplied component must
meet `spec/contracts/actql-expressions.json` at
`#/schemas/fragment/properties/request/properties/text_time_policy` and the
ordinary owned text-time admission, pattern, envelope and profile checks.
Neither policy defaults nor compiler budgets supply execution ceilings.
Missing-policy failures from timestamp patterns, regular expressions and text
envelopes share this selection request; malformed policies, unsupported
profiles, invalid patterns and budget failures do not. `input_requests_diagnostic`
retains the original typed failure establishing the frontier, without promising
that supplementation will satisfy later checks.

A text-rank operation without a selected lexical profile yields
`HostTextRankSelection`, identifying `/host_policy_profile/text_rank`. A valid
selection without its admitted artifact yields `TextRankProfileArtifact` instead.
The latter retains the exact admitted `TextRankSelection`, its original pin
cursor and environment owner. The caller can pass that selection to
`admit_text_rank_profile` with the profile bytes and required dependency bytes;
matching the pin alone does not admit the artifact. Rechecking receives the
resulting selected profile through the ordinary checking environment.
Readers do not reparse the selection or rebuild its field index.
Malformed selections, foreign environments and mismatched profiles remain
rejections. Selection and artifact requests neither assert backend support nor
prove that the remaining Program checks will succeed.

Calendar topology validates the selected component within its preparation
budget before interpreting a missing profile. An operation that needs Calendar
semantics without a selection yields `HostCalendarSelection`; the retained
diagnostic preserves that operation's authored location. A valid selection
without table material yields `CalendarProfileArtifact`, carrying its exact
`CalendarSelection`, table byte pin, external tzdb release and original pin cursor.
The caller uses `admit_calendar_profile` and supplies the resulting owned profile
to a fresh standard check. Invalid components and foreign profile owners remain
rejections, not supplementation requests. Topology preparation without Calendar
operations does not itself require table material; the complete Program's
profile attachment checks remain a separate boundary.

`NumericReductionProfile` identifies the authored aggregate that needs an
admitted numeric reduction profile. It is emitted only for a retained numeric
aggregate obligation in a supported group, window-group, analytic or pivot
operation when the checking environment has no profile. Its source and path
refer to that Program occurrence, not to an invented Host policy property.
The caller admits the profile in `spec/contracts/actql-numeric-reduction.json`
with `numeric_reduction.admit` and supplies it through `checking_environment`
before rechecking. Admission verifies the pinned profile and dependencies;
neither the request nor profile admission selects a future observation, grants
execution permission or discharges runtime checks. Other unresolved operations,
and unresolved operations despite an already supplied profile, remain rejections.

`AggregateStringByteLimit` retains the authored `string_agg` call when neither
its `max_bytes` guard nor the selected Host capacity's
`max_aggregate_string_bytes` supplies a finite output limit. The caller may
select the Host ceiling in a newly admitted environment, or author a positive
`max_bytes` guard and admit the changed Program before rechecking. Parameter
guards still use ordinary binding validation. The quantity is UTF-8 output
string payload bytes, not rows, serialized JSON size or artifact capacity;
existing minimum selection and atomic runtime enforcement remain unchanged.
Invalid guards, unresolved bindings, foreign occurrences and exhausted budgets
are not capacity requests. The request establishes only this known shortage,
not the validity of the rest of the Program.

`TemporalSearchInputRows` identifies an as-of or interval search occurrence and
the left or right operand for which candidate collection found no applicable
finite row bound. When both are absent, requests are returned left then right.
The original failed collector and its owned candidate memberships remain in
the diagnostic; reading the request does not rerun proof search. A caller can
supply applicable admitted evidence through the advanced evidence entry, or
change and readmit the Program so an existing count rule supplies the bound.
Authored positions locate the requirement but never establish evidence ownership.
Rechecking validates the actual input edges and recomputes the product under the
existing rules. A join output ceiling, publication ceiling or physical budget
is not an input-row proof. Overflow, foreign evidence, invalid occurrences and
compilation exhaustion remain rejections; no partial CheckedProgram is returned.

`KeyedAcquisitionInputRows` points to the authored join whose left input lacks
an applicable positive row bound for keyed acquisition. It is produced only
after bounded candidate selection, retaining the original join cursor instead
of recovering it from preparation indices in the SDK. Existing zero upper
bounds are not silently promoted to positive candidates. A newly supplied
bound must pass the ordinary Program, target and owner checks on rechecking;
alternatively a changed Program can obtain a bound from existing derivation
rules. Host output ceilings do not prove the left input bound. This requirement
does not authorize acquisition or establish a completed source observation.

Requests retain the exact checking environment as well as the admitted Program.
Parameter paths refer to the Program; Host policy paths refer to the Check
Environment. A missing policy property has no source cursor or byte span: its
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

Expression validation retains the exact Stage contexts used to collect its
sites, so site readers retrieve bindings without following selected-policy
preparation wrappers. Source capacity retains those same owned contexts after
the source-policy join. Operation resolution retains admitted cells directly;
values resource validation does not depend on Calendar or lexical wrapper layout.
These references preserve the existing owners without reconstruction or lookup
caches, and do not alter the accounting of the checks that use them.

Operation resolution phases retain the same immutable requirement inventory
directly. That inventory retains its Stage contexts, selected capacity environment
and checker-profile evidence. Scalar, frame, fill, range, query, cell and profile
checks do not recover the inventory by traversing their predecessors. Predecessor
results remain available where their actual resolutions are needed; retaining
the inventory alone does not establish that any such resolution succeeded.

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

`diagnostic_category` exposes `InvalidInput`, `InvalidConfiguration`,
`UnsupportedImplementation`, `CompileLimit`, `MissingInput`, and
`UnclassifiedFailure` independently of the origin domain. Classification uses
typed causes, never rendered error text or source paths. An unprojected internal
cause remains `UnclassifiedFailure`: it does not blame author input, promise
that changing configuration will help, or become an external requirement.
`MissingInput` is assigned only when the existing request-admission path has
established a typed partial requirement. The category neither changes failure
precedence nor authorizes retry success. `diagnostic_cause` retains the detailed
cause for investigation; ordinary callers need not traverse its phase wrappers.
For auto-format parsing, a resource-limited alternative prevents classification
as conclusively invalid input; both original alternative locations remain.

Location readers preserve the original coordinate representation: a source
span, a byte offset, a UTF-16 offset or explicit unavailability. Retained-input
limit failures can identify a source document without identifying an offending
token. Such failures have no invented root path or zero-length span. Auto-format
parse alternatives remain separately ordered JSON and YAML locations; neither
is promoted to a primary failure. Request origins distinguish Parameter
declarations in the Program from selections in the Check Environment, even if
both documents have the same source-path label. Reading a location does not
reparse input; returned paths are caller-owned copies of retained provenance.
Pipeline typing and Result checking expose their original path and span through
the same reader. Expression diagnostics additionally retain half-open Unicode
scalar offsets in the decoded expression, before token normalization. Those
offsets are not UTF-16 or document-byte coordinates; non-expression failures
have no expression range. Invalid checker limits identify check configuration,
not a fabricated authored token. The original typed cause remains available.

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

Arithmetic dependency collection is distinct from application ownership.
`capacity_witness.collect_program_dependencies` forms a closed union of admitted
bodies while retaining the exact source collections, including repeated source
occurrences. Equal CIDs may share a wire body, not an application or its owner.
Limit candidates are rebound to the union's arithmetic coordinates without
changing their wire identity or reissuing admission. Collection visits, retained
references and graph checks consume bounded work. This union does not establish
that a Graph input limit applies to a consumer's input: source application,
selected policy and limit-consumption checks remain scoped to their actual
producer. A consumer must not interpret an imported limit's local input name as
one of its own inputs.

Host evidence retains a direct immutable source-admission origin across ordinary
proof extensions. Comparing that origin does not require following preparation
history or comparing CIDs. Independently admitting the same closed claim body
creates a different origin. Origin equality does not replace current claim-table
correspondence, pipeline applicability, or selected-policy validation; it only
identifies the original supplied evidence retained by an extended table.

Extended source dependencies distinguish the original local enforcement prefix
and limit ledger from imported dependency bodies. Preparing Graph inputs requires
the retained producer Graph checks for every imported source origin, including
transitive origins. The enclosing application closure registers those exact
checks alongside the producer operation collections. Imported limits cannot be
consumed again by local sequence, join, components or traversal applications.
Equal local step ordinals do not require rebuilding a producer proof in the
consumer: its checked foreign premises remain attached to the retained producer
application, and actual input-edge checks still select the applicable owner.

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
including each operand's quantity, exact arity and explicitly permitted fallback arity.
Only available premises or a rule's admitted premise-free case can produce a
bound. Graph entity measures are not substituted for missing row premises.
Rows, nodes and edges have separate memoized states even at the same target.
Existing construction and projection laws bridge these quantities explicitly;
a rows-to-graph-to-rows path does not require caller-built intermediate proofs.
Quantity state storage is allocated on demand and charged before allocation;
lookup work is retained, and unsupported premises do not create a bound.
An already sufficient unary input bound is reused only when the existing
quantity-specific transfer rule also reaches that exact operand. Equal numeric
bounds alone do not establish applicability; an operation without that transfer
path constructs its own bound even when its multiplier is one.
When operation-specific construction lacks premises, an independently applicable
non-expanding transfer remains available. It follows the same metered target walk
and preserves the input owner. This does not omit validation of other operands
or the runtime conditions required by that transfer, such as exactly one right
row in a cross join. Count Parameter interpretation is shared with subsequent
application checking, and its incremental work/text is charged once.

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


## Public authored-input reports

The public Client `check(text, {format, parameterDeclarations, parameters})`
returns the registered `actql-check-outcome/0.1` envelope. Checking completion,
its scope-bound verdict and eventual execution outcomes are separate facts.
The public report is projected by the existing MoonBit check bridge before
serialization. Local and HTTPS use that projection with the same disclosure
policy. SQL/Text lowering retains its admitted Program; the same `check_parsed`
checker consumes it without replacing authored provenance with generated JSON.

The corrected unfinished check contract requires `reason_schema_cid`, identifying
`actql-check-reason/0.1`, on completed, failed and unavailable envelopes. Reports
require `inputs` and `requirements` as well as the existing scope, context,
reasons and coverage. The machine schema, generated Client wire/SDK types and
validators are updated together. Older Clients reject the additional closed
fields; newer Clients reject replies without them or with another reason-schema
identity. There is no compatibility adapter or interpretation of a rejected
reply as success. `actql-diagnostics/0.1`, `plan_result` and their historical
code/payload/CID meanings are unchanged.

The active producers and consumers share this one contract:

| Boundary | Contract use |
| --- | --- |
| `connectors_builtin_node/client_check.mbt` | Projects common parser/checker facts after Source disclosure and emits every outcome |
| `adapters/host-node/client-check.mjs` | Binds input revisions and context; validates the MoonBit response for installed Local/HTTPS Hosts |
| `scripts/check-outcome-contract.mjs` and protocol registry | Define the closed reason/outcome shapes and exact schema/registry pins |
| `scripts/generate-client-host-wire.mjs`, `packages/client-wire` | Generate types/structural guards; enforce location/document and verdict/evidence consistency |
| `packages/sdk` | Validates each response and binds locations to that call's immutable submitted inputs |
| `packages/local-node` build graph | Packages the same Host adapter and compiled bridge, with the SDK/client-wire package dependencies |
| Independent Host, SDK, generator and packed two-Source fixtures | Fix byte ranges and facts independently; reject malformed facts and contract mismatches; `scripts/fixtures/two-source-public-query.mjs` consumes the same report |
| `canonical_json` identity fixtures | Read current registered schema bodies against normative pins; historical identity vectors remain immutable |

The Client–Host `check` request shape and `actql-client-host/0.1` identity remain
unchanged; the registered check outcome/reason schemas are the response authority.
Coordinated publication does not imply that consumers in other environments have
updated. A closed-schema mismatch fails validation in that consumer, including
responses with no diagnostic reasons, rather than returning an empty success.

Text locations name the `source` document and its immutable revision, with
zero-based half-open UTF-8 byte ranges. BOM, CRLF, non-BMP and combining scalars
remain in the received bytes. EOF and insertion positions can be zero width.
Structured declarations and values use a different location kind with a JSON
pointer; these API inputs are objects, not authored JSON text. Their revisions
bind the exact JSON serialization supplied to the common admission owner. An
unavailable original position is omitted, including lowerer semantic failures
without owned source provenance. No generated JSON path is displayed as SQL.

The parser's typed lexical issues project as `query_lexical_invalid`, with
closed `facts.issue`: `unexpected_end`, `unexpected_token`, `invalid_escape`,
`invalid_scalar`, `empty_identifier`, `unterminated_comment`, `invalid_number`
or `invalid_parameter`. These facts contain no token text, Source name, private
cause or parser message. The parser's existing authored span supplies a source
location when present, including an exact zero-width position; no token range
is invented. Ordinary grammar `Syntax(String)` failures remain the generic
`query_syntax_invalid` reason. Lexical limits still project as analysis-budget
coverage, never as these invalid-input reasons. The SDK provides safe,
issue-specific explanations and advisory hints without interpreting messages,
reparsing source or applying an edit.

Adding this closed facts alternative changes the registered check reason and
outcome schema identities and their coordinated Host/SDK pins. Both consumers
reject the previous identity, including an otherwise empty verified report.
The `parameter_undeclared` condition explicitly retains its required parameter
fact despite the expanded union. Unknown reason codes retain only their safe
code-only shape. This does not change `actql-diagnostics/0.1`, its code/payload
meanings or frozen historical identity evidence.

The lowerer's typed `UnknownReference`, `InvalidArguments` and `InvalidNumber`
issues project as `query_expression_invalid` with closed `facts.issue` values
`unknown_reference`, `invalid_arguments` and `invalid_number`. The numeric issue
means the expression's precision, finite-value or signed-zero domain, distinct
from lexical `invalid_number` spelling. Argument facts describe the selected
operation's count or form, without asserting a particular overload or exposing
argument values. Authored origins supply original half-open UTF-8 ranges for
references, calls and numbers; generated or missing origins omit the location.
The projection reads existing typed failures without resolving names again or
searching the submitted string. Unaliased column failures currently lacking a
typed expression diagnostic remain generic `query_invalid` and omit a range.
Unresolved protected Source names cannot acquire an expression reason or span.
Wrapped expression construction/admission budgets remain incomplete analysis;
they never become expression violations. The lowerer's `UnsupportedFunction`
also remains incomplete analysis: its existing type covers unknown names,
quoted function names and unsupported qualified forms without distinguishing
a proven input violation from implementation support. It projects only the
existing `implementation_limit` coverage, not an expression reason or location.
That does not certify the construct as valid or allow a Program to be issued.
The common lowerer must supply a distinct typed violation before the public
bridge can blame an unknown function name; no diagnostic name catalog or
message classifier replaces that owner. Independent supplied violations and
missing-value Requirements remain visible beside this limit. The SDK's advice
asks the checking-context owner to review support without claiming that the
submitted construct is allowed.

This further facts extension changes the coordinated check reason and outcome
schema identities. Facts are validated per code: lexical issues cannot use an
expression-only fact, and expression reasons cannot use a lexical-only fact.
Shared `invalid_number` is interpreted only with its reason code. The SDK and
Host reject mismatched preceding identities even for empty verified responses;
no compatibility implementation is retained.

Document IDs (`source`, `parameter_declarations`, `parameters`) are roles within
one report, not private file paths. Each Host issues a keyed, domain-separated
revision over that role's exact bytes. These revisions are not public content
hashes, authorization grants or retrieval references. `context_ref` additionally
binds audience, disclosure policy, compiler, requested scope, admitted public
Host policy and checker profile selections, installed ModelTask contract CIDs,
visible Source contracts and bindings. The full private Environment CID still
binds internal publication ownership and Source authorization, but is excluded
from the public reference preimage. Adding or changing a hidden Source cannot
distinguish its presence through this reference. Changing authority, visible
Source contracts, policy or checker selections can
change `context_ref` without changing the same input revision.

Public Local and HTTPS ingress authenticate and authorize each check before
invoking its installed checker. A Source read-decision owner only controls its
own names' disclosure. Missing read tuples, denied or undecided decisions, and
non-abort exceptions from that owner all hide those names before checking;
their number cannot revoke the admitted whole check binding. With that binding,
the common checker returns a completed report containing independent safe
violations and the public unresolved coverage boundary for protected resolution.
Required bound values remain missing-value limits and typed Requirements.
Caller aborts still propagate, and connection authorization failures still
refuse the operation before checking. The common `unavailable` outcome remains
reserved for an unestablishable whole audience-bound context; a count of failed
Source read owners is not evidence of that condition. This changes neither
the closed outcome schema nor its identity, and adds no input persistence.

The SDK detaches structured caller input synchronously before awaiting credentials
or transport, and retains immutable input snapshots in a weak association with
that exact response. `getCheckInput` retrieves that call's snapshot;
`resolveCheckLocation` uses the same snapshot and checks identity, revision,
content and byte boundaries. A copied/externally parsed report has no association.
Unavailable input, another revision or edited text yields no resolved location;
the reason's safe code/explanation remains usable. The API applies no edits.
`resolveCheckTextRange` converts a resolved source location to zero-based UTF-16
line/character coordinates on that same revision. It counts original BOM and
combining code units, counts non-BMP scalars as two code units, and treats CRLF
as one line break with no representable interior position. Lone CR/LF break
lines; EOF and zero-width boundaries remain valid. Malformed original Unicode,
structured pointers and CRLF-interior boundaries have no editor range. This
adapter preserves exact/approximate precision and never normalizes the input.
Editor session/version custody remains with the editor integration: it associates
the submitted snapshot with its open buffer and compares current identity,
revision and text before rendering there. A reopened session cannot replace that
association. The helper is explicitly UTF-16, not an LSP server or edit applicator.
`explainCheckReason` provides safe English summaries/hints; unknown codes have an
explicit generic explanation and confer no retry or execution permission.

The Host adds no document database, persistent input store, history or re-fetch
API for checking. The existing request envelope/source limit is retained: 65,536
UTF-16 source code units at request validation and 65,536 original source bytes
at frontend admission; an input beyond an analysis budget is not an invalidity
proof. Structured admission keeps its existing bounded JSON/decode/binding
budgets. Report construction reserves a separate 65,536-byte, 4,096-node budget.
The submitted `byte_length` is a safe integer measurement, not evidence of
successful admission or an extra input limit; exhausted inputs still retain
their actual size. Installed HTTPS additionally retains its existing 65,536-byte
request-envelope limit and can refuse a request before checking.
The Host's request/analysis data becomes eligible for collection after processing
and response completion; neither deterministic immediate erasure nor a retention
interval is promised. The SDK association becomes eligible for collection when
its response is unreachable; application-retained snapshots remain application
owned. No secret input is copied into public Reasons.

Typed facts cover undeclared parameter names, supplied-value type mismatches
(expected/actual types, never values), and missing declared values. For nested
object fields and array items, the projection follows the existing binder's
supplied-input path through the admitted declaration and value. It reads the
declared child type rather than reporting the root container type. This does
not perform another admission or change the checker's conclusion.
Supplied constraint violations with an owned cause use
`supplied_value_constraint_violation` and typed `parameter`/`constraint` facts.
The current admitted families are numeric, duration, exact array length and
maximum array size. NumericConstraint aggregates integer/minimum/maximum failures;
projection does not select a failing subcondition by rechecking the value.
These reasons can carry the same owned structured location without publishing
the offending value. Other causes retain their safe generic reason. A missing
node, default-origin error or budget does not acquire invented constraint facts.
JSON pointer tokens escape `~` before `/`, retaining exact field spelling and
array indices. A missing submitted node or a pointer exceeding 4,096 UTF-16
code units has no public location; paths are never truncated or fabricated.
Default-origin failures do not acquire a supplied-document location.
Declaration admission failures can carry a reader-owned pointer in the submitted
`parameter_declarations` document, including an invalid default, type member or
metadata member. The pointer must resolve to an admitted submitted node; a missing
member is omitted rather than invented. An admitted empty declaration map has the
known root pointer `""`. Admission budgets and internal failures remain separate
from declaration violations and do not receive a violation location.
A missing value is a Requirement for bound-input checking, not a diagnostic or
verified template report. Its declaration pointer/revision identifies the full
submitted admission contract, including constraints; supplying a value requires
a new complete check. Other typed causes retain their less-specific registered
public reason until their projection is implemented. Protected Source resolution
has one generic unresolved boundary and no hidden candidate, count or location.
There is no negative-existence authority for installed query aliases; omission
from an audience-visible publication cannot prove absence. Provider Resource
catalog completeness is not query-alias completeness.

The first supported boundary is bound-input checking. Template-only checking,
fix application, report retrieval, LSP conversion and execution/Delivery outcome
explanations remain separate work. The input-report connection does not claim
the design's S1–S9/X1–X17/invariant completion gate.
