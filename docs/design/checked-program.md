# Checked Program construction

This is the construction contract for the main-side boundary described in
[Pure operation checking](pure-operation-checking.md#main-and-lowering-ownership).
It specifies the orchestration boundary, not a new wire artifact.
Language and the pinned machine contracts remain authoritative.
Existing `pipeline_check_context` results are implementation components of this
boundary; adding another component is not itself end-to-end completion.

## Entry and success

The entry is `program_check.check`. It takes source and admission
material, not a caller-assembled list of checker successes. Its conceptual
arguments are:

| Argument | Meaning and checks performed inside the boundary |
| --- | --- |
| Parsed Program | The normalized, source-owned `stage_syntax.Program`, including paths/spans. Parsing is a separate bounded entrance, not repeated by the checker. |
| Check Environment | The canonical integrity-checked `check_environment.WireEnvironment`. Integrity alone does not establish Catalog closure, policy validity, issuer trust or usable input evidence. |
| Supplied values | Parameter values and the applicable typed opaque-Binding evidence. Parameter declarations, defaults, used-name selection and binding ownership are derived from this Program, not supplied as a second declaration set. |
| Check configuration | Explicit selected language profiles, pinned semantic capabilities and available profile artifacts. These are checked against their governing contracts; backend availability is not a language admission rule. |
| Check budget | Aggregate admission/work/text/node/hash limits and per-traversal depth limits. These are not execution resource ceilings or Host authorization. |

These argument groups describe responsibilities; concrete auxiliary type names
are not additional accepted public structs. In particular, Binding evidence is
not an arbitrary JSON value plus a `validated` flag. A supplied claim is usable
only through the applicable existing admission boundary and its exact owner.
Inputs unavailable in an implementation produce a specific unsupported or
unresolved diagnostic, not empty evidence or fabricated values.

Success returns only an opaque `CheckedProgram`, constructible through the
validating entry. All selected semantics are static-ready for lowering; every
remaining execution check has a typed binding as described below. Missing caller
bindings, inconsistent evidence, unsupported static handling or an unresolved
mandatory static requirement produce an error with no partial CheckedProgram.
Public planning variants such as `needs_bindings` and `pending_predecessor` are
separate protocol results, not successful CheckedPrograms with weaker guarantees.

The entry has an explicit implementation-domain check, separate from the
language grammar. Its Local and Result-import domain accepts `values`, `derive`,
`filter`, `select`, `rename`, `drop`, `sort`, `take`, `distinct`, `dedupe_rows`, `append`, `join`, `cross_join`, `except` and `intersect`, including empty operation
sequences. Sort/take use the existing owned order-resolution closure and preserve
their distinct strategies and preconditions; accepting them does not synthesize
an order from physical enumeration. Result publication can target their explicit
`as` output, including a pipeline consuming an earlier Stage's Result.
Representative selection retains its exact input and operation-bound top-tie
execution check. Repeated grouping keys and the empty global key list keep their
existing meanings; neither constitutes proof that the selected representative
is unique in actual data.
Join consumes the existing cardinality selection, ordered-occurrence execution
check and exact selected-policy capacity application. All five join kinds
can close when their requirements are supplied. Authored cardinality and
null-key assertions retain separate checks over the exact left/right operands
and authored key tuples, before input use. Cardinality validates both sides,
right only or left only for one-to-one, many-to-one or one-to-many respectively;
null-key failure applies to either input. Static key evidence does not remove an
authored assertion, and repeated pairs do not create additional rows. Violation
rejects the whole join output. Full join additionally selects an eligible row
identity independently for each actual operand, using the deterministic candidate
key selector rather than the join-key uniqueness result. Multiple candidates are
not treated as missing evidence. Canonical-key eligibility includes reference
identities without granting authored ordering permission. Selection adds no sort
and synthesizes no key from physical enumeration. Work and name traversal consume
the shared resolution budget.

Each identity binding retains the selected key's producer and pending admission,
normalized tuple uniqueness and reference validation obligations, to be enforced
before input use. It is not proof that actual rows already passed those checks.
Absence of eligible identity on either operand rejects construction, including
unused full joins. Missing capacity likewise prevents construction. Result outputs
remain subject to the existing flat-name publication and order requirements.
Other operation paths, opaque Binding declarations and nonempty Effects are
reported as unsupported rather than made executable through missing evidence.
Selected SourceViews additionally require acquisition closure: shared Catalog
registration or mode support alone cannot pass the final source-execution audit.
Direct requests with fully bound static values now pass that audit only when
every selected input has the exact owned Host-combination, read-authorization,
request-egress, acquisition-resource and Carrier-response execution checks.
Their phases, atomic failure behavior and prerequisite edges are checked against
the source inventory, including unused inputs. The direct policy must refer to
the same bound request and selected response policy. Unknown classification is
retained for current runtime egress admission, never interpreted as permission.
Keyed provenance composition and unbound Host request values remain unsupported
by this final audit; changes/checkpoint obligations still require their separate
static mode closure. Successful checking neither performs acquisition nor claims
that a backend can implement the required enforcement.

SourceView-backed publication also closes its policy provenance. The current
transfer follows the Result's checked target backwards through select, rename,
drop, sort, distinct and dedupe, which retain source value provenance without
introducing new values or mixing inputs. It selects the exact direct source by
stage and input name, not every Program input. The publication retains the
effective policy object and CID, original target and the Carrier-response check
as its execution prerequisite. Lowering reads that binding rather than walking
the graph again to select policies.

Filter transfer additionally retains each exact checked predicate and its step
coordinate. All value leaves participate in provenance, including branches that
evaluation may skip: field references inherit the selected input's provenance,
while literals, Parameters and other value leaves without an admitted policy
attestation retain unknown provenance. This does not evaluate a predicate or
infer a public classification from successful type admission. Predicate readers
are indexed and preserve occurrences even when their effective policy CIDs are
equal. Each predicate and node consumes the shared preparation work budget.
The publication emitter combines that unknown flag with the direct acquisition
policy while retaining its authoritative source and response references.
`publication_policy_classification` reads the combined classification; the
retained `policy` member is the acquisition's original provenance, before the
predicate contributions. `emit_publication_source_policy` emits the combined
preimage corresponding to the publication's CID.

Take transfer retains its exact checked operation, count and offset through
indexed slice readers. Selection-control admission does not attest a data
classification, so those controls preserve unknown provenance rather than
acquiring the input's classification. The operation retains literal versus
Parameter identity and the owning Program supplies the corresponding bound
values. This transfer does not resolve or strengthen order, infer a capacity
bound, or grant publication permission: the existing operation/order/capacity
closures must still succeed. Both control positions consume preparation work.

Result imports retain the producer's completed publication through
`imported_publication`. Resolution follows the admitted import interface and
requires the exact producer Stage, Program owner, Unit identity and Result port;
equal CIDs alone cannot substitute another checked producer. Publication
construction proceeds in Stage order and only completed earlier publications
can supply this provenance. The consumer retains its own target and local
predicate/selection contributions while the imported publication retains the
producer's contributions and execution prerequisites. This forms a shared
immutable dependency graph, not a copied or flattened lineage. All searches and
policy emission consume the same preparation budget; a later failure exposes no
partial CheckedProgram.

Other transfer paths, including computed values and mixed-source composition,
still require their own composition rules. A SourceView-containing
Program with an unclosed publication policy fails `UnclosedPublicationPolicy`;
the missing result is not replaced with an empty policy or a whole-input union.
These are bounded implementation conditions, not restrictions on those authored
operations. Local-only Programs retain their existing construction path.
These implementation limits do not redefine the full construction contract or
the language's accepted operations. Extending the entry requires connecting the
corresponding semantic dependencies and execution obligations, not just adding
an operation spelling to its domain check.

Future Result values do not have to exist at Check. Their declared typed ports
and producer/gate correspondence do. A value-dependent condition remains an
execution obligation only when the governing rule permits that deferral and its
dependencies are connected. Check does not manufacture an observed Invocation,
completed predecessor, acquired row, receipt or issuer permission.

## Internal construction

The entry orchestrates existing admission and checking code rather than creating
parallel implementations of the rules. Its dependency order is:

1. Prepare the Program's declarations, effective Parameters and source-role
   inventory. Validate the environment components that are required or present
   under their existing contracts, and select input registrations from admitted
   source/contract evidence. Whole-environment integrity and membership remain
   distinct from the later local identity projection.
2. Check stages in source dependency order. Prepare a producer's Relation Result
   ports before checking consumers; resolve imports against those exact ports.
   Preserve all source stages, unused operations and repeated producer visits.
   Do not silently replace an earlier registration with an equal-shaped type.
3. Derive each stage's topology, types, bound references, conditional evidence,
   order strategies, resource applications and publication requirements. Reuse
   the same resolved-order owners when ports and contexts share them. Validate
   cross-producer proof ownership and the selected policy and binding owners.
4. Resolve expression and operation static requirements from their complete
   owned inventories. Derive local source/declaration/contract/import projections
   from these same owners. Check the required semantic identity relationships;
   process handles and step indices never substitute for these identities.
5. Build the exhaustive obligation coverage described below, validate dependency
   and application correspondence, and seal the result atomically. There is no
   alternate constructor that skips this final check.

Local schema registrations can be prepared by
`stage_local_inputs.prepare_environment` from the declaration owner and the
integrity-checked Environment. It admits every supplied schema snapshot, assigns
it to its source Stage, reconciles the declaration and verifies complete member
coverage. Unused inputs are included; unknown targets and unsupported snapshot
forms fail rather than being omitted. Member admission, per-Stage reconciliation
and final assembly share aggregate work/node/text ceilings under the existing
pass-usage conventions. Member decoding and subsequent semantic reconciliation
are distinct charged passes; prior Environment-envelope integrity admission is
outside this boundary.

For mixed inputs, this preparation accepts the SourceView declaration partition
owned by that exact source. It forwards the partition to each Stage's Local
admission and retains it in the resulting registrations. Connector slots are
therefore not misread as Local Relation declarations, while a same-named Local
slot in another Stage remains Local. An equal-shaped partition from a different
source is rejected before snapshot admission. This partition does not resolve
Catalog contracts or provide SourceView type, acquisition or capacity evidence;
the separate SourceView registration/request checks remain mandatory. Supplied
Local snapshots targeting connector slots are still rejected, not ignored.

`pipeline_check_context.prepare_source_registrations` constructs this partition
from one declaration Source and an admitted Source-request Catalog. It performs
selection and type-only SourceView registration, then derives the Environment
from that same Catalog owner for Local snapshot preparation. No second
Environment or caller-assembled selection is accepted. The return value is the
existing pair of SourceView and Local registrations, whose exact owners remain
available for later pipeline/input correspondence checks; it is not an additional
static-closure certificate. Collection and selection are already included in
SourceView registration usage, and Local preparation receives only the remaining
work allowance under its existing pass-accounting conventions. Local node/text
limits and SourceView input/view/order-key limits remain explicit. Catalog and
Environment admission precede this boundary; request/Parameter validation,
acquisition, capacity and execution obligations still follow it. A later Local
snapshot failure returns neither registration branch.

`prepare_sourceview_program` consumes that pair before constructing Stage
pipelines and Result imports. It requires the same Source, Environment and exact
SourceView partition in every Local Stage registration. It gathers only the
Catalog-selected type-only inputs and verifies their exact registration owners
against each resulting Stage before returning wiring. Equal-shaped registrations
from a different selection cannot be mixed. SourceView preparation, gathering,
Local topology and final correspondence checks share the work allowance, with
only exact retained prefixes counted once. The lower-level
`stage_results.prepare_local_program` accepts explicit SourceView registrations
but checks only their names, completeness and type-only form; it is not itself
Catalog admission. The owned wrapper supplies and validates that correspondence.
This constructs topology, not effective Parameter bindings, source requests,
complete semantic identities, obligation closure or execution permission.

`prepare_sourceview_context` composes that owned topology preparation, Parameter
binding and selected-context construction. It accepts the admitted SourceView
and Local registration pair, supplied values and raw capacity material/consumer
coordinates, not independent wiring, bound Parameters or successful capacity
applications. All existing partition, source, Environment, policy and producer
checks still run. A binding failure or a later Stage failure returns no context.

Topology preparation privately reports its nonshared gathering/correspondence
cost to this composition. The binder receives the remaining source work budget;
context construction shares the retained registration cost once and adds the
orchestration cost once to its reported usage. Source work/text ceilings are
also bounded by the enclosing context ceilings before preparation starts.
Equal semantic identities do not remove the cost of these additional passes.
Earlier Catalog admission and the remaining formal Program closure are separate;
this context is not an execution permission or an acquired SourceView result.

`stage_results.bind_prepared_program` then binds supplied/default Parameter
values against the declarations retained by that topology's exact Source and
collects the original Stage operation/Result owners. It shares the same final
assembly as Local source preparation rather than re-parsing or reissuing
pipelines. `prepare_local_program` retains its preparation usage privately in
the wiring; arbitrary `wire_results` output has no such provenance and cannot
be promoted by supplying usage numbers. The binding boundary includes retained
topology work/nodes/text, declaration admission and its own binding/collection
costs. Depth limits the new binding pass; topology was already checked under its
own depth limit. Earlier Catalog/SourceView registration and additional caller
orchestration remain separately accounted phases, not hidden costs certified
by this binder. Success is source preparation, not complete Program closure or
permission to execute unvalidated SourceView acquisitions.

The resulting `environment_input_at` registrations must be selected before
pipeline checking: snapshot evidence can refine types and conditional keys.
Attaching them to an already checked pipeline is not a substitute for using
those exact registrations at construction. Absent snapshots preserve available
source evidence rather than inventing a schema or capacity proof. This Local
snapshot boundary does not admit unrelated Catalog, policy, SourceView or Host
claims and is not the formal CheckedProgram entry.

When `stage_results.prepare_local_source` receives an Environment, it constructs
these registrations internally from its own declaration Source before preparing
any pipeline. `prepare_local_program` then uses each reconciled input contract
at registration, including snapshot-derived schema and conditional keys, and
retains the corresponding `ReconciledAttachment` in its Result wiring. Producer
ports and later imports therefore see the same evidence-backed types from the
start. The lower-level entrance rejects registrations owned by another Source.
Its source-only and reconciled attachment readers are distinct: a reconciled
registration is never represented as a source-only admission. The Environment
preparation prefix is charged once before Stage construction, with subsequent
attachment checks charging only their nonshared work. Policy, capacity and
publication closure still require their own later checks.

`attach_prepared_local_inputs` consumes the Environment and reconciled Stage
attachments retained by that Result wiring. It accepts no substitute Environment
or caller-assembled input array, and delegates the same exact Stage/evidence
checks as explicit reconciliation. The prior wiring and Environment costs are
checked before allocating the Stage handle array; handle collection and the
subsequent join share the work ceiling. Source-only wiring is not silently
upgraded to Environment-backed admission. The resulting contexts retain the
original registrations through source-identity and incoming-dependency checking.

`check_prepared_local_stage` selects a Stage's already resolved publication
orders and effective Parameters from its Local preparation. It constructs the
producer-visit binding array internally, then runs the existing order/guard/
capacity-owner checks and operation Parameter checks. Supplied capacity
applications are still explicit and must match the selected pipelines, policy
and producer ownership; missing applications are not filled with empty proofs.
The Stage work cap includes its retained order prefix, binding-handle allocation
and both checks. Source parsing and the full Local preparation prefix remain
separate costs for the eventual Program-level constructor. This entrance removes
caller selection of order and value owners, not the remaining capacity-material
or complete Program integration requirements.

`capacity_program_step.prepare_derived_applications` constructs ordinary
derived applications from admitted claims rather than requiring a caller to
assemble their successful `StepBound` dependencies. It resolves internal subject
references against one exact pipeline and walks proof inputs nonrecursively in
dependency order. Repeated input occurrences reuse the same checked dependency,
without deduplicating operands. Unknown subjects, unavailable external inputs,
unsupported proof forms or invalid applications fail the entire preparation.
The existing law/application checker still decides units, input correspondence,
arithmetic and bound values. Orchestration/collection work, input-link traversal
and operand passes have separate cumulative limits; none resets for each proof.
This is not a Program identity check, a Host admission or a replacement for
cross-producer application closure. Nonordinary sources retain their separate
coverage requirements, even when no ordinary proof is present.

Optional Graph input bounds are selected from one retained `GraphInputs` owner,
not supplied as an arbitrary list of proof successes. Its pipeline and admitted
claim collection must be the exact owners used for preparation. Input-measure
indexing is charged, and repeated proof operands retain their corresponding
checked Graph input. Missing external dependencies do not become zero counts.

`capacity_graph_preflight.prepare_application_coverage` runs Graph input checks,
derived proof preparation, consumer application checks and their final coverage
join from one pipeline, Host-source collection and selected policy. Consumer
requests contain unchecked step/limit coordinates, not successful applications.
Sequence, join, components and traversal ledgers all check operation coverage;
omitting both a request and its limit cannot silently remove the obligation.
The final join rejects unused or multiply consumed limits. Graph checks, proof
orchestration, requests, ledger construction and coverage share one work cap;
input-name bytes and the proof traversal/operand caps remain explicit dimensions.
Late failure exposes no partial coverage. Source admission precedes this entry;
Program ownership, authored-source identity, unsupported proof forms and actual
runtime enforcement are not supplied by this orchestration.

`prepare_program_checks` derives expression validation, pattern checks, text
bounds and profile admission from the source-producer context's exact selected
policy. It assembles these branches and checks operation profiles internally;
callers cannot substitute independent expression successes. Source-specific
work and text costs reduce the expression allowance before its checks run, and
the common selected-policy prefix is charged once. Pattern AST and policy/input
admission dimensions remain independent limits. Failure exposes no partially
assembled preparation. The returned operation-profile checks still require
operation resolution, semantic identities and exhaustive obligation closure;
this entrance does not claim a lowering-ready Program.

`prepare_program_sources` constructs Binding declarations and source request
slots from the selected context's Program, then checks requests, row bounds,
policy correspondence, lookup capacity and producer membership. The selected
policy's nonshared work and the owner join are reserved before constructing the
request branch; declaration work is included once through its slot inventory.
Typed row bounds and producer coordinates remain explicit inputs and must match
the actual keyed consumers and retained capacity owners. Empty collections are
valid only when those inventories require none. This does not manufacture
SourceView registrations, acquisition results or capacity claims, and it does
not turn request checking into Host execution permission.

`prepare_program_source_acquisitions` uses that same request/policy/producer
path but constructs the left-target bounds internally. Its only per-acquisition
selectors are unchecked producer-visit and claim indices into the retained
capacity closure. The classified keyed join supplies its actual left target;
neither that target, a substitute pipeline nor an independent successful bound
is accepted from the caller. Missing claims, unrelated targets and invalid
producer membership fail before source preparation can succeed. Repeated
acquisitions remain distinct even when they select the same claim.

Candidate selection, target traversal and row checks share the request work
ceiling. Traversal is charged once through the existing row-bound checker;
construction adds its own selection visits and reserves prior traversals before
building the next target. Final policy and producer checks retain their existing
aggregate costs. Local-only Programs require no acquisition selectors, while
SourceView Programs must cover every classified keyed join. This entrance
removes caller assembly of successful target checks, not runtime acquisition,
response validation, authority or complete CheckedProgram closure.

`check_prepared_local_stages` constructs all Stage contexts from that same
preparation and performs the final Stage-owner join internally. Gathering,
individual checks and producer-binding verification share one integration
budget; it is not reset at each Stage. A later failure returns no partial
context collection. Capacity applications and their optional owner mappings
remain explicit, with exactly one collection per Stage. This budget does not
replace accounting for the complete source-admission prefix.

`prepare_local_stage_contexts` selects each contextual pipeline and its effective
Parameter bindings from that same Local preparation, prepares capacity coverage
from explicit Host-source material and unchecked consumer coordinates, and calls
the Stage integration boundary internally. Material counts must match every
Stage and producer visit, including unused visits; absent material is not an
empty-proof default. The entrance accepts neither substitute pipelines nor
independent successful capacity applications. Cross-producer owner coordinates
still undergo the existing final owner checks.

Work and text budgets are shared across all Stages. Capacity coverage work is
counted once through its retained context; material visits, binding preparation
and usage reads add their own cost. Input-name bytes consume both their separate
cap and the text allowance, and proof input/operand work is cumulative across
producer visits. Prior wire and Host-source admission is outside this entrance.
A later missing visit, invalid consumer or exhausted budget returns no Stage
collection. This closes capacity preparation and Stage context integration, not
the remaining source/identity/obligation checks of `CheckedProgram`.

`prepare_local_context` derives its Environment from the prepared source's
retained Local input registration and admits that Environment's capacity
component before preparing Stage contexts. It then attaches the exact Result
wiring and reconciled inputs and validates policy/lookup selection internally.
No substitute Environment or separately selected policy is accepted. Missing
Environment or capacity material remains an error, not a default configuration.
The component's work/text and final policy-owner join are reserved before Stage
construction and counted once at selection; all intervening joins share the
remaining allowance. The component has explicit byte/node/depth caps, and Local
input nodes retain their independent limit. Source preparation records the
work/text prefix not retained by the exact operation, Result wiring and Local
input branches; context preparation reserves and charges that prefix once.
Thus declaration/binding admission and topology preparation are not omitted or
charged again as whole branches. Parsing precedes this entrance, and source
nodes/tokens/depth remain bounded by source preparation's explicit limits.
This entrance does not close source requests, Unit identities or execution
obligations.

For source preparation retaining connector declarations, `prepare_local_context`
also accepts their original `sourceview_resolution.PipelineInputs`. Its preceding
selection/registration work is reserved before capacity and wiring construction,
then charged by the reconciled-input join. That join checks the same Source,
Environment and per-Stage declaration partition and validates every type-only
registration against the retained pipeline. Missing or same-shaped replacement
registrations reject; Local snapshot evidence cannot stand in for SourceView
registration. The resulting selected-policy context can feed the existing source
request and source-identity preparation without reconstructing those owners.
This does not itself complete those checks, certify Unit identities, discharge
runtime obligations, or include every earlier caller orchestration cost.

`prepare_local_program_context` starts from the parsed Program, supplied
Parameter cursor, integrity-admitted Environment and explicit capacity material.
It constructs source-owned declarations, effective bindings and Local topology,
then invokes the context preparation above. Source preparation receives at most
the total context work/text allowance; its own stage/step/result/node/token/depth
and work/text caps remain additional limits. The aggregate charges source and
context work once through the retained prefix accounting, not two independent
budget resets. Failure in a later Stage returns no selected context. This is an
input-to-context preparation entrance, not the formal `CheckedProgram`
constructor: source requests, Unit identities, full static closure and runtime
obligation binding still follow it, and parsing/Host material admission precede it.

This order is a dependency graph, not a requirement to reconstruct earlier
results at every phase. Private incremental assembly can retain immutable
intermediates. Public low-level helpers remain useful for focused tests, but
their existence is not an alternative formal Program compilation entrance.

For Local inputs and Result imports, `stage_results.prepare_local_source`
derives the declaration owner and effective Parameters from the parsed Program
before preparing Stage topology and Result ports. It does not accept a second
declaration set or independently bound values. Missing bindings and invalid
supplied values prevent preparation; a later Stage failure exposes no prepared
source. The source Stage count is checked before copying Stage references.
Declaration and binding admission nodes/text consume the same allowances as
topology, with a per-traversal depth cap. Work includes topology plus Stage-copy
and owner-assembly costs; it is not a claim to count every instruction of the
admission algorithms. Parsing precedes this boundary. Environment, policy,
capacity and obligation closure still follow it, so this prepared result is not
a CheckedProgram or a claim that input data has been acquired.

The same preparation binds operation references before returning. It gathers
the exact collected Stages retained by Result ports, indexes their occurrences
in Program coordinates, and binds both Stage and Program indexes to its own
effective Parameter owner. Previously charged Stage-collection work is shared
once; handle gathering, additional indexing and binding consume the remaining
work allowance. No second declaration set, caller-provided Stage list or binding
set can be substituted at this entrance. These remain operation-only references;
source roles, incoming identities and other semantic inventories are not inferred
to be empty from this index.

Result collection at this entrance also reuses the exact checked Result bodies
that produced the Stage ports. It validates their correspondence to the retained
operation collection before returning the prepared source. Existing Result
admission costs are shared, while handle gathering and the final owner checks
remain charged. Failure in that final collection exposes no partial prepared
source. This supplies consistent Result owners to later context construction;
it does not discharge publication or execution obligations.

Source-role reference preparation uses `prepare_program_references` to derive
Stage bodies, declaration use and effective value projections from the same
checked operations and admitted request slots. It never reconstructs substitute
request slots or accepts a second effective binding set. Stage-body/use parsing
receives the remaining aggregate work allowance; the final owner join is reserved
before retaining the per-Stage inventories. Parser-specific caps remain explicit.

`prepare_program_source_identity` composes this reference branch with source
Binding requirements and the existing Program/Stage identity builder. Both
branches are derived internally from the retained operation checks. It reserves
the source-owner join and each branch's nonshared work before allocation, then
uses the same cumulative work and hash ceilings for identity emission. No caller
can replace the reference inventory, effective values or Binding inventory at
this entrance. The result is still a source identity: unresolved Host Binding
uses do not become admitted references, and no Invocation is inferred.

Operation resolution is orchestrated from one retained source identity by
`resolve_program_operations`. It constructs the expression closure and complete
operation requirement inventory, then runs order, scalar, frame, fill, range,
query, cell and data-profile checks before indexing their dispositions. Callers
do not supply a separately assembled collection of successful resolutions.
Selected profile artifacts still pass their existing exact-Environment ownership
checks. Any phase failure returns its typed diagnostic without exposing a partial
index.

Its requirement limit covers expression and operation occurrences together.
Its resolution limit covers the sum of specialized operation result entries,
including the Calendar and TextRank admissions; execution bindings and unresolved
slots are bounded by the requirement inventory. Each phase receives the remaining
entry allowance and the same cumulative work ceiling. The index may still contain
unresolved obligations: this orchestration is not the final validating constructor
and does not convert unsupported static work into execution checks.

Incoming integration can consume that exact index through
`link_resolved_program_incoming`, retaining its occurrence owners and execution
bindings without re-indexing. The identity prefix is shared once between the
incoming and operation branches; all branch-specific work, local-input inventory
work and the join remain charged. An equal-CID inventory from a different
admission owner is rejected. The lower-level profile-based entrance delegates to
the same join after indexing, so both paths have the same acceptance and budget
semantics rather than independent integration rules.

Shared work is counted once for an exact retained owner; additional branch work
and join validation are still charged. No phase resets the Program budget.
The final retained usage distinguishes parsing/prior admission where applicable,
integration work, emitted bytes/nodes and execution limits. Index allocation and
iteration are bounded before retaining entries. Runtime data is not materialized
as a whole Program-sized row tree to satisfy this constructor.

`prepare_program_incoming_gates` constructs every success-gate identity from the
retained incoming inventory atomically. Stage allocation, inventory visits and
gate construction share the remaining work budget; canonical preimage bytes and
nodes accumulate across gates, with depth bounded per emission. Stage-indexed
readers retain the exact incoming sites without copying collections. Result and
receipt requirements remain in the owner and are not discharged by this gate
collection. Unresolved Effect contracts prevent construction rather than being
replaced with empty maps. Gate identities specify readiness requirements, not
observations that their producers have succeeded.

## Exhaustive obligation coverage

Append input admission and concatenation order are separate execution bindings.
Both retain the exact checked operation and left/right operand occurrences,
including when both operands refer to the same producer. Input admission runs
before using the rows; ordered concatenation is checked before exposing output.
The latter retains any input logical-order witnesses without converting physical
enumeration into a total-order proof. A separate output-envelope disposition
retains the exact selected policy's `max_relation_output_rows` ceiling and rejects
the whole operation output on excess; it is not an observed count, a truncation
request or a heap-memory bound. The same policy remains available for input value
resource admission. Artifact publication has its own independently scoped limits.

Identity/completeness has its own disposition over both exact input occurrences.
Output completeness is complete only if both inputs are complete, and both input
provenances remain dependencies even if their fields are hidden. The output's
ordered logical values determine its value identity; neither input's value CID
is copied as the append output CID. Global row uniqueness is available only from
the pipeline's existing disjoint-discriminator/candidate-key evidence, never from
concatenation alone. This binding does not supply missing identity evidence to a
consumer that requires it. All four dispositions precede successful append output
use; input admission additionally precedes use of the input rows.

Complete-row set operations retain separate input-admission, typed comparison,
earliest-left-occurrence, left-relative output-bound and identity/completeness
dispositions over both operand occurrences. Equality is the existing typed-row
law, not arbitrary serialized-byte or precision-tagged decimal hash equality.
The checked operation retains `except` versus `intersect` and `all` versus
`distinct`; these determine the multiplicity calculation without deduplicating
the authored input edges. The left logical-order witness remains a dependency.
An output count no greater than the actual left count is not a bound on the
comparison working set. Right-side absence stays scoped to that captured input;
neither missing rows nor distinctness promote observation completeness.

`ResolveComparisonResources` binds a mandatory physical-realization requirement
to the exact operation, operands and selected Host policy. Its indexed categories
are comparison work, retained comparison state, and input/temporary byte usage.
These are not compiler check budgets or alternative semantic output bounds.
Lowering must select a resource contract covering all three with finite limits,
defined accounting and enforcement; the execution owner validates the same
operation and policy binding before input use. Allocation, spill and comparison
are bounded before exceeding those limits. Breach, cancellation or unavailable
enforcement rejects the whole operation output. A backend incapable of expressing
or enforcing a category cannot produce an executable Plan for this requirement.

This is intentionally a physical-realization obligation rather than a new
algorithm-independent Host-policy counter: hash joins, sorted scans and external
engines need different state accounting. A no-spill implementation does not need
temporary disk allocation, but still accounts for received and retained bytes.
The static constructor retains the mandatory categories, not a claim that a
physical contract was selected or installed. Lowering may not discharge them from
the left row bound, canonical value byte size, a generic `validated` flag, or the
presence of this binding. Its Plan must retain the selected resource contract and
its ownership separately from source/Unit meaning identity.

This follows the physical-operator resource boundary in smooth-cloud
`55b83448a` (`packages/data-plane-contract/src/validate.ts` and
`containers/data-plane/src/duckdb/executor.ts`): required memory/staging/temporary
limits are checked against the selected operator and passed to the engine.
That implementation is evidence for the separation, not execution conformance
for ActQL's typed equality or set multiplicity rules.

Cross join retains the compiler's checked product-count propagation and its
exact left/right count evidence alongside the selected join-family output limit.
Unknown operand or output bounds stay unknown, not zero and not the Host ceiling.
Before product enumeration, the execution check uses admitted operand counts and
checked arithmetic, respects all applicable proven bounds and the resolved output
limit, and fails rather than wrapping, truncating or publishing a prefix. This
runtime enforcement is not a manufactured static numeric capacity proof.
The separate ordering check retains left-major/right-minor logical order and both
order dependencies. An explicit `right_rows: one` remains its own pre-input-use
assertion, including when the left side is empty; it never selects one right row
or silently drops extra rows.

Cross-join operand identities are conditional selections. Their producer and
validation requirements remain attached when present; absence produces no
output identity proof. Unlike full join, the cross-join specification does not
require both operands to have identities merely to form the product. Consumers
requiring identity or total order still need their corresponding evidence.
Authored-guard limit assembly remains a separate requirement of the join-family
capacity entrance; an unsupported limit combination is not bypassed by these
product checks.

Source acquisition has distinct Host-combination and response-admission
dispositions. The former applies before provider access: the Host checks the
selected acquisition kind, authority, observation and Carrier combination and
prevents access if it cannot admit it. The latter applies before source output
use: actual values must satisfy the selected Carrier contract, or that output
is rejected. Both retain one exact Program-owned request and selected SourceView;
response admission depends on the same request's pre-access check, not an
equal-shaped check for another input. These are the execution boundaries in
[Connector SourceViews](../spec/language.md#sourceviews), not additional language
acceptance restrictions or evidence that the checks have already run.

Neither disposition subsumes mode support, request resource enforcement,
concrete Ref authority, keyed completeness/correlation/identity validation or
checkpoint obligations. Each applicable requirement needs its own connected
handling before a SourceView Program can pass the final construction boundary.
In particular, retaining these two dispositions is not a complete acquisition
closure and must not be used to remove an unresolved-source rejection alone.

`ReadAuthorization` separately requires current permission for the concrete
selected SourceView and request before provider access. Its subject exposes the
contract's typed `ReadMetadata`, `ReadContent` or `ReadBinary` authority, selected
from the admitted member rather than inferred from a view name or chosen by
current permissions. Host-combination support is its prerequisite, not a grant.
Resource enforcement depends on this authorization requirement, so response use
and keyed dispatch cannot bypass it. Failure prevents provider calls. Concrete
Ref provenance, provider/account boundaries and combined request egress policy
still require their own validation; read permission does not establish them.
This is a retained runtime obligation, not a compile-time authorization result.

`RequestEgress` retains the selected request's static field occurrences without
copying their arrays or reinterpreting literal business data. Indexed readers
expose the already checked literal or bound Parameter; unresolved Host bindings
remain explicitly represented, not replaced with a null value. `KeyedEgress`
additionally retains the exact keyed join, producer membership and correlation
mapping after request-value admission. Its input-dependent values are checked
before their dispatch, not fabricated during compilation. The associated
resource check depends on egress, and response use depends on those resource
checks. Each failure prevents provider access.

The indexed egress axes are sensitivity, completeness, MIME, bytes, availability,
provider-account boundary, region and current Host policy, matching
[External SourceView joins](../spec/language.md#external-joins). An axis that is
inapplicable to a particular value is handled under its selected contract; it
does not impose a MIME requirement on an ordinary number. These requirements do
not manufacture provenance or an effective policy CID. Combining request-input
and response provenance into the bound policy remains a static prerequisite of
formal SourceView integration. The presence of these runtime dispositions alone
cannot turn that missing static material into an accepted `CheckedProgram`.

Every selected request also carries `AcquisitionResources`, including direct and
unused SourceViews. It depends on that same request's Host-combination check and
applies before and throughout acquisition. Carrier-response admission depends on
it, as does keyed-request dispatch. The Host selects and installs the applicable
physical acquisition envelope before access, accounts for actual receipt and
retention rather than just logical output, and atomically rejects acquisition on
exhaustion. The requirement does not supply numerical limits, choose a transport,
or establish that enforcement has run. The selected implementation must provide
the applicable finite limits and their accounting/enforcement; a backend unable
to realize them cannot produce an executable plan. Compiler work budgets and
logical output bounds are not substitutes for this physical contract.

For query acquisition this preserves the receipt-versus-output distinction in
[Query acquisition](../spec/execution.md#query-acquisition). Keyed joins additionally
retain their existing request/byte/attempt/cost/duration envelope and correlation
checks; the generic requirement neither erases nor duplicates their logical count
evidence. Mode, authority, egress and persistent resource references remain
separate integration conditions, so adding this binding alone does not open the
formal SourceView entrance.

For each keyed join occurrence, request-value admission retains the original
join and its correlation-role mapping: it validates all authored left-key
components under the selected null-request policy and admits the representative
tuple values to the request contract before dispatch. Its resource check retains
the exact producer membership, resolved lookup counts and selected lookup policy;
decoded-body bounds do not stand in for wire-byte, attempt or deadline limits.
Response validation depends on both Carrier admission and that acquisition's
resource check. It checks requested-key membership, per-key completeness,
response cardinality, response identity uniqueness and external success, with
atomic failure under [External SourceView joins](../spec/language.md#external-joins).
Repeated join occurrences keep separate bindings even when they share one
SourceView. These bindings prescribe enforcement; they do not perform I/O,
choose a physical strategy or establish that a transport plan fits its envelope.

Response classification retains the exact selected SourceView data-policy
Envelope and the input's authored minimum separately. Known classifications
use `public < internal < confidential < restricted`; the effective classification
is their maximum. An authoritative `unknown` stays unknown for every authored
minimum, and an absent minimum preserves the authoritative classification.
This follows the strengthening rule in External SourceView joins and the
unknown-policy rule in [Check Environment](../spec/protocols/contracts.md#check-environment).
Sketch `87dc7144138edfcba108cdc59dc485ac976ba976:src/actql-compiler.ts`
uses the same maximum and unknown propagation. Its missing-policy `internal`
fallback is not needed here: SourceView policy admission requires the exact
referenced Envelope. Classification selection does not invent an effective
policy CID, combine request-input provenance, or authorize egress.

The response-only identity now has a bounded emitter,
`emit_source_response_policy`, for text, measurement or hashing sinks. Its
[normative preimage](../spec/language.md#external-joins) binds the concrete
source reference, selected view and authoritative policy CIDs, authored minimum
and resulting classification. It is not an identity of request provenance or
permission. The surrounding acquisition already binds the named input.
Source execution construction hashes this preimage once per selected request
under the shared work/byte/node budget and retains `response_policy_cid` beside
the exact policy object. All checks on that request share the same subject;
lowering does not reconstruct or reselect the policy. A failed construction
returns neither a partial inventory nor partially consumed caller budget.
The stage-local contract inventory selects `SourceResponsePolicyRules` for each
selected SourceView occurrence, including unused inputs that are still admitted.
Shared bodies are deduplicated without dropping their source sites. Local-only
stages do not acquire this root from another stage's Catalog entries or producer
traversal. This pins interpretation, not the concrete policy value or observation.

This explicitly fixes a previously unspecified preimage. Sketch's
`87dc7144138edfcba108cdc59dc485ac976ba976:src/actql-compiler.ts` uses an alias
effective-policy CID and a fallback origin set in its response projection. That
shape is not imported: its fallback can conflate unknown provenance with all
authored inputs, and its ResourceKind-derived source reference differs from the
current concrete Resource selector contract. Response policy and request-policy
composition remain separate; no observation data is inserted to fill that gap.

The effective-policy preimage identifies a policy set rather than a value's
lineage. It retains source Envelope CIDs, strengthened response-policy CIDs and
an explicit unknown-provenance flag. The value-occurrence correspondence remains
owned by the checking context; equal policy sets do not permit replacing that
context. Repeated uses of one policy do not change its restrictions, so the
reference sets are sorted and deduplicated without deduplicating value occurrences.
This is a new explicit identity decision: Sketch's alias-origin array is not part
of this policy identity. Aliases and input dependencies remain in the subject's
own identity. An empty set is unknown rather than an implicit public grant.

`EffectivePolicy` materializes only the selected policy-reference set, not row
data. Its private constructor accepts already selected, owned request/response
contributors; checked graph traversal remains responsible for choosing them.
It copies the contributor sequence, combines classifications, and sorts and
deduplicates source and response CIDs under the shared work budget. Duplicate
references do not remove contributor occurrences. Public indexed readers expose
the retained contributors, and the bounded emitter uses the same canonical
preimage for singleton and multiple-reference sets. A publication retains this
effective object separately from its acquisition and import dependencies.

For direct acquisitions, `DirectSourcePolicy` retains the exact parameterized
request and selected response policy. Construction verifies their shared input
owner. Static request admission currently supplies values and their literal,
Parameter or Host-binding origins, but no authoritative policy attestations for
those values. Each such occurrence therefore contributes unknown provenance;
the original request remains available through indexed readers, including a
Parameter's supplied/defaulted origin. Response policy references are retained
even when the combined classification is unknown. The bounded emitter uses the
shared effective-policy preimage and does not materialize another value tree.

Keyed acquisitions do not receive this direct-policy result: their correlation
producer's contributing policies must also be selected. Retaining a direct-policy
object does not establish runtime egress admission, Ref authority or completion
of the remaining SourceView construction conditions.

Each selected SourceView occurrence contributes `EffectiveDataPolicyRules` to
its owning stage's contract inventory, including admitted but unused inputs.
The contract's dependency on `SourceResponsePolicyRules` is an explicit closure
edge. Repeated occurrences share contract bodies without dropping their sites;
Local-only stages and unrelated Catalog entries do not inherit these roots.
This selects interpretation contracts, not a concrete policy value or an egress
permission, and does not claim keyed provenance composition is complete.

Coverage starts from the source, expression, operation, input, publication and
incoming-dependency inventories, not from the list of successful resolutions.
Each owned occurrence has exactly one disposition:

| Disposition | Required content |
| --- | --- |
| Statically resolved | The typed resolution and its exact source/producer/binding/policy owners. Conditional assumptions link to the execution checks that enforce them. |
| Execution check connected | A typed execution binding with subject, application point, prerequisite evidence/dependencies and prescribed failure behavior. |
| Unsupported or statically unresolved | A construction error. This disposition cannot appear inside a successful CheckedProgram. |

A nonempty execution-check collection is normal. An unclassified occurrence,
foreign resolution, duplicate disposition, missing dependency or unconsumed
resolution is not. Matching counts is necessary but cannot replace checking the
specific occurrence and its owner. Repeated references are separate occurrences
even when they share a resolved contract or execution dependency.

Classification matches the full typed obligation variants exhaustively, including
nested operation-family variants. No catch-all branch maps a new kind to success
or runtime. A coverage check compares the registered inventories with the handler
set so that a new kind in a previously irrelevant family also requires review.
Handling remains operation-specific; there is no universal `safe` or
`preserves_evidence` flag.

`close_program_operations` closes the operation-resolution inventory by visiting
each owned occurrence, not by accepting a zero unresolved-count assertion. It
retains either the exact static resolution or the typed execution binding and
rejects the first unresolved occurrence. Its opaque result has no unresolved
disposition and exposes indexed reads without copying arrays. The prior index
and every closing visit share the work cap. Execution bindings remain future
checks with their original subject, phase and failure behavior; closing them
does not assert that data passed. This covers the operation inventory only:
input, publication, source and incoming closure remain separate obligations of
the formal Program constructor.

`close_program_local_inputs` closes every retained Local input occurrence,
including unused declarations. It rejects unresolved duplicate-order selection
and retains raw admission, key-component validity and key-uniqueness checks as
applicable. The prerequisite sequence is checked against the exact same input
subject: raw admission precedes key validation, which precedes uniqueness.
Input visits and execution bindings consume shared work and separate collection
limits before retention. The opaque result does not contain admitted rows and
does not discharge SourceView, publication or incoming obligations. Its owner
retains those other inventories rather than treating them as absent.

`close_program_incoming` retains every connected Stage-activation check in source
occurrence order, including repeated Result imports. Unresolved receipt or
producer-success contracts prevent closure. Producer Stage-field scans are
charged per success occurrence as well as the inventory visits. Missing or
uncertain observations still require waiting or reconciliation, and predecessor
failure still prevents activation. This closes activation-check bindings only;
it does not construct Result-import interface identities or assert that a
predecessor has run successfully.

`close_program_publications` visits every Stage Result, not only root exports,
and links each static publication-order obligation to the retained Result port
and that Stage's exact integrated order context. It consumes the existing order
decision without choosing new keys or re-inferring order. The obligation enum is
matched exhaustively; new Result requirements need an explicit closing rule.
Stage, Result and obligation visits share the prior Program work ceiling. This
closes static order selection only: conditional input/key checks, output limits,
materialization and successful publication still require their own enforcement.

The same closure retains applicable Program row-bound candidates for each
Result's actual input target. Candidates come from that context's admitted
capacity applications, and retain exact consuming-visit, proof and producer
membership. Row-preserving paths and imports use the existing target-row
application rule; unrelated proofs and other measurement units are not
substituted. Rejected searches consume traversal work too. Candidate retention
shares the closure's work and collection ceilings, and indexed readers do not
copy proof arrays. These are Program upper-bound candidates, not a selected
publication limit: applicable Host and other ceiling candidates, canonical
minimum construction and atomic enforcement remain separate requirements.

`select_publication_row_limit` selects the numeric minimum of a Result's retained
Program row candidates and its exact capacity context's `max_artifact_rows`
ceiling. It accepts neither a substitute policy nor caller-supplied bounds. A
Host-only selection remains an enforcement restriction, not a proven row count.
Candidate ranges are indexed per Result, so selecting its limit does not rescan
other Results' candidates or copy their arrays. Selection work and candidate
limits include the Host candidate. This typed numeric decision still requires
canonical resolved-limit emission against the final protected semantic subject;
it is not itself that wire artifact or permission to publish. The selected Host
value is execution-policy information, not part of Unit Definition identity.

Publication limit subjects follow the Unit-scoped Result pointer in
[resolved limits](../spec/language.md#resolved-limits). This makes the subject
stable under unrelated enclosing-Program revisions and keeps it distinct from
an observation or an internal producer-visit index. Escaping the Result name as
one JSON Pointer token preserves arbitrary authored names without ambiguous
path segments. The general resolved-limit schema admits a subject string;
matching that string to the actual Unit, Result port and quantity is a semantic
application check, not something a self-CID or JSON Schema alone proves.

`close_stage_requirements` runs operation, Local-input, incoming-activation,
publication-order and source-mode closure internally from a single incoming-link owner. It does
not accept independently closed branches. Shared preparation is counted once;
each branch receives only the remaining work and disposition allowance. The
disposition limit covers operation entries, Local execution checks, activation
checks, publication entries, retained publication row candidates and source-mode
checks together; Local input occurrences have their own
additional bound. Failure in any later branch returns no combined closure.
This staged closure is a component of CheckedProgram, not its substitute:
SourceView/Host obligations, complete semantic identities and remaining runtime
enforcement must also be connected at the formal constructor.

`close_program_source_modes` visits every selected request from that same
Program's source preparation, including unused direct inputs. It retains the
exact Direct or Keyed request and its Stage/source-input coordinates. Those
coordinates index the selected SourceView request array, not all Stage inputs.
The retained support check must run before acquisition; unsupported runtime mode
prevents the request and its output. It is not Host authorization, a successful
read, completeness evidence or row admission.

The mode-obligation classification is exhaustive. A changes range still needs
its bounded-range resolution; `SourceStateRequirement` requires static
construction of the normative envelope with the actual Program identity.
Neither is converted to generic runtime support. Until those resolutions are
connected, closure rejects them with their exact Stage/input/obligation rather
than returning a partial success. Snapshot checkpoint metadata does not invent
a changes-state requirement. Stage visits, request visits and mode obligations
consume the same work cap, and support checks share the disposition limit with
the other staged requirements. Indexed readers expose the retained checks
without copying a request array or rerunning mode selection.

An execution binding retains:

- the protected typed subject: input, producer output, operation occurrence,
  expression occurrence, Result port or incoming gate;
- the enforcement point required by the law, such as input admission, before
  consuming a producer, during an operation, or before publication;
- the exact selected rule, bound quantity/strategy and evidence from which it
  was derived, plus references to prerequisite checks;
- the specified failure outcome and which output/continuation cannot be
  exposed when the check fails.

This is a semantic enforcement requirement, not a backend callback or a promise
that a backend already implements it. Its dependency graph cannot reference
another Program, an omitted producer or an unavailable future prerequisite.
Cycles in enforcement prerequisites are errors; this does not prohibit cycles
in Graph data admitted by the language. For example, a conditional candidate
key retains uniqueness admission, and a resolved capacity retains its quantity,
target and enforcement obligation. Neither becomes unconditional proof merely
because its static arithmetic or CID matches.

## Identity boundaries

[Local contract closure](local-contract-closure.md) separates the selected
contract set from source occurrence evidence and concrete execution decisions.

Contract selection is defined before its canonical JSON representation. It
includes the direct semantic dependencies and their required transitive
dependencies, including domain, guard, permission, scope and failure rules.
Unrelated Catalog additions do not become local semantic dependencies. Repeated
uses remain associated with their sites even if canonical storage shares a
contract. Unknown dependencies and conflicting pins prevent closure; dependency
cycles require an explicit governing rule rather than truncation at a visited set.

The contract closure identity, Unit Definition and concrete Invocation remain
different roles. Selected policy/capacity evidence belongs to the identities
specified by its governing rule, not automatically to source Definition. The
whole Check Environment or Catalog CID is not a fallback local preimage.
Membership/authenticity still have to be validated where required; excluding
them from a local hash does not waive those checks. Semantic preimages and fixed
independent vectors are established together with the selection rules.

The result retains source Program/Stage identities and required local definition
projections. Observation-dependent identities are not fields populated with
placeholder CIDs. They are constructed later from admitted concrete observations
and this result's exact semantic dependencies. Static readiness is neither an
Invocation nor authorization to run it.

## Lowering reads

Read-only count/index access exposes the source-owned stages, role-tagged input
edges and producer ports, checked operations and Carrier contracts, selected
bound values, exact order strategies and their dependencies, resource witnesses
and protected applications, local identity projections, and obligation bindings.
Paths/spans and embedded-expression ranges remain available for diagnostics.
Returned collections cannot mutate the sealed result, and large arrays are not
copied before the caller can apply its preparation budget.

Lowering consumes these decisions without re-resolving names, re-inferring keys
or order, choosing substitute policy or combining independently supplied checker
results. It verifies that its selected registry/backend can represent every
operation and required execution binding. Failure to represent one prevents an
executable Plan; it does not retroactively change language type acceptance.
Plan structure/identity validation and actual execution are downstream checks.

## End-to-end acceptance

The integration fixtures enter through the formal check entry, not through a
test helper that seals preassembled successes. Establish these paths early:

| Program | Essential coverage |
| --- | --- |
| Local, no external acquisition | A small typed local input or generator, transformation and named Result; actual source/Parameter/environment preparation through sealing. |
| Multiple stages with Result import | Producer port construction, consumer registration, local identities and incoming success requirements, with a failure in the later stage exposing no partial Program. |
| SourceView and capacity | Selection from the admitted Catalog, request/binding validation, quantity-specific capacity and producer dependency, with execution checks retained rather than performed. |

For each path, fix expected semantics independently of the product constructor.
Test equal-content evidence from another Program/environment, missing dependencies,
conflicting pins, repeated/unused branches, exact/short aggregate budgets and
late failures. Runtime checks remaining in a successful result are asserted by
subject, application and dependency, not merely by count.

The three paths start integration; they do not replace the complete agreed
operation scope. Extend a coverage matrix by operation, Carrier alternative,
evidence generation/transfer/invalidation and downstream consumer, selecting
representatives of distinct code paths rather than a Cartesian product.
Run JS/Wasm/native, API, format, document and metadata gates throughout this work.
Linux CI is checked for exact intermediate revisions as they become available,
not inferred from local success or postponed as the only final check. CI execution
does not authorize publishing a branch or modifying another worktree.
