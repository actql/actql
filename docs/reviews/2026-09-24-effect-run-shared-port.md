# Shared checked-Effect and Run port required by Salesforce

Status: implementation interface proposal, not a completion claim.
Initial baseline inspected: `311921b14d608617f715c531829c75139ac2f7a3`.
Rechecked against `5217412b1e2bce5592b9dcfab0cb54fd75c111f7`.

## Current product boundary

`src/program_check/source.mbt::audit_declarations` rejects every nonempty
Stage `effects` object. `src/stage_results/local_program.mbt` rejects Receipt
imports. `adapters/host-node/entry.mjs::runPublishedCapturedStrategy` and its
publication path are Effect-free. Salesforce currently provides admitted
Catalog observations, bounded reads, typed REST requests and responses, exact
provider target identities, and durable physical send custody. None of those
pieces constitutes a checked Program-to-Effect-Set Run.

The safe integration is one shared MoonBit-owned port, consumed by Connector
implementations. It must not be a Salesforce-specific Run owner or a second
Effect state machine in JavaScript.

The intervening MoonBit work now collects structurally checked Effect headers
and binds their direct Result references to exact checked Stage Result fields.
The binding retains each field's admitted type and its selector, key, command
target, or value role. The next increment rejects a Command target field that
is not a non-null value-level ResourceRef. A further target-only selector
matches its kind to the exact Command Contract in an identity-checked
Connector Catalog. The static candidate now requires the Catalog's admitted
role-reference closure as the owner of Command selection. This is not complete
Command Contract admission: permission, recovery, current authority, and the
checked Program's exact Environment binding remain open. Complete Mapping
Contract admission,
Preview, and apply permission are also still absent.
The bounded Mapping shape binder now matches each non-Command header's exact
authored reference and target to an identity-checked resolved body; Command
headers remain on the separate Command Contract path. It does not yet bind
that Environment to the standard checked Program or validate Mapping row
conversions and current authority.
The following bridge derives each member's selector and written field set
from those same retained headers and the explicit Mapping row field map, then
selects the exact static permission rule. This is not a current grant or a
complete checked Effect Set.
It now rejects missing required inline-create fields and missing mapped
source fields in retained Results. Direct Result-field copies check target
value shapes; literal values, null behavior, and conversion proofs remain open.
The same bridge validates the Mapping's conversion inventory before rule
selection, but retains each law as an obligation pending registered
implementation and type evidence.
Bounded literal admission now retains typed inline and contract-owned values
and rejects known null-behavior violations. It does not turn these bindings
into a complete Preview or apply permit: runtime Result-row null handling,
converters,
current grants, and whole-set preflight are still required.
Static Mapping admission now rejects nullable inline Result values aimed at
nonnullable target fields and rejects a nullable row source whose `write_null`
or `omit` behavior conflicts with target nullability or required presence.
The actual row-value evaluation and `reject` behavior still need to be
connected before an Effect can be sent.
The standard Program checker still rejects nonempty Effects. A complete
Mapping Contract body and its reference/permission/type admission must be
specified and connected before lifting that rejection; an arbitrary member
CID or a dynamic Salesforce describe is not a substitute.
The Connector SDK now admits an Effect-only bundle under the same owned
registration used for Acquisition and Compute. This is a registration
boundary, not Effect execution authority or a standard Host caller. The
Effect implementation remains absent from the product Run path described
below.
The checked Stage now has a bounded MoonBit comparison against an admitted
private Preview identity. It checks the exact member set, effect kinds, and
within-member failure policies, independent of Preview array order. This is
one static inventory guard only: the normal Program checker still rejects
Effects, and the Host has not yet bound that Preview to a Captured Run or
admitted apply authority.
The static Preview boundary also checks each member's authored Mapping or
Command reference and exact resolved Contract CID. The enclosing checked
Program now binds that Preview to its own Program Definition, Program semantics,
and Check Environment identities. A different Program, Environment, or
resolved Contract cannot reuse the Preview as static evidence. The boundary
does not establish the compiled Plan, Invocation, Captured Run, current grant,
target guard, or apply permission; it is deliberately not an execution permit.
The separate `EffectStaticCandidate` now combines Result binding, Mapping
shape/rule/literal admission, and Command target/inline-input admission under
one bounded work budget and one exact Environment owner. It rejects missing
coverage and foreign Program/Environment inputs. It is intentionally not a
checked Effect Set: the standard checker must still bind the Environment and
close registered conversions, Command semantics, policy, and runtime
authority before execution.
The checked Program now exposes its retained exact Environment owner, and the
checker configuration exposes the originally supplied owner. This makes the
future Program-to-Effect binding an ownership comparison, not a CID-only
reconstruction. The ordinary checker still rejects nonempty Effects.
An opaque `EffectComputationCandidate` now runs the ordinary computation check
after collecting bounded, structurally valid Effect headers from that exact
Program. It retains checked Stage Results, Environment and Catalog references
without exposing an executable `CheckedProgram`. The ordinary `CheckOutcome`
still rejects Effects; malformed headers, foreign owners, unrelated Bindings,
and missing Mapping closure cannot escape through the candidate. This is a
preparatory ownership bridge, not complete Effect checking or Run admission.
The static Mapping/Command close now returns one opaque
`EffectProgramStaticCandidate` retaining both the checked computation and its
complete Effect inventory. Downstream capture must consume this same owner;
the static close does not satisfy conversion, current authority, or apply
obligations.
The shared Captured DAG now offers a bounded pin for a completed cell-backed
task output. Closing the ordinary output port prevents new pins while an
existing pin keeps the allocation charged and avoids revoking its borrowed
view solely because of port close. The original completion must still be
available. Managed and external resident outputs are rejected by this pin:
their physical owner must supply an equivalent retention proof. The Effect
source port can now bind that pin to the exact checked Result occurrence for
cell-backed terminal outputs. It is not yet a complete Preview input or the
standard Effect Run port.
The Program check also retains the exact admitted Catalog role-reference
closure. Downstream Command selection can reuse that proof without repeating
Catalog hashing, while still checking the exact Program owner and current
execution authority. This retained proof alone does not authorize an Effect.
Result-correlated update, upsert, and delete now derive a pure AoA
`EFFECT.plan` pipeline from the retained Result and Mapping rule owner. The
static Preview binder recomputes its logical CID and rejects a missing or
foreign plan CID. `id` and `match` can share the same planning graph while
their distinct authority contracts remain separate. Literal changes are not
silently copied into the AoA field map. This is a checked planning fragment,
not a captured Result binding, physical payload, Preview admission, or write
permit; the standard Effectful Run port remains open.
Preview identity admission now retains the paired source Result name and
Result Artifact CID. Static checked-Stage admission rejects a different
source name, and the captured computation-chain check requires the exact
Artifact in that Captured Run. These checks do not yet prove the captured
rows' Effect Plan output or authorize apply.

