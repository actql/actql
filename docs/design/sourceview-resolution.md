# SourceView resolution

`selected_reference_count/at` expose the admitted role occurrences belonging to
the exact selected SourceView. They reuse the Catalog's member-range index,
without scanning all environment references, copying arrays, resolving names
again or replacing the Catalog membership proof with a matching CID. Repeated
references and their original cursors remain distinct. This exposes all declared
roles of that SourceView, not a mode-specific projection, transitive closure,
local Unit contract CID, or permission to execute. Semantic projection and other
interpreted contracts remain separate consumers of these owned dependencies.

`bind_source_producers` connects each acquisition's retained left-row proof to
the capacity application closure already owned by its stage's checked context.
Caller-supplied visit/claim coordinates select candidates only; the consumer
pipeline and exact immutable StepBound must match. The matched closure has
already validated proof dependencies, producer ownership and bound Parameters.
Equal CIDs or numeric limits cannot substitute another application. Repeated
producer occurrences retain their distinct validated visit coordinates, which
are internal handles rather than persistent semantic identities.

Every classified source stage and keyed join is covered in order under the combined work limit;
the result owns its membership arrays and retains the source capacity context.
It accepts no alternative caller-supplied capacity closure. Runtime obligations
remain attached to their original proof owners; membership neither executes
them nor creates source authority or a runnable Plan.

Lookup capacity resolution consumes `KeyedRowBounds` and the selected lookup
policy from the same Check Environment. For a left row bound N, it retains N
as the distinct-key upper bound, selects K = min(N, declared batch capability)
or K = 1 without batching, and computes ceil(N/K) batches. Logical requests are
batches times the per-request page bound; attempts multiply requests by the
Host attempt ceiling. Complete response rows are N times the per-key row bound,
independent of the join's output cap. Decoded response extent is logical requests
times the per-page decoded byte bound and must fit the decoded Host ceiling.
These computations use the existing safe-integer capacity representation and
reject unrepresentable products rather than rounding or clipping. A large
declared batch capability is clamped before integer conversion.

`check_source_capacity` applies this resolution to the source-policy connection
for every classified stage under one cumulative work limit. It retains the
original row proofs, source/facts owners and selected policy; it emits no public
identity or executable barrier. Request and wire byte ceilings are not minimum
actual message sizes. Transport fitting, reservations, retry capability, source
authority, Host Binding admission and producer application closure remain
separate requirements. No keyed acquisition means no invented lookup policy.

Native batching is retained by the checked SourceView request contract as an
optional `SourceBatching`. It resolves the request-key, batch-request and
response-key roles from their exact Catalog reference occurrences and retains
each admitted value contract and envelope. Prior shape admission checks the
closed batching body and `preserves_per_key_semantics: true`; this declaration
is not evidence that a backend has executed per-key semantics correctly.
Absence is distinct from malformed presence. The declared positive integral
`max_keys_per_request` is preserved without inventing a safe-integer ceiling;
acquisition resolution must bound the selected batch size by the proven left
row count before conversion to the barrier's bounded integer domain.
This admission does not infer a batch wire layout from type shapes, coerce a
single-key request into a batch, or issue a provider request.

`pipeline_check_context.bind_source_policy` joins source request/left-row
checks and selected Host policy at the exact same `ReconciledContexts` owner.
Equal policy CIDs or equal Program contents cannot substitute for that owner.
The shared input preparation is charged once, while both branches' additional
work and the connection itself count against the combined work limit. The
opaque result retains both branches, including absent lookup policy and all
producer dependencies. It does not establish acquisition bounds, transport
support or runtime authority: subsequent capacity resolution must consume this
connection and close those remaining obligations explicitly.

`sourceview_resolution` connects one prepared Program's authored inputs to one
typed Check Environment Catalog. The opaque result retains both exact owners,
the original input cursor and the selected SourceView request contract. A
SourceView's self `contract_cid` is retained separately from its full-body
membership hash. Equal hashes do not replace environment ownership.

