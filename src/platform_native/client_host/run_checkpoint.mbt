///|
/// Physical custody within the original Client journal. The common
/// Checkpoint Owner supplies closure, transition and resume-intent identities.
/// This record is neither a provider-send permit nor a cleanup receipt.
priv struct NativeClientCheckpointRecord {
  artifact : @checkpoint.SealedCheckpoint
  declared_results : Array[String]
  unknown_effects : Array[String]
  updated_at : String
  state : @checkpoint.RunStateView
  resolution_cid : String?
  verified_wire : String?
  resume_intent_id : String?
  resume_intent : @checkpoint.ResumeIntentView?
  settlement_only : Bool
  effect_ledger : Array[@effect.EffectLedgerEntry]
  binding : @checkpoint.ResumeBinding
}

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
fn checkpoint_optional_text(
  object : @decode.ObjectView,
  key : String,
) -> Result[String?, NativeClientCheckpointIssue] {
  match @decode.lookup(object, key) {
    Some(value) if @decode.is_null(value) => Ok(None)
    Some(value) =>
      @decode.text(value)
      .map(value => Some(value))
      .map_err(_ => InvalidMaterial)
    None => Err(InvalidMaterial)
  }
}

///|
fn checkpoint_wrapper_identity_valid(wire : String) -> Bool {
  try {
    let source = match
      @source.parse_json_bytes_preserving(@utf8.encode(wire), {
        max_input_bytes: 65536,
        max_nodes: 4096,
        max_depth: 64,
      }) {
      Ok(value) => value
      Err(_) => return false
    }
    let wrapper = @canonical.from_source(source, 4096, 64, 65536)
    guard @canonical.object_field(wrapper, "verified_resolution_cid")
      is Some(String(wrapper_cid)) &&
      @canonical.object_without_field(wrapper, "verified_resolution_cid")
      is Some(body) &&
      @canonical.object_field(wrapper, "resolution") is Some(resolution) &&
      @canonical.object_field(resolution, "resolution_cid")
      is Some(String(resolution_cid)) &&
      @canonical.object_without_field(resolution, "resolution_cid")
      is Some(resolution_body) else {
      return false
    }
    @canonical.cid_value(body, 65536, 4096, 64) == wrapper_cid &&
    @canonical.cid_value(resolution_body, 65536, 4096, 64) == resolution_cid
  } catch {
    _ => false
  }
}

///|
fn checkpoint_texts(
  object : @decode.ObjectView,
  key : String,
) -> Array[String]? {
  @decode.lookup(object, key).bind(value => {
    @decode.elements(value)
    .to_option()
    .bind(values => {
      if values.length() > 128 {
        return None
      }
      let texts : Array[String] = []
      for value in values {
        match @decode.text(value) {
          Ok(text) => texts.push(text)
          Err(_) => return None
        }
      }
      Some(texts)
    })
  })
}

///|
fn checkpoint_record_body(
  record : NativeClientCheckpointRecord,
) -> Result[String, NativeClientCheckpointIssue] {
  if record.declared_results.length() > 128 ||
    record.unknown_effects.length() > 128 ||
    record.effect_ledger.length() > 128 {
    return Err(InvalidMaterial)
  }
  try {
    let writer = @encode.writer(262144, 1024, 4)
    @encode.begin_object(writer)
    @encode.key(writer, "authorization_context_cid")
    @encode.string_value(writer, record.binding.authorization_context_cid)
    @encode.key(writer, "checkpoint")
    @encode.string_value(writer, record.artifact.wire)
    @encode.key(writer, "declared_results")
    @encode.begin_array(writer)
    for name in record.declared_results {
      @encode.string_value(writer, name)
    }
    @encode.end_array(writer)
    @encode.key(writer, "environment_binding_cid")
    @encode.string_value(writer, record.binding.environment_binding_cid)
    @encode.key(writer, "effect_ledger")
    @encode.begin_array(writer)
    for entry in record.effect_ledger {
      @encode.string_value(writer, @effect.effect_ledger_entry_wire(entry))
    }
    @encode.end_array(writer)
    for
      (key, value) in [
        ("resolution_cid", record.resolution_cid),
        ("resume_intent_id", record.resume_intent_id),
        ("verified_wire", record.verified_wire),
      ] {
      @encode.key(writer, key)
      match value {
        Some(value) => @encode.string_value(writer, value)
        None => @encode.null_value(writer)
      }
    }
    @encode.key(writer, "state")
    @encode.string_value(writer, record.state.wire)
    @encode.key(writer, "resume_intent")
    match record.resume_intent {
      Some(intent) =>
        @encode.string_value(writer, checkpoint_resume_body(intent))
      None => @encode.null_value(writer)
    }
    @encode.key(writer, "settlement_only")
    @encode.bool_value(writer, record.settlement_only)
    @encode.key(writer, "unknown_effects")
    @encode.begin_array(writer)
    for effect in record.unknown_effects {
      @encode.string_value(writer, effect)
    }
    @encode.end_array(writer)
    @encode.key(writer, "updated_at")
    @encode.string_value(writer, record.updated_at)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-native-client-checkpoint-row/0.1")
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => Err(InvalidMaterial)
  }
}