## Required port and owners

| Output from shared boundary | Required content | Consumer |
| --- | --- | --- |
| `CheckedEffectSet` | Exact checked Program, Stage and member occurrences; operation and `halt`/`continue`; source Result port; resolved Mapping/Command Contract CID; type, item-limit, policy and authority obligations | Effect proposal, Host admission |
| `CapturedEffectInput` | Same Run and Captured Run; immutable named Result generation, holding and source binding for every dependent member | Connector preview without re-executing Compute |
| `AdmittedEffectPreview` | Complete private Preview, semantic/member/row identities, checked inventory and exact physical Run bindings | Whole-set footprint and apply admission |
| `EffectApplyPermit` | Exact accepted Preview and authenticated partial-application acceptance where required; current capability, authority, source and target guards for every member | Durable dispatch owner |
| `EffectSetProgress` | Durable row facts and the common MoonBit frontier; independently advancing members and within-member row policy | Site request scheduling and reconciliation |
| `EffectRunCompletion` | Member and set receipts, final Run outcome, retained unknown responsibility, and existing publication/cleanup ownership | Standard Host response and publication |

The checked inventory must be projected from the retained `CheckedProgram`;
the caller must not supply an alternative list of effect IDs or identities.
The captured input must use the existing Run's Result holdings; a Preview must
not reacquire or rerun a missing source. Whole-set preflight and apply
admission precede the first mutation. Unknown or possibly dispatched rows
remain durable and are never made retryable by a new physical attempt ID.

The existing `effect_application` identity, footprint, frontier and ledger
rules, and `run_publication` Preview/receipt contracts remain authoritative.
The adapter retains HTTP and Store observations only. A Collections request
covering multiple rows needs an all-row durable send claim before its HTTP
call; a single-row claim is not sufficient batch custody. Its response must
be correlated to every original row without merging Effect Set members.

