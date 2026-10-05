///|
/// Bounds applied to every canonical artifact this package parses or emits.
pub(all) struct WireLimits {
  max_wire_bytes : Int
  max_nodes : Int
  max_depth : Int
} derive(Eq, Debug)

///|
/// Sealed decision subject of `actql-execution-checkpoint/0.1`.
/// `PrepareAttempt` always continues with `start_run` and binds no Run: there
/// is no Run or Run Definition before the preparation continues.
/// `RunUnit` always continues with `resume_unit` and binds the Run, its unit
/// and the immutable Run Definition CID (the top-level `run_id` and
/// `run_definition_cid` members of the wire).
pub(all) enum CheckpointSubject {
  PrepareAttempt(prepare_attempt_id~ : String)
  RunUnit(run_id~ : String, unit_id~ : String, run_definition_cid~ : String)
} derive(Eq, Debug)

///|
pub(all) enum CheckpointPhase {
  Preflight
  Commit
} derive(Eq, Debug)

///|
pub(all) enum CheckpointKind {
  RunScope
  ReadAccess
  DataEgress
  CostScope
  ModelInvocation
  EffectSet
} derive(Eq, Debug)

///|
/// Requirement claims are carried as data in the sealed Checkpoint. Which list
/// a Host requires is decided before issuance; this package only enforces the
/// closed per-kind lists accepted by the pinned schema.
pub(all) enum CheckpointRequirement {
  EffectScopeApproved
  InvocationScopeApproved
  PartialApplicationAccepted
} derive(Eq, Debug)

///|
/// Body of an execution Checkpoint before its self CID is computed.
pub(all) struct CheckpointRequest {
  checkpoint_id : String
  continuation_state_cid : String
  subject : CheckpointSubject
  phase : CheckpointPhase
  kind : CheckpointKind
  required_artifact_cid : String
  review_projection_cid : String
  requirements : Array[CheckpointRequirement]
  reason_code : String
  human_summary : String
  created_at : String
  expires_at : String
} derive(Eq, Debug)

///|
/// Canonical Checkpoint artifact with its verified self CID. Only this package
/// constructs it, from a request or from an admitted stored wire.
pub struct SealedCheckpoint {
  checkpoint : CheckpointRequest
  checkpoint_cid : String
  wire : String
} derive(Eq, Debug)

///|
/// Proof that the exact sealed wire was read back from committed durable
/// storage. Only a persisted Checkpoint can be projected as waiting.
pub struct PersistedCheckpoint {
  artifact : SealedCheckpoint
} derive(Eq, Debug)

///|
pub(all) enum CheckpointIssue {
  InvalidLimits
  InvalidWire
  InvalidObject
  MissingField(String)
  UnknownField(String)
  InvalidField(String)
  UnsupportedCombination
  InvalidRequirements
  InvalidTimeWindow
  IdentityMismatch
  PersistedWireMismatch
  Encoding
} derive(Eq, Debug)

///|
pub(all) enum ResolutionDecision {
  Approved
  Rejected
} derive(Eq, Debug)

///|
/// Result of the Host authorization port. The Host adapter authenticates the
/// Resolution proof and reviewer authority with Host-trusted keys; this
/// package checks that the reported identities agree with the Resolution and
/// with the authority set the Host bound to the Checkpoint.
///
/// `proof_preimage` is the exact text whose `proof.signature` the port
/// verified. It must be the unsigned Resolution CID text
/// (`resolution_proof_preimage`), so a port that verified any other bytes is
/// rejected.
pub(all) struct HostAuthentication {
  key_id : String
  reviewer_id : String
  expected_authority_scope_cid : String
  authority_context_cid : String
  policy_cid : String
  proof_preimage : String
} derive(Eq, Debug)

///|
/// One reviewer authority the Host permits to answer a specific Checkpoint.
pub(all) struct ReviewerAuthority {
  key_id : String
  reviewer_id : String
} derive(Eq, Debug)

///|
/// Admitted Resolution before the Host attests the verified wrapper.
/// `attestation_preimage` is the unsigned verified-wrapper CID text: the CID
/// of the wrapper without `host_attestation` and `verified_resolution_cid`.
/// The Host signs its UTF-8 bytes with Ed25519.
pub struct AdmittedResolution {
  checkpoint_cid : String
  resolution_id : String
  resolution_cid : String
  decision : ResolutionDecision
  attestation_preimage : String
  priv body : @json.CanonicalValue
}

///|
/// Canonical `actql-verified-checkpoint-resolution/0.1` record.
pub struct VerifiedResolution {
  checkpoint_cid : String
  resolution_id : String
  resolution_cid : String
  decision : ResolutionDecision
  verified_resolution_cid : String
  verified_at : String
  wire : String
  resume_intent_id : String?
} derive(Eq, Debug)

///|
/// Permission a committed approved verified Resolution grants a resumed
/// continuation: the verified reviewer, the claims its approval evidence
/// establishes, and, for a run-scope style approval, the instant from which
/// it no longer authorizes new work. An Effect Set attestation carries no
/// expiry of its own (`expires_at` is `None`).
pub struct ResumedApproval {
  checkpoint_cid : String
  resolution_cid : String
  verified_resolution_cid : String
  reviewer_id : String
  claims : Array[String]
  expires_at : String?
} derive(Eq, Debug)

