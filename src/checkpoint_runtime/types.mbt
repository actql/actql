///|
/// Bounds applied to every canonical artifact this package parses or emits.
pub(all) struct WireLimits {
  max_wire_bytes : Int
  max_nodes : Int
  max_depth : Int
} derive(Eq, Debug)

///|
/// Sealed decision subject of `actql-execution-checkpoint/0.1`.
/// `PrepareAttempt` always continues with `start_run`; `RunUnit` always
/// continues with `resume_unit`.
pub(all) enum CheckpointSubject {
  PrepareAttempt(String)
  RunUnit(String, String)
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
  run_id : String
  run_definition_cid : String
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
pub(all) struct HostAuthentication {
  key_id : String
  reviewer_id : String
  authority_context_cid : String
  policy_cid : String
} derive(Eq, Debug)

///|
/// One reviewer authority the Host permits to answer a specific Checkpoint.
pub(all) struct ReviewerAuthority {
  key_id : String
  reviewer_id : String
} derive(Eq, Debug)

///|
/// Admitted Resolution before the Host attests the verified wrapper.
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