The shared change should be one independently reviewable commit owning the
types, accessors, standard Host caller and acceptance tests. Salesforce then
consumes that port in a separate Connector commit. No existing Effect-free
publication guarantee is weakened to make an Effectful Run pass.

## Acceptance for the shared port

1. A valid multi-member Program produces the exact checked member inventory;
   malformed, unsupported or unclosed Effects are rejected before execution.
2. A Captured Run supplies all dependent immutable Result generations without
   a second Compute or SourceView call.
3. Preview identity and apply admission verify exact Run, authoring, source,
   authority, policy, row keys and every member's footprint before any send.
4. The common frontier preserves `attempt_all` across members while applying
   `halt` or `continue` only to rows of that member.
5. A process restart reconciles completed and uncertain rows from the same
   durable ledger; successful and unknown physical writes are not resent.
6. Member receipts, set receipt and final Run state use the admitted contract
   chain. Effectful publication does not masquerade as Effect-free success.
7. Local HTTPS tests assert request counts, row/member identity, zero sends on
   overlap or stale guards, cancellation exposure and retained cleanup.

The isolated Salesforce org and write authorization are still absent. Local
HTTPS evidence cannot be reported as live-provider verification.

## Fixed-SHA review application

`02-salesforce-effects.md` inspected `66b42189d2bb17407776fd74ca0e7ea9ddf73d01`.
SF-1's exact HTTPS request-target and SF-2's provider target identity were
corrected after that SHA. A later check also binds each physical write to the
corresponding admitted Preview row, not merely to a target somewhere in the
member footprint. The Salesforce Site suite passes 104/104 at
`6415fd2ab31058f829f735089f553a882017babc`, including local HTTPS target,
row-swap rejection, and whole-set footprint tests.
The common MoonBit frontier now reads a durable Collections batch as several
in-flight rows of one `continue` member. It withholds that member's next row,
allows independent members to proceed, and rejects concurrent in-flight rows
whose ledger heads name different physical requests. A real SQLite restart
fixture covers the batch claim and exact retry without another send claim.
These component results do not close SF-3: the ordinary checked Program,
standard Host, complete multi-member Preview/apply admission, final receipt,
and restart-safe reconciliation still require one connected product test path.
No live Salesforce org or authorized write scope has been provided.

The follow-up review at `89ef91382f20dc092c398ce920860fa82a57e149`
identified a mutable caller-owned JS claim wrapper across physical send awaits.
The adapter now snapshots each wrapper and the collection order before durable
claim and HTTP send, retaining the exact opaque MoonBit objects. Real SQLite
tests mutate the caller's single claim and collection array during the send,
then verify the original response binding after restart without a second send.
The same review found stale Workers composition output. Both generated bridge
packages and their conformance projection were regenerated from product
templates; the Workers suite passes 24/24 locally. These are component fixes,
not evidence that an Effectful standard Run is complete or that required CI has
passed at the new SHA.

Read-only recovery after a physical response was durably stored now has
separate single-record and Collections adapter paths. They check the immutable
request and exact MoonBit ledger claims, require a current evidence-view
decision, and reproject stored bytes without a write credential, Catalog
refresh, or physical send. Local HTTPS and SQLite restart tests verify success
without the write grant, denial of an unauthorized evidence read, foreign
payload and reordered-row rejection, and unchanged send and credential-use
counts. The decision is supplied by a trusted Host caller; the standard
Effectful Host entry has not yet connected that authority. The existing
capture entry still performs current write admission for new sends.

The follow-up review at `89ef91382f20dc092c398ce920860fa82a57e149`
(`02-salesforce-effects (1).md`) separates four findings. SF-24-1 is closed
by owned claim snapshots and restart tests; SF-24-2 is closed by regenerating
the Workers composition and verifying its bridge. SF-24-R1 is addressed at the
physical response component: an exact, currently authorized evidence read can
reproject a stored response without obtaining a new write grant or sending a
second request. Its standard Host authority binding remains part of the open
Effectful Run port, not a completed product recovery claim. SF-24-G1 remains
open: the standard checker rejects nonempty Effects, and the normal Host has
not yet admitted and published a multi-member Effect Set. Local HTTPS and
SQLite tests do not substitute for that path or for live Salesforce org
verification. The supplied review's CI status belongs to its fixed SHA; a
new required CI result must be checked against the final implementation SHA.

