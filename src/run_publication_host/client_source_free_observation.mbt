///|
/// A source-free Observation Set belongs to a checked compilation, not to a
/// caller-supplied Template CID. The installed Host supplies its data policy.
fn issue_client_source_free_invocation(
  template : @publication.RunEvidenceValue,
  data_policy_cid : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  (@publication.RunEvidenceValue, @publication.PublicationContract),
  @publication.RunEvidenceValueIssue,
] {
  let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(@publication.RunEvidenceValueIssue::RunEvidenceEncoding)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "capture_completed_at")
    @encode.null_value(writer)
    @encode.key(writer, "capture_started_at")
    @encode.null_value(writer)
    @encode.key(writer, "captured_input_artifact_cids")
    @encode.begin_array(writer)
    @encode.end_array(writer)
    @encode.key(writer, "consistency")
    @encode.string_value(writer, "no_external_sources")
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

///|
pub fn issue_client_values_source_free_invocation(
  compilation : ClientValuesCompilation,
  data_policy_cid : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  (@publication.RunEvidenceValue, @publication.PublicationContract),
  @publication.RunEvidenceValueIssue,
] {
  issue_client_source_free_invocation(
    client_values_compilation_template(compilation),
    data_policy_cid,
    max_wire_bytes,
    max_nodes,
    max_depth,
  )
}

///|
/// A source-free checked task graph uses the same no-external-source
/// observation as a direct Values compilation, bound to its own template.
pub fn issue_client_task_source_free_invocation(
  compilation : ClientTaskCompilation,
  data_policy_cid : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  (@publication.RunEvidenceValue, @publication.PublicationContract),
  @publication.RunEvidenceValueIssue,
] {
  // Absence of SourceView inputs does not mean absence of acquisition.
  // Model observations must enter the containing Invocation after capture.
  if compilation.infer is Some(_) {
    return Err(@publication.RunEvidenceReferenceMismatch("model_capture"))
  }
  if !@strategy.graph_source_free_inputs_complete(compilation.owner.graph) {
    return Err(
      @publication.RunEvidenceValueIssue::RunEvidenceReferenceMismatch(
        "source_free_compilation",
      ),
    )
  }
  issue_client_source_free_invocation(
    client_task_compilation_template(compilation),
    data_policy_cid,
    max_wire_bytes,
    max_nodes,
    max_depth,
  )
}

///|
pub fn issue_client_effect_source_free_invocation(
  compilation : ClientEffectCompilation,
  data_policy_cid : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  (@publication.RunEvidenceValue, @publication.PublicationContract),
  @publication.RunEvidenceValueIssue,
] {
  issue_client_source_free_invocation(
    client_effect_compilation_template(compilation),
    data_policy_cid,
    max_wire_bytes,
    max_nodes,
    max_depth,
  )
}
