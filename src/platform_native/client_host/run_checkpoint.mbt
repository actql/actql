///|
/// Physical custody within the original Client journal. The common
/// Checkpoint Owner supplies closure, transition and resume-intent identities.
/// This record is neither a provider-send permit nor a cleanup receipt.
type NativeClientCheckpointRecord = @host.ClientCheckpointJournalRecord

///|
pub(all) enum NativeClientCheckpointIssue {
  InvalidMaterial
  StaleRevision
  ConflictingResolution
  Expired
  NeedsOriginalContinuation
  State(@checkpoint.RunStateWireIssue)
  Signature(@effect_resolution.NativeResidentEffectResolutionIssue)
  Resume(@checkpoint.ResumeIssue)
  Ledger(@effect.EffectLedgerIssue)
  EffectBinding(@host.ClientEffectCheckpointBindingIssue)
}

///|
fn native_checkpoint_limits() -> @checkpoint.WireLimits {
  { max_wire_bytes: 65536, max_nodes: 4096, max_depth: 64, }
}

///|
fn checkpoint_cursor(wire : String) -> @decode.Cursor? {
  @source.parse_json_bytes_preserving(@utf8.encode(wire), {
    max_input_bytes: 262144,
    max_nodes: 4096,
    max_depth: 64,
  })
  .to_option()
  .bind(source => {
    @decode.admit(source, {
      max_nodes: 4096,
      max_depth: 64,
      max_string_bytes: 262144,
      max_total_string_bytes: 262144,
    }).to_option()
  })
}

///|
fn checkpoint_record_body(
  record : NativeClientCheckpointRecord,
) -> Result[String, NativeClientCheckpointIssue] {
  @host.client_checkpoint_journal_row_body(record).map_err(_ => InvalidMaterial)
}

///|
fn read_checkpoint_record(
  wire : String,
  definition : @publication.PublicationContract,
) -> Result[NativeClientCheckpointRecord, NativeClientCheckpointIssue] {
  @host.decode_client_checkpoint_journal_row(
    wire,
    definition,
    native_client_effect_ledger_limits(),
  ).map_err(_ => InvalidMaterial)
}

///|
pub fn native_client_run_checkpoint_state(
  record : NativeClientRunRecord,
) -> @checkpoint.RunStateView? {
  record.checkpoint.map(value => value.state)
}

///|
/// Persist the already-confirmed original Checkpoint and waiting projection
/// with the Run revision. Its retained continuation remains owned by Store;
/// no continuation is reconstructed from a current configuration or row index.
pub fn NativeClientRunJournal::wait_checkpoint(
  self : NativeClientRunJournal,
  request : @host.ClientRequestIdentity,
  compiled : @host.ClientCompiledRun,
  persisted : @checkpoint.PersistedCheckpoint,
  expected_revision : Int64,
  binding : @checkpoint.ResumeBinding,
  unknown_effects : Array[String],
  updated_at : String,
  current : () -> Bool,
) -> Result[NativeClientRunRecord, NativeClientRunJournalIssue] {
  self.wait_original_checkpoint(
    request,
    persisted,
    expected_revision,
    binding,
    unknown_effects,
    updated_at,
    current,
    definition => {
      if @host.check_client_compiled_run_definition(compiled, definition)
        is Err(_) {
        return Err(Checkpoint(InvalidMaterial))
      }
      Ok(@host.client_compiled_run_result_names(compiled))
    },
  )
}

///|
/// The actual checked Effect Run supplies its original unit and Result
/// inventory. The shared Checkpoint Owner admits its sealed review; the same
/// Client transaction commits waiting and independent custody. This is not a
/// Preview persistence proof, approval, reconstructed continuation or send.
pub fn NativeClientRunJournal::wait_effect_checkpoint(
  self : NativeClientRunJournal,
  request : @host.ClientRequestIdentity,
  allowed : @host.ClientEffectAllowedRun,
  persisted : @checkpoint.PersistedCheckpoint,
  expected_revision : Int64,
  binding : @checkpoint.ResumeBinding,
  unknown_effects : Array[String],
  updated_at : String,
  current : () -> Bool,
) -> Result[NativeClientRunRecord, NativeClientRunJournalIssue] {
  self.wait_effect_checkpoint_with_operations(
    request, allowed, persisted, expected_revision, binding, unknown_effects, updated_at,
    current,
  )
}