The 0.1 final Effectful Run Receipt now has a MoonBit-owned reference closure
and an issuer that derives its body from the prior computation Receipt. The
closure admits the exact Captured Run, private Preview, member receipts and
Effect Set receipt, and rejects altered computation evidence or a foreign
reference. It does not prove the checked Program kind, physical apply outcome,
current authority, or durable publication commit. The existing synthetic
reference fixture is not a standard Host Effectful execution test. Those
remaining proofs must be connected before this port is marked complete.
Final Receipt admission now also requires the captured Effect, Effect Plan,
and Effect Plan logical-CID inventories to name the same exact members as the
private Preview. This is inventory closure only. The synthetic plan values in
the reference fixture do not prove AoA plan identities or replace the missing
product Captured Run issuer.
The checked Program now also retains an admitted Run Definition owner after
MoonBit compares its exact Program Definition, Program semantics, Check
Environment, Compiled Plan, Invocation Template, authorization context, and
lifetime. Foreign Plan, Environment, Run, and outlived authority are rejected.
This is not executable Effect authority: executable-plan content, concrete
Invocation, captured Effect plans and values, current grants, and apply remain
to be admitted on the same owner before the standard Host may dispatch.
That Run owner now binds a private Preview to its exact concrete Invocation,
Run Definition, and Compiled Plan as well as the checked Stage inventory.
Foreign Run, Plan, Invocation, or Invocation Template is rejected. The
ObservationSet closure and Captured Run's Effect Plan and Result holding proofs
are still outstanding;
this Preview binding is not an apply permit.

The static Effect candidate can now prepare its exact checked computation DAG
through the ordinary physical planner while retaining the Effect owner. The
graph carries the Program's structural Effect flag. The standard Effect-free
Host publication entry rejects this graph before Compute, and the shared
captured-DAG identity admission rejects Effect-free Result publication for it.
The task-only computation entry does not grant apply authority. This is a
preparatory physical bridge, not a completed Effectful Run, Preview admission,
or standard Host multi-effect path.

The fixed-SHA common/Salesforce review at `871cc14c` identified mutable
invocation bindings and provider projection before raw response custody. The
shared Host/Site boundary now owns primitive scope bindings, limits, and the
call wrapper before asynchronous work. The shared physical dispatch path
stores exact bounded response bytes before Salesforce projection. Single and
Collections responses can be read after restart without a second send. Local
HTTPS and SQLite tests cover the mutation and crash-adjacent ordering cases;
they are not live Salesforce-org tests.
The projection callback now receives only the stored response, never the
ephemeral transport result. Salesforce uses limits owned before the HTTP
await. This keeps new-response interpretation on the same evidence boundary
as read-only recovery; the common bridge test rejects a second callback
argument for both single and Collections sends.

The common adapter now assembles scoped credential calls and owns exact
evidence-read authorization, claim verification, and Ledger lookup. Provider
code still derives the operation, request identity, and typed interpretation.
The Salesforce and DuckDB broad Acquisition paths now delegate issuance,
exact retained-row and transport verification, and one-shot capture to the
same MoonBit `QueryEvidenceCustody` owner. Provider-specific page or native
execution remains separate. This does not claim that every Acquisition
implementation has migrated, or that the standard Effectful Host Run path is
complete merely because the adapters and these broad paths share procedures.
The shared registration pins the trusted transport verifier before execution;
attempt selection, issuer liveness, exact retained rows, foreign records, and
one-shot capture are exercised by the Salesforce and DuckDB broad integration
fixtures. A combined fixture also checks independent provider issuers and
capture after one issuer closes. The original query integration suite passed
546/546 on JS, Wasm, and native; the combined fixture adds one case.

The static checked Effect-to-Preview binding now compares each authored
`max_items` guard with the Preview's resolved member bound. Both literal and
bound-Parameter guards come from the retained checked Program owner; a Preview
cannot increase either guard. The comparison is budgeted and does not replace
the later complete-scope count, Contract and Host ceilings, physical payload
equivalence, or current apply admission. The standard Effectful Host path is
still open.

## Common/Salesforce review at 871cc14c

