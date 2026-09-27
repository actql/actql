///|
/// Bind a completed source observation to the exact checked task Run.
pub fn issue_client_task_invocation(
  prepared : PreparedClientProgram,
  compilation : ClientTaskCompilation,
  admission : @publication.RunPublicationAdmission,
  run_definition : @publication.PublicationContract,
  source_evidence_wire : String,
  input_logical_wire : String,
  source_ref : String,
  source_contract_cid : String,
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
  if bind_client_task_run(prepared, compilation, admission, run_definition)
    is Err(_) {
    return Err(
      @publication.RunEvidenceValueIssue::RunEvidenceReferenceMismatch(
        "task_run",
      ),
    )
  }
  let source = match
    @publication.admit_run_evidence_value(
      "source_evidence", source_evidence_wire, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let input = match
    @publication.admit_run_evidence_value(
      "source_input_logical", input_logical_wire, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if @publication.admit_completed_source_observation_binding(
      source, input, source_ref, source_contract_cid, authority_scope_cid, data_policy_cid,
      max_wire_bytes, max_nodes, max_depth,
    )
    is Err(_) {
    return Err(
      @publication.RunEvidenceValueIssue::RunEvidenceReferenceMismatch(
        "source_evidence",
      ),
    )
  }
  let template = client_task_compilation_template(compilation)
  let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(@publication.RunEvidenceValueIssue::RunEvidenceEncoding)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "capture_completed_at")
    @encode.string_value(writer, capture_completed_at)
    @encode.key(writer, "capture_started_at")
    @encode.string_value(writer, capture_started_at)
    @encode.key(writer, "captured_input_artifact_cids")
    @encode.begin_array(writer)
    @encode.end_array(writer)
    @encode.key(writer, "consistency")
    @encode.string_value(writer, "independent_snapshots")
    @encode.key(writer, "data_policy_cid")
    @encode.string_value(writer, data_policy_cid)
    @encode.key(writer, "invocation_template_cid")
    @encode.string_value(
      writer,
      @publication.run_evidence_value_identity(template),
    )
    @encode.key(writer, "replayability")
    @encode.begin_object(writer)
    @encode.key(writer, "availability_evidence_cids")
    @encode.begin_array(writer)
    @encode.end_array(writer)
    @encode.key(writer, "materialized")
    @encode.bool_value(writer, false)
    @encode.end_object(writer)
    @encode.key(writer, "source_evidence_cids")
    @encode.begin_array(writer)
    @encode.string_value(
      writer,
      @publication.run_evidence_value_identity(source),
    )
    @encode.end_array(writer)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-observation-set/0.1")
    @encode.end_object(writer)
  } catch {
    _ => return Err(@publication.RunEvidenceValueIssue::RunEvidenceEncoding)
  }
  let body = @encode.finish(writer) catch {
    _ => return Err(@publication.RunEvidenceValueIssue::RunEvidenceEncoding)
  }
  let observation = match
    @publication.seal_run_evidence_value(
      "observation_set", body, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let invocation = match
    @publication.issue_run_invocation(
      template, observation, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok((observation, invocation))
}
