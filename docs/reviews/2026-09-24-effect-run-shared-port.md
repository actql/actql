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
The Program check also retains the exact admitted Catalog role-reference
closure. Downstream Command selection can reuse that proof without repeating
Catalog hashing, while still checking the exact Program owner and current
execution authority. This retained proof alone does not authorize an Effect.

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