The five findings in the fixed-SHA review are assessed against the current product
path, not treated as five unfixed defects at the reviewed SHA:

The Salesforce Acquisition assembly now resides in its Host package rather
than a provider-facing `acquisition` package. The provider `catalog` package
retains Salesforce metadata, SOQL, page, and write semantics without importing
Host custody or planning packages. Host owns the selected broad attempt,
evidence issuance, capture, and managed output lifetime. This removes a
misleading public package boundary; it is not a complete external Connector
SPI. The Host API still exposes internal checked-owner types, so an off-tree
Connector closure and a standard Effectful Run caller remain acceptance work.

| Finding | Disposition | Product evidence |
| --- | --- | --- |
| COMMON-SF-01 | Addressed | The shared owned invocation context snapshots scalar scope and limits before I/O. Catalog and Query compare later authority with that binding; local HTTPS tests mutate the original scope during a request and reject a foreign continuation. |
| COMMON-SF-02 | Addressed at physical custody | The common dispatch owner stores bounded raw single or Collections bytes before provider projection. Projection receives only the stored response. SQLite restart tests retain those bytes and never resend an uncertain write. Complete apply admission remains part of COMMON-SF-05. |
| COMMON-SF-03 | Partially addressed | Salesforce and DuckDB use one MoonBit `QueryEvidenceCustody` owner for issuance, exact verification and one-shot capture. They also use the same captured-evidence consumer binding, including liveness rechecks. Their Retained-to-Issued progression and some provider wrapper checks remain separate; the complete common owner is not yet proven. |
| COMMON-SF-04 | Addressed for the reviewed calls | Shared invocation assembly and evidence-read recovery own scope matching, current read authorization, exact Ledger lookup and projection ordering. The provider supplies operation/request identity and typed interpretation. A local SQLite test also projects a stored response through the common recovery API after restart. |
| COMMON-SF-05 | Open; completion blocker | The standard Host still rejects nonempty Effects. Checked/captured owner, complete multi-member apply permit, final receipt publication and restart-safe standard Run tests must be connected before Salesforce or the shared Effect port is complete. |

These local fixtures are not live Salesforce verification. The isolated org,
credential reference and write permission have not been supplied; no existing
Smooth Cloud connection may be substituted.

The checked physical graph can now retain the exact admitted Effect Run owner
in `CheckedEffectRunDAG`. Binding a graph to a separately checked candidate is
rejected even when a caller could reproduce matching CID strings. This keeps
the checked computation and Run proof together for the next capture boundary;
it is neither a captured Result nor apply authority. The ordinary Host still
rejects Effectful execution, so COMMON-SF-05 remains open.

The generic checked-DAG and captured-DAG entries now reject Effectful Programs.
Only the Effect-specific entries can prepare and open their physical compute,
and `CapturedEffectRunDAG` retains the same admitted Run owner through capture.
This prevents a caller from discarding the Effect closure by using an ordinary
computation entry. It does not yet prove the captured Result holdings, issue
the Effect Context, or permit a physical write.

The Effect-specific graph also binds each authored source Result to its exact
checked Stage Result port and bound preparation. This lookup is independent of
root publication aliases; the regression fixture gives the root export a
different name. The graph reserves bounded work for every Effect member and
retains the source occurrence for downstream capture. It is static provenance
only: output liveness, a consumer holding, row values, and apply admission
still require the captured execution and current authority.

The initial `CapturedEffectInput` port now pins a completed cell-backed output
through its exact checked member source, bound preparation and Result target.

The common pin also rejects a foreign Program owner and retains the backing
allocation after the ordinary output port closes. It does not copy cells or
authorize a write. Nonterminal Result targets and managed/resident outputs
remain unsupported here until they have equally exact physical retention;
the Host must not reacquire or rerun them as a fallback. Captured row identity,
Preview and apply admission, multi-member Run execution, and final publication
remain open under COMMON-SF-05.

The captured Effect input now starts the existing bounded Named Result view
export with its retained checked occurrence. The exporter applies authored
projection and order without copying a second table; a retained-output test
streams after the ordinary task port closes and checks exact rows and release.
This is still only an input-evidence path. No Effect Plan, row-to-payload proof,
whole-set apply permit, or standard Host dispatch is issued by this export.

