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
<!-- machine-import: ../../../spec/contracts/actql-remote-site-wire.json#/schemas/effect_resume_delivery sha256:d1120b333ee833e2f27b4c9c399708969a32699e2a59809ce90be23b11b42cd5 -->
<!-- machine-import: ../../../spec/contracts/actql-remote-site-wire.json#/schemas/poll_effect_resume sha256:583de328093d30eceab4bf49a9ac1b11ceec46f7ebd385da956bb9675275a265 -->
<!-- machine-import: ../../../spec/contracts/actql-remote-site-wire.json#/schemas/effect_current_reply sha256:d898c42ea28d2f776df4dbd1d910b27b3d13afe7f9479edca364a1387ef9e380 -->
<!-- machine-import: ../../../spec/contracts/actql-remote-site-wire.json#/schemas/effect_current_query sha256:a11afe0b0327e7c253cc2a8d621282cfc5c994fbb304ec2178ce5d2132a7e343 -->
<!-- machine-import: ../../../spec/contracts/actql-remote-site-wire.json#/schemas/poll_effect_current sha256:ec96478794b68708c384b01df952e25d99961e909927137398a9a05c4920079f -->

This document owns run-wire, checkpoint-wire, resolution-wire, preview-wire, apply-receipt, reconciliation-receipt. It does not define other owners' wire protocols or a particular Host implementation. Cross-owner links outside the declared dependencies are informative navigation to protocol bindings or conformance evidence; they do not import those documents' requirements. Narrow machine contracts remain authoritative for their explicitly referenced values and envelopes.

<!-- machine-import: ../../../spec/contracts/actql-interactive-run-control.json#/schemas/control_quantity sha256:4b2b7ef61e4ca0c4ec8f4c5ee5526305e4b97d0e11acba5be33ee15787399488 -->
<!-- machine-import: ../../../spec/contracts/actql-interactive-run-control.json#/schemas/control_money sha256:3ff2b76540c468cfb8465fc1ef353fa60ce79c0680ff07baa2a3e2108e73ebbf -->
<!-- machine-import: ../../../spec/contracts/actql-interactive-run-control.json#/schemas/control_guards sha256:78042c86816324a2a74619155ab4279ae7329b6f654144da5e45dbb34cdf7771 -->
<!-- machine-import: ../../../spec/contracts/actql-interactive-run-control.json#/schemas/control_interval sha256:96c7f78a4f3b7fa1c28767a62af8bb2b30d9b0e6d149221637161fa661caaa27 -->
<!-- machine-import: ../../../spec/contracts/actql-interactive-run-control.json#/schemas/control_profile sha256:de509d6973a97005a404c6312ec5dcec7a72088842659d4480990b0b672b43e3 -->
<!-- machine-import: ../../../spec/contracts/actql-interactive-run-control.json#/schemas/control_request_intent sha256:a6b7aac22908f080c9e98fbbcd318cbf44f2ba1524c3b035892f3df1d1f9b6cc -->
<!-- machine-import: ../../../spec/contracts/actql-interactive-run-control.json#/schemas/control_admission sha256:f71d8bc18652162c270821b33feb3310f2747cab5d874fa3674a5796de5fc008 -->
<!-- machine-import: ../../../spec/contracts/actql-interactive-run-control.json#/schemas/logical_step_key sha256:493523f1d72c47ac9486c8578b48d9e969c95cf02cdb8826f0fcba6033101070 -->
<!-- machine-import: ../../../spec/contracts/actql-interactive-run-control.json#/schemas/logical_port_key sha256:5e6d862b4a4a1b778c39e466598ccf88eeeb4a2395f8b990a69f6dfa271cac86 -->
<!-- machine-import: ../../../spec/contracts/actql-interactive-run-control.json#/schemas/logical_source_locator sha256:40d85149915b4f67a9ee59a8ed043dcf1e8e78b89b29762021d182683a764a08 -->
<!-- machine-import: ../../../spec/contracts/actql-interactive-run-control.json#/schemas/logical_port sha256:f9bf3a936eded99c37d35dca9552e16e6344e290e1626278b06740f158131c8a -->
<!-- machine-import: ../../../spec/contracts/actql-interactive-run-control.json#/schemas/logical_step sha256:358b99d025a24cb2136eecd815d76d4420ebca12376ab6e3f2ef9b8a2abb8038 -->
<!-- machine-import: ../../../spec/contracts/actql-interactive-run-control.json#/schemas/logical_map sha256:89c090b128f4cd79aa09cc767eb439890032f8c897f3f44ec93c0159b4495df4 -->
<!-- machine-import: ../../../spec/contracts/actql-interactive-run-control.json#/schemas/run_control_capabilities sha256:8ef39dfb5463ce5518cc213da341906af7fc9f74996a172608f574dd874a6794 -->
<!-- machine-import: ../../../spec/contracts/actql-interactive-run-control.json#/schemas/plan_view sha256:51856c457b3eae9724d9626319ad865f38baee748f341f179d3575b2558c5bf4 -->
<!-- machine-import: ../../../spec/contracts/actql-interactive-run-control.json#/schemas/control_resume_origin sha256:a6aecb1e607745939e7d1e3a16a89c61ec9d0d6ff272aab22e000f40687ea13f -->
<!-- machine-import: ../../../spec/contracts/actql-interactive-run-control.json#/schemas/controlled_run_state sha256:95db721d1dd426ae5323fa89b11a045e1c8e445ed720e7f55f6dac54bedb0d2c -->
<!-- machine-import: ../../../spec/contracts/actql-interactive-run-control.json#/schemas/control_command sha256:3652d5b0ccd085bcb7077cae918e6c802fa6d8e7d2ef57fdf533b591bcb23365 -->
<!-- machine-import: ../../../spec/contracts/actql-interactive-run-control.json#/schemas/control_operation_ref sha256:789a793ad961d9b353c7ce7e7291c5ea6332c5c5eda5626a86ddeb89b762f2b8 -->
<!-- machine-import: ../../../spec/contracts/actql-interactive-run-control.json#/schemas/control_operation_receipt sha256:22eeab3c3f9f494a4bb19441508e774e9fe647e7df0cf7bf4b63ac2a895c0822 -->
<!-- machine-import: ../../../spec/contracts/actql-interactive-run-control.json#/schemas/control_operation_observation sha256:a3b7c22419a2a4de7c2573080d71b98f6f899dff632bf68a19f86e1c34d9668b -->
<!-- machine-import: ../../../spec/contracts/actql-interactive-run-control.json#/schemas/control_operation_lookup sha256:7d5e46b305d4ba94016a79f624d1bc1a3c2011fca87c7821ae529a599078f606 -->
<!-- machine-import: ../../../spec/contracts/actql-interactive-run-control.json#/schemas/sample_source sha256:ccffb92dfb366ccab5346593fd071e6baf6c943b74fd895c256a56dde3187d84 -->
<!-- machine-import: ../../../spec/contracts/actql-interactive-run-control.json#/schemas/sample_capture sha256:dd9dd44cf547d9350fa1035eb3ac43cb07ab86d9efb4e413a60c0ddfc29bcdc6 -->
<!-- machine-import: ../../../spec/contracts/actql-interactive-run-control.json#/schemas/sample_cell sha256:c60e20a17f880fb29e963a31cdbfd1bf77f93b128baccfd086d7ad31efd27aee -->
<!-- machine-import: ../../../spec/contracts/actql-interactive-run-control.json#/schemas/sample_relation sha256:f2f21a34ac9ca8f2d90960c05c26e84e60030e344c0da8726cdb0ebbf4bdad6b -->
<!-- machine-import: ../../../spec/contracts/actql-interactive-run-control.json#/schemas/sample_graph sha256:28cd043650698fa9ffa3a5ce63df35fb9842d428495b25329a680521531a1102 -->
<!-- machine-import: ../../../spec/contracts/actql-interactive-run-control.json#/schemas/sample_vectors sha256:aac6c7925d0d1530470025c220cd318ae05478e3e6a3fc549f3650e4347a412b -->
<!-- machine-import: ../../../spec/contracts/actql-interactive-run-control.json#/schemas/sample_events sha256:b1f560c21d34be458106a6d9bba1beda6c0fae10c4495b2e719de752ae7aa067 -->
<!-- machine-import: ../../../spec/contracts/actql-interactive-run-control.json#/schemas/run_sample sha256:2dd54eb2b19fa3a2711de876dea2b965a3490c69482df328915415f8c24f1bf6 -->
<!-- machine-import: ../../../spec/contracts/actql-interactive-run-control.json#/schemas/run_view sha256:080a02459f184f92fb956141c2105b3ea36d0ac7f2efd02f06dcc9ac4b08a293 -->
<!-- machine-import: ../../../spec/contracts/actql-interactive-run-control.json#/schemas/resolved_control_profile sha256:6c2bb8de6b1f74fc37ecd43a3b3b667ff660e46e09c32846d34544dcace804f9 -->
<!-- machine-import: ../../../spec/contracts/actql-interactive-run-control.json#/schemas/control_operation_query sha256:411c0a6ceb270757a5ded2334285827387b9a67257e2b62bcc29fb28c4bd32ca -->
<!-- machine-import: ../../../spec/contracts/actql-interactive-run-control.json#/schemas/sample_selector sha256:345ec8f736c15213fc6c312f010cccf9146ec43c0033221d1f3b385a0f74f269 -->
<!-- machine-import: ../../../spec/contracts/actql-interactive-run-control.json# sha256:d79ac12e9ce9785353324da1a17a96af1c01b0692b56eb42692d15c598be781d -->
<!-- machine-import: ../../../spec/contracts/actql-interactive-run-control.json#/schemas/run_plan_view sha256:bc7d46d0fead62582cde82f78ce9467814640a8ccd293541ee30e31efba6ed77 -->
<!-- machine-import: ../../../spec/contracts/actql-interactive-run-control.json#/schemas/effectful_static_plan_view sha256:290df7e7a6ceeab8d5198bc7fd39ba4a65d213fa80f83e5a6381b94c6dbde645 -->
<!-- page-contents:start -->
## On this page

