///|
pub(all) enum ClientCapturedSourceLogicalIssue {
  ForeignPrepared
  ForeignIdentity
  ForeignRequirement
  Encoding(@encode.EncodeFailure)
  Evidence(@publication.RunEvidenceValueIssue)
  Admission(@publication.SourceInputLogicalIssue)
}

///|
/// Issue the logical input from the exact measured capture and checked task.
/// The existing source owner proves acquisition completion; this identity
/// grants neither physical source access nor permission to restart it.
pub fn issue_captured_source_input_logical(
  graph : @strategy.CheckedDAG,
  source : @query.CapturedInputSource,
  identity : @query.CapturedSourceRelationIdentity,
  requirement : @planning.QueryRequirement,
  task? : Int = 0,
) -> Result[@publication.RunEvidenceValue, ClientCapturedSourceLogicalIssue] {
  let program = @checked.source_identity(@strategy.graph_program(graph))
  guard task >= 0 &&
    task < @strategy.graph_captured_prefix(graph) &&
    @strategy.graph_task_owner(graph, task) is Some(source_owner) &&
    @query.captured_source_matches(source, program, source_owner) else {
    return Err(ForeignPrepared)
  }
  if !@query.captured_source_relation_identity_matches_source(identity, source) {
    return Err(ForeignIdentity)
  }
  guard @strategy.graph_task_owner(graph, task) is Some(owner) else {
    return Err(ForeignPrepared)
  }
  if !physical_equal(@planning.query_requirement_program(requirement), program) ||
    !physical_equal(
      @query.query_sequence_owner(
        @planning.query_material_owner(
          @planning.query_requirement_material(requirement),
        ),
      ),
      owner,
    ) {
    return Err(ForeignRequirement)
  }
  let rows = @query.captured_source_relation_logical_cid(identity)
  let schema = @query.captured_source_relation_schema_cid(identity)
  let source_contract = @planning.query_requirement_source(requirement).1
  let order = "{\"stable\":false,\"keys\":[]}"
  let writer = @encode.writer(4096, 128, 16) catch {
    issue => return Err(Encoding(issue))
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-source-input-logical/0.1")
    @encode.key(writer, "logical_relation_cid")
    @encode.string_value(writer, rows)
    @encode.key(writer, "relation_schema_cid")
    @encode.string_value(writer, schema)
    @encode.key(writer, "source_contract_cid")
    @encode.string_value(writer, source_contract)
    @encode.key(writer, "completeness")
    @encode.string_value(writer, "complete")
    @encode.key(writer, "ordering_evidence")
    @encode.begin_object(writer)
    @encode.key(writer, "stable")
    @encode.bool_value(writer, false)
    @encode.key(writer, "keys")
    @encode.begin_array(writer)
    @encode.end_array(writer)
    @encode.end_object(writer)
    @encode.end_object(writer)
  } catch {
    issue => return Err(Encoding(issue))
  }
  let body = @encode.finish(writer) catch {
    issue => return Err(Encoding(issue))
  }
  let evidence = match
    @publication.seal_run_evidence_value(
      "source_input_logical", body, 4096, 128, 16,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Evidence(issue))
  }
  match
    @publication.admit_completed_source_input_logical(
      evidence, rows, schema, source_contract, order, 4096, 128, 16,
    ) {
    Ok(_) => Ok(evidence)
    Err(issue) => Err(Admission(issue))
  }
}