///|
// Same checked Owner and transition; optional original I/O changes no law.
fn NativeClientRunJournal::wait_effect_checkpoint_with_operations(
  self : NativeClientRunJournal,
  request : @host.ClientRequestIdentity,
  allowed : @host.ClientEffectAllowedRun,
  persisted : @checkpoint.PersistedCheckpoint,
  expected_revision : Int64,
  binding : @checkpoint.ResumeBinding,
  unknown_effects : Array[String],
  updated_at : String,
  current : () -> Bool,
  operations? : NativeClientJournalOperationAccess? = None,
) -> Result[NativeClientRunRecord, NativeClientRunJournalIssue] {
  self.wait_original_checkpoint(
    request,
    persisted,
    expected_revision,
    binding,
    unknown_effects,
    updated_at,
    current,
    definition => {
      let prepared = @host.client_effect_compilation_owner(allowed.compilation)
      let identity = @host.prepared_client_effect_identity(prepared)
      if @host.client_request_program_cid(request) !=
        identity.program_definition_cid ||
        @host.client_request_parameters_cid(request) !=
        identity.parameter_values_cid {
        return Err(Checkpoint(InvalidMaterial))
      }
      match
        @host.admit_client_effect_review_checkpoint_binding(
          allowed,
          definition,
          persisted.artifact.wire,
          native_checkpoint_limits(),
        ) {
        Ok(_) => ()
        Err(issue) => return Err(Checkpoint(EffectBinding(issue)))
      }
      let stages = @syntax.stages(
        @host.prepared_client_effect_computation_source(prepared),
      )
      if unknown_effects.any(name => {
          !stages.any(stage => @syntax.effect_names(stage).contains(name))
        }) {
        return Err(Checkpoint(InvalidMaterial))
      }
      let results : Array[String] = []
      for index in 0..<@host.prepared_client_effect_result_count(prepared) {
        guard @host.prepared_client_effect_result_name(prepared, index)
          is Some(name) else {
          return Err(Checkpoint(InvalidMaterial))
        }
        results.push(name)
      }
      Ok(results)
    },
    operations~,
  )
}