Resolution indexes the complete supplied view set once. It validates the
data-policy address and full-selector uniqueness before examining any input,
including unused views. It neither filters candidates by request compatibility,
permissions or selected read modes nor infers the Resource from `resource_kind`.
Explicit selection uses the full triple; omitted selection requires exactly one
candidate and records `actql.source.sole-view-completion` without rewriting source.
Ambiguity diagnostics sort names by UTF-16 with budgeted iterative merge sort.

Resource addresses are delimited by the already known Connector instance and
view name, not guessed by splitting at arbitrary slashes or fragment markers.
The normative owner is [Connector SourceViews](../spec/language.md#sourceviews).
Sketch at `87dc7144` likewise matches against the output data-policy address,
not ResourceKind. Its additional URI-prefix/slash cleanup is not adopted:
the language's exact instance and Resource selectors do not introduce those
aliases. This clarification preserves literal percent escapes and internal
delimiters and permits two Resources of the same kind to expose the same view.
The earlier Catalog integrity check's kind-based duplicate-selector test cannot
establish this property and is deferred to this policy-aware boundary.

Limits bound input count, view count and cumulative work, including the preceding
authored-input collection. Work is charged before indexing, text copying and
candidate sorting; failure returns no partial result. SourceView shape, typed
request/Carrier and data-policy proofs remain prerequisites, with their own
admission budgets. These limits are not a whole-process heap ceiling.

The result is not a final CheckedProgram or an execution permission. Request
binding and value validation, read-mode selection, source snapshots, authority,
policy enforcement and runtime obligations still require their own checks.
No lowerer, evaluator or backend adapter is implemented by this package.

## Source-bound pipeline registration

`prepare_pipeline_inputs` indexes the resolved inputs by stage once and retains
each selected SourceView's exact `SourceViewCarrier` proof. `pipeline_input_at`
returns only a `CarrierInput` using the original typed Carrier from its admitted
Catalog schema. Relation, Graph, Events and Vectors remain distinct; event roles,
vector identity order and component dimensions are not flattened into a Relation.
The registration does not invent keys, ranking, order, capacities or producer
evidence from the type contract. Carrier facts require their separate admission.

`attach_pipeline_inputs` checks an exact source-owned `CollectedStage` and its
actual original registrations. It rejects a foreign Program source, a separately
read Catalog Carrier with equal contents, a reconstructed Carrier or another
registration variant. Names resolve within the selected stage and caller arrays
are not retained. The opaque attachment keeps the complete resolution and stage
owners; handle equality here is internal correspondence, not a public identity.

Preparation charges the retained resolution work, stage/input indexing and names.
Attachment includes preparation and stage collection work, input enumeration and
name indexing/comparison. Exact bounds succeed and failure exposes no partial
attachment. The per-stage consumer does not scan all other stages' SourceViews.
Repeated use conservatively retains prior-pass charges rather than discounting
equal-looking evidence. These are logical-work limits, not runtime row budgets.

This is a type-only connection before request-role classification: it neither
selects direct versus keyed acquisition nor discharges read-mode, request,
classification, authority, materialization or runtime obligations. Local inputs
and stage imports retain their own attachment boundaries. The final Program
constructor must join those owners and obligations; this attachment alone is
not a lowering-ready or executable Program.

## Source-owned consumer positions

`collect_pipeline_uses` joins an exact pipeline attachment with source-bound
stage Results. The original `CollectedStage` must be the same object retained
by the Results' operation collection; equal syntax or an independently repeated
collection does not establish that ownership. The result retains both owners.

Each SourceView has an indexed list of actual consumer positions: ordinary
operation input edges with their roles, logical join right edges, and direct
Result references. Input registration order need not match declaration order.
Self-joins retain both occurrences. A later consumer of a produced step is not
misreported as another direct read of the original input. Merely selecting a
current input without consuming it adds no occurrence. Unused declarations keep
an empty list; this does not excuse their declaration or Catalog validation.

A join-right occurrence alone is not proof of keyed acquisition: a complete
directly read Relation can also be joined. Acquisition classification must
combine these positions with the selected Catalog correlation contract and
validate the applicable request coverage. Missing request fields alone cannot
establish keyed use. The index does not claim correlation, response completeness,
capacity or execution support.

The pass visits inputs, all operation edges and Results once, with charged name
indexing and constant-time indexed access to occurrences. Its work measures this
pass only; retained attachment and Result prerequisites keep their own usage.
Program input reconciliation constructs these indices itself for every stage
and charges them to its shared work limit. Callers cannot supply a partial list
of consumers, and a later failure exposes no partially reconciled Program.

## Acquisition request classification

The normative owner is the acquisition-request-classification rule in
[Parameters](../spec/language.md#parameters). Full correlation-field coverage
selects a direct request, including when the result is a join operand. Zero
coverage selects a keyed template only with at least one actual join-right
consumer and no direct consumer. Partial coverage, a directly consumed
incomplete template, and an unused incomplete template fail. Static non-key
fields still undergo complete request admission. Without correlation, direct
request admission applies even to unused declarations.

This clarifies the previously unspecified classification boundary without
changing source grammar. The fixed reference `87dc7144:src/actql.ts` instead
treats a correlated join-right input as external even when its request is fully
supplied, and accepts zero-coverage templates based on omissions. The selected
rule preserves the meaning of explicitly supplied values and requires actual
consumers to justify join-supplied values. This is a semantic check involving
Catalog roles and Program topology, not a constraint expressible by the source
input JSON Schema alone. Ordinary join, mode and completeness requirements
remain applicable after classification.

`check_pipeline_requests` retains exact PipelineUses and RequestParameters
owners, invokes the selected mode/request/binding checks itself, and exposes
only the complete stage result. Its work, type-pair, value-node and text budgets
are shared across all inputs. Direct and keyed results retain distinct types;
neither means execution authorization.

`pipeline_check_context.check_source_requests` constructs this result for every
stage in ReconciledContexts. It uses that Program's selected BoundValues, builds
one shared request/binding index, and charges the exact already-retained
resolution once. Each stage receives only the remaining budget. The resulting
SourceRequestContexts retains the Program input assembly and source slots;
callers cannot substitute unrelated bindings or omit an inconvenient stage.
This closes request classification and static binding, not correlation-key
matching, response completeness, capacity, policy, reference authority or final
Program identity. Host bindings remain explicitly unresolved.

## Lookup capacity facts

The Host `lookup_execution` component supplies the separate acquisition envelope.
Sketch `87dc7144` reads five unversioned positive-safe-integer fields there but
does not define a closed shared schema. The Check Environment contract now
fixes that component and adds an explicit aggregate decoded-response ceiling.
This follows the existing lookup accounting protocol's distinction between
wire and decoded bytes; the reference compiler's comparison of one response
byte cap with logical page bytes is not imported as a proof of both units.
Existing transport-policy per-attempt compressed/decompressed bounds and
timeouts remain authoritative and are not duplicated as new source vocabulary.
The component is not a backend capability or authorization claim.

`check_environment.check_lookup_execution` validates the optional component and
retains both absence and the exact WireEnvironment owner. Present policy fields
are exposed through distinct typed ceiling selectors; the response wire and
decoded selectors cannot alias. A bounded canonical hash sink computes the full
component CID without materializing serialized text or bytes. The pass meters
profile-key discovery, component inspection and canonical component byte size;
unrelated nested policy bodies remain the responsibility of their own readers.

`pipeline_check_context.bind_capacity_policy` performs this check even when no
source acquisition uses lookup. Its selected context retains that result and
includes the component work, bytes and scalar-node count in the shared policy
budget. Missing lookup policy remains explicit and does not prohibit unrelated
programs or grant lookup execution. Subsequent acquisition resolution must use
this same selected environment, not an independently supplied policy body.

The external-join rules require per-key completeness and finite source capacity,
but previously did not define their carrier-facts component grammar. The shared
Check Environment contract defines a closed, versioned `lookup_capacity`
component while leaving unrelated facts members to their own contracts.
Absence is unknown, not a zero bound or an implicit completeness guarantee.

Sketch `87dc7144` (`src/actql-compiler.ts`) reads an unversioned capacity object
and the generic root `completeness: "complete"`. The new component deliberately
does not promote that root claim: upstream candidate completeness and response
completeness for requested keys are separate evidence axes. Its byte unit is
explicitly decoded response-body octets. Logical-page capacity cannot prove
compressed transport, retry or failed-attempt wire-byte bounds. This clarifies
previously unspecified units rather than claiming the reference already made
that distinction. Legacy facts require explicit publication under the new body
contract, not repair during admission.

The containing facts envelope owns the claim; a future capacity application
must retain the selected SourceView and its same-Catalog reference. Component
admission is not Catalog authority or observed response validation. Host policy
selection, actual left-row bounds, batching and runtime enforcement remain
separate inputs to acquisition capacity resolution.

`check_environment.check_lookup_capacities` validates every carrier-facts
envelope in the exact Catalog reference environment, including unreferenced
envelopes. Its opaque result retains each original envelope and links output
facts to their same-environment SourceView member; structurally equal members
from another environment cannot retrieve those links. Missing components stay
`None`, distinct from an admitted `HardLimitOnly` component. Neither is proof
of complete requested-key acquisition.

The pass charges registry entries, reference occurrences, inspected object keys
and component strings under one work budget, and separately bounds the number
of facts envelopes. Unrelated nested facts remain opaque; their source-tree
admission budget is owned by the preceding environment boundary. No partial
result escapes a later malformed or over-budget envelope. Numeric bounds remain
exact safe integers, with rows, pages and decoded bytes exposed separately.

`check_keyed_facts` attaches those declarations to every actual checked keyed
join, using the selected input's original SourceView member. It requires the
same Catalog reference proof as the pipeline inputs, not merely equal CIDs or
equal numeric bounds. The opaque result retains the checked join, facts owner,
same-Catalog reference and admitted capacity together. Missing capacity and
`HardLimitOnly` reject keyed acquisition; neither changes the acceptance of a
complete direct request that happens to be a join operand.

The Program source-request boundary validates all facts once, under its shared
remaining work budget, then retains each stage's joined facts. A failure in a
later stage cannot expose a partially accepted Program context. This connection
does not yet establish the actual left producer's row bound, Host transport
envelope or response validation; these must join the same ownership closure
before executable acquisition can be claimed.

`check_keyed_row_bounds` requires a positive row bound for the exact left target
of every checked keyed join, in checked-join order. It accepts only opaque
`capacity_program_step.TargetRows` values, not numeric assertions. Equal counts
on another target or an independently checked pipeline are rejected. The result
copies the supplied array and retains the original row proof and keyed facts.
Traversal work is charged per bound occurrence in addition to correspondence
checks; reusing a bound does not make its logical validation cost disappear.

`pipeline_check_context.check_source_row_bounds` covers every classified stage
and retains the exact `SourceRequestContexts`. It includes preceding request
work and all left-target traversal work in one budget, with no partial result
on late failure. These are source acquisition prerequisites, not a substitute
for the existing whole-producer capacity/application closure. Host request,
attempt, transport, decoded-body and duration envelopes remain separate from
this positive logical row bound.

## Keyed join role binding

`check_keyed_joins` checks all keyed join-right consumers retained by
PipelineRequests. Full joins fail at this boundary. The set of authored
right-side equality fields must equal the selected correlation response roles;
extra fields keep their exact pair source and missing roles identify the join.
Each result retains the exact request, checked join, left input target and
Catalog correlation proof. Program request checking invokes this pass itself
for every stage under the same remaining work budget.

The normative repeated-key-role-binding rule in
[External SourceView joins](../spec/language.md#external-joins) preserves the
general join rule admitting repeated pairs and repeated fields. Unlike
`87dc7144:src/actql-compiler.ts`, role coverage is not a pair-count equality.
Every authored pair retains its role index. In Catalog tuple order, each role
also identifies its first authored pair as the request representative. This
fixes the previously unspecified representative choice without dropping later
predicates or changing the logical join. All authored left-key components still
participate in null-request validation, including those not chosen as tuple
representatives. The original checked operation retains their sources, types,
null policy and cardinality assertion; the role map is not a replacement join.

Correlation names are indexed once per input, with a bounded linear scan of
each join's pairs and roles. The result does not prove request-value admission,
left capacity, completeness, response identity, policy or backend support.
Lowering cannot treat this correspondence alone as acquisition permission.

## Direct read-mode selection

`select_direct_mode` consumes one owned ResolvedInput. An authored `scan.mode`
selects that exact advertised mode; otherwise the validated Contract default is
used. Missing support does not fall back to another mode. A watch selection is
statically unsupported in ActQL 0.1 even though advertising watch is legal.
An explicit snapshot can override a watch default when snapshot is advertised.

The opaque DirectMode retains the exact input, selected mode contract, selection
origin, diagnostic cursor and this pass's work usage. Advertised-mode lookup is
indexed by environment member, with same-environment and section checks. A
foreign member with equal bytes or CID cannot select a mode from this proof.
Explicit-selection diagnostics refer to the authored `scan.mode`; default-mode
diagnostics refer to the selected Catalog mode body. Returning obligations makes
a fresh array and cannot mutate the retained selection.

Every selection retains runtime mode-support revalidation. Every changes
selection, explicit or default, additionally retains two distinct unfinished
obligations: prove the requested page/range is bounded, and build the normative
content-addressed source-state requirement using the actual Program Definition,
input, SourceView and checkpoint contract. The latter is static planning work,
not a runtime check to be postponed. No provisional Program identity or concrete
checkpoint is invented here. Advertised boundedness alone proves neither actual
range admission nor capacity, consistency or completeness.

`prepare_source_state_requirement` constructs the static requirement from an
owned Program source identity and its selected acquisition request. The request
index addresses that Stage's SourceView requests, not all authored inputs.
Snapshot mode returns no requirement. Changes mode retains the exact selected
checkpoint contract envelope CID, not merely its value-schema body hash, and
hashes the normative preimage under explicit byte, node and depth limits.

Changes requirements use `required` and `explicit_state_required`: neither the
authoring language nor the selected checkpoint contract defines an inferred
initial checkpoint. This preserves the reference compiler's explicit-state
choice while applying it to default-mode selections as well. Concrete state is
admitted at the Run boundary; building this requirement does not discharge the
separate bounded-range obligation or authorize acquisition. Process-local owner
references prevent mixing selections, whereas the requirement CID depends only
on its normative semantic fields.

The source-state requirement preimage includes the normalized authored `stage_id`
as well as the unchanged input name and Program Definition CID. This distinguishes
same-named inputs in different Stages without inventing an encoded name syntax.
The complete canonical object excluding only `requirement_cid` is hashed. Schema
validation requires a nonempty Stage ID; correspondence to the actual declaring
Stage and canonical text validity remain semantic checks.

This is an explicit extension of the flat-input preimage in Sketch
`87dc7144138edfcba108cdc59dc485ac976ba976:src/actql-source-state.ts`, which has no
Stage component. Reusing that preimage unchanged would merge distinct source
slots of a staged Program. The shared embedded requirement schemas therefore
require `stage_id`, and affected Plan schema identities change. Concrete
checkpoint values and internal Stage indices are not substitutes. Fixed vectors
cover Stage separation, property-order invariance and rejection of the missing
Stage field; they do not prove that changes-range or runtime state admission is
implemented.

The selection also retains an opaque ModeCheckpoint when the selected mode
declares a checkpoint. Its exact `checkpoint.value_schema` reference occurrence
and already admitted ProtocolValueContract remain paired. The lookup does not
choose the first checkpoint envelope, another mode's contract, or an expiration
schema. Optional snapshot checkpoints are retained without introducing a
changes-state obligation. A changes mode always has this value contract by the
preceding shape/coherence proof. Concrete checkpoint value admission and the
source-state requirement envelope still belong to subsequent integration.

This follows [read modes](../spec/language.md#sourceviews), not the broader
execution limitations in `87dc7144:src/actql.ts`. That reference rejects all
advertised unbounded changes and required acknowledgements at the same boundary.
This selector retains the range obligation and leaves delivery/backend support
to their explicit checks; it does not claim those selections are executable.

DirectMode is not a keyed-join mode proof and does not classify a declaration's
consumer. `select_keyed_mode` separately rejects any authored scan and requires
a bounded default snapshot/changes mode. Its opaque result retains the exact
resolved input, Catalog mode and checkpoint value contract. It never selects a
different advertised mode to make an unbounded default pass. Its reported work
includes the scan-presence check and the shared mode/checkpoint inspection;
successful boundary tests charge that work exactly. Changes state, range and
runtime mode support obligations remain explicit even for a bounded mode.

This result establishes only the keyed read-mode prerequisite. It neither
classifies an input as a keyed consumer nor proves relation-valued acquisition,
correlation coverage, response completeness, left-side bounds or request closure.
Those checks are required separately by the external-join contract.
Program integration must discharge those consumer-specific obligations rather
than substitute a DirectMode as proof of keyed compatibility. Per-call work is
separate from the retained input-resolution work and must be budgeted cumulatively
by that integration boundary.

## Direct and keyed request templates

`check_keyed_request` is the separate static-request boundary for keyed
acquisition. It requires the exact selected Catalog correlation proof and
reserves every correlation request role. An authored occurrence of any such
field is rejected at that field; every other declared field is required even
when nullable. Unknown fields and incompatible literal, Parameter or Host
Binding types are rejected by the same admission engine as direct requests.
Nested business data remains opaque to reference substitution. The reserved
names are indexed once under the work budget, not rescanned per authored field.

The opaque `KeyedRequest` retains the original correlation proof, resolved
input, source request context and admitted static fields. It cannot be supplied
where a `DirectRequest` is required: the correlation fields have deliberately
not been supplied. Direct request admission still requires those fields even
when the selected SourceView advertises correlation. A missing correlation
contract is not inferred from absent request fields.

`bind_keyed_request_parameters` uses the same declaration-owned binding index
as direct requests. It retains the original typed Parameter values and rules,
leaves Host bindings explicit, and never creates values for correlation roles.
Its result is not a complete wire request. Matching typed join keys, mode
selection, response completeness, capacity and authority remain separate
prerequisites. Admission and binding report their own work/value usage so the
Program integration boundary can charge them without resetting shared limits.

`prepare_requests` joins the complete source-owned slot inventory with one
Resolved collection. It requires the same prepared stage source and retains
both owners. Indexing by stage and input is performed once, not once per
consumer. Its work includes both preceding passes; it does not reinterpret
literal descendants or infer usage from missing request fields.

`check_direct_request` consumes that context and an input from the exact owned
resolution. It validates every authored field against the selected checked
request schema and requires every declared field, including nullable fields.
Absent request is valid only when the request field set is empty; this does not
relax the source reader's prohibition on explicitly empty request syntax.
Fields retain their source order, original Slot, target Contract and one of:

- A literal admitted without repair by `value_admission`. Nested business
  `$param`, `$binding` and `literal` keys are not reinterpreted.
- An exact Parameter declaration whose value contract is assignable to the
  request role, including recursive shape, nullability and declared extents.
- An exact Binding declaration with the required Ref kind. ResourceKind must
  match; an expected artifact media type requires that declared media type.
  An unconstrained artifact target permits a more specific declared media type.

Parameter and Binding variants remain unresolved values, not fabricated witness
data. Concrete binding, Parameter rules, Ref issuer evidence, request revalidation
and actual acquisition authority remain necessary before executable planning.
Nullable Ref absence is a literal null, not a fabricated issued reference.
The opaque DirectRequest cannot be built from caller-supplied field/type pairs.

This uses the complete-field rule in [Parameters](../spec/language.md#parameters)
and assignment relation in [Value contracts](../spec/language.md#value-contracts).
`87dc7144:src/actql.ts` checks Binding kind/media similarly, but its request helper
omits missing nullable fields and recursively interprets binding-shaped data;
those behaviors conflict with the current explicit source rules and are not
imported. Keyed access requires its own static/correlation-role coverage and
consumer proof; it must not use DirectRequest to justify an incomplete keyed
template or infer a keyed use solely from omissions.

Each direct check reports work, comparison pairs, literal value nodes and literal
UTF-8 bytes. Assignment uses the existing comparison engine with usage reporting,
not another implementation. Values share the remaining literal budget across
fields, and failures publish no partial DirectRequest. Literal text accounting
includes keys inside literal objects; outer request role names consume work.
Depth bounds each literal subtree. Enclosing request emission still needs its
own complete output byte/node/depth bounds. Program integration must accumulate
these per-input usages; none of these limits claims a whole-heap bound.

## Binding Parameter occurrences

`prepare_request_parameters` binds one RequestContext to an admitted BoundValues
set from its exact prepared Parameter declaration owner. A reusable name index
is shared across direct requests, with preparation charged once. Separately
parsed equal declarations or equal values do not establish ownership.
`bind_request_parameters` then requires the exact same RequestContext and
replaces only Parameter occurrences with their original BoundParameter handles.
Literal handles remain unchanged, and Host Binding declarations remain explicit
unbound entries. Repeated references share an immutable BoundParameter rather
than copying its value tree. The result retains the request and binding owners,
per-occurrence work, and the count of unresolved Host Binding occurrences.

BoundParameter retains its ParameterType and rules, its checked value and its
supplied/default origin. In particular, duration is not reduced to an untyped
string by this connection. Typed value identity, consumer wire representation
and actual source-request evidence remain distinct concerns. This pass neither
serializes a provider request nor computes `resolved_request_cid` from raw
Parameter spellings. It does not fabricate missing values or recompute defaults.

This opaque ParameterizedRequest proves the Parameter connection, not whole
request execution readiness. Final request construction still needs correct
typed wire handling, opaque Binding admission, source policy/authority and the
consumer-specific acquisition contract. Even zero unresolved Host Bindings is
not an execution permit. Program integration must add per-request binding work
to the retained static request checks and shared preparation cost.

`direct_request_bindings` and `keyed_request_bindings` enumerate remaining Host
Binding uses from those opaque parameterized requests. The bounded result owns
the exact request and stores only original field indices, preserving declaration,
expected type and source-slot ownership. Repeated uses of one declaration are
separate requirements, not separate value copies. Literal and Parameter fields
are not interpreted as Binding uses. The retained count bounds allocation before
scanning; work charges the inventory plus every inspected field without copying
the field array. Issuer evidence, current usage authorization and concrete Ref
admission remain unperformed. An empty inventory establishes only absence of
Host Binding uses in this request, not completeness of a Program or permission
to issue the request.

`pipeline_check_context.collect_source_bindings` inventories every classified
stage/input from the owned `ProgramPreparation`, applying one cumulative work
and use-count limit. It retains empty request inventories as well as nonempty
ones, so omission is not confused with a scanned request having no Binding use.
Each lookup returns the owned request inventory; stage/input indices are local
coordinates, not persistent identities. This is a missing-admission inventory,
not a Host validator or a replacement for the issuer/authorization boundary.
