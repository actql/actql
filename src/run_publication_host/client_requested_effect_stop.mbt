///|
/// An additional continuation restriction, not Account authorization. Only the
/// existing Client/Checkpoint composition binds this view. The physical journal
/// must independently authenticate the submitted intent's original Run linkage;
/// this pure projection cannot establish a COMMIT, approval or resume claim.
struct ClientRequestedEffectStop {
  intent : ClientSubmittedIntent
  request : ClientRequestIdentity
  allowed : ClientEffectAllowedRun
  definition : @publication.PublicationContract
  preview : ClientRequestedEffectStopPreview
}

///|
priv enum ClientRequestedEffectStopPreview {
  LiveStopPreview(@strategy.CapturedEffectPreviewInputs)
  SavedStopPreview(@effect_binding.EffectProgramRunPreview)
}

///|
pub(all) enum ClientRequestedEffectStopIssue {
  ForeignRequest
  ForeignRun
  ForeignPreview
  ForeignContinuation
  Limit
  OriginalLifetime
  RestoredPreview(@effect_binding.EffectProgramRunPreviewIssue)
  Checkpoint(@checkpoint.CheckpointIssue)
}

///|
/// Keep the admitted intent, original logical request, compiled Run and sealed
/// Preview together. No supplied CID or Boolean selects a different original.
/// The selected compilation has one Effect-bearing Unit; this does not restrict
/// the language's multi-Unit semantics or approve an unexecuted later Unit.
pub fn issue_client_requested_effect_stop(
  intent : ClientSubmittedIntent,
  reference : ClientSubmissionReferenceRecord,
  request : ClientRequestIdentity,
  allowed : ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
  preview : @strategy.CapturedEffectPreviewInputs,
) -> Result[ClientRequestedEffectStop?, ClientRequestedEffectStopIssue] {
  if !intent.stop_before_commit {
    return Ok(None)
  }
  let prepared = allowed.compilation.owner
  if !client_submission_reference_matches_request(reference, request) ||
    prepared_client_effect_request_scope(prepared, request) is Err(_) {
    return Err(ForeignRequest)
  }
  if bind_client_effect_compiled_run(prepared, allowed, definition) is Err(_) {
    return Err(ForeignRun)
  }
  let original : ClientRequestedEffectStop = {
    intent,
    request,
    allowed,
    definition,
    preview: LiveStopPreview(preview),
  }
  check_requested_effect_stop_original(original).map(_ => Some(original))
}

///|
/// Rebind the saved original materials and the already admitted historical
/// Preview. This performs no capture, re-execution, approval or dispatch. The
/// Host must separately confirm the same original Journal and Store custody.
pub fn restore_client_requested_effect_stop(
  intent : ClientSubmittedIntent,
  reference : ClientSubmissionReferenceRecord,
  request : ClientRequestIdentity,
  materials : ClientEffectRunMaterials,
  invocation : @publication.PublicationContract,
  preview : @publication.EffectPreviewIdentity,
  limits : ClientCapturedEffectPreviewLimits,
) -> Result[ClientRequestedEffectStop?, ClientRequestedEffectStopIssue] {
  if !intent.stop_before_commit {
    return Ok(None)
  }
  guard materials.request is Some(original_request) &&
    client_request_identity_relation(original_request, request) == SameRequest &&
    client_submission_reference_matches_request(reference, request) &&
    physical_equal(materials.prepared, materials.compilation.owner) &&
    physical_equal(materials.compilation, materials.allowed.compilation) else {
    return Err(ForeignRequest)
  }
  let run = match
    bind_client_effect_compiled_run(
      materials.prepared, materials.allowed, materials.run_definition,
    ) {
    Ok(value) => value
    Err(_) => return Err(ForeignRun)
  }
  let stages = @syntax.stages(materials.prepared.source)
  let checked = match
    @effect_binding.bind_effect_program_run_preview(
      run, invocation, stages.length() - 1, preview, limits.max_work, limits.plan,
    ) {
    Ok(value) => value
    Err(issue) => return Err(RestoredPreview(issue))
  }
  let original : ClientRequestedEffectStop = {
    intent,
    request,
    allowed: materials.allowed,
    definition: materials.run_definition,
    preview: SavedStopPreview(checked),
  }
  check_requested_effect_stop_original(original).map(_ => Some(original))
}