///|
/// Family-specific checked owners validate the exact retained definition and
/// supply their declared Results inside this single original transaction.
fn NativeClientRunJournal::wait_original_checkpoint(
  self : NativeClientRunJournal,
  request : @host.ClientRequestIdentity,
  persisted : @checkpoint.PersistedCheckpoint,
  expected_revision : Int64,
  binding : @checkpoint.ResumeBinding,
  unknown_effects : Array[String],
  updated_at : String,
  current : () -> Bool,
  validate_owner : (@publication.PublicationContract) -> Result[
    Array[String],
    NativeClientRunJournalIssue,
  ],
  operations? : NativeClientJournalOperationAccess? = None,
) -> Result[NativeClientRunRecord, NativeClientRunJournalIssue] {
  if unknown_effects.length() > 128 ||
    unknown_effects.any(value => value.length() > 65536) {
    return Err(Checkpoint(InvalidMaterial))
  }
  if !current() {
    return Err(AuthorizationDenied)
  }
  let reads = operations.map(value => value.reads)
  self.transaction_with_reads(
    () => {
      let record = match self.retained(request, reads~) {
        Ok(Some(value)) => value
        Ok(None) => return Err(CustodyLost)
        Err(issue) => return Err(issue)
      }
      if record.revision != expected_revision {
        return Err(Checkpoint(StaleRevision))
      }
      let artifact = persisted.artifact
      let declared_results = match validate_owner(record.definition) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      guard @publication.run_definition_run_id(record.definition) is Ok(run_id) &&
        artifact.checkpoint.run_id() == Some(run_id) &&
        artifact.checkpoint.run_definition_cid() ==
        Some(@publication.publication_contract_identity(record.definition)) &&
        record.physical_start_claimed &&
        !record.cancellation_requested else {
        return Err(Checkpoint(InvalidMaterial))
      }
      if record.checkpoint is Some(_) {
        return Err(Checkpoint(NeedsOriginalContinuation))
      }
      if updated_at < artifact.checkpoint.created_at ||
        @checkpoint.checkpoint_expired_at(artifact, updated_at) != Ok(false) {
        return Err(Checkpoint(Expired))
      }
      let wire = match
        @checkpoint.issue_waiting_run_state(
          persisted,
          updated_at,
          declared_results,
          native_checkpoint_limits(),
        ) {
        Ok(value) => value
        Err(issue) => return Err(Checkpoint(State(issue)))
      }
      let checkpoint : NativeClientCheckpointRecord = {
        artifact,
        declared_results,
        unknown_effects: unknown_effects.copy(),
        updated_at,
        state: @checkpoint.admit_run_state_wire(
          wire,
          native_checkpoint_limits(),
        ).unwrap(),
        binding,
        resolution_cid: None,
        verified_wire: None,
        resume_intent_id: None,
        resume_intent: None,
        settlement_only: false,
        effect_ledger: [],
      }
      // Reject a projection which could not be safely restored before commit.
      let body = match checkpoint_record_body(checkpoint) {
        Ok(value) => value
        Err(issue) => return Err(Checkpoint(issue))
      }
      if read_checkpoint_record(body, record.definition) is Err(_) {
        return Err(Checkpoint(InvalidMaterial))
      }
      let next = { ..record, checkpoint: Some(checkpoint), }
      match
        insert_client_journal_value(
          self.database,
          "client_effect_custody",
          @host.client_request_scope_cid(request),
          effect_ledger_custody_body(next).unwrap(),
          operations,
        ) {
        Ok(_) => ()
        Err(issue) => return Err(Physical(issue))
      }
      self.save_with_operations(next, operations~)
    },
    reads~,
  )
}

///|
/// Verify installed Native Host signatures and current reviewer authority,
/// then commit closure, Run projection and the common resume identity in one
/// original journal transaction. Returning Resuming is not permission to send.
pub fn NativeClientRunJournal::resolve_effect_checkpoint(
  self : NativeClientRunJournal,
  request : @host.ClientRequestIdentity,
  crypto : @crypto.Library,
  verified_wire : String,
  authentication : @checkpoint.HostAuthentication,
  reviewers : Array[@checkpoint.ReviewerAuthority],
  keys : Array[@effect_resolution.NativeEffectHostAuthority],
  current : () -> Bool,
  now : () -> String,
) -> Result[NativeClientRunRecord, NativeClientRunJournalIssue] {
  self.resolve_effect_checkpoint_with_operations(
    request,
    crypto,
    verified_wire,
    authentication,
    reviewers,
    keys,
    current,
    now,
    None,
  )
}

