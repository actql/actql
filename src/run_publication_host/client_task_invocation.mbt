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
  if compilation.infer is Some(_) {
    return Err(@publication.RunEvidenceReferenceMismatch("model_capture"))
  }
  if prepared_client_acquisition_count(prepared) != 1 ||
    bind_client_task_run(prepared, compilation, admission, run_definition)
    is Err(_) {
    return Err(
      @publication.RunEvidenceValueIssue::RunEvidenceReferenceMismatch(
        "task_run",
      ),
    )
  }
  issue_client_captured_invocation_from_template(
    client_task_compilation_template(compilation),
    source_evidence_wire,
    input_logical_wire,
    source_ref,
    source_contract_cid,
    authority_scope_cid,
    data_policy_cid,
    capture_started_at,
    capture_completed_at,
    max_wire_bytes,
    max_nodes,
    max_depth,
  )
}

///|
/// The checked Effect compilation and captured root must belong to the
/// admitted Run. Source Evidence is admitted against that exact source before
/// it becomes an Observation Set; an equal CID is not an owner substitute.
pub fn issue_client_effect_captured_invocation(
  prepared : PreparedClientEffectComputation,
  compilation : ClientEffectCompilation,
  admission : @publication.RunPublicationAdmission,
  run_definition : @publication.PublicationContract,
  captured_source : @query.CapturedInputSource,
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
  let graph = @strategy.checked_effect_computation_graph(prepared.graph)
  guard @strategy.graph_task_owner(graph, 0) is Some(first) else {
    return Err(
      @publication.RunEvidenceValueIssue::RunEvidenceReferenceMismatch(
        "source_task",
      ),
    )
  }
  if !physical_equal(compilation.owner, prepared) ||
    !@query.captured_source_matches(
      captured_source,
      @checked.source_identity(@strategy.graph_program(graph)),
      first,
    ) ||
    @publication.check_run_publication_program_binding(
      admission,
      run_definition,
      prepared_client_effect_computation_definition_cid(prepared),
      prepared_client_effect_computation_semantics_cid(prepared),
      prepared_client_effect_computation_environment_cid(prepared),
    )
    is Err(_) {
    return Err(
      @publication.RunEvidenceValueIssue::RunEvidenceReferenceMismatch(
        "effect_run",
      ),
    )
  }
  issue_client_captured_invocation_from_template(
    client_effect_compilation_template(compilation),
    source_evidence_wire,
    input_logical_wire,
    source_ref,
    source_contract_cid,
    authority_scope_cid,
    data_policy_cid,
    capture_started_at,
    capture_completed_at,
    max_wire_bytes,
    max_nodes,
    max_depth,
  )
}

///|
fn issue_client_captured_invocation_from_template(
  template : @publication.RunEvidenceValue,
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
  issue_client_captured_observation_from_template(
    template,
    [@publication.run_evidence_value_identity(source)],
    data_policy_cid,
    capture_started_at,
    capture_completed_at,
    max_wire_bytes,
    max_nodes,
    max_depth,
  )
}

///|
/// One Observation Set grammar covers the complete acquired inventory.
fn issue_client_captured_observation_from_template(
  template : @publication.RunEvidenceValue,
  source_evidence_cids : Array[String],
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
    for cid in source_evidence_cids {
      @encode.string_value(writer, cid)
    }
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
/// The two acquired task occurrences, identities, requirements, and evidence
/// must cover the checked prefix exactly and in task order. No serialized CID
/// may replace the live checked owner, and no successful side is sufficient.
pub fn issue_client_multi_task_invocation(
  prepared : PreparedClientProgram,
  compilation : ClientTaskCompilation,
  admission : @publication.RunPublicationAdmission,
  run_definition : @publication.PublicationContract,
  captures : Array[@query.CapturedInputSource],
  identities : Array[@query.CapturedSourceRelationIdentity],
  requirements : Array[@planning.QueryRequirement],
  source_evidence_wires : Array[String],
  input_logical_wires : Array[String],
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
  // Source observations cannot discharge the model capture custody boundary.
  if compilation.infer is Some(_) {
    return Err(@publication.RunEvidenceReferenceMismatch("model_capture"))
  }
  if bind_client_task_run(prepared, compilation, admission, run_definition)
    is Err(_) {
    return Err(@publication.RunEvidenceReferenceMismatch("task_run"))
  }
  if prepared_client_acquisition_count(prepared) != 2 ||
    captures.length() != 2 ||
    identities.length() != 2 ||
    requirements.length() != 2 ||
    source_evidence_wires.length() != 2 ||
    input_logical_wires.length() != 2 {
    return Err(@publication.RunEvidenceReferenceMismatch("source_coverage"))
  }
  if prepared_client_publication_data_policy_cid(prepared) !=
    Some(data_policy_cid) {
    return Err(
      @publication.RunEvidenceReferenceMismatch("publication_data_policy"),
    )
  }
  let source_cids : Array[String] = []
  for task in 0..<2 {
    let captured = captures[task]
    let identity = identities[task]
    let requirement = requirements[task]
    if !client_captured_task_tuple_matches(
        prepared, captured, identity, requirement, task,
      ) {
      return Err(@publication.RunEvidenceReferenceMismatch("source_task"))
    }
    guard @planning.query_requirement_source_evidence_facts(requirement)
      is Some(facts) else {
      return Err(@publication.RunEvidenceReferenceMismatch("source_policy"))
    }
    let source = match
      @publication.admit_run_evidence_value(
        "source_evidence",
        source_evidence_wires[task],
        max_wire_bytes,
        max_nodes,
        max_depth,
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let input = match
      @publication.admit_run_evidence_value(
        "source_input_logical",
        input_logical_wires[task],
        max_wire_bytes,
        max_nodes,
        max_depth,
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let (source_ref, source_contract) = @planning.query_requirement_source(
      requirement,
    )
    if @publication.admit_completed_source_input_logical(
        input,
        @query.captured_source_relation_logical_cid(identity),
        @query.captured_source_relation_schema_cid(identity),
        source_contract,
        "{\"stable\":false,\"keys\":[]}",
        max_wire_bytes,
        max_nodes,
        max_depth,
      )
      is Err(_) ||
      @publication.admit_completed_source_observation_binding(
        source,
        input,
        source_ref,
        source_contract,
        authority_scope_cid,
        facts.source_data_policy_cid,
        max_wire_bytes,
        max_nodes,
        max_depth,
      )
      is Err(_) {
      return Err(@publication.RunEvidenceReferenceMismatch("source_evidence"))
    }
    source_cids.push(@publication.run_evidence_value_identity(source))
  }
  issue_client_captured_observation_from_template(
    client_task_compilation_template(compilation),
    source_cids,
    data_policy_cid,
    capture_started_at,
    capture_completed_at,
    max_wire_bytes,
    max_nodes,
    max_depth,
  )
}
