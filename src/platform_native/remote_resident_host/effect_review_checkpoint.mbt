///|
pub(all) enum ResidentEffectReviewCheckpointIssue {
  Unavailable
  ForeignCapture
  InvalidLimits
  RunLifetimeUnavailable
  Request(@host.ClientRequestIdentityIssue)
  Capture(ResidentEffectCaptureCustodyIssue)
  Preview(ResidentEffectPreviewCustodyIssue)
  Encoding
  Keys(@effect.EffectPreviewRecoveryKeysIssue)
  Checkpoint(@checkpoint.CheckpointIssue)
  RunBinding(@host.ClientEffectCheckpointBindingIssue)
}

///|
/// Original private review/continuation bytes and a common-issued Checkpoint.
/// This preparation is not durable custody, a waiting transition, approval or
/// a resume permit. The caller must retain both evidence holdings and persist
/// these exact bytes before the existing Run owner can commit waiting.
pub struct ResidentEffectReviewCheckpoint {
  source_owner : ResidentSourceCompute
  capture_owner : ResidentEffectCaptureCustody
  preview_owner : ResidentEffectPreviewCustody
  store_authority : String
  checkpoint : @checkpoint.SealedCheckpoint
  continuation_wire : String
  review_wire : String
}

///|
fn effect_checkpoint_text(
  writer : @encode.Writer,
  name : String,
  value : String,
) -> Unit raise @encode.EncodeFailure {
  @encode.key(writer, name)
  @encode.string_value(writer, value)
}

