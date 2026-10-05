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
    @encode.begin_object(writer)
    for
      (name, value) in [
        ("version", "actql-model-provider-binding/0.1"),
        ("provider_id", provider_id),
        ("installation_revision_cid", ids[0]),
        ("configuration_contract_cid", ids[1]),
        ("configuration_cid", ids[2]),
      ] {
      @encode.key(writer, name)
      @encode.string_value(writer, value)
    }
    @encode.end_object(writer)
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
