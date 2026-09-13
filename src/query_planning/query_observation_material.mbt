///|
fn emit_query_observation(
  requirement : QueryRequirement,
  payload : QueryRecordPayload,
  cids : Array[String],
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  @encode.key(writer, "actual_access")
  emit_query_access(payload.access, writer)
  @encode.key(writer, "coverage")
  @encode.begin_object(writer)
  @encode.key(writer, "complete")
  @encode.bool_value(writer, true)
  @encode.key(writer, "filter_evidence_cid")
  @encode.string_value(writer, cids[1])
  @encode.key(writer, "scope_cid")
  @encode.string_value(writer, payload.scan_scope_cid)
  @encode.key(writer, "select_evidence_cid")
  @encode.string_value(writer, cids[2])
  @encode.key(writer, "source_validation_evidence_cid")
  @encode.string_value(writer, cids[0])
  @encode.end_object(writer)
  @encode.key(writer, "output")
  emit_query_output(payload.output, writer)
  @encode.key(writer, "owner")
  @encode.begin_object(writer)
  @encode.key(writer, "input")
  @encode.string_value(writer, requirement.input)
  @encode.key(writer, "program_source_cid")
  @encode.string_value(
    writer,
    @context.program_identity_definition_cid(requirement.program),
  )
  @encode.key(writer, "stage")
  @encode.string_value(writer, requirement.stage)
  @encode.end_object(writer)
  @encode.key(writer, "parameter_values_cid")
  @encode.string_value(writer, requirement.material.parameter_values_cid)
  @encode.key(writer, "requirement_cid")
  @encode.string_value(writer, requirement.cid)
  @encode.key(writer, "resolved_request_cid")
  @encode.string_value(writer, requirement.material.request_cid)
  @encode.key(writer, "retention")
  @encode.string_value(writer, "process")
  @encode.key(writer, "snapshot")
  emit_query_snapshot(payload.snapshot, writer)
  @encode.key(writer, "source_contract_cid")
  @encode.string_value(writer, requirement.source_contract_cid)
  @encode.key(writer, "source_ref")
  @encode.string_value(writer, requirement.source_ref)
  @encode.key(writer, "version")
  @encode.string_value(writer, "actql-query-observation/0.1")
  @encode.end_object(writer)
}
