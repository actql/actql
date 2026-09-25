# Host authorization: execution accounts and delegated decisions

Status: agreed design, 2026-09-11. Design-only revision based on
`8bc037388c454f7568fa5121d896ecd42dd5429a` in `actql/actql`.
This document records the approved authorization model;
it does not change the currently pinned wire schemas or claim implementation
conformance. Existing normative owners and machine contracts must be updated
together before claiming support for this model.

## Purpose

ActQL describes cross-system acquisition, transformation and action independently
of physical execution. That description supports both placement/optimization and
programmable execution control. Human approval is one possible Host workflow,
not the purpose or mandatory final step of every Program.

ActQL owns a small, common execution
account authorization model; the Host owns application-user authorization and
the handling of delegated decisions. Account configuration has common semantics
across Hosts.

The agreed configuration outcomes are **allow / deny / delegate**, not
allow / deny / review. `delegate` selects who decides; it is not a third final
permission or a requirement for human review.

## Two authorization layers

| Layer | Subject and responsibility |
| --- | --- |
| ActQL | A DB-account-like execution principal, with configuration for connection, resource and operation. Common interpretation produces allow, deny or delegate. |
| Host/application | Authentication and business authorization of actual users; mapping users/requests to execution accounts; deciding delegated requests; choosing automated services, CLI interaction or human workflows. |
| Connector | Technical connection and operation contracts, schemas, identity and provider capabilities. No ActQL grants, business authorization rules or mandatory approval policy. |

An execution account need not exist for every real-world user. A Local CLI can
use one account corresponding to its operator. A Cloud service can share an
execution account while resolving individual business users inside its Host.
Account mapping must come from trusted Host context, not a Program's claim.

Provider-side access enforcement remains independent. A configured ActQL allow
does not create OAuth scopes, DB privileges or provider-required approval
evidence. Connector transport may have to convey such technical requirements;
this does not authorize its author to define ActQL account permissions or
business policy. The storage and exact representation of those technical facts
remain a contract-definition task, not a new permission DSL in this document.

## Configuration, separate from Programs

The initial interface is a configuration file, not a new GRANT language. Its
conceptual address is execution principal × connection × resource × operation.
Program source cannot grant permission to itself or select a stronger account.
Administration and access to configuration are Host responsibilities.

These dimensions describe available scoping granularity, not an obligation to
enumerate every combination. Explicit all-target selectors permit broad rules:
a Local execution account can allow all resources/operations on its selected
connections; a Cloud service account can delegate a broad scope except explicitly
excluded system prohibitions. Each dimension can be scoped independently.

An explicit all-target selector includes future members of that dimension,
including newly added resources or operations (and new connections if the
connection dimension is also all-target). This is intentional authorization,
not automatic expansion of an enumerated list. Use explicit finite selections
where additions should require a configuration change. Broad account grants
do not supply provider credentials or relax technical admission or data policy.

For the new configuration model, no matching effective rule means deny. A missing
individual entry is not a denial when a broad rule matches. Subtract exclusions,
then resolve matching outcomes; no-match is a fallback, not a synthetic deny
rule conflicting with every allow/delegate. Distinguish no-match denial from
explicit denial in diagnostics. Excluding X from a broad allow/delegate does not
itself forbid a separate rule for X; any remaining matches determine its outcome.

Configuration interpretation is common across Hosts. Conflicting overlapping
entries are configuration errors, not deny-wins, last-rule-wins or
Host-dependent precedence. There is no combined priority contest between
ActQL account settings and the Host's application authorization rules.

Concrete file syntax, selector vocabulary, operation identifiers and diagnostics
require a coordinated contract revision. This
design does not infer grants from missing configuration or default to allow,
or present an illustrative configuration as accepted syntax. Broad delegation
with system-level prohibitions must be expressed without conflicting entries;
a catch-all delegate plus an overlapping deny is not an implicit exception rule.

