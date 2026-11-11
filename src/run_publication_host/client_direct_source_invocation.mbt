///|
/// Original checked acquisition kind, not a Query/Whole conversion, read
/// grant or another resource owner. Installed callers retain these originals.
pub(all) enum ClientDirectSourceOriginal {
  QuerySourceOriginal(@planning.QueryRequirement)
  WholeSourceOriginal(@acquisition.SourceAcquisition)
}

///|
/// Bind complete mixed Direct Source observations to the SAME Effect Run.
/// Model and generation observations retain their distinct existing issuers.
pub fn issue_client_effect_direct_sources_invocation(
  prepared : PreparedClientEffectComputation,
  compilation : ClientEffectCompilation,
  admission : @publication.RunPublicationAdmission,
  definition : @publication.PublicationContract,
  occurrences : ClientDirectAcquisitionOccurrences,
  captures : Array[@query.CapturedInputSource],
  identities : Array[@query.CapturedSourceRelationIdentity],
  originals : Array[ClientDirectSourceOriginal],
  sources : Array[@publication.RunEvidenceValue],
  inputs : Array[@publication.RunEvidenceValue],
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
  if !physical_equal(compilation.owner, prepared) ||
    !client_direct_acquisition_occurrences_match_effect_program(
      occurrences, prepared,
    ) ||
    bind_prepared_client_effect_run(prepared, admission, definition) is Err(_) {
    return Err(@publication.RunEvidenceReferenceMismatch("effect_run"))
  }
  if !compilation.compiled.infers.is_empty() {
    return Err(@publication.RunEvidenceReferenceMismatch("model_capture"))
  }
  if compilation.compiled.serialization is Some(_) {
    return Err(@publication.RunEvidenceReferenceMismatch("content_generation"))
  }
  issue_client_direct_source_observation(
    client_effect_program_view(prepared),
    client_effect_compilation_template(compilation),
    occurrences,
    captures,
    identities,
    originals,
    sources,
    inputs,
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
fn issue_client_direct_source_observation(
  prepared : PreparedClientProgram,
  template : @publication.RunEvidenceValue,
  occurrences : ClientDirectAcquisitionOccurrences,
  captures : Array[@query.CapturedInputSource],
  identities : Array[@query.CapturedSourceRelationIdentity],
  originals : Array[ClientDirectSourceOriginal],
  sources : Array[@publication.RunEvidenceValue],
  inputs : Array[@publication.RunEvidenceValue],
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
  prepare_client_direct_source_observation(
    prepared, template, occurrences, captures, identities, originals, sources, inputs,
    authority_scope_cid, data_policy_cid, capture_started_at, capture_completed_at,
    max_wire_bytes, max_nodes, max_depth,
  ).map(value => (value.observation, value.invocation))
}

///|
fn prepare_client_direct_source_observation(
  prepared : PreparedClientProgram,
  template : @publication.RunEvidenceValue,
  occurrences : ClientDirectAcquisitionOccurrences,
  captures : Array[@query.CapturedInputSource],
  identities : Array[@query.CapturedSourceRelationIdentity],
  originals : Array[ClientDirectSourceOriginal],
  sources : Array[@publication.RunEvidenceValue],
  inputs : Array[@publication.RunEvidenceValue],
  authority_scope_cid : String,
  data_policy_cid : String,
  capture_started_at : String,
  capture_completed_at : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientDirectSourceObservation, @publication.RunEvidenceValueIssue] {
  if max_wire_bytes < 1 || max_nodes < 1 || max_depth < 1 {
    return Err(@publication.RunEvidenceInvalidLimits)
  }
  let count = captures.length()
  if count < 1 ||
    count > max_nodes ||
    identities.length() != count ||
    originals.length() != count ||
    sources.length() != count ||
    inputs.length() != count ||
    !client_direct_observations_cover_sources(prepared, count) {
    return Err(@publication.RunEvidenceReferenceMismatch("source_coverage"))
  }
  if client_direct_acquisition_occurrence_count(occurrences) != count {
    return Err(@publication.RunEvidenceReferenceMismatch("source_coverage"))
  }
  let publication_policy = prepared_client_publication_data_policy_cid(prepared)
  for index, capture in captures {
    let identity = identities[index]
    let original = originals[index]
    let source = sources[index]
    let input = inputs[index]
    guard client_direct_acquisition_occurrence_at(occurrences, index)
      is Some((stage, ordinal, task)) &&
      prepared_client_captured_task_source_matches(prepared, capture, task) &&
      @query.captured_source_relation_identity_matches_source(identity, capture) else {
      return Err(@publication.RunEvidenceReferenceMismatch("source_coverage"))
    }
    let facts = match original {
      QuerySourceOriginal(requirement) => {
        if !client_captured_task_tuple_matches(
            prepared, capture, identity, requirement, task,
          ) ||
          !@query.captured_source_matches_query(
            capture,
            @planning.query_material_owner(
              @planning.query_requirement_material(requirement),
            ),
          ) {
          return Err(@publication.RunEvidenceReferenceMismatch("source_task"))
        }
        match @planning.query_requirement_source_evidence_facts(requirement) {
          Some(value) => value
          None =>
            return Err(
              @publication.RunEvidenceReferenceMismatch("source_policy"),
            )
        }
      }
      WholeSourceOriginal(acquisition) => {
        if !client_source_acquisition_matches_program(
            prepared, stage, ordinal, acquisition,
          ) ||
          !@query.captured_source_matches_input_acquisition(
            capture, acquisition,
          ) {
          return Err(@publication.RunEvidenceReferenceMismatch("source_task"))
        }
        match @planning.source_acquisition_evidence_facts(acquisition) {
          Some(value) => value
          None =>
            return Err(
              @publication.RunEvidenceReferenceMismatch("source_policy"),
            )
        }
      }
    }
    if !@publication.run_evidence_value_fits(
        source, max_wire_bytes, max_nodes, max_depth,
      ) ||
      !@publication.run_evidence_value_fits(
        input, max_wire_bytes, max_nodes, max_depth,
      ) {
      return Err(@publication.RunEvidenceInvalidWire)
    }
    if publication_policy != Some(data_policy_cid) {
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
  }
  // An earlier Source may be retired by a later original liveness callback.
  if !captures.all(@query.captured_source_available) {
    return Err(@publication.RunEvidenceReferenceMismatch("source_task"))
  }
  let (observation, invocation) = match
    issue_client_captured_observation_from_template(
      template,
      sources.map(@publication.run_evidence_value_identity),
      data_policy_cid,
      capture_started_at,
      capture_completed_at,
      max_wire_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({
    occurrences,
    captures: captures.copy(),
    identities: identities.copy(),
    originals: originals.copy(),
    sources: sources.copy(),
    inputs: inputs.copy(),
    observation,
    invocation,
  })
}

///|
/// Retain the originals admitted once for this same Run; this is no completion.
pub fn prepare_client_effect_direct_sources_publication(
  prepared : PreparedClientEffectComputation,
  compilation : ClientEffectCompilation,
  admission : @publication.RunPublicationAdmission,
  definition : @publication.PublicationContract,
  occurrences : ClientDirectAcquisitionOccurrences,
  captures : Array[@query.CapturedInputSource],
  identities : Array[@query.CapturedSourceRelationIdentity],
  originals : Array[ClientDirectSourceOriginal],
  sources : Array[@publication.RunEvidenceValue],
  inputs : Array[@publication.RunEvidenceValue],
  authority_scope_cid : String,
  data_policy_cid : String,
  capture_started_at : String,
  capture_completed_at : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  ClientEffectDirectSourcesPublication,
  @publication.RunEvidenceValueIssue,
] {
  if !physical_equal(compilation.owner, prepared) ||
    !client_direct_acquisition_occurrences_match_effect_program(
      occurrences, prepared,
    ) ||
    bind_prepared_client_effect_run(prepared, admission, definition) is Err(_) {
    return Err(@publication.RunEvidenceReferenceMismatch("effect_run"))
  }
  if !compilation.compiled.infers.is_empty() {
    return Err(@publication.RunEvidenceReferenceMismatch("model_capture"))
  }
  if compilation.compiled.serialization is Some(_) {
    return Err(@publication.RunEvidenceReferenceMismatch("content_generation"))
  }
  prepare_client_direct_source_observation(
    client_effect_program_view(prepared),
    client_effect_compilation_template(compilation),
    occurrences,
    captures,
    identities,
    originals,
    sources,
    inputs,
    authority_scope_cid,
    data_policy_cid,
    capture_started_at,
    capture_completed_at,
    max_wire_bytes,
    max_nodes,
    max_depth,
  ).map(value => {
    owner: prepared,
    source: value,
    run_definition_cid: @publication.publication_contract_identity(definition),
  })
}
