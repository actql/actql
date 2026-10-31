///|
/// The same original full-input capture supplies the ordinary Source
/// observation. It is never cast to a Query requirement or emitted/readmitted.
pub fn issue_client_compiled_whole_source_invocation(
  run : ClientCompiledRun,
  definition : @publication.PublicationContract,
  capture : @query.CapturedInputSource,
  identity : @query.CapturedSourceRelationIdentity,
  acquisition : @acquisition.SourceAcquisition,
  source : @publication.RunEvidenceValue,
  input : @publication.RunEvidenceValue,
  authority_scope_cid : String,
  data_policy_cid : String,
  capture_started_at : String,
  capture_completed_at : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  (@publication.RunEvidenceValue, @publication.PublicationContract),
  @publication.RunEvidenceValueIssue,
] {
  guard run.compilation is Tasks(compilation) &&
    compilation.infers.is_empty() &&
    compilation.serialization is None &&
    bind_client_task_run(run.owner, compilation, run.admission, definition)
    is Ok(_) else {
    return Err(@publication.RunEvidenceReferenceMismatch("task_run"))
  }
  if max_wire_bytes < 1 || max_nodes < 1 || max_depth < 1 {
    return Err(@publication.RunEvidenceInvalidLimits)
  }
  if !@publication.run_evidence_value_fits(
      source, max_wire_bytes, max_nodes, max_depth,
    ) ||
    !@publication.run_evidence_value_fits(
      input, max_wire_bytes, max_nodes, max_depth,
    ) {
    return Err(@publication.RunEvidenceInvalidWire)
  }
  if prepared_client_acquisition_count(run.owner) != 1 ||
    !client_single_direct_observation_covers_sources(run.owner) ||
    !client_source_acquisition_matches_program(run.owner, 0, 0, acquisition) ||
    !prepared_client_captured_task_source_matches(run.owner, capture, 0) ||
    !@query.captured_source_matches_input_acquisition(capture, acquisition) ||
    !@query.captured_source_relation_identity_matches_source(identity, capture) {
    return Err(@publication.RunEvidenceReferenceMismatch("source_coverage"))
  }
  guard @planning.source_acquisition_evidence_facts(acquisition) is Some(facts) else {
    return Err(@publication.RunEvidenceReferenceMismatch("source_policy"))
  }
  if prepared_client_publication_data_policy_cid(run.owner) !=
    Some(data_policy_cid) {
    return Err(
      @publication.RunEvidenceReferenceMismatch("publication_data_policy"),
    )
  }
  if @publication.admit_completed_source_input_logical(
      input,
      @query.captured_source_relation_logical_cid(identity),
      @query.captured_source_relation_schema_cid(identity),
      facts.source_contract_cid,
      "{\"stable\":false,\"keys\":[]}",
      max_wire_bytes,
      max_nodes,
      max_depth,
    )
    is Err(_) ||
    @publication.admit_completed_source_observation_binding(
      source,
      input,
      facts.source_ref,
      facts.source_contract_cid,
      authority_scope_cid,
      facts.source_data_policy_cid,
      max_wire_bytes,
      max_nodes,
      max_depth,
    )
    is Err(_) {
    return Err(@publication.RunEvidenceReferenceMismatch("source_evidence"))
  }
  issue_client_captured_observation_from_template(
    client_task_compilation_template(compilation),
    [@publication.run_evidence_value_identity(source)],
    data_policy_cid,
    capture_started_at,
    capture_completed_at,
    max_wire_bytes,
    max_nodes,
    max_depth,
  )
}