///|
// The same original operation, with its existing bounded SQL/constructor
// routes. None preserves the unchanged public legacy codec profile.
fn NativeClientRunJournal::resolve_effect_checkpoint_with_operations(
  self : NativeClientRunJournal,
  request : @host.ClientRequestIdentity,
  crypto : @crypto.Library,
  verified_wire : String,
  authentication : @checkpoint.HostAuthentication,
  reviewers : Array[@checkpoint.ReviewerAuthority],
  keys : Array[@effect_resolution.NativeEffectHostAuthority],
  current : () -> Bool,
  now : () -> String,
  operations : NativeClientJournalOperationAccess?,
) -> Result[NativeClientRunRecord, NativeClientRunJournalIssue] {
  if !current() {
    return Err(AuthorizationDenied)
  }
  if operations is Some(original) &&
    !physical_equal(self.database, original.reads.database) {
    return Err(CustodyLost)
  }
  let reads = operations.map(original => original.reads)
  let before = match self.lookup_with_reads(request, true, reads~) {
    Ok(Retained(value)) => value
    Ok(_) => return Err(CustodyLost)
    Err(issue) => return Err(issue)
  }
  guard before.checkpoint is Some(original) else {
    return Err(Checkpoint(InvalidMaterial))
  }
  let verified = match
    @effect_resolution.admit_native_effect_resolution(
      crypto,
      original.artifact,
      verified_wire,
      authentication,
      reviewers,
      keys,
      current,
      native_checkpoint_limits(),
    ) {
    Ok(value) => value
    Err(issue) => return Err(Checkpoint(Signature(issue)))
  }
  let updated_at = now()
  if !current() {
    return Err(AuthorizationDenied)
  }
  self.transaction_with_reads(
    () => {
      let record = match self.retained(request, reads~) {
        Ok(Some(value)) => value
        Ok(None) => return Err(CustodyLost)
        Err(issue) => return Err(issue)
      }
      if record.revision != before.revision {
        return Err(Checkpoint(StaleRevision))
      }
      guard record.checkpoint is Some(checkpoint) else {
        return Err(Checkpoint(InvalidMaterial))
      }
      let closure = match checkpoint.resolution_cid {
        Some(cid) => @checkpoint.CheckpointClosure::Resolved(cid)
        None => @checkpoint.CheckpointClosure::Open
      }
      match
        @checkpoint.decide_resolution_commit(
          checkpoint.artifact,
          closure,
          verified,
        ) {
        DuplicateResolution => return Ok(record)
        ConflictingResolution => return Err(Checkpoint(ConflictingResolution))
        CheckpointExpired => return Err(Checkpoint(Expired))
        CommitResolution => ()
      }
      // Historical verification cannot extend an open Checkpoint's answer
      // deadline. Duplicates above still identify the original durable answer.
      match @checkpoint.checkpoint_expired_at(checkpoint.artifact, updated_at) {
        Ok(false) => ()
        _ => return Err(Checkpoint(Expired))
      }
      if record.cancellation_requested &&
        verified.decision == @checkpoint.Approved {
        return Err(Checkpoint(NeedsOriginalContinuation))
      }
      let next = match
        @checkpoint.resolution_effect(
          checkpoint.artifact,
          verified.decision,
          unknown_effects=checkpoint.unknown_effects,
        ) {
        MoveRun(value) => value
        _ => return Err(Checkpoint(InvalidMaterial))
      }
      if !@checkpoint.run_transition_allowed(checkpoint.state.status, next) {
        return Err(Checkpoint(InvalidMaterial))
      }
      let wire = if verified.decision == @checkpoint.Approved {
        @checkpoint.issue_lifecycle_run_state(
          checkpoint.state.run_id,
          next,
          updated_at,
          checkpoint.declared_results,
          native_checkpoint_limits(),
        )
      } else {
        @checkpoint.issue_waiting_exit_run_state(
          checkpoint.state.run_id,
          updated_at,
          checkpoint.declared_results,
          checkpoint.unknown_effects,
          native_checkpoint_limits(),
        )
      }
      let wire = match wire {
        Ok(value) => value
        Err(issue) => return Err(Checkpoint(State(issue)))
      }
      self.save_with_operations(
        {
          ..record,
          checkpoint: Some({
            ..checkpoint,
            updated_at,
            state: @checkpoint.admit_run_state_wire(
              wire,
              native_checkpoint_limits(),
            ).unwrap(),
            resolution_cid: Some(verified.resolution_cid),
            verified_wire: Some(verified.wire),
            resume_intent_id: verified.resume_intent_id,
            resume_intent: verified.resume_intent_id.map(_ => {
              state: @checkpoint.ResumePending,
              generation: 0L,
              claimant: "",
              lease_expires_ms: 0L,
            }),
            settlement_only: false,
          }),
        },
        operations~,
      )
    },
    reads~,
  )
}