A documented Local initial profile with a version and exact content CID may be
materialized as explicit configuration on first Host use. This is a defined
bootstrap operation, not a missing-config allow fallback. Record its adoption
durably and never recreate removed/restricted grants or silently expand them on
upgrade. See [Local initialization](oss-host-authorization.md#local-initialization)
for its scope and lifecycle. Connector registration alone grants no authority.

Agreed exclusion semantics: express "delegate except X" through explicit set
exclusion, without enumerating an open resource universe's complement. Apply
each rule's exclusions to its selected set before checking overlap. If remaining
sets overlap with different outcomes, reject the configuration. Specificity,
entry order and deny-wins do not resolve conflicts. A delegate rule excluding X
and a separate deny rule for X therefore have disjoint effective scopes.
Concrete selector/exclusion syntax and validation remain contract-design work.

Conflict detection is symbolic over selector expressions, independent of the
currently discovered Catalog or resource population. For all-target and finite
sets with explicit subtraction, compare the effective selector sets over the
open universe, not their intersection with today's discovered resources.
For example, delegate all except {X} conflicts with deny {X, Y} at Y even when
Y does not yet exist. Reject that configuration at admission. Discovery of a
new member must not create a previously undetected selector conflict. Adding
selector forms requires an exact overlap-validation rule; discovery sampling
is not a substitute.

Selectors denote sets of tuples in principal × connection × resource × operation.
Subtraction and intersection operate on those tuple sets. A tuple exclusion such
as connection=A AND resource=X can make an effective scope non-Cartesian;
overlap in each individual dimension is not sufficient to prove a conflict.
The exact tuple-set intersection must be nonempty for a conflict to exist.

An explicit deny also constrains subsequent configuration edits: adding an
allow/delegate whose effective scope intersects that deny produces a conflict.
No-match deny is only a fallback and imposes no such constraint; a later matching
grant can authorize a formerly unmatched scope. A deny entry is not immutable:
an authorized administrator can remove or change it explicitly.

## Boundary behavior

| Account outcome | Core behavior | Host responsibility |
| --- | --- | --- |
| allow | Continue within the admitted scope without an authorization callback or dummy Checkpoint. | May have independently checked the request before submitting it. ActQL does not claim that it did. |
| deny | Do not dispatch the affected work. A delegated answer cannot override this outcome. | Record initial rejection or expose the existing Run failure as appropriate. |
| delegate | Emit a bound decision request and retain the continuation; do not cross the boundary without accepted permission. | Resolve application authorization immediately, or arrange later resolution. Human participation is optional. |

The Host can answer an immediate delegated request without creating a
Checkpoint that is immediately resolved. If an answer is deferred, persist the
existing sealed Checkpoint and continuation before relinquishing execution.
The exact immediate-response envelope remains to be mapped to the existing
authorization protocol; this design does not invent a second resume API.

Final authorization is permit or reject. An unresolved request is not a permit.
Timeout, unavailable decision service or invalid evidence never becomes implicit
allow, and must remain distinguishable from an intentional rejection. Exact
failure/retry mapping is a protocol follow-up, not a new universal Run state.

Local may handle delegation with CLI interaction or a simple externally
retrievable decision mechanism. Cloud may configure delegate for operations
requiring application-user authorization and deny for system-level prohibitions.
Cloud routing, organization membership and approval workflows are not required
Local features. Neither configuration is a new mandatory default.

## What remains in Core

Core retains technical admission, the relationship between decision subject and
actual work, continuation identity, and outcome semantics:

- allow cannot repair invalid types/contracts, exceeded bounds or unsupported
  capabilities, and cannot bypass provider requirements;
- a decision covers only its bound scope, context and validity conditions;
- unresolved Checkpoints block their corresponding boundary;
- delayed answers resume captured results and the original continuation, not a
  rerun of SourceViews or inference under the old decision;
- duplicate answers cannot cause duplicate application; conflicting answers
  cannot both resolve the same request;
- existing atomic decision storage, Checkpoint closure, resume-intent creation,
  fencing, engine pinning and reconciliation requirements are preserved;
- rejection after earlier acquisition or Effects retains those facts, including
  cost, partial success and unknown outcomes. Initial denial and later denial
  are not interchangeable.

The authorization port is a logical boundary; it need not be a network service
or separate process. Host owns physical persistence and authenticated answer
delivery. Core owns admission of the resulting transition.

## Effects and risk acceptance

Connectors do not prescribe ActQL approval policy or mandatory approval presets.
Connector-defined
`permission_rules` as technical derivation of required provider permissions from
effect kind, selector and exact write-field set. They neither grant ActQL
execution-account authority nor prescribe approval policy. Preserve that
technical derivation and its exactness checks independently of ActQL grants
and business-approval policy. An ActQL permit does not satisfy missing provider
permission requirements.

Multiple Effects do not inherently require
`partial_application_accepted`. A Host may require an explicit risk claim for
a delegated decision; if present/required, its authenticated subject and
validity still matter. Direct allow requires neither a human nor a fabricated
risk claim. Allow evidence is not evidence that a person accepted business risk.

All-member preflight, complete Effect Set scope, unchanged partial-application
semantics and per-member/item outcome records remain required. This design
does not introduce subset approval or cross-provider transactions.

## Optimization and authorization

Account checks retain their configured connection/resource/operation scope.
Host application policy may inspect additional business facts. Authored metadata
and physical-plan facts are different inputs; an optimizer must not silently
substitute one for the other.

An earlier decision is reusable only when its bound scope, context and validity
remain applicable. Changed egress, destination, cost or other decision inputs
require a valid new decision or foregoing the transformation. A policy CID
alone does not establish freshness for time, budget or membership-dependent
decisions. Core need not implement a general dependency-inference engine.

Semantic-risk-based routing is a useful Reference Host recommendation, not a
prohibition on application-specific Host policy. It is not a new Core rule
priority system.

## Preservation and non-goals

Keep current private classification, encryption, retention, data-policy
inheritance, authentication/signature profiles and Local product defaults.
Do not conflate moving authorization decisions with weakening data protection.
No new policy DSL, user directory, role hierarchy, external approval service,
runtime implementation or publication is part of this design-only change.

## Normative and machine-contract specification work

This design requires coordinated prose and pinned machine definitions, with
independently expected cases. Design agreement alone is not wire support.

| Owner | Required follow-through |
| --- | --- |
| [Language](../spec/language.md#effects) | Preserve declarative Effects and prohibition on self-authorization; separate execution-account grants from Connector technical evidence. Preserve private Result evidence. |
| [Contracts](../spec/protocols/contracts.md#mapping-contracts) | Define permission_rules and permission sets as exact technical provider requirements, not ActQL grants or approval policy. |
| [Execution](../spec/execution.md#checkpoints) | Define account outcomes and delegated immediate/deferred paths, initial versus later denial, technical admission and scope/validity checks; risk claims are conditional on Host requirements. |
| [Routing](../spec/execution.md#policy-routing) | Move application-policy recommendations to Reference Host; retain authorization-preserving optimization obligations. |
| [Run](../spec/protocols/run.md#resolution-admission) | Reuse sealed Checkpoint/Resolution and atomic continuation; make risk claims conditional. Specify authenticated immediate answers without fabricating a Checkpoint. |
| [CLI](../cli.md) | Configuration belongs to execution accounts; run is the ordinary entry; approve/reject handles deferred decisions. |
| Concrete configuration | Encode all-target selectors including future members, set exclusion and no-match deny. Reject conflicting effective scopes symbolically as sets of tuples in the full Cartesian domain, independently of discovery; per-dimension overlap alone is insufficient with tuple exclusions. No specificity precedence or complement enumeration. |
| Machine schemas and Check Environment | Define technical permission evidence, account outcomes, delegated answers, conditional claims and canonical preimages. Update affected schemas, pins, requirements and acceptance vectors together. |
| Product decisions and evidence | Bind conformance evidence to the exact tested contracts and design expectations. |

Configuration delegation, Host resolution and durable preflight `checkpoint`
are different layers and require explicit protocol definitions.
No stored artifact is admitted under altered meaning using its old CID.
This change does not authorize an independent version bump or rewriting history.

## Acceptance cases

These are fixed design expectations, not claims of executed tests:

1. Account allow: zero authorization callbacks and zero mandatory Checkpoints.
2. Account deny: no affected dispatch; a Host permit cannot override the deny.
3. Delegate with immediate permit: execute without a dummy Checkpoint.
4. Delegate with immediate reject: no affected dispatch; preserve prior outcomes.
5. Deferred delegate: persist, restart and resolve the same captured continuation.
6. Shared Cloud account: different authenticated business users may receive
   different Host answers without creating one ActQL account per person.
7. Conflicting configuration: reject it rather than choosing by priority/order.
8. Multi-Effect allow without risk claim: allowed after technical preflight;
   partial outcomes are still recorded.
9. Host-required risk claim missing: do not treat it as accepted delegation.
10. Changed subject, expired context or duplicate/conflicting answer: preserve
    existing binding and idempotency rules; no authority transfer or duplicate work.
11. Invalid Program under allow: retain the technical failure.
12. Changed authorization-relevant placement facts: reauthorize or do not apply
    the transformation; result equality alone is insufficient.
13. Delegate all except {X} and deny {X, Y}: reject the conflict at Y even
    before Y is discovered. Delegate all except {X, Y} and deny {X, Y}: disjoint.
14. Adding allow X against explicit deny X: configuration error. Adding allow X
    when X was only unmatched: valid if no other effective rule conflicts.

Design agreement is complete for the two-layer responsibility split. Concrete
configuration and wire specification are explicitly unfinished, not implementation
details silently decided by whichever Host is written first.

## Relationship to current pinned contracts

This is an intentional semantic change, not merely clarification. The
normative owners and pinned machine contracts are authoritative for their
artifacts; this design guide cannot override them. The table records the
migration from the earlier Contract-floor and review model to the owners that
now specify account routing, delegated answers and conditional risk claims.
Locations were checked on this branch's specification baseline `8bc037388c454f7568fa5121d896ecd42dd5429a`; anchors and case IDs are
preferred to line numbers when the files move.

| Current fact | Design target | Required work |
| --- | --- | --- |
| [Mapping/Command contracts](../spec/protocols/contracts.md#mapping-contracts), lines 326 and 414, include mapping minimum approval / minimum_approval. | Connectors do not prescribe ActQL approval policy. | Remove the business minimum fields and dependent requirements/preimages; retain exact technical permission_rules and provider permission requirements. Revise schemas, pins and independent vectors together. |
| [CLI](../cli.md), line 160, and [Effect application](../spec/execution.md#effect-application), lines 511–515, preserve the monotone Contract/Host floor for effect_policy. | Execution-account configuration determines allow/deny/delegate. | Replace floor resolution and define the account config contract. Distinguish existing effect_policy from the new setting; no silent reinterpretation of configuration or evidence. |
| [Execution checkpoints](../spec/execution.md#checkpoints), line 475, and Effect application, lines 550–552, require multi-Effect risk acceptance; [Run](../spec/protocols/run.md#resolution-admission) requires the extra claim for multi-Effect review. | Risk claims are required only when the Host requires them for delegation. | Revise Execution/Run conditions and related schemas/claim acceptance cases; preserve complete-scope preflight and partial-outcome records. |
| [Execution checkpoints](../spec/execution.md#checkpoints), lines 460–462, bind evaluated allow/review/deny to policy identity. | Account outcomes are allow/deny/delegate; Host responses and durable checkpoint are separate layers. | Define the configuration-to-decision protocol mapping, immediate/deferred evidence and affected identities; do not globally rename review tokens. |
| [Product acceptance cases](../../spec/product-decisions/acceptance-cases.json), D2.contract-floor and D2.multi-review, encode the existing floor and review model. | No Connector floor; delegated answers and Host-conditional risk claims. | Explicitly revise/retire affected D2 expectations and adoption records, add independent new-model cases, and retain historical evidence as evidence of its tested contracts. |
| [Policy routing](../spec/execution.md#policy-routing), lines 616–632, prohibits structural inputs and constrains packaging-equivalent routing. | Host owns application decision criteria; authorization reuse must preserve actual decision inputs and validity. | Revise routing requirements and acceptance cases; keep binding/optimization guarantees and make semantic-risk routing a Reference Host recommendation. |