- [Terms](#run-terms)
- [Checkpoint and Resolution admission](#resolution-admission)
- [Fixed Model invocation approval](#model-invocation-approval)
- [Private preview row state](#preview-row-state)
- [Stage wire and immutable history](#stage-wire)
- [Policy and human risk acceptance](#policy-risk-acceptance)
- [Renewal and template evidence](#approval-renewal)
- [Logical request and dispatch evidence](#logical-request)
- [Source-state operator claim](#source-advance-claim)
- [Authorized private inspection](#private-inspection)
- [Execution-account configuration](#account-config)
- [Machine contracts](#machine-contracts)
- [Negotiated Interactive Run Control](#interactive-run-control)
<!-- page-contents:end -->

<a id="run-terms"></a>

## Terms

- **Review projection** — the redacted, content-addressed view of sealed
  evidence presented for review and bound by the approval ([Review and receipt artifacts](#review-artifacts)).

<a id="original-update-selection-custody"></a>

#### Original UPDATE selection custody

<!-- requirement-block: original-update-selection-custody.run-definition-projection -->
The admitted Run Definition issuer MUST copy the optional
`effect_target_selections_cid` from its admitted Compiled Plan automatically,
including omission when absent. This field uses the existing Run Definition
identity and self-CID exclusion. The caller supplies no separate selection
flag, custody claim or projection argument, and the field grants no read or
write authority.

<!-- requirement-block: original-update-selection-custody.exact-run-binding -->
Run binding and start MUST verify exact optional equality among the admitted
Run Definition, its Compiled Plan, and the canonical selection array retained
in the existing Executable Plan and original compilation material. Presence
and absence are part of equality, so stripping a field or the whole original
material envelope cannot downgrade a selection-bearing Run to a legacy Run.
Legacy Runs without selection context retain their previous canonical bytes
and identities.

<!-- requirement-block: original-update-selection-custody.before-capture-read -->
Restore, continuation and recovery MUST establish this binding before their
first captured-material Store read, as well as before applicable target reads
or Effect sends. A missing, replaced or mismatched original fails closed rather
than reselecting aliases or accepting a newly reconstructed expectation. The
admitted Run Definition supplies the independently retained expectation; the
possibly missing compilation material does not define its own absence policy.
Current installation-owner, grants, approval, lease, dispatch and
unknown-outcome protections remain independent obligations. Source schema
checks alone do not establish that these execution boundaries are verified.

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

The 0.1 preimage is exact. `logical_relation_cid` is the existing ordered-row
Relation identity; it is not a second hash of the row payload. The checked
source contract, observed Relation schema, completed
capture, and logical ordering are bound separately:

```text
SourceInputLogical = CID({
  version: "actql-source-input-logical/0.1",
  logical_relation_cid,
  source_contract_cid,
  relation_schema_cid,
  completeness,
  ordering_evidence
})
```

The capture owner issues completeness and ordering only after its bounded
read finishes. This identity excludes physical attempt, observation time,
and placement. Source Evidence retains their observation, provenance, and
freshness bindings. Equal input identities do not imply equal observation,
current authorization, or permission to acquire again.

<!-- requirement-block: runtime-source-evidence.completed-listing-original-report-correlation -->
A completed file-listing input MUST additionally carry the closed
`file_listing_reports: {row_count, rows}` field. Each row has exactly
`row_ordinal`, `resource_ref_cid`, `version`, `reported_media_type`, and
`media_type`. Ordinals and occurrence multiplicity describe the same captured
input bound by `input_logical_cid`, schema and snapshot reference, not a
downstream Result or a new ordering guarantee. `version` is exact nullable
Text; the original nullable provider report and its nullable case-only MIME
projection remain paired with the same Resource. Missing report evidence is
not NULL and cannot be repaired from schema, later content acquisition or
another listing. Non-listing observations omit this field and keep their
existing canonical bodies.

<!-- requirement-block: runtime-source-evidence.completed-listing-single-transfer-custody -->
The existing Row acquisition/capture Owner MUST transfer selected report
correlation once before retiring transient page observations. Completion,
transport settlement, capture custody and the original reservation remain
necessary; the field's data shape or CID grants none of them. Retained reports,
projected values, records, backing and encoding overlap must stay funded until
actual cleanup or transfer. Existing evidence byte/node/work limits still
apply; an oversized correlation is refused rather than dropped or encoded
under a silently enlarged bound. A completed empty listing carries zero rows,
but only an explicitly empty exact-path selection implies no enumeration I/O.
An empty glob result does not imply zero provider reads.

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
| `run_unit` | `preflight` | `model_invocation` | `model_invocation_scope` |
| `run_unit` | `commit` | `effect_set` | `effect_set_preview` |

A `prepare_attempt` subject contains `prepare_attempt_id` and
`continuation: start_run`. A `run_unit` subject contains `run_id`, `unit_id`,
and `continuation: resume_unit`. Only a `run_unit` Checkpoint carries the
top-level `run_id`, equal to its subject's, and `run_definition_cid`; a
`prepare_attempt` Checkpoint carries neither. Its Resolution likewise carries
`run_id` and `run_definition_cid` for a Run-unit Checkpoint, or only
`prepare_attempt_id` for a preparation Checkpoint. Non-Effect Checkpoints require exactly
`[invocation_scope_approved]`. An Effect Commit Checkpoint requires
`[effect_scope_approved]` or
`[effect_scope_approved, partial_application_accepted]`. The latter records
that the Host's declared policy for that delegated decision requires the risk
claim; the number of Effect Set members alone never selects it, so a
multi-member Effect Set Checkpoint with `[effect_scope_approved]` is valid.

<!-- requirement-block: resolution-admission.an-immediate-delegated-answer-must-bind-the-exact-decision-subject resolution-admission.admitting-an-immediate-answer-must-not-persist-a-checkpoint-or-create-a-resume-intent resolution-admission.a-delegated-answer-must-not-be-admitted-without-a-delegate-outcome-for-its-subject -->
Only an execution-account `delegate` outcome creates a delegated decision
([Account authorization routing](../execution.md#policy-routing)). Its decision
subject is the exact `actql-execution-checkpoint/0.1` body that the Host would
persist if it deferred, identified by its `checkpoint_cid`, with one of the
valid combinations above. An immediate permit or reject is an
`actql-checkpoint-resolution/0.1` verified through the same Host authorization
port. It MUST bind that subject CID, its preparation or Run identity, required
artifact, review projection and current authorization context. Admitting an
immediate answer MUST NOT persist a Checkpoint, enter `waiting_checkpoint`, or
create a resume intent; the verified Resolution is retained as the decision
evidence of the permitted or rejected unit. A deferred answer persists that
same body as the Checkpoint, and its later Resolution uses the atomic admission
below. A delegated answer MUST NOT be admitted for a subject whose current
account outcome is not `delegate`, so no answer overrides an account `deny` or
no-match. A missing, malformed, unauthenticated, expired or undelivered answer
is a technical decision failure, not a permit or a rejection.

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

<!-- requirement-block: resolution-admission.a-resolution-proof-must-sign-the-unsigned-resolution-cid resolution-admission.a-host-attestation-must-sign-the-unsigned-verified-wrapper-cid -->
Resolution identities follow the evidence-envelope convention of
[Stage wire and immutable history](#stage-wire). `resolution_cid` is the CID of
the complete Resolution without `resolution_cid`, so it includes `proof`.
`proof.signature` MUST be the Ed25519 signature, in padded base64, over the
UTF-8 bytes of the unsigned Resolution CID text, which is the CID of the
Resolution without both `resolution_cid` and `proof`. Likewise,
`verified_resolution_cid` is the CID of the complete verified wrapper without
`verified_resolution_cid`, so it includes `host_attestation`.
`host_attestation.signature` MUST be the Ed25519 signature, in the same
encoding, over the UTF-8 bytes of the unsigned wrapper CID text, which is the
CID of the wrapper without both `host_attestation` and
`verified_resolution_cid`. The signed CID binds the artifact `version`, so a
signature cannot be replayed as another artifact kind. `proof.key_id` and
`host_attestation.host_key_id` select only Host-trusted keys.

<a id="model-invocation-approval"></a>

### Fixed Model invocation approval

<!-- requirement-block: model-invocation-approval.fixed-scope -->
Before requesting delegated approval, the Run owner MUST fix an
`actql-model-invocation-scope/0.1` original with `run_definition_cid`,
`task_index`, `strategy_revision`, `inference_barrier_cid`,
`input_artifact_cid`, the complete ordered duplicate-free
`model_call_slot_cids`, `provider_binding_cid`, `authorization_context` and
`self_cid`. Its self CID hashes the complete canonical body excluding only
`self_cid`. An empty call inventory is valid for an empty checked input and
grants no provider send. Order and multiplicity in the actual checked input
remain bound through the original input and call-slot artifacts.

<!-- requirement-block: model-invocation-approval.original-closure -->
The owner MUST admit and retain the scope's referenced originals and verify
their complete dependency closure against the actual Run occurrence, checked
Model contracts, actual input rows and keys, request arguments, retry policy,
limits and egress scope. An unexplained caller-supplied CID is not evidence of
those facts. Existing `plan.request_cid` and `fixed_request_cid` identify the
original request-expression mapping; neither is an alias for the invocation
scope. Changing any identity-bearing occurrence, input, request, contract,
provider binding or authorization fact requires a new scope and decision.

<!-- requirement-block: model-invocation-approval.authorization-context -->
The closed `authorization_context` MUST contain `account_id`,
`configuration_cid`, `entry_id`, `principal`, `connection`, `resource`,
`operation: infer`, `boundary: activation` and `context_cid`, taken from
trusted current authority. It omits `subject_cid` to avoid a self-cycle. The
completed scope CID becomes the Activation decision's `subject_cid`, the
Checkpoint's `required_artifact.artifact_cid` and the Resolution's
`required_artifact_cid`.

<!-- requirement-block: model-invocation-approval.provider-binding -->
The Host MUST derive and admit `actql-model-provider-binding/0.1` from
nonsecret installation and configuration originals: `provider_id`,
`installation_revision_cid`, `configuration_contract_cid`,
`configuration_cid` and `self_cid`. Its self CID excludes only `self_cid`.
The installation binds implementation revision, route, tenant, security
principal and request shaping. Credential secret values and function text are
excluded; ordinary secret rotation alone does not alter this nonsecret
binding. A change to target, principal or request shaping changes the binding,
even if the provider's display name remains unchanged.

<!-- requirement-block: model-invocation-approval.exact-review -->
The existing `actql-run-review-projection/0.1` MUST bind its
`displayed_scope.model_invocation_scope_cid` and
`displayed_scope.model_call_slot_cids` to this exact scope and inventory.
Redaction may hide private request content but never substitute identities or
omit calls. Its `prepared_invocation_cid` and the run-scope compatibility
approval's corresponding field identify the actual original PreparedInvocation
retained by this Run's admission, not the Model scope. The common verifier
checks that association against retained originals; a matching caller summary
or unrelated PreparedInvocation is insufficient. Public Model Checkpoint
summary metadata carries that original as `preparedInvocationCid` only for
`model_invocation`; consumers that cannot verify this kind refuse it explicitly.

<!-- requirement-block: model-invocation-approval.per-call-send -->
Before each new delegated Model send, the owner MUST have current approved
scope, `infer` authority and independent egress permission, and durably record
send start for that exact call in the existing call owner before physical
dispatch. The Model dispatch authority carries `model_invocation_scope_cid`
for every new delegated send. Approval fixes the call set, while durable
send-start, received-response and result-unknown evidence is per call rather
than one once-only marker for the complete set. No Model call precedes its
required invocation approval, and no Effect write precedes its required
Effect approval.

<!-- requirement-block: model-invocation-approval.restart-reuse -->
On restart, the owner MUST reuse durably saved responses and never resend a
call whose original send may have started without a saved response. Such a
call remains `result_unknown` attempt evidence, not a fabricated provider
failure, successful slot capture or completed barrier. Proven-unsent calls
may progress under current approval, infer authority and egress, subject to
the checked failure policy; one unknown call does not itself authorize
replaying another. A completed barrier still requires its ordinary actual
slot observations and completeness evidence.

<!-- requirement-block: model-invocation-approval.expiry-and-history -->
Expiry, cancellation, rejection or changed authority MUST stop all remaining
unsent calls without erasing sent-call observation, accounting or cleanup
obligations. Historical authority and response bytes without the optional
scope field remain valid for no-send replay and observation only; recovery
never upgrades them into permission for a new send. Per-call recovery extends
the existing call ownership and durable evidence path, not a second scheduler
or journal. Source read, Model invocation, egress and Effect permissions never
substitute for one another.

<a id="preview-row-state"></a>

### Private preview row state

<!-- requirement-block: preview-row-state.closed-relation-source preview-row-state.source-free-omits-binding preview-row-state.relation-source-inventory preview-row-state.recovery-complete-sources preview-row-state.no-private-source-free-fallback -->
An Effect Preview member with a captured Relation source MUST contain exactly
one of `source_result` or `source_table_input`, together with
`result_artifact_cid`. A source-free member MUST omit all three fields. The
two source names identify different checked Stage namespaces, even when their
spelling is equal. `source_table_input` is permitted only for `store` and binds
the declared private closed Table input, not a published Named Result. Its
schema may retain Conditional presence; ordinary Named Result requirements
are unchanged. Preview admission and source inventory checks MUST preserve
this discriminant and refuse a substituted namespace, missing Artifact,
mixed source fields, or source kind unsupported by a downstream consumer.
Neither field nor an equal content CID establishes live custody, approval,
current authority, or permission to send. Recovery MUST account for every
source-consuming member, including private inputs; an unsupported private
source MUST NOT be reinterpreted as source-free.

<!-- requirement-block: preview-row-state.physical-source-namespace preview-row-state.physical-source-exact-binding -->
A physical `actql-effect-source-artifact/0.1` MUST contain exactly one of
`source_result` or `source_table_input`. The source namespace is part of its
canonical preimage; equal names and logical content do not permit substitution.
The physical Artifact MUST match the admitted Preview's typed source, source
binding, Run Invocation, Store authority and semantic Artifact facts, including
schema, logical content, completeness, row count and effective policies. This
binding does not itself establish live custody, durable recovery or permission
to commit; those obligations remain with the existing capture and Effect owners.

<!-- requirement-block: preview-row-state.for-every-preview-row-implementations-must-first-compute-row-preview-cid preview-row-state.common-preview-admission-must-recompute-every-row-cid -->
For every preview row, implementations MUST first compute
`row_preview_cid = CID({version, program_definition_cid, invocation_cid, effect_identity_cid,
resolved_contract_cid, operation, target_row_identity, preview_strength,
target_guard, intended_changes, before, after})`. The `version` in this
preimage is `actql-effect-preview-row/0.1`. The Program Definition and
Invocation CIDs come from the enclosing private Preview. The Effect identity,
operation, and preview strength come from the enclosing member.
`resolved_contract_cid` is the member's resolved Command Contract CID for a
command, otherwise its resolved Mapping Contract CID. The remaining fields
come from that exact `changes[]` entry. The preimage is canonical JSON; the
transported `row_preview_cid` is not part of its own preimage. Common Preview
admission MUST recompute and compare every row CID before admitting the member
or set CID. A missing field is not supplied with a default.

<!-- requirement-block: preview-row-state.target-guard-and-intended-changes-are-required-closed-forms -->
`target_guard` is required and has the closed form
`{state: "version", version_cid: CID}` or `{state: "not_applicable"}`.
The version form binds the connector's exact target version/content guard.
An update, delete, or update-side upsert admitted as `full_diff` or `targeted`
requires that form. An upsert with a present `before` row is update-side for
this purpose. Unresolved target scope cannot be admitted as a Preview.
Create uses the not-applicable form. A command without a
version guard may also use it. This form does not waive another required
admission guard.
`intended_changes` is required and has the closed form
`{state: "present", value: CanonicalJSON}` or `{state: "not_applicable"}`.
The present value is the exact approved mutation or typed command payload,
including field omission versus an explicit null. The not-applicable form is
only for an operation with no row payload, such as delete or a payload-free
command. Apply uses this
approved value and rechecks the current target guard; it MUST NOT rebuild the
approved mutation from current target state. Neither field may contain a
credential or secret. A caller-facing review view is a redacted projection of
the private Preview, not a replacement for this preimage.

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
and its own CID. An individual apply receipt contains the set Preview CID,
its exact member Preview CID, approval-attestation CID exactly when approval
was required, and disjoint
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

<!-- requirement-block: review-artifacts.each-member-apply-receipt-must-bind-exact-member-preview -->
Each member apply receipt MUST bind its exact member Preview CID as well as
the set Preview CID. A row partition alone cannot identify a member whose
preview contains no rows.

<!-- requirement-block: review-artifacts.an-effect-review-projection-must-include-each-effect-s-kind-target -->
The private Effect Preview binds the evidence available for its strength and
may contain sensitive business values, but not credentials or secret material.
It declares `sensitivity: private`, an authority-evidence retention
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

<!-- requirement-block: review-artifacts.sealed-review-original-row-evidence -->
A newly sealed Effect review and its approval admission MUST bind every
displayed member and row to the same original private Preview, including the
member's exact `preview_strength` and the row's exact `target_guard` and
`intended_changes`, while preserving `before` and `after` without wrapping,
normalizing or replacing their states or values. The three additional closed
row fields remain optional only for structural compatibility with historical
absent-field encodings; their omission or mismatch is insufficient evidence
for a new sealed review or approval. Strength is the original `full_diff` or
`targeted`, not an inferred Effect kind. This does not fabricate unavailable
before evidence, a version guard, a `not_applicable` state, an intended request
or stronger evidence, and does not rewrite a historical pending Run.

<!-- requirement-block: review-artifacts.original-resource-scope-target -->
Private Preview and review scope targets MUST preserve the original string,
`{field}` selector or concrete closed `resource_ref` alternative, independently
of each row's exact target identity. A field selector with ResourceRef row
identities remains a field selector; one row is not a representative scope.
The concrete alternative uses exactly the existing ResourceRef contract, not
the entire row-identity union, a stringified reference or a newly issued grant.

<!-- requirement-block: review-artifacts.projection-self-identity-and-store-address -->
The `review_projection_cid` MUST hash the complete canonical review projection
excluding only its own root field, including every present row extension and
every other required top-level field. Its self identity is distinct
from the physical Store's digest of complete bytes. The Checkpoint and approval
bind that exact original review identity, Preview, authority scope, claims,
Authoring Context and immutable redaction policy; a public shape or CID is not
authority to apply or resume an Effect.

The row Outcome Receipt has two closed response alternatives. The HTTP
alternative retains its original credential-use, status and byte preimage.
The local alternative has `response_kind: local_operation` and
`local_operation_receipt_cid`, without HTTP or Credential fields. That identity
selects the same SQLite backend's atomic original-operation receipt, binding
installation, target, request, dispatch, authorization/approval use and version
to the exact Preview row. Its physical SHA-256 addresses complete saved local
receipt bytes; it does not replace either receipt's semantic self-CID. Only
committed UPDATE or known conflict outcomes are local terminal evidence;
uncertain COMMIT remains Unknown and cannot authorize a resend.

<!-- requirement-block: effect-outcome-wire.upsert-action -->
The `effect_row_outcome_receipt` for an applied upsert MUST include
`typed_outcome.action` as `created` or `updated`, bound by `typed_outcome_cid`
and the receipt CID to the original dispatch operation.
The field is not valid for another operation or a non-applied outcome. A
failed apply-time condition uses the existing typed error with code `conflict`.

<!-- requirement-block: review-artifacts.approval-attestation-must-bind-both-effect-preview-cid-and-the-exact-review-projection-cid review-artifacts.redaction-must-not-substitute-for-an-authority-preview stage-wire.product-36870f813edf policy-risk-acceptance.present-risk-acceptance-evidence-must-bind-issuer-policy-preview-and-scope approval-renewal.product-6542a3eac80f logical-request.product-26cde1934ed3 source-advance-claim.product-026cf595ba1a private-inspection.product-f6c29d1d5272 -->
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
tagged issuer `human|policy`. It is required only when a Host's declared policy
requires it for a delegated decision; Effect Set member count alone never
requires it, and an account `allow` neither requires nor fabricates it. When
present, authenticated evidence MUST bind issuer, policy
CID, decision, exact Preview and review projection, authority scope and expiry.
The policy path under a resolved allow or an immediate delegated permit
requires no human Checkpoint, including multi-Effect stages. A deferred
decision still signs the complete stage scope. Earlier coarse allow cannot
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
and signs namespace/scope/policy/expiry/nonce, exact fenced graph state and commit
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

<a id="account-config"></a>

### Execution-account configuration

An execution-account configuration is an `actql-execution-account-config/0.1`
document. It binds one `account_id` and a finite set of entries, each with a
unique `entry_id`, one outcome `allow`, `deny` or `delegate`, one selector for
each of `principal`, `connection`, `resource` and `operation`, and a set of
tuple `exclusions`. A selector is `{all: true}`, which includes current and
future members of that dimension, or `{any_of: [...]}`, a finite set of exact
identifiers. An exclusion is one selector per dimension and denotes their
Cartesian tuple set. The optional `bootstrap` member records the provenance of
a materialized Local bootstrap profile: profile ID, version and exact content
CID. Routing semantics are owned by [Account authorization routing](../execution.md#policy-routing).

<!-- requirement-block: account-config.the-run-owner-must-present-a-basic-operation-class -->
The trusted Run owner MUST present the operation identifier of a protected
boundary as `read`, `write`, `infer` or `effect`, derived from that boundary's existing
operation contract: `read` for preparation input capture, acquisition and
catalog or metadata reads, including Model metadata; `infer` for invoking a
Model provider; `write` for dispatching work to, or
transferring or egressing data to, another Site, recipient or Store; and
`effect` for an Effect commit. Covered pure computation is not a protected
operation. The boundary kind belongs to the decision subject, never to the
operation identifier.

<!-- requirement-block: account-config.finite-read-grants-do-not-expand -->
Admission MUST NOT expand a finite `read` grant or a previously materialized
bootstrap profile to include `infer`. Explicit `{all: true}` retains its
declared current-and-future-member semantics. Model invocation, Source read,
data egress and Effect commit remain independent protected decisions.

<!-- requirement-block: account-config.a-configuration-must-use-one-canonical-spelling account-config.identifiers-must-match-by-exact-equality account-config.admission-must-decide-overlap-by-this-exact-rule -->
A configuration MUST use one canonical spelling: entries in strictly
ascending `entry_id` order, each `any_of` array in strictly ascending order, and
each `exclusions` array in strictly ascending order of its tuples' canonical JSON
text, with UTF-16 code-unit ordering throughout. Order, equality and identity are
decided over admitted identifiers, whose separate contract requires NFC-plus-LF text;
two values equal after normalization are duplicates. Its identity is the CID of the
complete canonical document; evidence and Checkpoints bind that CID. A
principal, connection, resource or operation identifier MUST match only by
exact equality with the identifier the trusted Run owner presents for the
boundary, without prefixes, patterns or case folding. An entry's effective set
is the Cartesian product of its four selectors minus the union of its
exclusions. For two entries with different outcomes, the candidate box is the
per-dimension intersection of their selectors, where `all` intersected with a
finite set is that set. The configuration conflicts when that box, minus the
exclusions of both entries, is nonempty. Admission MUST decide overlap by this
exact rule: in each dimension, use the box's finite set, or, for `all`, every
identifier named by those exclusions in that dimension plus one fresh
identifier that only `all` contains; the configuration conflicts exactly when
some point of that finite grid lies outside every exclusion. The result is
therefore independent of discovered connections, resources and operations.

<a id="remote-site-wire"></a>

## Remote Site internal wire

<!-- requirement-block: remote-site-wire.single-current-format remote-site-wire.reject-obsolete-records -->
Remote dispatch requests, managed-output subjects and outbound poll dispatches
MUST use one current 0.1 form with the closed field sets pinned below. A reader
MUST reject unsupported labels and obsolete field sets, including old bodies
relabeled as current. It must not invent missing input bindings, measurement
identities or physical observations. An unreadable saved record is not an empty
journal and does not authorize another execution.

A dispatch identity hashes its entire canonical request body, including the
version and exact input-binding CID, and excludes the self CID. A managed-output
subject identity hashes its entire canonical body, including the dispatch,
holding and measurement identities, excluding its self CID. Holding and
execution-evidence identities transitively bind the corrected dispatch and
subject preimages. Canonical bodies use UTF-8, sorted keys and the existing
canonical JSON scalar encoding. The outbound poll envelope has no independent
execution authority: its embedded canonical request, claimed dispatch CID,
input-binding body and CID must all agree. Schema shape validation alone does
not prove those relationships, integer/byte capacity or current authorization;
the existing MoonBit admission owner enforces them.

The independent fixed preimages and digests are in
`spec/fixtures/remote-site-wire-vectors.json`. Unsupported historical bytes
remain owned and preserved pending an explicit migration decision outside
controlled development fixtures. A version correction is not a migration.

<!-- requirement-block: remote-site-wire.output-report-durable-acceptance remote-site-wire.output-report-ack-custody remote-site-wire.output-report-exact-replay remote-site-wire.output-report-unknown-custody -->
An Output report MUST be acknowledged only after exact durable acceptance,
using `actql-remote-output-report-reply/0.1` bound to the original report,
dispatch and Output intent CIDs. The Site MUST validate and durably save that
ACK before closing report custody. HTTP success or physical release alone is
not an ACK. Exact retransmission MUST reuse the saved report bytes and the
receiver's saved acceptance fact without advancing execution or revision.
Unknown responses and unconfirmed ACK saves MUST retain report custody;
only a validated, scoped refusal may suspend automatic retries. Physical
cleanup remains independently operable, including after payload release.

<a id="captured-effect-dependencies"></a>

## Captured Effect dependency inventory

<!-- requirement-block: captured-effect-dependencies.explicit-inventory -->
The Captured Run Effect context MUST include `effect_dependency_inventory`,
including an explicit empty array when no runtime upstream dependencies are
required. Each closed entry contains `kind`, `cid`, and the canonical `body`.
Entries are ordered by CID then kind in UTF-16 order; duplicate kind/CID pairs
are invalid. Equal bytes under different declared roles are not interchangeable.

<!-- requirement-block: captured-effect-dependencies.closed-bodies captured-effect-dependencies.import-correspondence -->
The checked local Effect inputs select roots. Typed body references determine
the required transitive closure of acquired inputs and preceding local Results.
Readers MUST reject missing, altered, unused, cyclic or wrong-kind dependencies.
They MUST verify Result import position/interface, producer local Manifest,
exact Result Artifact and consumer local Invocation correspondence. Correct
individual hashes alone do not establish that correspondence or current Run
and namespace authority. A Run-wide CID is not added to local semantic preimages.

The closure is bounded by 4,096 entries, 16 MiB of canonical envelope and
evidence bytes, 65,536 references and 64 dependency edges in a path. Existing
stricter admission limits still apply. Relation payloads remain subject to
their existing Store capacity and schema checks and are held by existing owners.
An entry's CID does not replace a recoverable body or retained payload.

<!-- requirement-block: captured-effect-dependencies.durable-before-wait captured-effect-dependencies.no-repair -->
Required bodies, payloads, holdings and the Preview/capture correspondence MUST
be durable before resumable commit approval wait is exposed. Recovery MUST NOT
repair missing evidence by reacquisition or recomputation. Current mutation
authorization and target checks remain separate from the saved observations.
Cleanup failures and unknown writes retain their existing recovery owners.

This required field changes Effect context and Captured Run CIDs, and therefore
their downstream references. This is a coordinated incompatible 0.1 correction:
readers reject missing or mixed shapes without modifying historical records or
inferring permission to resend. No old-format supplementation is defined.

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
../../../spec/contracts/actql-remote-site-wire.json#/schemas/dispatch_request sha256:6625db4f9182af1d5b56e07227e194ac0665d198f5c17d4c5e36421d1f079e86
../../../spec/contracts/actql-remote-site-wire.json#/schemas/managed_output_subject sha256:26bc383f313192dfa296e2e298b2a3ae5fbfc3ac3eb2ea695bb87c3eb0ed692f
../../../spec/contracts/actql-remote-site-wire.json#/schemas/poll_dispatch sha256:ca7951b1ccab716fdf738573b94f402f92ccbdaeadbf4ab699b00a777003ab56
../../../spec/contracts/actql-remote-site-wire.json#/schemas/poll_cancel sha256:53e69b8d3b2b27c7e90ef106f6b888b5267cce91a1145048c2ab5b46f32dd8fc
../../../spec/contracts/actql-remote-site-wire.json#/schemas/output_report_reply sha256:db3cd45931cdbbdf86ac79545a19a0691b1240d1b78fe963812eb331f9820284
../../../spec/contracts/actql-remote-site-wire.json#/schemas/effect_checkpoint_report sha256:37ae97f48d65d838aa9ebf2859425a4a952e8e2ea012b58cb319f0f3d6831b86
../../../spec/contracts/actql-remote-site-wire.json#/schemas/effect_checkpoint_reply sha256:087b35471447e082dbdb4f39e77bb91b4bfb90de7be348aebb57d395d9617784
../../../spec/contracts/actql-protocol-schemas.json#/schemas/observation_facts sha256:bb63f5ddcba12a33225cc5fefc2ddf69ceed007524cb890d96004363b4ad0db4
../../../spec/contracts/actql-protocol-schemas.json#/schemas/event_delivery_evidence sha256:e9e5f043206fdf00720bbd14f12a765796b3686a4485505f77ba0a2533767582
../../../spec/contracts/actql-protocol-schemas.json#/schemas/effect_outcome sha256:9b2a918f994cd00147d4acd038639534dd767ff7f4e119b5a5fb43b9463592b1
../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/source_evidence sha256:63485b767c477d6ed77853478eefbf7f3af055c2bfac78e915e2db8bb89b51bc
../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/source_input_logical sha256:1b11bde1c1081b782d14ffe080ad5c511144724e8c8fd2d0c1c772828d1c09ea
../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/observation_set sha256:a2a967e39998c2d2037b035d81aab0eb5dce50b308c6d0c08f8b88512307f59c
../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/model_invocation_evidence sha256:9b883bf32553da51b01bd88ff912f460eb2308034b33a591a18f7f6e91c38b27
../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/model_capture_bundle sha256:9e4c76623e09216b81f70ca5573b90dc6f17f4a8754638345da2f8ec617507ba
../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/effect_preview sha256:8b96ef58002bd3dcf7404fba1d692f1e5baf1b7decb54fc493756a08f8e825e1
../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/effect_source_artifact sha256:58e2c6121d2089cc025f14a863664ab9bbc64f219b594f6416b16fd83c685bdc
../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/effect_row_outcome_receipt sha256:8b4147335ba233b174f0493e12ca98ce76a39ea7046b2d911653df8ad116e79c
../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/effect_local_operation_receipt sha256:b02752bd4be29b22e064abf4ffb907332f5be4e58f8e0645d2bc12ef256c6bc5
../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/review_projection sha256:99680abc66cdaa569fb44ac546fd1f814ed128e5d1ed3002d38d3a885acfe87b
../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/approval_attestation sha256:482ee09bcbed57fd19edd49e01d81882a3bbeb398ea9176c09e1717883a21ba9
../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/effect_apply_receipt sha256:4f4aabc61bc08bf79ecfe89cf958906e99d5bde4e12b3e95f5ef6539c9964c62
../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/effect_set_apply_receipt sha256:311b168738be9062ba8ff88d5e3d3d1d7fbbfe3935ee334cb6216d92e0a4b9cb
../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/effect_reconciliation_receipt sha256:8a80246cc33e6c8b3997085e15a31deb8b975c5f060bfebd5fb250e40a22f57c
../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/run_receipt sha256:62f9011e9e702f3d620f70513eac6260a21b980687b7574c1bdce55984b1aba8
../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/runtime_error sha256:065e22b471b7e63c67061a75854e5ca3d1821841fcc07016742d6b715632608d
../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/execution_context sha256:49bb0acf26e64ffc1d0802b03b251f27476732ad28c80f0c89b35c5cbf5734b2
../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/run_policy sha256:d1c763d2ba8357fd33fa41afd690eed8088a310e4640fa615907c4866a125db6
../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/prepared_invocation sha256:b3aa019105b4b6db51c69b2b96771ebe184f87c1f7eff3347bf5aef1cd9482f9
../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/run_review_projection sha256:6c1ee39379eb6a433bc555cbea5918dfb8d757ee12b7afa20de63fb34caad11e
../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/run_scope_approval sha256:ab7aa04f5afe9b7479ab2bc1ad078b2df41bde6248fd6eae1d0f88a94ffaa3de
../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/run_authorization sha256:f3085180be28dfc3f7b6151adf56796255a257a73205fabf674be281a05e4ed9
../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/run_definition sha256:fa0af630d657a970ca5bba7fe82fa2adb97076dd9c8ae12ad8fdff87d52953b6
../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/execution_checkpoint sha256:2463a0ebef2f3b78f2603d934a4e4e85851a4afa956abcdedec641594c92f91c
../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/model_provider_binding sha256:a4a37e0016403b483aa267dca7aae6c682940d2b23343b95defbcac2a1ca92b3
../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/model_invocation_scope sha256:2ae55fd7143e29dc3468123dbea9979c65f0aeac9adc392098db87679ebf88c3
../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/checkpoint_resolution sha256:46a6fdc061fa09bfbed96bbaf438cf051d343ed304870db13d5893529238dba5
../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/verified_checkpoint_resolution sha256:6dc98be34ae34a02069f644651abbf9eb90ac3117495895e83362faf32c12b76
../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/run_state sha256:3fbfc2cc5a79449fd05fce58e0fad25f6eef0ecde8314a222417a2e233db28c2
../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/execution_account_config sha256:12fabf23550cc9bb9ab5023865de0a8e6393a271d7f8c68d31fc1f6dfa41db20
../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/captured_run sha256:feed43823ca2721a948906e49866261d6dff991d20aec1dd7330ea7b433e86fd
../../../spec/contracts/actql-production-profile-schemas.json#/schemas/lookup_evidence sha256:4e50bf4d62354e45aca753d9f436e1002721c78604bcf2a7bfcf6365f8200dc5
```

<!-- stage-contract-pins:start -->
```text
../../../spec/contracts/actql-stage-contracts.json#/schemas/local_receipt sha256:00965a81fd89d80964295525f9f4f151cf7bc250f8f10539bfb4e83dc319d01a
../../../spec/contracts/actql-stage-contracts.json#/schemas/completion_evidence sha256:fb3a8c295b5069f4e7490ee97be9897d20e2ab97ca82874c9bb98146cf02fae7
../../../spec/contracts/actql-stage-contracts.json#/schemas/logical_request sha256:182296e19f04bbe04b1088213a20397486374ac42d9fd54379c9f942b33f649c
../../../spec/contracts/actql-stage-contracts.json#/schemas/risk_acceptance sha256:fc73a9f0e8db05f04bc47f74f5101a61496cc3341a8df73bc4d9e43ac522d570
../../../spec/contracts/actql-stage-contracts.json#/schemas/template_approval sha256:ef1ac71328e0a6483b2fae329cc56b5bde0920b086c3c1940de89186a45a9fca
../../../spec/contracts/actql-stage-contracts.json#/schemas/template_instantiation sha256:525028fdd701aab546c52f87aad69e008262f3107093d62361b8eadf2a2b0ac3
../../../spec/contracts/actql-stage-contracts.json#/schemas/approval_renewal sha256:f3e64e5cab0b7b74b00224fcd8011c129438bc4ea7e4258a1010442065ecf1b5
../../../spec/contracts/actql-stage-contracts.json#/schemas/source_advance_claim sha256:14ad763d0e911fadda97695d4ba50726ef9196a5ba41a6d3367295aaccd48c76
```
<!-- stage-contract-pins:end -->

<!-- lookup-identity-pins:start -->
```text
../../../spec/contracts/actql-lookup-identities.json#/evidence_slots sha256:d5257ad4c6368df06bdd720a132c1759b46ed0d3457b46e66e750b1f7f4aaa66
../../../spec/contracts/actql-lookup-identities.json#/laws sha256:c56618640aa84af330359c39433472fcafb476bef1f94323c3934ff49a8d508f
```
<!-- lookup-identity-pins:end -->


<a id="run-observation-revisions"></a>

### Run observation revisions and waiting

<!-- requirement-block: run-observation.state-revision -->
Every `actql-run-state/0.1` observation MUST carry a state-level nonnegative
safe-integer `revision`, monotonically advancing for published logical state,
control or Result-availability changes of that original Run and preserved
across restart and attach.
A read alone does not advance it. It is distinct from `control.revision`,
which tracks the cancellation-control owner. Exhaustion is refused rather
than wrapping or resetting a revision. A revision conveys neither approval
nor physical-stop evidence.

<!-- requirement-block: run-observation.wait-since -->
A `wait({since})` request MUST validate `since` as an observed state revision
and return a stable waiting or terminal observation whose revision is greater
than `since`, or an explicit timeout without a fabricated state change.
Without since, an already stable observation returns immediately. With since,
the same stable revision does not satisfy the wait. Status and wait use the
same original Run projection and current read authorization; neither starts,
resumes, reacquires or resends work to make progress visible.

<a id="original-read-only-continuation"></a>

### Original read-only submission continuation

<!-- requirement-block: original-read-only-continuation -->
An optional `readOnly: true` in the original Client submit packet and opaque
submitted intent MUST restrict that same Common preparation's complete checked
Effect inventory before Source acquisition, Model invocation, Effect Preview
or dispatch, including zero-row, unreachable and currently denied Effects.

<!-- requirement-block: original-read-only-identity -->
The restriction MUST participate in the original canonical fingerprint and
durable saved intent, preserving absent original bytes and CIDs, rejecting
false, null and unknown spellings, and treating a changed choice under the same
submission identity as an intent conflict rather than a replacement Run.

<!-- requirement-block: original-read-only-recovery -->
Recovery MUST preserve the restriction through the original saved intent and
Run/material admission, without inferring it from current configuration,
equal-CID data, a short-query label or a new preparation.

The choice is a continuation restriction, not Account authority. It does not
imply `stopBefore:commit`, and approval does not allow an Effect when both
choices occur. Effect-free Source and Model work keeps its original current
authorization, egress and resource requirements. General startSource behavior
without the field is unchanged. Node and Python short queries select the field
on that same original submit packet, not through a separate preflight request.

<a id="client-cancellation-observations"></a>

### Client cancellation observations

<!-- requirement-block: client-cancellation-observation -->
A Client cancellation response reports request acceptance (`accepted`), an
existing request (`already_requested`), or an observed terminal Run
(`already_terminal`), bound to the exact Run reference and control revision.
It MUST NOT assert physical stop merely because the request was accepted.

<!-- requirement-block: client-cancellation-start-exclusion -->
The Host MUST persist cancellation under the same exclusion boundary as a
physical start claim. An accepted cancellation before that claim prevents a
later start, including a resend or restart using the original request ID.

<!-- requirement-block: client-cancellation-control-observation client-cancellation-stop-evidence -->
The optional `control` member of `actql-run-state/0.1` contains the retained
control `revision`, `cancellation_requested`, and `physical_stop` (`unknown`
or `confirmed`). Absence means the Host does not supply this observation.
The Host MUST preserve one control revision across asynchronous publication
observation and MUST NOT infer physical stop from a missing worker or timeout.

<!-- requirement-block: client-cancellation-outcome -->
A cancellation confirmed before physical start can have outcome `cancelled`.
An accepted request after physical start MUST NOT rewrite a committed success
or an uncertain publication outcome. Physical stop confirmation remains
independent of Result availability and delivery completion.

<a id="installation-publication-storage-association"></a>

### Installation publication storage association

<!-- requirement-block: installation-publication-storage.closed-data installation-publication-storage.exact-store installation-publication-storage.identity installation-publication-storage.not-authority -->
The private `actql-installation-publication-storage-binding/0.1` DATA body MUST
contain exactly `key_generation_cid`, `private_namespace`, `store_authority_cid`,
`store_contract_wire` and `version`, with SHA-256 content identifiers for the two
CID fields and `publication-private` for `private_namespace`.
The embedded String MUST retain the exact existing Local Store contract bytes
in `version`, `isolation`, `store_authority_cid` order, with version
`actql-local-publication-store/0.1`, isolation `execution-namespace`, and the same
outer Store authority. Reordering or re-encoding that embedded contract is not
an equivalent original. The bounded Common reader MUST accept only the existing
canonical JSON encoding and the expected SHA-256 identity of the complete UTF-8
bytes without a self field or exclusions, refusing extra, missing, null,
duplicate, noncanonical or inconsistent fields and an unexpected identity.
This association MUST NOT be treated as an admitted Store, original metadata
observation, durable publication or generation admission, Credential use,
current authority, cleanup acknowledgement or physical resource funding.
Actual original Store membership and installation publication custody remain
independent duties of their existing consuming Owners; matching DATA or
public CIDs cannot manufacture those originals. Existing Model/Run evidence
purposes and bytes remain unchanged.

<!-- machine-import: ../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/installation_publication_storage_binding sha256:99aa1c53014df8cb2bbaeef9768d461d55a7fcf0e765f8cc1d7c0ee496565b0d -->

<a id="resident-effect-resume-transport"></a>

### Resident Effect resume transport

<!-- requirement-block: resident-effect-resume-routing resident-effect-resume-preservation -->
The `actql-remote-poll-effect-resume/0.1` envelope carries the exact original
Dispatch Request JSON and the report-bound Effect resume delivery JSON. Its
`dispatch_request_cid` MUST match both the admitted request identity and the
embedded delivery's dispatch identity. The envelope MUST NOT replace materials,
refresh the original Run lifetime, create an execution attempt or imply that the
transported claim is current authorization.

<!-- requirement-block: resident-effect-resume-admission resident-effect-resume-pending -->
Routing admission is distinct from approval and execution admission. The
retained holder MUST admit the unchanged delivery against its own durable
accepted Checkpoint report, independently installed authentication and current
resume fence before an Effect send. A missing receiving review Owner MUST leave
the original responsibility pending; receipt of the envelope is not execution,
settlement, publication or cleanup evidence. The inner delivery is limited to
262144 UTF-8 bytes and the canonical outer envelope to 1048576 UTF-8 bytes.


<a id="resident-effect-current-query"></a>

### Original resident Effect current queries

<!-- requirement-block: resident-effect-current-query-binding resident-effect-current-query-binding.2 resident-effect-current-query-binding.3 -->
`actql-remote-effect-current-query/0.1` MUST bind a fresh query ID, its canonical
CID, the original dispatch, accepted report, Checkpoint and checked Effect
member. The Host MUST obtain that member from the original checked Owner,
and the Native receiver MUST reject a different member or original report.
This query is not an execution attempt, approval or dispatch permission.

<!-- requirement-block: resident-effect-current-reply-binding resident-effect-current-reply-binding.2 resident-effect-current-reply-binding.3 resident-effect-current-reply-binding.4 -->
`actql-remote-effect-current-reply/0.1` MUST retain that exact query correlation,
the original report scope, optional original Ledger head, common recovery-action
code and saved-response presence. An absent head MUST have action 0 and no saved
response. A present head MUST have action 1, 3, 4, 5, 6 or 7; a prepared head
(action 1) MUST NOT claim saved response. Invalid or contradictory custody is a
refusal, never an empty successful observation. A saved response with possible
or unknown dispatch remains unresolved until its original Ledger terminal is
admitted; the response body and credential-use data stay private.

<!-- requirement-block: resident-effect-current-transport-freshness resident-effect-current-transport-freshness.2 resident-effect-current-transport-freshness.3 resident-effect-current-transport-freshness.4 -->
The receiving Host MUST authenticate the current Site/generation and match its
own outstanding query before using a reply as a current observation. It MUST
issue a fresh challenge after reconstruction; old saved replies are historical
evidence, not current facts. The Native receiver MUST authorize original evidence
access before Store reads and recheck it before disclosure. Query/reply admission
and canonical CID agreement MUST NOT imply current approval, permission to send,
physical stop, publication, cleanup completion or reservation return. Current
Run/cancellation/authority/holding and Ledger fences remain separate.

<a id="interactive-run-control"></a>

## Negotiated Interactive Run Control contracts

The initial `actql-interactive-run-control-registry/0.1` registers separate
controlled state, Plan/Run views, control Profile, original request intent,
resolved admission, logical map/ports, commands, immutable receipts, later
observations and typed Carrier Samples. Registration is not runtime support.
The four Sample projections are not full Carrier snapshots or Result schemas.
The existing compiler, Run, Checkpoint, Ledger, material and publication Owners
remain authoritative; a read projection does not decide lifecycle transitions.

<!-- requirement-block: interactive-original-intent interactive-legacy-projection interactive-control-cas interactive-receipt interactive-map interactive-sample interactive-observation interactive-pending-observation interactive-pending-unknown interactive-capability -->
Negotiated admission MUST first bind the original SubmissionRef, unchanged
legacy request fingerprint, normalized requested Profile and optional expected
Plan, then immutably bind that intent to the originally adopted Plan/map and
resolved Profile; a duplicate uses the original binding without preparation.

Legacy `actql-run-state/0.1`, legacy start and RunDefinition preimages MUST
remain unchanged; old status/wait use exact old-state projection or
`RunStateVersionUnsupported` for paused/manual-origin resuming, with genuine
Checkpoint/Resolution evidence required for formal-origin resuming.

Control intent MUST use the original Run and existing integer revision
`0..2147483647`/CAS fence, with `ControlRevisionExhausted` on exhaustion,
separate manual command/continuation/fence and actual Checkpoint/Resolution
origins, and no new authority, revision clock or automatic resend.

An initial OperationReceipt MUST remain immutable with accepted/completed/
unknown meaning at issue time, while later suppression or completion is a
separate original-receipt-linked observation; not-found/history-unavailable
is not permission to resend or proof of no acceptance.

Logical IDs and ports MUST bind the actual adopted Compiled Plan, checked
Stage/operation occurrence and role/ordinal, preserving input-only output
as `input_output` rather than a fabricated produced operation; exact names
and authorized input selection come from the original immutable map.

Sample contracts MUST preserve typed original source/capture identity,
Carrier kind, absence versus NULL, occurrence/order evidence and independent
finite holding claims, with forbidden containing no source/shape/count/ref,
selection-required for ambiguous input, and no acquisition or recomputation.

Run Inspect MUST use current read/egress authority and existing Owner-local
provenance, declaring non-atomic composition and unknown quantities rather
than a global synchronized cut, guessed zero usage or newly generated preview.
The negotiated `pause_pending`, `expiry_pending` and `cleanup_pending` fields
MUST be emitted as booleans only when obtained from their existing Owner.
An omitted field means an unknown observation and MUST NOT be completed as
`false`. Unsupported capability is separate from an unknown observation.

Installed capability publication MUST distinguish static planning/inspection,
durable control, Sample collection, full intermediates and cost Guards, and
advertise only independently implemented and publicly verified paths.

All new identity-bearing envelopes hash their complete canonical body excluding
only `self_cid`, using the existing SHA-256 canonical JSON rules. The version
field is the identity domain. No response, later observation or containing
receipt is included indirectly in its own preimage. New Profile is an external
binding, not a field added to old Program/Plan/RunDefinition bodies. Original
selector order is retained; effective target inventory is compiler-resolved
once. Control identity is not proof of authority or dispatch.

The logical Step key is `{version, compiled_plan_cid, stage_ordinal,
occurrence}` where occurrence is either operation ordinal or input-output port
ordinal. Port keys bind Plan, Step identity, role and port ordinal. Source
locators name the actual Stage input or original logical producer output.
Numbers here are checked semantic positions, not physical task numbers,
execution order, workers or retry counters. Schema validation and self-CID
validation are separate from matching referenced bodies and current authority.

Required retention resolves its entire checked target inventory before support
filtering. Optional deficiency stays an honest diagnostic, not a business
failure exemption for corruption or global resource violations. Sample-only,
full intermediate and required continuation claims have separate lifetimes.
Host-installed limits govern sizes/duration; wire integers do not invent a
global default budget. Four typed Sample schemas register no sampler.

Profile cost and interval override use distinct original cumulative origins;
real Checkpoints do not reset either. Unknown charges remain unknown, with
registered admission `GuardExceeded`/`GuardUnavailable` separate from paused
stop reasons. This registration implements neither a money estimator nor a
cost Guard. Batch control remains a separate unsupported advanced capability.

The new negotiated money amount domain is a canonical decimal **string** in
`0..9223372036854775807` micro-units. This finite range matches existing
Ledger `cost_units` checked Int64 aggregation; it is not a limit on general
mathematical Money or other language numeric domains. Zero is `"0"`; leading
zeros, signs, exponents, whitespace and fractions are invalid in `amount_micro`.
Exact facade decimal-unit normalization is separate: `USD:5.00` yields
`amount_micro="5000000"` without binary floating-point arithmetic. Overflow
is rejected, never wrapped or clamped; unknown is never converted to zero.

Currency syntax is three uppercase ASCII letters, following the alphabetic
code convention of [ISO 4217](https://www.iso.org/iso-4217-currency-codes.html).
Syntax alone does not certify a code or price. A future supported Guard must
strictly match its currency to the selected revision-bound tariff and covered
scope, including support and freshness. This registration creates neither a
currency Catalog nor a price Owner; read-only P1 advertises cost unsupported.

<a id="original-model-resource-state"></a>
## Original Model resource state

The private `original_model_state` Store role carries Model-bound original
resource evidence. Its owned binding artifact is
`actql-model-original-resource-state/0.1`; the role and wire version name
different abstraction levels. It has no self-CID or self-holding field.
The selected Store receipt content-addresses the complete bytes independently.
Registration alone establishes no restored Ledger, physical profile or send grant.

<!-- requirement-block: original-resource.closed-binding -->
The original checked Run/Model resource Owner MUST issue and validate the closed
origin against its original Run ID, RunDefinition CID, PreparedInvocation CID,
Host policy, execution context, Program and parameter identities, inference
barrier, selected immutable runtime/layout/response profile and actual private
Store binding, without deriving these facts from the decoded packet or current
configuration alone.

<!-- requirement-block: original-resource.original-bytes -->
The resource state CID MUST identify the existing Writer's exact UTF-8 bytes,
including the original decimal integer strings and positional record order,
without configuration normalization, reserialized aggregate usage or a self-CID cycle.

<!-- requirement-block: original-resource.preparation-not-current -->
A preparation-base document MUST remain original preparation evidence with a
null cut, never a current post-startup Ledger or a usable restoration grant.

<!-- requirement-block: original-resource.current-cut -->
The same Core resource/Model Owner MUST hold current-cut custody in its opaque
stable parked/stopping phase, bind a complete current census and the actual
Run version, full ordered Slot/Entry/settlement vector and resume-intent fence,
and invalidate the cut in the existing journal before unpark, entry or resource
mutation can proceed; Run version alone cannot establish unchanged resources.

<!-- requirement-block: original-resource.ack-and-admission -->
Restoration admission MUST verify the original selected namespace, key generation,
derived holding, actual Store acknowledgement, content CID and same-journal CAS,
then recheck every current fence after awaits before the original resource Owner
atomically admits exact reservation/holding/delegation/quantity/spent-serial state.

<!-- requirement-block: original-resource.no-send -->
Restored resource evidence MUST NOT grant Model send, change unknown attempts to
unsent, reset or refund original usage, repair old records with new grants or
replace the original current-authority and reconciliation checks.

<!-- requirement-block: original-resource.custody -->
Original Model state MUST retain its existing Store/cleanup custody while
Retained Result, unknown reconciliation or pending cleanup requires it, including
failed retirement/close and retry, rather than deriving safe disposal from a
generic terminal flag alone.

<!-- requirement-block: original-resource.bootstrap -->
The trusted installed physical envelope MUST fund metadata bytes, holding-entry
and directory acquisition, bounded codec and all simultaneous retained/workspace
before acquisition or allocation, refusing unavailable or unjustified supply
rather than substituting object-byte limits, guessed coefficients or spare limits.

The current state record separates consumed attempts from reserved attempts,
live reservations, live holdings and live delegations. Its serial-cursor tuple
retains the capacity, attempt and holding identity boundaries independently;
each reservation also records whether an attempt is reserved or already started.
These data fields do not replace the original Core checks of token identity,
quantity debt, currentness, complete census or physical cleanup.

<!-- machine-import: ../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/model_original_resource_state sha256:33b975b742274ca24e3997ec9c57762d4131de8659dd1111ad2d7e74671b3842 -->

<a id="effectful-static-plan-view"></a>

## Effectful static Plan projection

<!-- requirement-block: effectful-static.original effectful-static.component effectful-static.unobserved -->
An `actql-effectful-static-plan-view/0.1` issuer MUST read the same original
checked Effect preparation and compilation, retaining the Program and parameter
identities, Check Environment, computation Plan/map, unit and Effect occurrences
without accepting a caller's detached declaration snapshot as original custody.

The computation component MUST retain the existing PlanView and LogicalMap
bytes and identities, with its declared Mapping targets, Command Resource kinds
and Result/Table/no-row inputs remaining distinct from a full physical Effect
plan, resolved target or executable Run.

Actual target/value observations, current permission, gate and approval MUST
remain unknown and sealed Preview unavailable until their existing Owners
observe them; contract minimum none is not permission, required approval is
not human-only, and a Command's not-represented minimum is not none.

The envelope is static with provider I/O zero. Its projection does not start a
Run, acquire a Source, invoke a Model or dispatch a write. Existing readonly
disclosure authorization remains separate. Member/work and complete nested
read/emit limits apply together; registration advertises no installed capability.

<a id="scoped-durable-submission-names"></a>
## Scoped durable submission names

The closed `submit-named-intent` operation is an intentional initial contract
extension for a public request name. Its `requestName` uses the same bounded
caller-ID domain as an original submission nonce; it is not a Run ID or a grant.
The request also carries the ordinary original submitted intent and CID,
`attemptRef`, and a retained candidate `submissionRef` for a first binding.
The authenticated Host supplies the original workspace, actor and authority
scope, not caller-selected substitutes. Old explicit-epoch submission bytes,
canonical intent identities and exact-reference response validation are unchanged.

<!-- requirement-block: named-submission.atomic-original -->
The existing Journal Owner MUST atomically resolve or bind the authenticated
workspace/actor/name key to one original authenticated submission reference and
exact submitted intent before preparation or I/O, admitting only the first
confirmed insertion to preparation and refusing changed intent or authority scope.

<!-- requirement-block: named-submission.current-correlation -->
The Host MUST verify current authenticated scope before disclosure and after
awaits, correlate every named reply to its exact request name, intent and attempt,
and return the same original reference and outcome without interpreting the
candidate epoch, equal CID, caller name or lookup as new execution authority.

<!-- requirement-block: named-submission.unresolved-custody -->
Named custody MUST retain preparing, failed, unknown, corrupt, missing and retired
history behind the same original Journal fences and finite admission capacity,
without minting replacement work, evicting a consumed name into unused capacity,
automatically retrying preparation or inferring no prior execution from response loss.

An observed reply can contain the existing original initial check observation.
Later resolution is read-only observation, not a recreated check, renewed epoch
or continuation. A noncommitted refusal certifies only the selected attempt;
conflict cannot replace the retained intent. Existing deliberate risk-restart,
Run/Effect reconciliation, current authorization and resource rules remain separate.

The structural projections are `submission_name`
(`sha256:2c70e3f78e693a207550d3d6c57cf1a2cb26a5b0f7bcf89fea0044f666a26c4b`)
and `named_submission_attempt`
(`sha256:ce219bc256b0f466cef1245d078fdc056d45aaef1293517c3fd58812bb51e5e8`)
in the existing [Client–Host machine contract](../../../spec/contracts/actql-client-host.json).
The ordinary contract generator projects their validators and types; the
independent boundary vectors pin those exact bodies. These structural DATA
projections do not authenticate their contents or replace the Journal issuer.
