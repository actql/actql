///|
/// Canonical nonsecret installation originals are selected by the trusted Host.
/// This checks their bytes and binding identity, not their operational truth.
pub fn issue_client_model_provider_binding(
  provider_id : String,
  installation_wire : String,
  configuration_contract_wire : String,
  configuration_wire : String,
) -> Result[@publication.RunEvidenceValue, @publication.RunEvidenceValueIssue] {
  let ids : Array[String] = []
  for
    wire in [installation_wire, configuration_contract_wire, configuration_wire] {
    guard parse_plan_identity_value(wire, 65536, 4096, 32) is Some(value) else {
      return Err(@publication.RunEvidenceInvalidWire)
    }
    let canonical = @canonical.stringify_value(value, 65536, 4096, 32) catch {
      _ => return Err(@publication.RunEvidenceInvalidWire)
    }
    if canonical != wire {
      return Err(@publication.RunEvidenceInvalidWire)
    }
    ids.push("sha256:" + @sha.hex(@utf8.encode(wire)))
  }
  try {
    let writer = @encode.writer(16384, 256, 8)
    emit_client_model_provider_binding_body(
      writer,
      provider_id,
      ids[0],
      ids[1],
      ids[2],
      None,
      (cid, writer) => @encode.string_value(writer, cid),
    )
    @publication.seal_run_evidence_value(
      "model_provider_binding",
      @encode.finish(writer),
      16384,
      256,
      8,
    )
  } catch {
    _ => Err(@publication.RunEvidenceInvalidWire)
  }
}

///|
/// Check the resolved route against the original nonsecret configuration of
/// an admitted binding. A capability caller funds these bounded reads before
/// retaining the selection. Physical installation and send approval are
/// checked separately by their original owners.
pub fn client_model_resolved_configuration_matches(
  binding : @publication.RunEvidenceValue,
  configuration_wire : String,
  provider_id : String,
  selector : String,
  model_id : String,
  adapter_kind : String,
  api_mode : String,
  endpoint : String,
) -> Bool {
  if @publication.run_evidence_value_name(binding) != "model_provider_binding" ||
    configuration_wire.length() > 65536 {
    return false
  }
  guard parse_plan_identity_value(
      @publication.run_evidence_value_json(binding),
      16384,
      256,
      8,
    )
    is Some(original) &&
    @canonical.object_field(original, "provider_id")
    is Some(@canonical.String(original_provider)) &&
    original_provider == provider_id &&
    @canonical.object_field(original, "configuration_cid")
    is Some(@canonical.String(configuration_cid)) &&
    parse_plan_identity_value(configuration_wire, 65536, 4096, 32)
    is Some(configuration) else {
    return false
  }
  if configuration_cid != "sha256:" + @sha.hex(@utf8.encode(configuration_wire)) {
    return false
  }
  for
    (field, expected) in [
      ("provider_id", provider_id),
      ("selector", selector),
      ("endpoint", endpoint),
      ("model_id", model_id),
      ("adapter_kind", adapter_kind),
      ("api_mode", api_mode),
    ] {
    guard @canonical.object_field(configuration, field)
      is Some(@canonical.String(actual)) &&
      actual == expected else {
      return false
    }
  }
  true
}

///|
// Same original field order/spelling. Measurement includes the sealer's one
// self-CID field by encoded extent only, without issuing a binding or CID.
fn[C] emit_client_model_provider_binding_body(
  writer : @encode.Writer,
  provider_id : String,
  installation : C,
  contract : C,
  configuration : C,
  self_cid : C?,
  emit_cid : (C, @encode.Writer) -> Unit raise @encode.EncodeFailure,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  @encode.key(writer, "version")
  @encode.string_value(writer, "actql-model-provider-binding/0.1")
  @encode.key(writer, "provider_id")
  @encode.string_value(writer, provider_id)
  @encode.key(writer, "installation_revision_cid")
  emit_cid(installation, writer)
  @encode.key(writer, "configuration_contract_cid")
  emit_cid(contract, writer)
  @encode.key(writer, "configuration_cid")
  emit_cid(configuration, writer)
  if self_cid is Some(cid) {
    @encode.key(writer, "self_cid")
    emit_cid(cid, writer)
  }
  @encode.end_object(writer)
}

///|
/// Pure construction DATA for the original binding/sealed evidence body.
/// No input contract, provider or authority has been admitted by this measure.
pub fn measure_client_model_provider_binding_construction(
  provider_id : String,
) -> (Int, Int, Int)? {
  let writer = @encode.measuring_writer(16384, 256, 8) catch {
    _ => return None
  }
  emit_client_model_provider_binding_body(
    writer,
    provider_id,
    (),
    (),
    (),
    Some(()),
    measure_client_fragment_cid,
  ) catch {
    _ => return None
  }
  Some(@encode.finish_measurement_usage(writer)) catch {
    _ => None
  }
}

///|
/// Bind against the retained original compilation, not a reconstructed Run
/// admission supplied by the Host. The physical owner also checks completeness.
pub fn bind_client_model_invocation_scope(
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  scope : @publication.RunEvidenceValue,
  provider : @publication.RunEvidenceValue,
  input : @publication.RunEvidenceValue,
  slots : Array[@publication.RunEvidenceValue],
  expected : @publication.ModelInvocationBoundary,
) -> Result[
  @publication.BoundModelInvocationScope,
  @publication.RunEvidenceValueIssue,
] {
  if check_client_compiled_run_definition(compiled, definition) is Err(_) {
    return Err(@publication.RunEvidenceReferenceMismatch("model_scope.run"))
  }
  @publication.bind_model_invocation_scope(
    compiled.admission,
    definition,
    scope,
    provider,
    input,
    slots,
    expected,
  )
}