The physical capture boundary can now pin the complete checked Effect source
inventory in one custody step. It retains positions for members with no Result
source, rolls back every earlier pin if any later source is missing, foreign,
or over its per-task ceiling, and releases repeated consumers together. Tests
of the underlying checked Result pin set keep terminal task ports closed while
consumer pins remain live and confirm the ledger returns to zero after
release. The Effect-specific multi-source entry still needs a connected
captured-Run fixture. This owner does not yet capture Effect Plan rows or
authorize a Preview or mutation; the standard Effectful Host entry remains
the completion blocker.

The captured input set now retains its exact Effect Run owner. A private Run
Preview can bind to that set only through the same physical Run owner; the
common binder maps Preview member IDs to checked source occurrences under a
work ceiling and rejects a missing or revoked input. An equal-CID Run owner is
not interchangeable. This establishes live input custody for Preview
processing, but it does not prove that the captured rows match the Preview's
Artifact or intended write payload. No apply permit or standard Host dispatch
is implied by this binding. Current three-target fixtures cover exact owner,
bounded lookup and reordered member mapping; the physical Preview-input
binding itself still needs a connected captured-Run regression.

The whole-set write-footprint check can now consume the admitted private
Preview retained by the exact checked Run owner. It derives member identities
and target inventories from that owner rather than a caller-assembled list;
the two-member fixture rejects overlapping targets and enforces target and
work ceilings. The earlier wire-plus-declared-inventory control remains for
existing adapter callers, but is not the ownership proof for a standard Run.
This check alone does not establish current authority, target freshness,
captured row/payload equivalence, or mutation admission.

## Integration review at 15904a32f

The fixed-SHA review `01-salesforce-effects-review.md` identifies five
integration concerns. The shared `logical_request_scope` package now owns the
0.1 caller-ID admission and CID preimage. Effect dispatch uses that exact
opaque owner; its ledger admits the caller ID before opening durable storage.
The independent CID vector and NFC, control-character, and UTF-8 byte-limit
tests run on JS, Wasm, and native. The Distribution Client branch must replace
its separate `client_request_identity` rule with this owner before SF-2 can
close across both product entries. The Client intent fingerprint remains
distinct from an Effect dispatch key.

SF-1 (external public SPI closure), SF-3 (source-free Effectful Run capture),
SF-4 (managed and nonterminal Result borrowing), and SF-5 (standard multi-
member Effect Run) remain open. The existing `CapturedEffectPreviewInputs`
binding is a private input identity guard, not apply authority. No local
fixture or this shared CID migration is live Salesforce verification.

The SF-4 audit also found that Effect source pins used the authored Stage
index as a physical task index. Carrier segmentation can move a Stage's Result
Step to another task. The checked graph now retains the Stage-to-task mapping,
binds each Effect source to the exact physical target, and passes that task to
the common pin. A Carrier-segmented graph and a checked Effect source exercise
the mapping separately; a connected segmented Effect Run fixture is still
required. Managed/resident retention and the standard Effect Run remain open.

The captured Named Result publication export now acquires the same checked
consumer pin used by Effect input custody. Its pin remains live through the
bounded export and durable replay, and `cancel` releases it exactly once.
The common `CapturedResultBorrow` binds the checked occurrence and physical
pin as one owner; both the cell-backed Effect input and publication consume
this owner rather than pairing a loose output with a separate occurrence.
A captured-graph fixture retains one Result for an Effect-like consumer and
publication independently: closing the ordinary task port and releasing the
first consumer do not revoke the publication view or prematurely return its
held bytes. The two consumers produce identical checked rows and fields. A
failed export preparation also releases its acquired pin.
This closes the cell-backed shared-consumer lifetime gap, not all of SF-4.

Salesforce broad acquisition no longer imports the Host's `connector_sdk` or
physical cost model merely to construct a candidate. The selected candidate
is assembled in `connectors/salesforce/host`; a dependency gate prevents the
provider acquisition package from taking those two direct dependencies back.
This is an SF-1 boundary reduction, not public SPI closure. The acquisition
package still exposes checked query, lowering, and execution types. An
off-tree provider facade and source-compatibility fixture remain required
before declaring the external Connector SPI complete.
The standard Effectful Host still must acquire a nonterminal Result before its
ordinary port closes; managed and Carrier-managed Results need representation-
specific physical holding and generation proofs. No implicit copy, reread,
or recomputation is accepted as a substitute.

