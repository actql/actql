# Checked Program construction

This is the construction contract for the main-side boundary described in
[Pure operation checking](pure-operation-checking.md#main-and-lowering-ownership).
It specifies the orchestration target, not an already available API or a new
wire artifact. Language and the pinned machine contracts remain authoritative.
Existing `pipeline_check_context` results are implementation components of this
boundary; adding another component is not itself end-to-end completion.

## Entry and success

The intended entry is `program_check.check`. It takes source and admission
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

`check_prepared_local_stages` constructs all Stage contexts from that same
preparation and performs the final Stage-owner join internally. Gathering,
individual checks and producer-binding verification share one integration
budget; it is not reset at each Stage. A later failure returns no partial
context collection. Capacity applications and their optional owner mappings
remain explicit, with exactly one collection per Stage. This budget does not
replace accounting for the complete source-admission prefix.

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