///|
fn read_checkpoint_record(
  wire : String,
  definition : @publication.PublicationContract,
) -> Result[NativeClientCheckpointRecord, NativeClientCheckpointIssue] {
  guard checkpoint_cursor(wire) is Some(cursor) &&
    @decode.closed_object(cursor, [
      "version", "checkpoint", "declared_results", "unknown_effects", "state", "updated_at",
      "authorization_context_cid", "environment_binding_cid", "resolution_cid", "verified_wire",
      "resume_intent_id", "resume_intent", "settlement_only", "effect_ledger",
    ])
    is Ok(object) &&
    epoch_text(object, "version") ==
    Some("actql-native-client-checkpoint-row/0.1") &&
    epoch_text(object, "checkpoint") is Some(checkpoint_wire) &&
    epoch_text(object, "state") is Some(state_wire) &&
    epoch_text(object, "updated_at") is Some(updated_at) &&
    epoch_text(object, "authorization_context_cid")
    is Some(authorization_context_cid) &&
    epoch_text(object, "environment_binding_cid")
    is Some(environment_binding_cid) &&
    checkpoint_texts(object, "declared_results") is Some(declared_results) &&
    checkpoint_texts(object, "unknown_effects") is Some(unknown_effects) &&
    checkpoint_texts(object, "effect_ledger") is Some(ledger_wires) else {
    return Err(InvalidMaterial)
  }
  let limits = native_checkpoint_limits()
  let artifact = match
    @checkpoint.admit_checkpoint_wire(checkpoint_wire, limits) {
    Ok(value) => value
    Err(_) => return Err(InvalidMaterial)
  }
  let state = match @checkpoint.admit_run_state_wire(state_wire, limits) {
    Ok(value) => value
    Err(_) => return Err(InvalidMaterial)
  }
  guard @publication.run_definition_run_id(definition) is Ok(run_id) &&
    artifact.checkpoint.run_id() == Some(run_id) &&
    artifact.checkpoint.run_definition_cid() ==
    Some(@publication.publication_contract_identity(definition)) &&
    state.run_id == run_id else {
    return Err(InvalidMaterial)
  }
  let resolution_cid = match
    checkpoint_optional_text(object, "resolution_cid") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let verified_wire = match checkpoint_optional_text(object, "verified_wire") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let resume_intent_id = match
    checkpoint_optional_text(object, "resume_intent_id") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let resume_intent = match checkpoint_optional_text(object, "resume_intent") {
    Ok(Some(wire)) =>
      match
        read_checkpoint_resume(wire, {
          authorization_context_cid,
          environment_binding_cid,
        }) {
        Some(intent) => Some(intent)
        None => return Err(InvalidMaterial)
      }
    Ok(None) => None
    Err(issue) => return Err(issue)
  }
  guard @decode.lookup(object, "settlement_only") is Some(settlement) &&
    @decode.boolean(settlement) is Ok(settlement_only) else {
    return Err(InvalidMaterial)
  }
  if (resume_intent_id is Some(_)) != (resume_intent is Some(_)) ||
    (
      settlement_only &&
      (
        resume_intent is None ||
        resume_intent.map(value => value.state) ==
        Some(@checkpoint.ResumePending)
      )
    ) {
    return Err(InvalidMaterial)
  }
  let expected = match (resolution_cid, verified_wire) {
    (None, None) if resume_intent_id is None => {
      let persisted = @checkpoint.confirm_checkpoint_persisted(
        artifact,
        artifact.wire,
      ).unwrap()
      @checkpoint.issue_waiting_run_state(
        persisted, updated_at, declared_results, limits,
      )
    }
    (Some(cid), Some(verified)) => {
      guard checkpoint_wrapper_identity_valid(verified) &&
        @checkpoint.verified_resolution_attestation_preimage(verified, limits)
        is Ok(_) &&
        checkpoint_cursor(verified) is Some(wrapper) &&
        @decode.open_object(wrapper) is Ok(wrapper) &&
        @decode.lookup(wrapper, "resolution") is Some(resolution) &&
        @decode.open_object(resolution) is Ok(resolution) &&
        epoch_text(resolution, "resolution_cid") == Some(cid) &&
        epoch_text(resolution, "checkpoint_cid") ==
        Some(artifact.checkpoint_cid) else {
        return Err(InvalidMaterial)
      }
      match epoch_text(resolution, "decision") {
        Some("approved") if resume_intent_id ==
          @checkpoint.resume_intent_id(artifact.checkpoint_cid, cid, limits) =>
          @checkpoint.issue_lifecycle_run_state(
            run_id,
            Resuming,
            updated_at,
            declared_results,
            limits,
          )
        Some("rejected") if resume_intent_id is None =>
          @checkpoint.issue_waiting_exit_run_state(
            run_id, updated_at, declared_results, unknown_effects, limits,
          )
        _ => return Err(InvalidMaterial)
      }
    }
    _ => return Err(InvalidMaterial)
  }
  if expected != Ok(state_wire) {
    return Err(InvalidMaterial)
  }
  let effect_ledger : Array[@effect.EffectLedgerEntry] = []
  for wire in ledger_wires {
    let limits = native_client_effect_ledger_limits()
    guard @effect.admit_effect_ledger_entry(
        wire,
        limits.max_wire_bytes,
        limits.max_nodes,
        limits.max_depth,
      )
      is Ok(entry) &&
      entry.effect_preview_cid == artifact.checkpoint.required_artifact_cid else {
      return Err(InvalidMaterial)
    }
    let prior = effect_ledger_head(
      effect_ledger,
      entry.logical_item_locator_cid,
    )
    if !@effect.effect_ledger_entry_follows(prior, entry) {
      return Err(InvalidMaterial)
    }
    effect_ledger.push(entry)
  }
  if !effect_ledger.is_empty() &&
    resume_intent.map(value => value.state) != Some(@checkpoint.ResumeClaimed) {
    return Err(InvalidMaterial)
  }
  let record : NativeClientCheckpointRecord = {
    artifact,
    declared_results,
    unknown_effects,
    state,
    updated_at,
    resolution_cid,
    verified_wire,
    resume_intent_id,
    resume_intent,
    settlement_only,
    effect_ledger,
    binding: { authorization_context_cid, environment_binding_cid, },
  }
  guard checkpoint_cursor(@publication.publication_contract_json(definition))
    is Some(definition_cursor) &&
    @decode.open_object(definition_cursor) is Ok(definition_object) &&
    epoch_text(definition_object, "authorization_context_cid") ==
    Some(authorization_context_cid) else {
    return Err(InvalidMaterial)
  }
  if @checkpoint.decide_resume_claim(
      {
        state: ResumePending,
        generation: 0L,
        claimant: "",
        lease_expires_ms: 0L,
      },
      "binding-validation",
      0L,
      1L,
      record.binding,
      record.binding,
    )
    is Err(_) {
    return Err(InvalidMaterial)
  }
  if @checkpoint.issue_waiting_exit_run_state(
      run_id, updated_at, declared_results, unknown_effects, limits,
    )
    is Err(_) {
    return Err(InvalidMaterial)
  }
  match checkpoint_record_body(record) {
    Ok(expected) if expected == wire => Ok(record)
    _ => Err(InvalidMaterial)
  }
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
  if !current() {
    return Err(AuthorizationDenied)
  }
  let before = match self.lookup(request, true) {
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
  self.transaction(() => {
    let record = match self.retained(request) {
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
    self.save({
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
    })
  })
}