///|
/// Prepare the original Effect review from authenticated capture/Preview
/// readback. This Native provider snapshot includes both original wire bodies,
/// authoring and request identity; its byte CID is never the Captured Run CID.
/// It does not restore a holder or supply an Effect execution/recovery permit.
/// No Source read, Compute, Provider call, write or custody release occurs.
pub fn ResidentSourceCompute::prepare_effect_review_checkpoint(
  self : ResidentSourceCompute,
  materials : @host.ClientEffectRunMaterials,
  inputs : @strategy.CapturedEffectInputs,
  request : @host.ClientRequestIdentity,
  capture : ResidentEffectCaptureCustody,
  preview : ResidentEffectPreviewCustody,
  checkpoint_id : String,
  created_at : String,
  expires_at : String,
  limits : @checkpoint.WireLimits,
) -> Result[ResidentEffectReviewCheckpoint, ResidentEffectReviewCheckpointIssue] {
  if limits.max_wire_bytes < 1 ||
    limits.max_wire_bytes > 262144 ||
    limits.max_nodes < 1 ||
    limits.max_nodes > 10000 ||
    limits.max_depth < 1 ||
    limits.max_depth > 64 {
    return Err(InvalidLimits)
  }
  if !self.resident_effect_inputs_current(inputs) {
    return Err(Unavailable)
  }
  let scope = match
    @host.prepared_client_effect_request_scope(materials.prepared, request) {
    Ok(value) => value
    Err(issue) => return Err(Request(issue))
  }
  let captured = match capture.confirm() {
    Ok(value) => value
    Err(issue) => return Err(Capture(issue))
  }
  let (identity, review_wire) = match preview.confirm() {
    Ok(value) => value
    Err(issue) => return Err(Preview(issue))
  }
  let run_cid = @publication.publication_contract_identity(
    materials.run_definition,
  )
  let captured_cid = @publication.publication_contract_identity(captured)
  let preview_cid = @publication.effect_preview_semantic_identity(identity)
  // Both owners were issued through the common complete computation-chain
  // validator. Match their original holding, authority and capture rather than
  // trusting equal target bytes or a caller-provided CID.
  if @publication.effect_preview_run_identity(identity) != run_cid ||
    @publication.effect_capture_holding_authority(capture.binding) !=
    @publication.effect_capture_holding_authority(preview.binding) ||
    @publication.effect_capture_holding_identity(capture.binding) !=
    @publication.effect_capture_holding_identity(preview.binding) ||
    @publication.publication_contract_identity(
      @publication.effect_capture_holding_contract(preview.binding),
    ) !=
    captured_cid ||
    @strategy.captured_effect_inputs_run_definition_cid(inputs) != Some(run_cid) ||
    @publication.effect_computation_record_holding_cid(
      materials.run_definition,
      @publication.effect_capture_holding_authority(capture.binding),
    ) !=
    Some(@publication.effect_capture_holding_identity(capture.binding)) {
    return Err(ForeignCapture)
  }
  // The review window cannot create a fresh lifetime for the original Run.
  // Current Host authorization is still required independently at waiting,
  // approval and physical start; this is evidence preparation only.
  if !@host.client_effect_run_start_current(
      materials.allowed,
      materials.run_definition,
      created_at,
    ) ||
    !@host.client_effect_run_start_current(
      materials.allowed,
      materials.run_definition,
      expires_at,
    ) {
    return Err(RunLifetimeUnavailable)
  }
  match
    @effect.recover_effect_preview_apply_keys(
      identity, scope, 1, 10000, 20000, 4096, 32, 8,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Keys(issue))
  }
  let binding = match
    self.effect_review_input_binding(materials, inputs, request) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let unit = @host.client_effect_compilation_unit_id(materials.compilation)
  let encoded = try {
    let writer = @encode.writer(
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
    )
    @encode.begin_object(writer)
    effect_checkpoint_text(
      writer, "version", "actql-installed-effect-continuation/0.1",
    )
    effect_checkpoint_text(writer, "run_definition_cid", run_cid)
    effect_checkpoint_text(writer, "unit_id", unit)
    effect_checkpoint_text(writer, "preview_cid", preview_cid)
    @encode.key(writer, "provider")
    @encode.begin_object(writer)
    match binding {
      Retained(body) =>
        effect_checkpoint_text(writer, "retained_input_binding", body)
      Acquired(source_ref, source_contract_cid) => {
        effect_checkpoint_text(writer, "acquired_source_ref", source_ref)
        effect_checkpoint_text(
          writer, "acquired_source_contract_cid", source_contract_cid,
        )
      }
    }
    effect_checkpoint_text(
      writer,
      "captured_run_wire",
      @publication.publication_contract_json(captured),
    )
    effect_checkpoint_text(writer, "review_wire", review_wire)
    effect_checkpoint_text(
      writer,
      "authoring_context_cid",
      preview.authoring_cid,
    )
    effect_checkpoint_text(
      writer,
      "store_authority_cid",
      @publication.effect_capture_holding_authority(capture.binding),
    )
    @encode.key(writer, "request")
    @encode.begin_object(writer)
    effect_checkpoint_text(
      writer,
      "authority_scope_cid",
      @host.client_request_authority_scope_cid(request),
    )
    effect_checkpoint_text(
      writer,
      "request_id",
      @host.client_request_caller_id(request),
    )
    effect_checkpoint_text(
      writer,
      "logical_request_scope_cid",
      @host.client_request_scope_cid(request),
    )
    effect_checkpoint_text(
      writer,
      "intent_fingerprint_cid",
      @host.client_request_intent_cid(request),
    )
    effect_checkpoint_text(
      writer,
      "program_definition_cid",
      @host.client_request_program_cid(request),
    )
    effect_checkpoint_text(
      writer,
      "parameter_values_cid",
      @host.client_request_parameters_cid(request),
    )
    effect_checkpoint_text(
      writer,
      "caller_input_intent_cid",
      @host.client_request_input_cid(request),
    )
    @encode.end_object(writer)
    @encode.end_object(writer)
    @encode.end_object(writer)
    let value = @canonical.from_json(
      @json.parse(@encode.finish(writer)),
      limits.max_nodes,
      limits.max_depth,
      limits.max_wire_bytes,
      data_keys=true,
    )
    Ok(
      @canonical.stringify_value(
        value,
        limits.max_wire_bytes,
        limits.max_nodes,
        limits.max_depth,
      ),
    )
  } catch {
    _ => Err(Encoding)
  }
  let continuation_wire = match encoded {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let run_id = match
    @publication.run_definition_run_id(materials.run_definition) {
    Ok(value) => value
    Err(_) => return Err(ForeignCapture)
  }
  let sealed_checkpoint = match
    @checkpoint.seal_checkpoint(
      {
        checkpoint_id,
        continuation_state_cid: "sha256:" +
        @sha.hex(@sha.digest(@utf8.encode(continuation_wire))),
        subject: @checkpoint.RunUnit(
          run_id~,
          unit_id=unit,
          run_definition_cid=run_cid,
        ),
        phase: @checkpoint.Commit,
        kind: @checkpoint.EffectSet,
        required_artifact_cid: preview_cid,
        review_projection_cid: "sha256:" +
        @sha.hex(@sha.digest(@utf8.encode(review_wire))),
        requirements: [@checkpoint.EffectScopeApproved],
        reason_code: "effect_review",
        human_summary: "Approve the complete Effect Set",
        created_at,
        expires_at,
      },
      limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Checkpoint(issue))
  }
  // The same common Run/unit binding is consumed by the Cloud adapter.
  // Genuine capture and paired Store custody still have their own owners.
  match
    @host.admit_client_effect_review_checkpoint_binding(
      materials.allowed,
      materials.run_definition,
      sealed_checkpoint.wire,
      limits,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(RunBinding(issue))
  }
  if !self.resident_effect_inputs_current(inputs) {
    return Err(Unavailable)
  }
  Ok({
    source_owner: self,
    capture_owner: capture,
    preview_owner: preview,
    store_authority: @publication.effect_capture_holding_authority(
      capture.binding,
    ),
    checkpoint: sealed_checkpoint,
    continuation_wire,
    review_wire,
  })
}
