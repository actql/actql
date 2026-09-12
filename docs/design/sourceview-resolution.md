# SourceView resolution

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

## Direct request templates

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
