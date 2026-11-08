///|
/// A keyed observation is accepted only with the exact original Direct capture
/// and complete checked Source inventory. A captured task prefix alone does not
/// establish that a later keyed Source has been acquired.
pub fn issue_client_compiled_keyed_task_invocation(
  run : ClientCompiledRun,
  definition : @publication.PublicationContract,
  capture : @query.CapturedInputSource,
  identity : @query.CapturedSourceRelationIdentity,
  requirement : @planning.QueryRequirement,
  source_evidence_wire : String,
  input_logical_wire : String,
  keyed : ClientKeyedLookupObservation,
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
  let (compilation, left, right) = match
    client_keyed_invocation_original_facts(
      run, definition, capture, identity, requirement, keyed, data_policy_cid,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
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
  issue_client_keyed_invocation_from_originals(
    compilation, identity, source, input, keyed, left, right, authority_scope_cid,
    data_policy_cid, capture_started_at, capture_completed_at, max_wire_bytes, max_nodes,
    max_depth,
  )
}

///|
fn issue_client_compiled_keyed_task_invocation_original(
  run : ClientCompiledRun,
  definition : @publication.PublicationContract,
  capture : @query.CapturedInputSource,
  identity : @query.CapturedSourceRelationIdentity,
  requirement : @planning.QueryRequirement,
  source : @publication.RunEvidenceValue,
  input : @publication.RunEvidenceValue,
  keyed : ClientKeyedLookupObservation,
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
  let (compilation, left, right) = match
    client_keyed_invocation_original_facts(
      run, definition, capture, identity, requirement, keyed, data_policy_cid,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  issue_client_keyed_invocation_from_originals(
    compilation, identity, source, input, keyed, left, right, authority_scope_cid,
    data_policy_cid, capture_started_at, capture_completed_at, max_wire_bytes, max_nodes,
    max_depth,
  )
}

///|
fn client_keyed_invocation_original_facts(
  run : ClientCompiledRun,
  definition : @publication.PublicationContract,
  capture : @query.CapturedInputSource,
  identity : @query.CapturedSourceRelationIdentity,
  requirement : @planning.QueryRequirement,
  keyed : ClientKeyedLookupObservation,
  data_policy_cid : String,
) -> Result[
  (
    ClientTaskCompilation,
    @planning.QuerySourceEvidenceFacts,
    @planning.QuerySourceEvidenceFacts,
  ),
  @publication.RunEvidenceValueIssue,
] {
  guard run.compilation is Tasks(compilation) &&
    compilation.infers.is_empty() &&
    bind_client_task_run(run.owner, compilation, run.admission, definition)
    is Ok(_) else {
    return Err(@publication.RunEvidenceReferenceMismatch("task_run"))
  }
  let lookup = keyed.lookup
  let acquisition = lookup.left.acquisition
  guard acquisition.program is KeyedPure(owner) &&
    physical_equal(owner, run.owner) &&
    client_keyed_left_single_source_matches(lookup.left, capture) &&
    client_captured_task_tuple_matches(owner, capture, identity, requirement, 0) &&
    client_keyed_lookup_observation_wires(keyed) is Some(_) else {
    return Err(@publication.RunEvidenceReferenceMismatch("source_owner"))
  }
  if !client_keyed_observation_covers_sources(owner, acquisition, requirement) {
    return Err(@publication.RunEvidenceReferenceMismatch("source_coverage"))
  }
  if prepared_client_publication_data_policy_cid(owner) != Some(data_policy_cid) {
    return Err(
      @publication.RunEvidenceReferenceMismatch("publication_data_policy"),
    )
  }
  guard @planning.query_requirement_source_evidence_facts(requirement)
    is Some(left) &&
    @planning.keyed_source_evidence_facts(acquisition.facts) is Some(right) else {
    return Err(@publication.RunEvidenceReferenceMismatch("source_policy"))
  }
  Ok((compilation, left, right))
}

///|
fn issue_client_keyed_invocation_from_originals(
  compilation : ClientTaskCompilation,
  identity : @query.CapturedSourceRelationIdentity,
  source : @publication.RunEvidenceValue,
  input : @publication.RunEvidenceValue,
  keyed : ClientKeyedLookupObservation,
  left : @planning.QuerySourceEvidenceFacts,
  right : @planning.QuerySourceEvidenceFacts,
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
  if @publication.admit_completed_source_input_logical(
      input,
      @query.captured_source_relation_logical_cid(identity),
      @query.captured_source_relation_schema_cid(identity),
      left.source_contract_cid,
      "{\"stable\":false,\"keys\":[]}",
      max_wire_bytes,
      max_nodes,
      max_depth,
    )
    is Err(_) ||
    @publication.admit_completed_source_observation_binding(
      source,
      input,
      left.source_ref,
      left.source_contract_cid,
      authority_scope_cid,
      left.source_data_policy_cid,
      max_wire_bytes,
      max_nodes,
      max_depth,
    )
    is Err(_) ||
    @publication.admit_completed_source_observation_binding(
      keyed.source,
      keyed.input,
      right.source_ref,
      right.source_contract_cid,
      authority_scope_cid,
      right.source_data_policy_cid,
      max_wire_bytes,
      max_nodes,
      max_depth,
    )
    is Err(_) {
    return Err(@publication.RunEvidenceReferenceMismatch("source_evidence"))
  }
  issue_client_captured_observation_from_template(
    client_task_compilation_template(compilation),
    [
      @publication.run_evidence_value_identity(source),
      @publication.run_evidence_value_identity(keyed.source),
    ],
    data_policy_cid,
    capture_started_at,
    capture_completed_at,
    max_wire_bytes,
    max_nodes,
    max_depth,
  )
}

///|
/// Count physical Source selections, not their separate authorization/egress/
/// resource obligations. Repeated keyed JOIN occurrences remain separate;
/// equal Source CIDs cannot hide an omitted or independently owned selection.
fn client_keyed_observation_covers_sources(
  owner : PreparedClientProgram,
  keyed : ClientKeyedAcquisition,
  requirement : @planning.QueryRequirement,
) -> Bool {
  if prepared_client_acquisition_count(owner) != 1 {
    return false
  }
  let query = @query.query_sequence_requirement(
    @planning.query_material_owner(
      @planning.query_requirement_material(requirement),
    ),
  )
  let direct_input = @acquisition.query_acquisition_source_index(query)
  let checked = @strategy.graph_program(owner.graph)
  let mut selections = 0
  let mut direct = 0
  let mut requests = 0
  for index in 0..<@checked.source_execution_count(checked) {
    let check = @checked.source_execution_at(checked, index).unwrap()
    let subject = @checked.source_execution_subject(check)
    match @checked.source_execution_kind(check) {
      @checked.HostCombination => selections += 1
      @checked.CarrierResponse =>
        if subject.request is @acquisition.Direct(_, _) {
          if subject.stage != keyed.binding.stage ||
            subject.input != direct_input {
            return false
          }
          direct += 1
        }
      @checked.KeyedRequest(_) => {
        if !physical_equal(check, keyed.check) {
          return false
        }
        requests += 1
      }
      _ => ()
    }
  }
  selections == 2 && direct == 1 && requests == 1
}

///|
/// The legacy single-observation issuer is complete only for one Direct
/// selection. A later keyed request cannot be discharged by its left prefix.
fn client_single_direct_observation_covers_sources(
  owner : PreparedClientProgram,
) -> Bool {
  client_direct_observations_cover_sources(owner, 1)
}

///|
fn client_direct_observations_cover_sources(
  owner : PreparedClientProgram,
  count : Int,
) -> Bool {
  let checked = @strategy.graph_program(owner.graph)
  let mut selections = 0
  for index in 0..<@checked.source_execution_count(checked) {
    let check = @checked.source_execution_at(checked, index).unwrap()
    match @checked.source_execution_kind(check) {
      @checked.HostCombination => {
        if !(@checked.source_execution_subject(check).request
          is @acquisition.Direct(_, _)) {
          return false
        }
        selections += 1
      }
      @checked.KeyedRequest(_) => return false
      _ => ()
    }
  }
  selections == count
}