///|
/// An immediate delegated answer admitted against the Checkpoint body the Host
/// would persist if it deferred. It is not bound to a persisted Checkpoint:
/// no function accepts it as a Checkpoint, a waiting state or a commit
/// candidate, and it never yields a resume intent.
pub struct ImmediateAdmittedResolution {
  priv admitted : AdmittedResolution
}

///|
/// Host-verified immediate permit or reject. It is the retained decision
/// evidence of the permitted or rejected unit: the Checkpoint body was not
/// persisted, the Run does not enter `waiting_checkpoint`, and there is no
/// resume intent. Its type is distinct from `VerifiedResolution`, so it
/// cannot be committed by `decide_resolution_commit`.
pub struct ImmediateResolution {
  checkpoint_cid : String
  resolution_id : String
  resolution_cid : String
  decision : ResolutionDecision
  verified_resolution_cid : String
  verified_at : String
  wire : String
} derive(Eq, Debug)

///|
/// What committing a verified Resolution does to the Checkpoint's subject.
pub(all) enum ResolutionEffect {
  /// A Run-unit Checkpoint: `waiting_checkpoint` moves to this status.
  MoveRun(@publication.RunOutcomeStatus)
  /// An approved preparation Checkpoint: the same preparation attempt
  /// continues through its resume intent; no Run exists yet.
  ContinuePreparation
  /// A rejected preparation Checkpoint: the attempt ends and no Run is
  /// created.
  EndPreparation
} derive(Eq, Debug)

///|
pub(all) enum ResolutionIssue {
  ResolutionInvalidLimits
  ResolutionInvalidWire
  ResolutionInvalidObject
  ResolutionMissingField(String)
  ResolutionUnknownField(String)
  ResolutionInvalidField(String)
  ResolutionIdentityMismatch
  CheckpointBindingMismatch(String)
  DecisionOutsideWindow
  DecisionAfterVerification
  EvidenceRequired
  EvidenceForbidden
  EvidenceMismatch(String)
  AuthenticationMismatch(String)
  AuthorityNotPermitted
  InvalidAttestation
  ResolutionEncoding
} derive(Eq, Debug)

///|
/// Durable closure state of one Checkpoint as read inside the store
/// transaction that decides a Resolution or expiry.
pub(all) enum CheckpointClosure {
  Open
  Resolved(String)
  Expired
} derive(Eq, Debug)

///|
pub(all) enum ResolutionCommitAction {
  CommitResolution
  DuplicateResolution
  ConflictingResolution
  CheckpointExpired
} derive(Eq, Debug)

///|
pub(all) enum ResumeIntentState {
  ResumePending
  ResumeClaimed
  ResumeCompleted
} derive(Eq, Debug)

///|
/// Stored resume intent fields read inside the store transaction.
/// `generation` is the fencing token; 0 means never claimed.
pub(all) struct ResumeIntentView {
  state : ResumeIntentState
  generation : Int64
  claimant : String
  lease_expires_ms : Int64
} derive(Eq, Debug)

///|
pub(all) struct ResumeClaim {
  claimant : String
  generation : Int64
} derive(Eq, Debug)

///|
/// Authorization-context and environment-binding identities that must be
/// unchanged before a delayed continuation is dispatched.
pub(all) struct ResumeBinding {
  authorization_context_cid : String
  environment_binding_cid : String
} derive(Eq, Debug)

///|
pub(all) enum ResumeClaimAction {
  /// Take the intent with this new fencing generation and lease expiry.
  ClaimIntent(Int64, Int64)
  /// A current claimant holds an unexpired lease.
  ClaimBusy
  /// The intent was already completed with its Run transition.
  ClaimCompleted
  /// Bound facts changed while waiting: complete the intent together with
  /// `resuming -> failed`, dispatching nothing.
  ClaimInvalidated(Int64)
} derive(Eq, Debug)

///|
pub(all) enum ResumeFenceAction {
  /// The caller is the current, unexpired claimant.
  FenceCurrent
  /// Superseded, expired, unknown, or already completed: no mutation.
  FenceStale
} derive(Eq, Debug)

///|
pub(all) enum ResumeIssue {
  InvalidClaimant
  InvalidLease
  InvalidClock
  InvalidBinding
  InvalidIntent
} derive(Eq, Debug)

///|
/// Admitted `actql-run-state/0.1` projection fields needed by the journal.
pub struct RunStateView {
  run_id : String
  status : @publication.RunOutcomeStatus
  checkpoint_cid : String?
  wire : String
} derive(Eq, Debug)

///|
pub(all) enum RunStateWireIssue {
  RunStateInvalidWire
  RunStateInvalidField(String)
  RunStateUnknownField(String)
  RunStateMissingField(String)
  RunStateRelation(@publication.RunStateIssue)
  RunStateEncoding
} derive(Eq, Debug)
