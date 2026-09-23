# Shared checked-Effect and Run port required by Salesforce

Status: implementation interface proposal, not a completion claim.
Baseline inspected: `311921b14d608617f715c531829c75139ac2f7a3`.

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