The Salesforce managed query handle is now opaque to callers outside its
package. Its previous public fields exposed mutable query state and the
internal managed-output owner, allowing an external package to construct or
alter a query without the preparation boundary. This removes one SF-1 type
leak, but the public acquisition functions still mention Host-only query,
lowering, and execution types. The external facade and off-tree vertical
fixture remain open; this change must not be counted as SPI closure.

The common Result borrow now exposes its own liveness check. Effect Preview
binding and lookup use that check, and the ordinary Effect input lookup no
longer returns an input whose individual borrow was released while the set
owner remained live. A three-target captured-Result regression checks that
releasing the Effect-like borrow makes only that borrow unavailable while an
independent publication export can still finish. This tightens SF-4's
cell-backed path; it does not add managed or nonterminal retention, a Preview
payload proof, or standard Effect dispatch authority.

### External SPI closure inventory

The current package-public MoonBit surface is an internal composition API,
not the promised external Connector SPI. Its generated signatures identify
the exact split required before a provider can compile off-tree:

| Provider requirement | Current exposure | Intended owner |
| --- | --- | --- |
| Resource, field, operation and scoped capability descriptions | Salesforce `catalog` projection and generic Catalog contracts | Stable provider facade and provider implementation |
| Bounded query request, page order and typed cell admission | `ReadProjection`, `QueryPage`, `ManagedOutputValues` | Provider interpretation through a Host-created bounded sink |
| Selected checked query and residual computation | `QueryRequirement`, `AcquisitionChoice`, `BoundPrepared` | Internal Host bridge, never an external provider constructor |
| Attempt, issuer, retained output, capture and consumer binding | `QueryEvidenceRegistration`, `CapturedInputSource` | Shared Host custody and physical Site observation |
| Effect request and stored response interpretation | Salesforce single/collection request projections | Provider semantics behind common apply and response custody |
| Capacity, retry, cleanup and final completion | `connector_sdk` and common Engine owners | Internal Host/Engine authority |

The next SPI change must define a source-stable provider-facing package and
move one real Salesforce Catalog-to-read-to-capture path through it. A separate
MoonBit project must then build an off-tree reference provider using only that
package and its declared semantic dependencies. The generated `.mbti` closure
must include callbacks and error payloads, not just nominal opaque types.
An off-tree package that only registers a name is not the acceptance fixture.

### Fixed-SHA Salesforce review disposition

`01-salesforce-effects-review.md` at `15904a32` is an acceptance list, not a
claim that every finding remains open at the current branch head:

| Finding | Current disposition |
| --- | --- |
| SF-1 / SPI-01 | Partial. The Salesforce acquisition assembly now lives in the Host package while the provider Catalog has no Host or planning imports. `connector_sdk` still exposes internal checked-owner types; the external devkit, off-tree build, and source-compatibility test remain open. |
| SF-2 / INT-01 | Addressed by the integrated common logical-request owner. Client intent fingerprint and Effect dispatch identity remain separate. |
| SF-3 / INT-02 | Partial. The checked Effect Run owner has a source-free physical open through the ordinary private DAG lifecycle. The standard Values-to-Effect-to-final-Receipt Client/Host path remains open. |
| SF-4 / INT-04 | Partial. Cell-backed completed outputs support independent common pins. The common Result boundary can now pin an exact Managed or Carrier-managed completion reference against the checked occurrence and task holding. The Host must still connect representation-specific export, Effect input binding and current authority. Nonterminal Result coverage remains unproven. Unsupported representations must fail before Effect send. |
| SF-5 | Open. The ordinary checker and standard Client/Host still reject nonempty Effects. No Salesforce-specific submit path substitutes for a multi-member Run. |

The Host-package move passes Salesforce conformance on JS, Wasm and native,
the query integration JS suite, and the local Salesforce Site suite. These
tests do not replace the off-tree SPI, four-way source/Effect Run matrix,
managed Result borrowing, or standard multi-member Effect Run acceptance.

The ordinary Values-to-Local managed path now exercises two independent
resident Result borrows. Closing the producer port prevents new pins while
both existing pins remain live; releasing one does not revoke the other.
Closing the underlying physical output makes the remaining borrow unavailable,
and final release leaves the ledger empty. This checks common physical custody
only. It does not turn a managed Result into an Effect payload or publication
view without the installed Host's exact representation-specific export.
