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
Connector Catalog. This is not complete Command Contract admission: input,
permission, recovery, current authority, and the checked Program's exact
Environment binding remain open. Complete Mapping Contract admission,
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
corrected after that SHA. The Salesforce Site suite passes 103/103 at the
rechecked HEAD, including local HTTPS target and whole-set footprint tests.
These component results do not close SF-3: the ordinary checked Program,
standard Host, complete multi-member Preview/apply admission, final receipt,
and restart-safe reconciliation still require one connected product test path.
No live Salesforce org or authorized write scope has been provided.
