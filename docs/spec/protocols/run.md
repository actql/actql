---
spec_id: actql.protocol.run
status: adopted
version: actql/0.1
normative_dependencies: [actql.execution, actql.protocol.contracts, actql.protocol.artifacts]
---

# ActQL run

[Specification index](../README.md)

<!-- normative-import: actql.execution actql/0.1 -->
<!-- normative-import: actql.protocol.contracts actql/0.1 -->
<!-- normative-import: actql.protocol.artifacts actql/0.1 -->

This document owns run-wire, checkpoint-wire, resolution-wire, preview-wire, apply-receipt, reconciliation-receipt. It does not define other owners' wire protocols or a particular Host implementation. Cross-owner links outside the declared dependencies are informative navigation to protocol bindings or conformance evidence; they do not import those documents' requirements. Narrow machine contracts remain authoritative for their explicitly referenced values and envelopes.

<!-- page-contents:start -->
## On this page

- [Terms](#run-terms)
- [Checkpoint and Resolution admission](#resolution-admission)
- [Private preview row state](#preview-row-state)
- [Stage wire and immutable history](#stage-wire)
- [Policy and human risk acceptance](#policy-risk-acceptance)
- [Renewal and template evidence](#approval-renewal)
- [Logical request and dispatch evidence](#logical-request)
- [Source-state operator claim](#source-advance-claim)
- [Authorized private inspection](#private-inspection)
- [Machine contracts](#machine-contracts)
<!-- page-contents:end -->

<a id="run-terms"></a>

## Terms

- **Review projection** — the redacted, content-addressed view of sealed
  evidence presented for review and bound by the approval ([Review and receipt artifacts](#review-artifacts)).

<a id="runtime-source-evidence"></a>

#### Runtime source evidence

Every runtime source observation emits `actql-source-evidence/0.1`. Its evidence
is discriminated by the checked input declaration:

```text
Common: source_ref, input_logical_cid, source_contract_cid, schema_evidence_cid,
        output_carrier, observed_at, completeness, ordering_evidence,
        consistency_level, source_evidence_cid
LocalSourceEvidence: Common; no invented Connector or SourceView identity
ConnectorSourceEvidence: Common + capability_evidence_cid, authority_scope_cid,
        source_view_contract_cid, connection_evidence_cid, read_mode;
        snapshot_ref and checkpoint when supplied by the declared delivery mode
```

<!-- requirement-block: runtime-source-evidence.run-receipts-must-report-single-snapshot-or-independent-snapshots-reading-two-systems runtime-source-evidence.run-receipts-must-report-single-snapshot-or-independent-snapshots-reading-two-systems.second -->
`input_logical_cid` binds semantic content/snapshot, source contract, schema,
completeness, and logical ordering, but not observation time or presentation.
The enclosing source-evidence CID additionally binds capabilities, authority,
when applicable, and canonical UTC `observed_at`. Run receipts MUST report
`single_snapshot` or `independent_snapshots`; reading two systems at different
times MUST NOT be presented as one cross-source transaction.

A connector that supplies `snapshot_ref`, version, cursor, watermark, or
content identity is responsible for its stability and collision resistance.
Page number, request time, provider enumeration order, or a mutable URL alone
is not a logical snapshot identity. If the connector cannot prove snapshot
identity, it reports the weaker consistency level and a content-derived
observation identity; the runtime must not promote it to snapshot consistency.

<!-- requirement-block: runtime-source-evidence.checked-and-runtime-source-contract-cid-schema-evidence-cid-and-capability-evidence-cid-when-applicable-must runtime-source-evidence.any-mismatch-is-actql-e-source-evidence-drift-and-requires-rechecking-against-the-new -->
Checked and runtime `source_contract_cid`, `schema_evidence_cid`, and
`capability_evidence_cid` when applicable MUST be compared before computation. Any mismatch is
`ACTQL_E_SOURCE_EVIDENCE_DRIFT` and requires rechecking against the new evidence;
execution MUST NOT reinterpret a sealed Plan against changed evidence. A
compatible change, such as adding an unused field where the input contract
permits it, may pass rechecking without a Program edit. This does not permit
continued execution under the old Plan.

<a id="resolution-admission"></a>

### Checkpoint and Resolution admission

<!-- requirement-block: resolution-admission.unsupported-combinations-are-invalid-a-host-must-not-treat-independently -->
Protected reads MAY require a Checkpoint during preparation, before content is
fetched. Other Checkpoints belong to a concrete Run unit. A preparation
Checkpoint binds immutable preparation identity and the exact Prepared
Invocation or read scope, not a not-yet-created Run Definition. A Run-unit
Checkpoint binds the immutable Run Definition CID and continuation-state CID.
Both variants bind subject, one valid closed phase/kind/artifact combination, exact required
artifact CID, exact redacted review-projection CID, requirements, reason,
creation time, and expiration. Its identity is
`actql-execution-checkpoint/0.1`. Unsupported combinations are invalid; a Host
MUST NOT treat independently valid enum values as an open cross product.

The valid combinations are exactly:

<!-- requirement-block: resolution-admission.subject-phase-kind-required-artifact -->
| Subject | Phase | Kind | Required artifact |
| --- | --- | --- | --- |
| `prepare_attempt` | `preflight` | `run_scope` | `prepared_invocation` |
| `prepare_attempt` or `run_unit` | `preflight` | `read_access` | `read_scope` |
| `run_unit` | `preflight` | `data_egress` | `egress_scope` |
| `run_unit` | `preflight` | `cost_scope` | `budget_scope` |
| `run_unit` | `commit` | `effect_set` | `effect_set_preview` |

A `prepare_attempt` subject contains `prepare_attempt_id` and
`continuation: start_run`. A `run_unit` subject contains `run_id`, `unit_id`,
and `continuation: resume_unit`. Non-Effect Checkpoints require exactly
`[invocation_scope_approved]`. An Effect Commit Checkpoint requires
`[effect_scope_approved]` or
`[effect_scope_approved, partial_application_accepted]`; multi-Effect review
requires the latter.

<!-- requirement-block: resolution-admission.its-decision-time-must-be-no-earlier-than-checkpoint-creation resolution-admission.approved-resolution-evidence-bytes-must-hash-to-the-authored-approval-evidence-cid resolution-admission.a-rejection-must-not-carry-approval-evidence resolution-admission.a-host-authorization-port-must-authenticate-the-actor-and-verify resolution-admission.resolution-storage-checkpoint-closure-run-transition-and-creation-of-the -->
An approval or rejection is an `actql-checkpoint-resolution/0.1` bound to the
exact Checkpoint CID, its preparation or Run identity, required artifact, review
projection, actor, and decision time. Its decision time MUST be no earlier than
Checkpoint creation and earlier than expiration. Approved Resolution Evidence
bytes MUST hash to the authored `approval_evidence_cid`. A rejection MUST NOT
carry approval Evidence. A Host authorization port MUST authenticate the actor
and verify current policy and reviewer authority using Host-trusted keys. An
Evidence object cannot appoint its own trusted public key. Only that
Host-verified Resolution enters the durable store. Resolution storage,
Checkpoint closure, Run transition, and creation of the unique resume intent
MUST be atomic. The resume dedupe identity is derived from the Checkpoint and
Resolution CIDs. Duplicate delivery of the same verified Resolution is
idempotent; a conflicting Resolution is invalid. The Resolution is the durable
authority decision. Review or compatibility artifacts supply bound evidence
to an adapter; they are not a second independent authority source.

<!-- requirement-block: resolution-admission.every-field-in-a-host-verified-resolution-wrapper-must-identify-the -->
Every field in a Host-verified Resolution wrapper MUST identify the same
authority decision: its Resolution CID, Checkpoint CID, authority-context CID,
signer key ID, and reviewer identity cannot contradict one another.

<a id="preview-row-state"></a>

### Private preview row state

<!-- requirement-block: preview-row-state.for-every-preview-row-implementations-must-first-compute-row-preview-cid -->
For every preview row, implementations MUST first compute
`row_preview_cid = CID({version, program_definition_cid, invocation_cid, effect_identity_cid,
resolved_contract_cid, operation, target_row_identity, preview_strength,
target_guard, intended_changes, before, after})`.
Private `before` and `after` evidence use the closed union:

<!-- requirement-block: preview-row-state.rowstate -->
<!-- normative-code: grammar -->
```text
RowState := {state: "present", value: Row}
          | {state: "absent"}
          | {state: "unavailable"}
          | {state: "not_applicable"}
```

<a id="review-artifacts"></a>

#### Review and receipt artifacts

An approval attestation contains the exact Effect Preview CID, approver,
canonical UTC approval time,
preview-authority-scope CID, review claims, an Ed25519 key identity/signature,
and its own CID. An individual apply receipt contains the preview CID,
approval-attestation CID exactly when approval was required, disjoint
`applied`/`accepted`/`unknown`/`failed`/`unattempted` row-preview identities, a
typed outcome, status, optional stale-error CID, and receipt CID. An Effect Set
apply receipt binds the complete set preview, set approval, fixed `attempt_all`
policy, every member preview and provider outcome, dispatch evidence, aggregate
status, and its own CID. A run
receipt binds every identity layer, source evidence, Result Manifest identity,
Result Artifact identities, completeness, and cross-source consistency. A
Result delivery receipt separately binds one Result Artifact to one canonical
serialization and its released byte identity ([Result delivery](artifacts.md#result-delivery)). Runtime errors bind
phase, stable code/message, already materialized artifact CIDs, and
`partial_output_published: false`.

<!-- requirement-block: review-artifacts.an-effect-review-projection-must-include-each-effect-s-kind-target -->
The private Effect Preview binds the evidence available for its strength and may contain
secrets. It declares `sensitivity: private`, an authority-evidence retention
class, and encryption required. Its transport envelope also carries the
separately self-addressed Authoring Context; that sidecar is deliberately
excluded from `effect_preview_cid`. Review UIs display the canonical
`actql-review-projection/0.1` artifact, which binds the private
`effect_preview_cid`, exact `authoring_context_cid`, immutable
`redaction_policy_cid`, displayed scope, permissions, rows, and authoring
context, plus its own CID and restricted/encrypted retention metadata.
An Effect review projection MUST include each Effect's kind, target, count,
and every row identity with the following strength-specific evidence:

<!-- requirement-block: review-artifacts.effect-preview-semantic-exclusions-do-not-waive-exact-apply-binding -->
The exact 0.1 member and set CID preimages, including the exclusion of derived
row idempotency keys and physical Run identity, are defined in
[Effect preview, approval, and application](../execution.md#effect-application).
Those exclusions MUST NOT waive exact Run, authoring, request, or
authorization binding at apply.

<!-- requirement-block: review-artifacts.row-variant-required-review-evidence-full-diff -->
| Row variant | Required review evidence |
| --- | --- |
| `full_diff` | Before, intended after/change, and target version; unchanged fields omitted from the diff |
| `targeted` | Exact target, intended change, target guard, and explicit before-unavailable status |
| `create`, `command`, `store` | Kind-specific intended operation, payload or typed request, and exact scope |

<!-- requirement-block: review-artifacts.approval-attestation-must-bind-both-effect-preview-cid-and-the-exact-review-projection-cid review-artifacts.redaction-must-not-substitute-for-an-authority-preview stage-wire.product-36870f813edf policy-risk-acceptance.product-7a26116de02b approval-renewal.product-6542a3eac80f logical-request.product-26cde1934ed3 source-advance-claim.product-026cf595ba1a private-inspection.product-f6c29d1d5272 -->
Redaction and unavailable evidence are distinct states. Neither is represented
as an invented empty before object; a redacted projection still binds the
exact underlying private preview.
Approval attestation MUST bind both `effect_preview_cid` and the exact
`review_projection_cid`; this records the semantics and explanation the
approver actually saw.
Redaction MUST NOT substitute for an authority preview. Apply/run
receipts partition exact row outcomes and reference every identity-bearing
artifact by CID.

<a id="stage-wire"></a>

### Stage wire and immutable history

Stage is source provenance, not a wire-selected runtime mode. These bindings
use `pending_predecessor` for an otherwise checked unit awaiting control/data
under [Plan results](contracts.md#planning-wire); waiting is not missing caller
bindings and does not issue an executable Plan or fabricated Invocation. They
use ordinary graph nodes and local Run artifacts. Node Plan, Invocation, Result,
receipt semantics and template/review inputs bind only local Unit Definition,
used values, local contract closure and exact required producer evidence.
Parent Program revision and whole-lock CIDs belong to authenticated graph
membership, not their transitive semantic preimages. In the single-unit
envelopes above, program_definition_cid means the extracted local definition.
Required issuer/scope/policy/provenance is never discarded for hash locality.

The local receipt wire names local_invocation_cid, local_manifest_cid and
effect_outcome_cids explicitly. They resolve to local-computation-semantics,
local-result-manifest and local-effect-outcome respectively, not identically
shaped or differently kinded Run audit artifacts. Receipt views bind
semantic_outcome_cid; their original audit receipt and Captured Run are bound by
a semantic-projection-attestation. Admission verifies the actual source-derived
projection and authenticated membership, not merely schema shape or self-CIDs.

Program wire binds the logical request scope, request fingerprint, Program
Definition, checked stage template, effective parameter-values CID and starting
engine/contract lock. Each stage record binds its stable stage ID and Stage
Definition, ordered position, immediate-predecessor gate, import contracts and
availability requirements. A pending predecessor is not a fabricated concrete
Invocation or a request for caller bindings. Concrete Stage Plans bind import
artifact/receipt CIDs and effective values; captured observations establish the
Stage Invocation. Attempts bind prior attempt CIDs and physical provenance.

The latter attempt and graph links are outer evidence: they do not re-enter
local Preview or reusable template hashes. Verify local semantics AND authorized
producer/consumer membership at admission. One-shot Resolution remains scoped
to its exact checkpoint/run/nonce; reusable local template and graph launch
admission are separate. A downstream-only edit preserves unchanged upstream
template identities, not automatic authority to launch a new graph.

Receivers MUST validate closed shapes, self-CIDs, kinds, references, scope and
semantic consistency without repairing incoming artifacts. Past terminal
attempt receipts are immutable. Stage receipts bind all local Results, item
outcomes and their original correlation. Completion evidence separately binds
OperationRef, provider completion contract and result availability. A Program
receipt binds the ordered history and export manifest only when appropriate;
it never fabricates future stage artifacts or treats partial history as success.

For the registered evidence envelopes, `self_cid` hashes the complete envelope
without itself. Detached authentication signs the unsigned payload CID obtained
by excluding both `self_cid` and `authentication_evidence_cid`; its issuer,
signature algorithm and trust are validated under the authentication contract.
Template instantiation and renewal precede the new authorization that references
them: neither contains that new authorization's CID. Template risk claims bind
the template scope directly, not a future exact-Preview acceptance artifact.
JSON Schema checks are necessary but do not authenticate any CID-only witness.

<a id="approval-attestation"></a>
<a id="policy-risk-acceptance"></a>

### Policy and human risk acceptance

Risk acceptance has one proposition, `partial_application_accepted`, and a
tagged issuer `human|policy`. Authenticated evidence MUST bind issuer, policy
CID, decision, exact Preview and review projection, authority scope and expiry.
The policy path under resolved allow requires no human Checkpoint, including
multi-Effect stages. Require-review still signs the complete stage scope.
The monotone Contract/Host minimum is preserved; earlier coarse allow cannot
authorize an expanded future scope. Human review authority is not data-read
authority. Claims with wrong issuer, scope, Preview or expiry fail admission.

<a id="approval-renewal"></a>

### Renewal and template evidence

Renewal evidence binds old/new Preview, original authorization, exact diff,
guard, permission/payload/scope comparison, policy rule, issuer and expiry.
Template evidence binds Program/Stage definitions, parameters, known artifacts,
producer/effect/receipt contract and correlation, fixed operation/target kind/
write fields/payload, typed ID/Ref substitution slots, scope ceilings, review
context and risk. Instantiation evidence binds template CID, actual receipt
CIDs, substitutions and the new exact Preview. Admission MUST verify static
dependency eligibility and concrete substitution separately. These artifacts
produce fresh authorization, never transplant an old signature onto new bytes.
New business observations or out-of-envelope substitutions require ordinary
concrete authorization. Schema/lock auto-renewal is not included.

<a id="logical-request"></a>

### Logical request and dispatch evidence

Ingress binds authenticated scope and caller request ID to an immutable intent
fingerprint. Ledger records bind logical item locator, exact Preview, dispatch
key, canonical request, recovery capability, reservation/fence, attempt chain,
outcome and retention horizon. The CID preimages are owned by Execution's
logical-request law. Physical Run/worker/attempt identity is audit provenance,
not idempotency entropy. A same-key different request MUST fail. Successful
records replay without dispatch; uncertain records require exact-request
reconciliation. Expired/missing history never establishes first-request status.

<a id="source-advance-claim"></a>

### Source-state operator claim

The closed source_state_advance_authorized claim has separate operator authority
and signs tenant/scope/policy/expiry/nonce, exact fenced graph state and commit
scope, captured batch/pending checkpoint list/generations, all unmet obligation
outcomes and dispositions, handoff ownership, and the operator review. It uses
the common authenticated evidence envelope, not partial-application acceptance
as an alias. The eligibility and ack receipts record normal versus exceptional
commit without changing node outcomes. Missing authority, handoff or exact state
MUST fail; ordinary Effect allow cannot authorize this claim.

Each unmet entry names kind node_milestone or effect_item, exact outcome evidence
and complete item_outcome_evidence_cids. Cancelled, timed_out, budget_exhausted
and rejected remain distinct original states. A cancelled parent is not proof
of no dispatch: applied descendants remain recorded and unknown/accepted_pending
descendants require durable handoff. Kind, obligation and every item must match
the sealed commit scope and fenced state; duplicates or omitted obligations
reject. Exceptional eligibility never changes the original terminal status.

<a id="private-inspection"></a>

### Authorized private inspection

Private inspection MUST independently authorize read access to bound values,
rows, before/after evidence, attempts and receipts within their retained scope.
Approval authority alone cannot grant that access. Public explain remains
redacted. Inspection never returns signing/encryption keys or Connector secrets.
Progress is nonsemantic status, not a partially materialized Result.

<a id="machine-contracts"></a>

## Machine contracts

These exact schema/law references are owned here. Their identities do not include this document or another owner's aggregate contract.

<!-- requirement-block: machine-contracts.product-29677c2581a3 -->
The five acquisition references in Lookup Evidence MUST resolve under the
lookup identity registry's evidence_slots and laws, not as arbitrary CIDs or
final Result Artifacts. The succeeded attempt receipt precedes the validated
Relation and successful Lookup Evidence; unsuccessful receipts remain retained
without a fabricated output. The evidence attempts table must equal the bound
receipt table. Final Invocation identity includes that completed evidence
closure only after its typed correspondence and authority have been admitted.

<!-- requirement-block: machine-contracts.exact-artifacts -->
<!-- normative-code: law -->
```text
../../../spec/contracts/actql-protocol-schemas.json#/schemas/observation_facts sha256:bb63f5ddcba12a33225cc5fefc2ddf69ceed007524cb890d96004363b4ad0db4
../../../spec/contracts/actql-protocol-schemas.json#/schemas/event_delivery_evidence sha256:e9e5f043206fdf00720bbd14f12a765796b3686a4485505f77ba0a2533767582
../../../spec/contracts/actql-protocol-schemas.json#/schemas/effect_outcome sha256:e1c2f7c0f3b894c66c9fb205fdef574cba048873ecbc79f2981a0b8bf4450b0f
../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/source_evidence sha256:434d2f1c97a9721e01d5eb614577d8620bc3662e2b5b3b05bdecb3029d2eafa6
../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/observation_set sha256:960b462c42c793913e981f64473c374538283d1dc7379cc694239d729e8f8537
../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/model_invocation_evidence sha256:9b883bf32553da51b01bd88ff912f460eb2308034b33a591a18f7f6e91c38b27
../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/model_capture_bundle sha256:9e4c76623e09216b81f70ca5573b90dc6f17f4a8754638345da2f8ec617507ba
../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/effect_preview sha256:ffacfcbd6992627eb07489e40ffff7b33db144e8d34ff80ac7d06221dcf45712
../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/review_projection sha256:7585ae7f6737a8a0a196df98e64f496fbca271c910840f1116f6d7990caf39fb
../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/approval_attestation sha256:482ee09bcbed57fd19edd49e01d81882a3bbeb398ea9176c09e1717883a21ba9
../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/effect_apply_receipt sha256:30139b17ce3db707b669b038a89c0ca89d4b5fa4b77d5062e9abc44cc5a93d26
../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/effect_set_apply_receipt sha256:ae7b45405ba8e504cc1fa4e7acf660395c3c0915451c26cf38d9373a183b2bdf
../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/effect_reconciliation_receipt sha256:d28124575ba45a4fa25936a4200918d2208d5757f286c114051a46ba5e9f4fa4
../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/run_receipt sha256:3ad8dc111a4dbc7ba8f9f6b9379f437e808cd665d3ce1cac5057068f495fd8e0
../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/runtime_error sha256:065e22b471b7e63c67061a75854e5ca3d1821841fcc07016742d6b715632608d
../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/execution_context sha256:bce481b86ddcbd958ab98c54df73a7040d21ab8115088f25cb7552928cfb30de
../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/run_policy sha256:d1c763d2ba8357fd33fa41afd690eed8088a310e4640fa615907c4866a125db6
../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/prepared_invocation sha256:b3aa019105b4b6db51c69b2b96771ebe184f87c1f7eff3347bf5aef1cd9482f9
../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/run_review_projection sha256:a883398aa5f831befbc132a18a48c4233b4596edcec616d5d3328aea62df8c38
../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/run_scope_approval sha256:ab7aa04f5afe9b7479ab2bc1ad078b2df41bde6248fd6eae1d0f88a94ffaa3de
../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/run_authorization sha256:f3085180be28dfc3f7b6151adf56796255a257a73205fabf674be281a05e4ed9
../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/run_definition sha256:62b4314c02685e9c685870abcc1eb690bff333e7e743ec81ae3ad87f7b3ac045
../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/execution_checkpoint sha256:c0dc4575988d74a799ea739c0eeef7ae17d94618649c3eebfa671e28bdb77e41
../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/checkpoint_resolution sha256:2946a790957ed322c1f2e800bb4d8a0dd22a33ae7bd02be823ff42aaa6035355
../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/verified_checkpoint_resolution sha256:a0576742d08e69b46c928ac8b13e8479f26d47ccf8bc474c1fa1d0807254a820
../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/run_state sha256:11f4930151996e513da6da627a101504ac0ff7aee1a9ae077219c126b39aab1c
../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/captured_run sha256:f2f2a5293d2ce81867a4439381eb267870e1169d2bac86290656353385bed993
../../../spec/contracts/actql-production-profile-schemas.json#/schemas/lookup_evidence sha256:9aca3664e28a690ef22c34a577e2089631b01a45a3b80df92ebae276db47b596
```

<!-- stage-contract-pins:start -->
```text
../../../spec/contracts/actql-stage-contracts.json#/schemas/local_receipt sha256:00965a81fd89d80964295525f9f4f151cf7bc250f8f10539bfb4e83dc319d01a
../../../spec/contracts/actql-stage-contracts.json#/schemas/completion_evidence sha256:fb3a8c295b5069f4e7490ee97be9897d20e2ab97ca82874c9bb98146cf02fae7
../../../spec/contracts/actql-stage-contracts.json#/schemas/logical_request sha256:182296e19f04bbe04b1088213a20397486374ac42d9fd54379c9f942b33f649c
../../../spec/contracts/actql-stage-contracts.json#/schemas/risk_acceptance sha256:fc73a9f0e8db05f04bc47f74f5101a61496cc3341a8df73bc4d9e43ac522d570
../../../spec/contracts/actql-stage-contracts.json#/schemas/template_approval sha256:a55fff821004ba45c57bbc0e7910d2a1d23134f056ff9d2f2f8e7f6f43e96d2e
../../../spec/contracts/actql-stage-contracts.json#/schemas/template_instantiation sha256:525028fdd701aab546c52f87aad69e008262f3107093d62361b8eadf2a2b0ac3
../../../spec/contracts/actql-stage-contracts.json#/schemas/approval_renewal sha256:f3e64e5cab0b7b74b00224fcd8011c129438bc4ea7e4258a1010442065ecf1b5
../../../spec/contracts/actql-stage-contracts.json#/schemas/source_advance_claim sha256:cbd592cd24ee74462fadf765ccf7354ba1dc64c376c476720a82508f6d01df51
```
<!-- stage-contract-pins:end -->

<!-- lookup-identity-pins:start -->
```text
../../../spec/contracts/actql-lookup-identities.json#/evidence_slots sha256:d5257ad4c6368df06bdd720a132c1759b46ed0d3457b46e66e750b1f7f4aaa66
../../../spec/contracts/actql-lookup-identities.json#/laws sha256:c56618640aa84af330359c39433472fcafb476bef1f94323c3934ff49a8d508f
```
<!-- lookup-identity-pins:end -->