///|
// Recheck the actual original capture, not a copied semantic Preview identity.
// Availability callbacks may retire it; the terminal retained read follows them.
fn check_requested_effect_stop_original(
  original : ClientRequestedEffectStop,
) -> Result[Unit, ClientRequestedEffectStopIssue] {
  let prepared = original.allowed.compilation.owner
  let checked = match original.preview {
    LiveStopPreview(preview) => @strategy.captured_effect_preview_owner(preview)
    SavedStopPreview(preview) => preview
  }
  let run = @effect_binding.effect_program_run_preview_owner(checked)
  if !physical_equal(
      @effect_binding.effect_program_run_static_candidate(run),
      prepared.candidate,
    ) ||
    !physical_equal(
      @effect_binding.effect_program_run_admission(run),
      original.allowed.admission,
    ) ||
    @publication.publication_contract_json(
      @effect_binding.effect_program_run_definition(run),
    ) !=
    @publication.publication_contract_json(original.definition) {
    return Err(ForeignPreview)
  }
  let stage = @effect_binding.effect_program_run_preview_stage(checked)
  let stages = @syntax.stages(prepared.source)
  if stage < 0 ||
    stage >= stages.length() ||
    stages[stage].id !=
    client_effect_compilation_unit_id(original.allowed.compilation) {
    return Err(ForeignPreview)
  }
  if original.preview is LiveStopPreview(preview) {
    if !@strategy.captured_effect_preview_inputs_available(preview) ||
      !@strategy.captured_effect_preview_inputs_retained(preview) {
      return Err(OriginalLifetime)
    }
  }
  Ok(())
}

///|
fn requested_effect_stop_preview_cid(
  original : ClientRequestedEffectStop,
) -> String? {
  match original.preview {
    LiveStopPreview(preview) => @strategy.captured_effect_preview_subject_cid(preview)
    SavedStopPreview(preview) =>
      Some(@publication.effect_preview_semantic_identity(
        @effect_binding.effect_program_run_preview_identity(preview),
      ))
  }
}

///|
/// Identity DATA for the original continuation codec, not a permission token.
/// The caller must retain this same opaque view through its current checks.
pub fn client_requested_effect_stop_intent_cid(
  original : ClientRequestedEffectStop,
) -> String {
  client_submitted_intent_cid(original.intent)
}

///|
/// Original Run lifetime DATA for the Host's bounded Checkpoint expiration.
/// This neither extends that lifetime nor establishes approval/currentness.
pub fn client_requested_effect_stop_lifetime(
  original : ClientRequestedEffectStop,
) -> Result[(String, String), ClientRequestedEffectStopIssue] {
  match check_requested_effect_stop_original(original) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match @publication.run_definition_lifetime(original.definition) {
    Some(value) => Ok(value)
    None => Err(ForeignRun)
  }
}

///|
fn requested_effect_stop_value(
  wire : String,
  limits : @checkpoint.WireLimits,
) -> Result[@canonical.CanonicalValue, ClientRequestedEffectStopIssue] {
  if limits.max_wire_bytes < 1 ||
    limits.max_wire_bytes > 1048576 ||
    limits.max_nodes < 1 ||
    limits.max_nodes > 65536 ||
    limits.max_depth < 1 ||
    limits.max_depth > 64 {
    return Err(Limit)
  }
  let source = match
    @source.parse_json_bytes_preserving(@utf8.encode(wire), {
      max_input_bytes: limits.max_wire_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    }) {
    Ok(value) => value
    Err(issue) =>
      match issue.issue {
        InputLimit | NodeLimit | DepthLimit => return Err(Limit)
        _ => return Err(ForeignContinuation)
      }
  }
  try {
    let value = @canonical.from_source(
      source,
      limits.max_nodes,
      limits.max_depth,
      limits.max_wire_bytes,
      data_keys=true,
    )
    if @canonical.object_field_count(value) is None {
      return Err(ForeignContinuation)
    }
    Ok(value)
  } catch {
    @canonical.InputLimit => Err(Limit)
    _ => Err(ForeignContinuation)
  }
}

///|
fn emit_requested_effect_stop_continuation(
  original : ClientRequestedEffectStop,
  provider : @canonical.CanonicalValue,
  target : @canonical.CanonicalValue?,
  limits : @checkpoint.WireLimits,
) -> Result[String, ClientRequestedEffectStopIssue] {
  match check_requested_effect_stop_original(original) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  guard requested_effect_stop_preview_cid(original)
    is Some(preview_cid) else {
    return Err(OriginalLifetime)
  }
  try {
    let writer = @encode.writer(
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
    )
    @encode.begin_object(writer)
    @encode.key(writer, "preview_cid")
    @encode.string_value(writer, preview_cid)
    @encode.key(writer, "provider")
    @canonical.emit_value(provider, writer)
    @encode.key(writer, "requested_stop")
    @encode.begin_object(writer)
    @encode.key(writer, "intent_cid")
    @encode.string_value(writer, original.intent.cid)
    @encode.end_object(writer)
    @encode.key(writer, "run_definition_cid")
    @encode.string_value(
      writer,
      @publication.publication_contract_identity(original.definition),
    )
    if target is Some(value) {
      @encode.key(writer, "target_read_binding")
      @canonical.emit_value(value, writer)
    }
    @encode.key(writer, "unit_id")
    @encode.string_value(
      writer,
      client_effect_compilation_unit_id(original.allowed.compilation),
    )
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-installed-effect-continuation/0.1")
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => Err(Limit)
  }
}

