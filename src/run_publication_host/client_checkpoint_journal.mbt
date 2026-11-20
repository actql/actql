///|
/// Complete existing physical checkpoint row. These admitted originals do not
/// issue custody, a signature, a resume claim or a physical cleanup receipt.
pub(all) struct ClientCheckpointJournalRecord {
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
pub(all) enum ClientCheckpointJournalIssue {
  InvalidMaterial
} derive(Eq, Debug)

///|
fn client_checkpoint_journal_limits() -> @checkpoint.WireLimits {
  { max_wire_bytes: 65536, max_nodes: 4096, max_depth: 64, }
}

///|
fn client_checkpoint_cursor(wire : String) -> @decode.Cursor? {
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
fn client_checkpoint_optional_text(
  object : @decode.ObjectView,
  key : String,
) -> Result[String?, ClientCheckpointJournalIssue] {
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
fn client_checkpoint_wrapper_identity_valid(wire : String) -> Bool {
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
fn client_checkpoint_texts(
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
pub fn client_checkpoint_journal_row_body(
  record : ClientCheckpointJournalRecord,
) -> Result[String, ClientCheckpointJournalIssue] {
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
        @encode.string_value(writer, client_checkpoint_resume_row_body(intent))
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
pub fn decode_client_checkpoint_journal_row(
  wire : String,
  definition : @publication.PublicationContract,
  ledger_limits : @checkpoint.WireLimits,
) -> Result[ClientCheckpointJournalRecord, ClientCheckpointJournalIssue] {
  guard client_checkpoint_cursor(wire) is Some(cursor) &&
    @decode.closed_object(cursor, [
      "version", "checkpoint", "declared_results", "unknown_effects", "state", "updated_at",
      "authorization_context_cid", "environment_binding_cid", "resolution_cid", "verified_wire",
      "resume_intent_id", "resume_intent", "settlement_only", "effect_ledger",
    ])
    is Ok(object) &&
    client_checkpoint_text(object, "version") ==
    Some("actql-native-client-checkpoint-row/0.1") &&
    client_checkpoint_text(object, "checkpoint") is Some(checkpoint_wire) &&
    client_checkpoint_text(object, "state") is Some(state_wire) &&
    client_checkpoint_text(object, "updated_at") is Some(updated_at) &&
    client_checkpoint_text(object, "authorization_context_cid")
    is Some(authorization_context_cid) &&
    client_checkpoint_text(object, "environment_binding_cid")
    is Some(environment_binding_cid) &&
    client_checkpoint_texts(object, "declared_results")
    is Some(declared_results) &&
    client_checkpoint_texts(object, "unknown_effects") is Some(unknown_effects) &&
    client_checkpoint_texts(object, "effect_ledger") is Some(ledger_wires) else {
    return Err(InvalidMaterial)
  }
  let limits = client_checkpoint_journal_limits()
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
    client_checkpoint_optional_text(object, "resolution_cid") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let verified_wire = match
    client_checkpoint_optional_text(object, "verified_wire") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let resume_intent_id = match
    client_checkpoint_optional_text(object, "resume_intent_id") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let resume_intent = match
    client_checkpoint_optional_text(object, "resume_intent") {
    Ok(Some(wire)) =>
      match
        decode_client_checkpoint_resume_row(wire, {
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
      guard client_checkpoint_wrapper_identity_valid(verified) &&
        @checkpoint.verified_resolution_attestation_preimage(verified, limits)
        is Ok(_) &&
        client_checkpoint_cursor(verified) is Some(wrapper) &&
        @decode.open_object(wrapper) is Ok(wrapper) &&
        @decode.lookup(wrapper, "resolution") is Some(resolution) &&
        @decode.open_object(resolution) is Ok(resolution) &&
        client_checkpoint_text(resolution, "resolution_cid") == Some(cid) &&
        client_checkpoint_text(resolution, "checkpoint_cid") ==
        Some(artifact.checkpoint_cid) else {
        return Err(InvalidMaterial)
      }
      match client_checkpoint_text(resolution, "decision") {
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
    let limits = ledger_limits
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
    let prior = client_checkpoint_ledger_head(
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
  let record : ClientCheckpointJournalRecord = {
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
  guard client_checkpoint_cursor(
      @publication.publication_contract_json(definition),
    )
    is Some(definition_cursor) &&
    @decode.open_object(definition_cursor) is Ok(definition_object) &&
    client_checkpoint_text(definition_object, "authorization_context_cid") ==
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
  match client_checkpoint_journal_row_body(record) {
    Ok(expected) if expected == wire => Ok(record)
    _ => Err(InvalidMaterial)
  }
}

///|
pub fn client_checkpoint_resume_row_body(
  intent : @checkpoint.ResumeIntentView,
) -> String raise @encode.EncodeFailure {
  let writer = @encode.writer(4096, 16, 2)
  @encode.begin_object(writer)
  for
    (key, value) in [
      ("claimant", intent.claimant),
      ("generation", intent.generation.to_string()),
      ("lease_expires_ms", intent.lease_expires_ms.to_string()),
      (
        "state",
        match intent.state {
          ResumePending => "pending"
          ResumeClaimed => "claimed"
          ResumeCompleted => "completed"
        },
      ),
    ] {
    @encode.key(writer, key)
    @encode.string_value(writer, value)
  }
  @encode.end_object(writer)
  @encode.finish(writer)
}

///|
pub fn decode_client_checkpoint_resume_row(
  wire : String,
  binding : @checkpoint.ResumeBinding,
) -> @checkpoint.ResumeIntentView? {
  guard client_checkpoint_cursor(wire) is Some(cursor) &&
    @decode.closed_object(cursor, [
      "claimant", "generation", "lease_expires_ms", "state",
    ])
    is Ok(object) &&
    client_checkpoint_text(object, "claimant") is Some(claimant) &&
    client_checkpoint_text(object, "generation") is Some(generation_text) &&
    client_checkpoint_text(object, "lease_expires_ms") is Some(expires_text) &&
    client_checkpoint_text(object, "state") is Some(state_text) else {
    return None
  }
  try {
    let generation = @string.parse_int64(generation_text)
    let lease_expires_ms = @string.parse_int64(expires_text)
    if generation.to_string() != generation_text ||
      lease_expires_ms.to_string() != expires_text {
      return None
    }
    let state = match state_text {
      "pending" if generation == 0L && claimant == "" && lease_expires_ms == 0L =>
        @checkpoint.ResumePending
      "claimed" if generation > 0L &&
        generation < 9223372036854775807L &&
        lease_expires_ms > 0L &&
        lease_expires_ms <= 9007199254740991L => {
        // Use the common Owner and the original retained binding for
        // claimant validation, without granting another claim on restore.
        if @checkpoint.decide_resume_claim(
            {
              state: ResumePending,
              generation: 0L,
              claimant: "",
              lease_expires_ms: 0L,
            },
            claimant,
            0L,
            1L,
            binding,
            binding,
          )
          is Err(_) {
          return None
        }
        @checkpoint.ResumeClaimed
      }
      // Completion needs actual Effect Set/publication facts and is not
      // admitted by this physical claim connection.
      _ => return None
    }
    let view : @checkpoint.ResumeIntentView = {
      state,
      generation,
      claimant,
      lease_expires_ms,
    }
    if client_checkpoint_resume_row_body(view) != wire {
      return None
    }
    Some(view)
  } catch {
    _ => None
  }
}

///|
fn client_checkpoint_ledger_head(
  entries : Array[@effect.EffectLedgerEntry],
  locator_cid : String,
) -> @effect.EffectLedgerEntry? {
  let mut head = None
  for entry in entries {
    if @effect.effect_ledger_entry_locator_cid(entry) == locator_cid {
      head = Some(entry)
    }
  }
  head
}

///|
fn client_checkpoint_text(object : @decode.ObjectView, key : String) -> String? {
  @decode.lookup(object, key).bind(value => @decode.text(value).to_option())
}
