///|
/// Re-emit an admitted physical declaration for the SAME normalized Task.
/// This is bounded DATA construction, not profile installation, physical
/// adequacy, a capacity reservation, raw custody or permission to send.
pub fn normalized_public_model_task_response_profile(
  value : NormalizedPublicModelTask,
  template : ModelResponseProfile,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_work : Int,
) -> Result[(String, String), ModelTaskIssue] {
  let source = Some(value.declaration.original)
  if max_bytes < 0 || max_nodes < 0 || max_depth < 0 || max_work < 0 {
    return Err({ kind: InvalidLimits, source, })
  }
  if value.mock_profile is Some(_) ||
    template.kind != StructuredGenerate ||
    template.installation.completion_basis != "generation_finish" ||
    template.probability_source is Some(_) ||
    template.probability_profile_cid is Some(_) {
    return Err({ kind: ReferenceMismatch, source, })
  }
  // One bounded hash preimage and one bounded final wire traversal. Physical
  // simultaneous originals/writer/output remain on the existing Host owner.
  if 2L * (max_bytes.to_int64() + max_nodes.to_int64()) > max_work.to_int64() {
    return Err({ kind: WorkLimit, source, })
  }
  try {
    let hash = @encode.hashing_writer(max_bytes, max_nodes, max_depth)
    emit_normalized_response_profile(value, template, None, hash)
    let cid = "sha256:" + @encode.finish_hash(hash)
    let output = @encode.writer(max_bytes, max_nodes, max_depth)
    emit_normalized_response_profile(value, template, Some(cid), output)
    Ok((@encode.finish(output), cid))
  } catch {
    _ => Err({ kind: BodyLimit, source, })
  }
}

///|
/// The admitted reader fixes all omitted constant fields. Preserve every
/// retained physical field, ordered observation and finite numerical limit;
/// substitute only Task/input/output identities from the original declaration.
fn emit_normalized_response_profile(
  value : NormalizedPublicModelTask,
  template : ModelResponseProfile,
  self_cid : String?,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  let installation = template.installation
  @encode.begin_object(writer)
  @encode.key(writer, "adapter")
  @encode.begin_object(writer)
  for
    (name, text) in [
      ("build_artifact_cid", installation.build_artifact_cid),
      ("builder_id", installation.builder_id),
      ("builder_revision", installation.builder_revision),
      ("codec_id", installation.codec_id),
      ("codec_revision", installation.codec_revision),
      ("port_abi", "model-physical-port/1"),
    ] {
    @encode.key(writer, name)
    @encode.string_value(writer, text)
  }
  @encode.key(writer, "sdk")
  match installation.sdk {
    None => @encode.null_value(writer)
    Some(sdk) => {
      @encode.begin_object(writer)
      for
        (name, text) in [
          ("interface", sdk.interface),
          ("lock_artifact_cid", sdk.lock_artifact_cid),
          ("package", sdk.package_name),
          ("version", sdk.version),
        ] {
        @encode.key(writer, name)
        @encode.string_value(writer, text)
      }
      @encode.end_object(writer)
    }
  }
  @encode.end_object(writer)
  @encode.key(writer, "completion")
  @encode.begin_object(writer)
  @encode.key(writer, "basis")
  @encode.string_value(writer, installation.completion_basis)
  for name in ["endpoint_envelope", "output_contract", "transport_eof"] {
    @encode.key(writer, name)
    @encode.bool_value(writer, true)
  }
  for
    (name, text) in [
      ("validator_artifact_cid", installation.validator_artifact_cid),
      ("validator_id", installation.validator_id),
      ("validator_revision", installation.validator_revision),
    ] {
    @encode.key(writer, name)
    @encode.string_value(writer, text)
  }
  @encode.end_object(writer)
  @encode.key(writer, "controls")
  @encode.begin_object(writer)
  for name in ["cache", "fallback", "hedging", "media_fetch"] {
    @encode.key(writer, name)
    @encode.bool_value(writer, false)
  }
  @encode.key(writer, "model_requests")
  @encode.number_value(writer, 1.0)
  for
    name in [
      "redirect", "repair", "retry", "sdk_telemetry", "tools", "workflow_restore",
    ] {
    @encode.key(writer, name)
    @encode.bool_value(writer, false)
  }
  @encode.end_object(writer)
  @encode.key(writer, "limits")
  @encode.begin_object(writer)
  let limits = template.limits
  for
    (name, quantity) in [
      ("active_slots", limits.active_slots),
      ("adapter_holding_bytes", limits.adapter_holding_bytes),
      ("adapter_workspace_bytes", limits.adapter_workspace_bytes),
      ("chunk_bytes", limits.chunk_bytes),
      ("chunks", limits.chunks),
      ("header_bytes", limits.header_bytes),
      ("metadata_bytes", limits.metadata_bytes),
      ("metadata_depth", limits.metadata_depth),
      ("metadata_nodes", limits.metadata_nodes),
      ("parse_depth", limits.parse_depth),
      ("parse_nodes", limits.parse_nodes),
      ("parse_work", limits.parse_work),
      ("request_bytes", limits.request_bytes),
      ("response_bytes", limits.response_bytes),
      ("unsettled_slots", limits.unsettled_slots),
    ] {
    @encode.key(writer, name)
    @encode.number_value(writer, quantity.to_double())
  }
  @encode.end_object(writer)
  @encode.key(writer, "observations")
  @encode.begin_array(writer)
  for observation in template.observations {
    @encode.string_value(writer, observation)
  }
  @encode.end_array(writer)
  @encode.key(writer, "operation")
  @encode.begin_object(writer)
  @encode.key(writer, "endpoint")
  @encode.string_value(writer, installation.endpoint)
  @encode.key(writer, "method")
  @encode.string_value(writer, installation.http_method)
  @encode.key(writer, "streaming")
  @encode.bool_value(writer, installation.streaming)
  @encode.end_object(writer)
  @encode.key(writer, "probability")
  @encode.null_value(writer)
  if self_cid is Some(cid) {
    @encode.key(writer, "self_cid")
    @encode.string_value(writer, cid)
  }
  @encode.key(writer, "task")
  @encode.begin_object(writer)
  for
    (name, text) in [
      ("contract_cid", value.task_cid),
      ("input_schema_cid", value.declaration.input.cid),
      ("kind", "structured_generate"),
      ("output_schema_cid", value.declaration.output.cid),
    ] {
    @encode.key(writer, name)
    @encode.string_value(writer, text)
  }
  @encode.end_object(writer)
  @encode.key(writer, "version")
  @encode.string_value(writer, "actql-model-response-profile/0.1")
  @encode.end_object(writer)
}