///|
/// Extend the existing installed continuation codec only when the original
/// admitted intent selected a stop. Physical provider and target-read members
/// remain bounded opaque DATA interpreted by their existing Owners.
pub fn issue_client_requested_effect_stop_continuation(
  original : ClientRequestedEffectStop,
  provider_wire : String,
  target_read_binding_wire : String?,
  limits : @checkpoint.WireLimits,
) -> Result[String, ClientRequestedEffectStopIssue] {
  let provider = match requested_effect_stop_value(provider_wire, limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let target = match target_read_binding_wire {
    None => None
    Some(wire) =>
      match requested_effect_stop_value(wire, limits) {
        Ok(value) => Some(value)
        Err(issue) => return Err(issue)
      }
  }
  emit_requested_effect_stop_continuation(original, provider, target, limits)
}

///|
fn check_requested_effect_stop_continuation(
  original : ClientRequestedEffectStop,
  wire : String,
  limits : @checkpoint.WireLimits,
) -> Result[Unit, ClientRequestedEffectStopIssue] {
  let value = match requested_effect_stop_value(wire, limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard @canonical.object_field(value, "provider") is Some(provider) &&
    @canonical.object_field_count(provider) is Some(_) else {
    return Err(ForeignContinuation)
  }
  let target = @canonical.object_field(value, "target_read_binding")
  if target is Some(value) && @canonical.object_field_count(value) is None {
    return Err(ForeignContinuation)
  }
  let expected = match
    emit_requested_effect_stop_continuation(original, provider, target, limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if wire != expected {
    return Err(ForeignContinuation)
  }
  Ok(())
}

///|
/// Seal the existing Effect Set checkpoint body from the same original pair.
/// Store read-back, reviewer authentication, Resolution, current Account and
/// single-use resume admission remain with their existing Owners.
pub fn seal_client_requested_effect_stop(
  original : ClientRequestedEffectStop,
  body : @checkpoint.CheckpointRequest,
  continuation_wire : String,
  limits : @checkpoint.WireLimits,
) -> Result[@checkpoint.SealedCheckpoint, ClientRequestedEffectStopIssue] {
  let prepared = original.allowed.compilation.owner
  if prepared_client_effect_request_scope(prepared, original.request) is Err(_) ||
    bind_client_effect_compiled_run(
      prepared,
      original.allowed,
      original.definition,
    )
    is Err(_) {
    return Err(ForeignRun)
  }
  match check_requested_effect_stop_original(original) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match
    check_requested_effect_stop_continuation(
      original, continuation_wire, limits,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  if body.continuation_state_cid !=
    "sha256:" + @sha.hex(@utf8.encode(continuation_wire)) {
    return Err(ForeignContinuation)
  }
  let run_id = match @publication.run_definition_run_id(original.definition) {
    Ok(value) => value
    Err(_) => return Err(ForeignRun)
  }
  if body.subject !=
    @checkpoint.RunUnit(
      run_id~,
      unit_id=client_effect_compilation_unit_id(original.allowed.compilation),
      run_definition_cid=@publication.publication_contract_identity(
        original.definition,
      ),
    ) ||
    body.phase != @checkpoint.Commit ||
    body.kind != @checkpoint.EffectSet ||
    body.requirements != [@checkpoint.EffectScopeApproved] ||
    body.reason_code != "user_requested_stop" {
    return Err(ForeignRun)
  }
  if body.required_artifact_cid !=
    requested_effect_stop_preview_cid(original).unwrap_or(
      "",
    ) {
    return Err(ForeignPreview)
  }
  if !client_effect_run_start_current(
      original.allowed,
      original.definition,
      body.created_at,
    ) ||
    !client_effect_run_start_current(
      original.allowed,
      original.definition,
      body.expires_at,
    ) {
    return Err(OriginalLifetime)
  }
  @checkpoint.seal_checkpoint(body, limits).map_err(issue => Checkpoint(issue))
}

///|
/// Admit the existing closed Checkpoint body codec before applying the original
/// requested-stop binding. Canonicalization/CID generation stays in that Owner.
pub fn seal_client_requested_effect_stop_body(
  original : ClientRequestedEffectStop,
  body_wire : String,
  continuation_wire : String,
  limits : @checkpoint.WireLimits,
) -> Result[String, ClientRequestedEffectStopIssue] {
  let candidate = match @checkpoint.seal_checkpoint_body(body_wire, limits) {
    Ok(value) => value
    Err(issue) => return Err(Checkpoint(issue))
  }
  seal_client_requested_effect_stop(
    original,
    candidate.checkpoint,
    continuation_wire,
    limits,
  ).map(value => value.wire)
}
