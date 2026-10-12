///|
/// Close the actual Content completion under the same Run and admitted
/// Definition. Acquired input brings the checked original Source observation;
/// Model observations still require the joint capture path. An Effect Run can
/// borrow these observations, but they grant no approval or apply receipt and
/// do not establish its Effect completion or terminal success.
pub fn issue_client_serialization_invocation(
  run : ClientCompiledRun,
  definition : @publication.PublicationContract,
  generation : ClientSerializationGeneration,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  (@publication.RunEvidenceValue, @publication.PublicationContract),
  @publication.RunEvidenceValueIssue,
] {
  if check_client_compiled_run_definition(run, definition) is Err(_) ||
    @publication.publication_contract_identity(definition) !=
    @publication.publication_contract_identity(generation.definition) ||
    client_serialization_generation_output_for(generation, run) is None {
    return Err(@publication.RunEvidenceReferenceMismatch("content_generation"))
  }
  guard client_compiled_run_serialization(run) is Some(component) &&
    client_compiled_run_infers(run).is_empty() &&
    @publication.bound_content_generation_value(generation.evidence)
    is Some(evidence) &&
    @publication.bound_content_generation_availability(generation.evidence)
    is Some(availability) else {
    return Err(@publication.RunEvidenceReferenceMismatch("content_generation"))
  }
  let source_free = @strategy.graph_source_free_inputs_complete(run.owner.graph)
  let acquired = match generation.captured {
    Some(captured) if !source_free &&
      physical_equal(captured.owner, run.owner) &&
      captured.task == component.task &&
      captured.step == component.step =>
      Some(
        @publication.model_source_observation_originals(captured.observation),
      )
    None if source_free => None
    _ =>
      return Err(
        @publication.RunEvidenceReferenceMismatch("content_source_coverage"),
      )
  }
  let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(@publication.RunEvidenceEncoding)
  }
  let body = try {
    @encode.begin_object(writer)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-observation-set/0.1")
    @encode.key(writer, "invocation_template_cid")
    @encode.string_value(
      writer,
      @publication.run_evidence_value_identity(run.template),
    )
    for field in ["source_evidence_cids", "captured_input_artifact_cids"] {
      @encode.key(writer, field)
      @encode.begin_array(writer)
      if field == "source_evidence_cids" && acquired is Some((source, _, _, _)) {
        @encode.string_value(
          writer,
          @publication.run_evidence_value_identity(source),
        )
        if generation.captured is Some(captured) &&
          captured.keyed is Some(keyed) {
          @encode.string_value(
            writer,
            @publication.run_evidence_value_identity(keyed.source),
          )
        }
      }
      @encode.end_array(writer)
    }
    @encode.key(writer, "content_generation_cids")
    @encode.begin_array(writer)
    @encode.string_value(
      writer,
      @publication.run_evidence_value_identity(evidence),
    )
    @encode.end_array(writer)
    @encode.key(writer, "consistency")
    @encode.string_value(
      writer,
      if source_free {
        "no_external_sources"
      } else {
        "independent_snapshots"
      },
    )
    for field in ["capture_started_at", "capture_completed_at"] {
      @encode.key(writer, field)
      match acquired {
        Some((_, _, started, completed)) =>
          @encode.string_value(
            writer,
            if field == "capture_started_at" {
              started
            } else {
              completed
            },
          )
        None => @encode.null_value(writer)
      }
    }
    @encode.key(writer, "data_policy_cid")
    @encode.string_value(
      writer,
      @publication.captured_effect_dependency_body_cid(component.policy),
    )
    @encode.key(writer, "replayability")
    @encode.begin_object(writer)
    @encode.key(writer, "materialized")
    @encode.bool_value(writer, true)
    @encode.key(writer, "availability_evidence_cids")
    @encode.begin_array(writer)
    @encode.string_value(writer, availability)
    @encode.end_array(writer)
    @encode.end_object(writer)
    @encode.end_object(writer)
    @encode.finish(writer)
  } catch {
    _ => return Err(@publication.RunEvidenceEncoding)
  }
  let observation = match
    @publication.seal_run_evidence_value(
      "observation_set", body, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  @publication.issue_content_run_invocation(
    run.template,
    observation,
    [generation.evidence],
    max_wire_bytes,
    max_nodes,
    max_depth,
  ).map(invocation => (observation, invocation))
}

///|
pub fn client_serialization_generation_evidence_for(
  generation : ClientSerializationGeneration,
  run : ClientCompiledRun,
) -> @publication.RunEvidenceValue? {
  if !client_serialization_generation_available_for(generation, run) {
    return None
  }
  @publication.bound_content_generation_value(generation.evidence)
}

///|
pub fn client_serialization_generation_derivation_for(
  generation : ClientSerializationGeneration,
  run : ClientCompiledRun,
) -> @publication.RunEvidenceValue? {
  if !client_serialization_generation_available_for(generation, run) {
    return None
  }
  @publication.bound_content_generation_derivation(generation.evidence)
}
