///|
pub(all) enum PreparedModelInvocationScopeIssue {
  ForeignOriginal
  Encoding
  Evidence(@publication.RunEvidenceValueIssue)
}

///|
/// Project scope evidence from the exact prepared input and ordered calls.
/// The original Read funds the writer and evidence parser before this call.
/// The existing scope binding still checks Run identity and authorization.
pub fn project_prepared_model_invocation_scope(
  definition : @publication.PublicationContract,
  prepared : ModelPreparedCallSet,
  provider : @publication.RunEvidenceValue,
  boundary : @publication.ModelInvocationBoundary,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[@publication.RunEvidenceValue, PreparedModelInvocationScopeIssue] {
  guard prepared_model_input_artifact(prepared) is Some(input) &&
    prepared_model_call_count(prepared) is Some(count) else {
    return Err(ForeignOriginal)
  }
  try {
    let writer = @encode.writer(max_bytes, max_nodes, max_depth)
    @encode.begin_object(writer)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-model-invocation-scope/0.1")
    @encode.key(writer, "run_definition_cid")
    @encode.string_value(
      writer,
      @publication.publication_contract_identity(definition),
    )
    @encode.key(writer, "task_index")
    @encode.number_value(writer, boundary.task_index.to_double())
    @encode.key(writer, "strategy_revision")
    @encode.number_value(writer, boundary.strategy_revision.to_double())
    @encode.key(writer, "inference_barrier_cid")
    @encode.string_value(writer, boundary.inference_barrier_cid)
    @encode.key(writer, "input_artifact_cid")
    @encode.string_value(
      writer,
      @publication.run_evidence_value_identity(input),
    )
    @encode.key(writer, "model_call_slot_cids")
    @encode.begin_array(writer)
    for slot in 0..<count {
      guard prepared_model_call_at(prepared, slot) is Some(call) else {
        return Err(ForeignOriginal)
      }
      @encode.string_value(
        writer,
        @publication.run_evidence_value_identity(call),
      )
    }
    @encode.end_array(writer)
    @encode.key(writer, "provider_binding_cid")
    @encode.string_value(
      writer,
      @publication.run_evidence_value_identity(provider),
    )
    @encode.key(writer, "authorization_context")
    @encode.begin_object(writer)
    for
      (key, value) in [
        ("account_id", boundary.account_id),
        ("configuration_cid", boundary.configuration_cid),
        ("entry_id", boundary.entry_id),
        ("principal", boundary.principal),
        ("connection", boundary.connection),
        ("resource", boundary.resource),
        ("operation", "infer"),
        ("boundary", "activation"),
        ("context_cid", boundary.context_cid),
      ] {
      @encode.key(writer, key)
      @encode.string_value(writer, value)
    }
    @encode.end_object(writer)
    @encode.end_object(writer)
    @publication.seal_run_evidence_value(
      "model_invocation_scope",
      @encode.finish(writer),
      max_bytes,
      max_nodes,
      max_depth,
    ).map_err(issue => PreparedModelInvocationScopeIssue::Evidence(issue))
  } catch {
    _ => Err(Encoding)
  }
}

///|
/// Borrow the existing admitted provider evidence. The same prepared Plans
/// check its identity during the original invocation-scope binding.
pub fn admitted_model_invocation_provider_binding(
  provider : AdmittedStructuredModelProvider,
) -> @publication.RunEvidenceValue {
  provider.capability.binding
}
