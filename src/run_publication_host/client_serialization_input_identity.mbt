///|
/// Existing closed Content proof codec: input Artifact, derivation and
/// generation. The latter two issuers already enforce these bounds. The input
/// Artifact has nine String fields (version plus eight original CIDs), three
/// nonnegative Int fields and its sealed identity; it embeds no row, schema,
/// Program body or Source response. Empty invocation bindings are fixed too.
/// These are codec bounds, not a Resource allowance or a new proof owner.
pub fn client_serialization_evidence_codec_bounds() -> (Int, Int, Int) {
  (16384, 256, 16)
}

///|
/// A borrowed identity proof, not another input/capture/cleanup owner. Its
/// receipt comes from the existing bounded completed-Relation export. This
/// token binds actual content to this compiler and exact completed input.
struct ClientSerializationInputEvidence {
  run : ClientCompiledRun
  input : ClientSerializationInput
  artifact : @publication.RunEvidenceValue
  captured : ClientSerializationCapturedInput?
}

///|
pub fn start_client_serialization_input_identity(
  input : ClientSerializationInput,
  values : @execution.ValueLimits,
  payload_wire : @execution.RowWireLimits,
  logical_wire : @execution.RowWireLimits,
  schema : @execution.RelationSchemaIdentityLimits,
  max_work : Int,
  max_workspace_slots : Int,
) -> Result[
  @execution.CompletedRelationIdentityScan,
  @execution.CompletedExportIssue,
] {
  @execution.start_completed_relation_identity_scan(
    input.input,
    input.rows,
    values,
    payload_wire,
    logical_wire,
    schema,
    max_work,
    max_workspace_slots,
  )
}

///|
/// Only an export of the original input may establish its Artifact. Equal
/// rows, a producer fragment CID or another Run's receipt are insufficient.
pub fn bind_client_serialization_input_identity(
  run : ClientCompiledRun,
  input : ClientSerializationInput,
  receipt : @execution.CompletedRelationExportReceipt,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  ClientSerializationInputEvidence,
  @publication.RunEvidenceValueIssue,
] {
  if !@strategy.graph_source_free_inputs_complete(run.owner.graph) {
    return Err(
      @publication.RunEvidenceReferenceMismatch("content_input_artifact"),
    )
  }
  bind_client_serialization_input_identity_owned(
    run,
    input,
    receipt,
    max_wire_bytes,
    max_nodes,
    max_depth,
    None,
  )
}

///|
/// An acquired input requires its live original capture proof, not merely an
/// export of equal rows or a Source evidence CID supplied by a caller.
pub fn bind_client_acquired_serialization_input_identity(
  run : ClientCompiledRun,
  input : ClientSerializationInput,
  receipt : @execution.CompletedRelationExportReceipt,
  captured : ClientSerializationCapturedInput,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  ClientSerializationInputEvidence,
  @publication.RunEvidenceValueIssue,
] {
  if !client_serialization_captured_input_matches(captured, run, input) {
    return Err(
      @publication.RunEvidenceReferenceMismatch("content_source_owner"),
    )
  }
  bind_client_serialization_input_identity_owned(
    run,
    input,
    receipt,
    max_wire_bytes,
    max_nodes,
    max_depth,
    Some(captured),
  )
}

///|
fn bind_client_serialization_input_identity_owned(
  run : ClientCompiledRun,
  input : ClientSerializationInput,
  receipt : @execution.CompletedRelationExportReceipt,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  captured : ClientSerializationCapturedInput?,
) -> Result[
  ClientSerializationInputEvidence,
  @publication.RunEvidenceValueIssue,
] {
  guard client_compiled_run_serialization(run) is Some(component) &&
    physical_equal(component.owner, run.owner) &&
    physical_equal(
      @lower.serialization_owner(component.barrier),
      @lower.serialization_owner(input.barrier),
    ) &&
    @lower.serialization_step(component.barrier) ==
    @lower.serialization_step(input.barrier) &&
    @execution.completed_relation_export_matches_output(receipt, input.input) else {
    return Err(
      @publication.RunEvidenceReferenceMismatch("content_input_artifact"),
    )
  }
  let rows = @execution.completed_relation_export_measurement(receipt).row_count
  if rows != input.rows {
    return Err(
      @publication.RunEvidenceReferenceMismatch("content_input_artifact.rows"),
    )
  }
  // Keep caller refusals below the existing closed proof bounds. A large
  // generic contract decoder ceiling cannot become this constructor's size.
  let (proof_bytes, proof_nodes, proof_depth) = client_serialization_evidence_codec_bounds()
  let max_wire_bytes = Int::min(max_wire_bytes, proof_bytes)
  let max_nodes = Int::min(max_nodes, proof_nodes)
  let max_depth = Int::min(max_depth, proof_depth)
  let bindings = match
    issue_prepared_client_empty_invocation_bindings(
      run.owner,
      max_wire_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(_) =>
      return Err(
        @publication.RunEvidenceReferenceMismatch("invocation_bindings"),
      )
  }
  let identity = prepared_client_identity(run.owner)
  let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(@publication.RunEvidenceEncoding)
  }
  let body = try {
    @encode.begin_object(writer)
    for
      (key, value) in [
        ("version", "actql-content-input-artifact/0.1"),
        ("program_definition_cid", identity.program_definition_cid),
        ("parameter_values_cid", identity.parameter_values_cid),
        (
          "invocation_bindings_cid",
          @publication.run_evidence_value_identity(bindings),
        ),
        ("input_fragment_cid", component.input.logical_cid),
        (
          "logical_relation_cid",
          @execution.logical_relation_cid(
            @execution.completed_relation_export_identity(receipt),
          ),
        ),
        (
          "relation_schema_cid",
          @execution.relation_schema_cid(
            @execution.completed_relation_export_schema_identity(receipt),
          ),
        ),
        (
          "ordered_rows_cid",
          @execution.output_stream_identity(
            @execution.completed_relation_export_content(receipt),
          ).0,
        ),
        (
          "effective_data_policy_cid",
          @publication.captured_effect_dependency_body_cid(component.policy),
        ),
      ] {
      @encode.key(writer, key)
      @encode.string_value(writer, value)
    }
    for
      (key, value) in [
        ("task_ordinal", component.task),
        ("step_ordinal", component.step),
        ("row_count", rows),
      ] {
      @encode.key(writer, key)
      @encode.number_value(writer, value.to_double())
    }
    @encode.end_object(writer)
    @encode.finish(writer)
  } catch {
    _ => return Err(@publication.RunEvidenceEncoding)
  }
  @publication.seal_run_evidence_value(
    "content_input_artifact", body, max_wire_bytes, max_nodes, max_depth,
  ).map(artifact => { run, input, artifact, captured, })
}

///|
pub fn client_serialization_input_artifact(
  evidence : ClientSerializationInputEvidence,
) -> @publication.RunEvidenceValue {
  evidence.artifact
}
