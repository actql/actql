///|
pub(all) enum ClientAcquisitionIssue {
  MissingStage
  MissingRequests
  UnsupportedAcquisition(@acquisition.QueryAcquisitionIssue)
}

///|
pub(all) enum ClientQueryRequirementIssue {
  Acquisition(ClientAcquisitionIssue)
  Sequence(@query.QuerySequenceIssue)
  Material(@planning.QueryMaterialIssue)
  Requirement(@planning.QueryRequirementIssue)
}

///|
/// Select a physical acquisition only from the requests sealed by the same
/// checked Program that owns the downstream Run graph. This remains a logical
/// acquisition; the Host must separately authorize a physical source and
/// retain its observed output before opening the captured Run.
pub fn prepare_client_query_acquisition(
  prepared : PreparedClientProgram,
  stage : Int,
  source_index : Int,
) -> Result[@acquisition.QueryAcquisition, ClientAcquisitionIssue] {
  let identity = @checked.source_identity(
    @strategy.graph_program(prepared.graph),
  )
  guard @context.program_identity_stage_at(identity, stage) is Some(_) else {
    return Err(MissingStage)
  }
  guard @context.program_identity_stage_requests(identity, stage)
    is Some(requests) else {
    return Err(MissingRequests)
  }
  @acquisition.derive_query_acquisition(requests, source_index, 1000000).map_err(issue => {
      UnsupportedAcquisition(issue)
    },
  )
}

///|
/// Derive the same checked acquisition from an Effectful Program without
/// exposing its private Effect-free graph view to an installed adapter.
pub fn prepare_client_effect_query_acquisition(
  prepared : PreparedClientEffectComputation,
  stage : Int,
  source_index : Int,
) -> Result[@acquisition.QueryAcquisition, ClientAcquisitionIssue] {
  prepare_client_query_acquisition(
    client_effect_program_view(prepared),
    stage,
    source_index,
  )
}

///|
/// Bind the selected source request to the exact checked generated sequence
/// and Program identity before a physical Connector candidate is considered.
pub fn prepare_client_query_requirement(
  prepared : PreparedClientProgram,
  generated : @execution.GeneratedSequence,
  stage : Int,
  source_index : Int,
  guards : @planning.QueryLogicalGuards,
  limits : @planning.QueryMaterialLimits,
) -> Result[@planning.QueryRequirement, ClientQueryRequirementIssue] {
  let acquisition = match
    prepare_client_query_acquisition(prepared, stage, source_index) {
    Ok(value) => value
    Err(issue) => return Err(Acquisition(issue))
  }
  let sequence = match
    @query.prepare_query_sequence(acquisition, generated, limits.max_work) {
    Ok(value) => value
    Err(issue) => return Err(Sequence(issue))
  }
  let material = match @planning.prepare_query_material(sequence, limits) {
    Ok(value) => value
    Err(issue) => return Err(Material(issue))
  }
  let identity = @checked.source_identity(
    @strategy.graph_program(prepared.graph),
  )
  @planning.prepare_query_requirement(material, identity, guards, limits).map_err(issue => {
      Requirement(issue)
    },
  )
}

///|
/// Keep acquisition requirements and their generated sequence under the
/// same checked Effect computation. This still grants no provider read.
pub fn prepare_client_effect_query_requirement(
  prepared : PreparedClientEffectComputation,
  generated : @execution.GeneratedSequence,
  stage : Int,
  source_index : Int,
  guards : @planning.QueryLogicalGuards,
  limits : @planning.QueryMaterialLimits,
) -> Result[@planning.QueryRequirement, ClientQueryRequirementIssue] {
  prepare_client_query_requirement(
    client_effect_program_view(prepared),
    generated,
    stage,
    source_index,
    guards,
    limits,
  )
}

///|
/// The graph seals the complete acquisition prefix. Physical task ordinals
/// outside this prefix cannot be substituted as acquired roots.
pub fn prepared_client_acquisition_count(value : PreparedClientProgram) -> Int {
  @strategy.graph_captured_prefix(value.graph)
}

///|
/// The original checked Catalog facts for one Source. These facts are used
/// to validate a later physical observation, never to authorize a file read.
pub fn prepared_client_source_evidence_facts(
  value : PreparedClientProgram,
  stage : Int,
  source_index : Int,
) -> @planning.QuerySourceEvidenceFacts? {
  prepare_client_query_acquisition(value, stage, source_index)
  .to_option()
  .bind(@planning.query_acquisition_source_evidence_facts)
}

///|
pub fn prepared_client_captured_task_source_matches(
  value : PreparedClientProgram,
  source : @query.CapturedInputSource,
  task : Int,
) -> Bool {
  if task < 0 || task >= prepared_client_acquisition_count(value) {
    return false
  }
  guard @strategy.graph_task_owner(value.graph, task) is Some(owner) else {
    return false
  }
  @query.captured_source_matches(
    source,
    @checked.source_identity(@strategy.graph_program(value.graph)),
    owner,
  )
}

///|
/// Bind the whole capture tuple to the exact task owner, even when two
/// captures have identical content, schemas, or source contract CIDs.
fn client_captured_task_tuple_matches(
  value : PreparedClientProgram,
  source : @query.CapturedInputSource,
  identity : @query.CapturedSourceRelationIdentity,
  requirement : @planning.QueryRequirement,
  task : Int,
) -> Bool {
  guard @strategy.graph_task_owner(value.graph, task) is Some(owner) else {
    return false
  }
  prepared_client_captured_task_source_matches(value, source, task) &&
  @query.captured_source_relation_identity_matches_source(identity, source) &&
  physical_equal(
    @planning.query_requirement_program(requirement),
    @checked.source_identity(@strategy.graph_program(value.graph)),
  ) &&
  physical_equal(
    @query.query_sequence_owner(
      @planning.query_material_owner(
        @planning.query_requirement_material(requirement),
      ),
    ),
    owner,
  )
}

///|
/// Resolve effective policy from every exact checked final Result occurrence.
/// Missing, incompatible, or incomplete two-source provenance is rejected;
/// the first acquisition policy is never promoted to a Run-wide policy.
pub fn prepared_client_publication_data_policy_cid(
  value : PreparedClientProgram,
) -> String? {
  let graph = value.graph
  let program = @strategy.graph_program(graph)
  let source_owner = @checked.source_identity(program)
  let count = @strategy.graph_result_count(graph)
  if count == 0 {
    return None
  }
  let mut selected : String? = None
  for result in 0..<count {
    guard @strategy.graph_result_task(graph, result) is Some(task) &&
      @strategy.graph_task_unit_index(graph, task) is Some(unit) &&
      @strategy.graph_result_occurrence(graph, result) is Some(occurrence) &&
      @strategy.graph_task_owner(graph, task) is Some(owner) &&
      physical_equal(
        @execution.managed_result_occurrence_owner(occurrence),
        owner,
      ) &&
      @checked.unit_publication_count(program, unit) is Some(publications) else {
      return None
    }
    let port = @execution.managed_result_occurrence_port(occurrence)
    let mut found : @checked.PublicationSourcePolicy? = None
    for index in 0..<publications {
      let publication = @checked.unit_publication_at(program, unit, index).unwrap()
      let resolution = @context.publication_row_limit_result(
        @checked.publication_selection(publication),
      )
      if resolution.stage == unit &&
        physical_equal(resolution.port, port) &&
        physical_equal(
          @results.port_result(resolution.port),
          @results.port_result(port),
        ) {
        if found is Some(_) {
          return None
        }
        found = @checked.publication_source_policy(publication)
      }
    }
    guard found is Some(policy) else { return None }
    if prepared_client_acquisition_count(value) == 2 {
      let covered = [false, false]
      if @checked.publication_policy_source_count(policy) != 2 {
        return None
      }
      for index in 0..<2 {
        let check = @checked.publication_policy_source_at(policy, index).unwrap()
        let subject = @checked.source_execution_subject(check)
        if !physical_equal(subject.owner, source_owner) ||
          subject.stage < 0 ||
          subject.stage > 1 ||
          subject.input != 0 ||
          covered[subject.stage] ||
          !(@checked.source_execution_kind(check) is @checked.CarrierResponse) {
          return None
        }
        covered[subject.stage] = true
      }
      if covered != [true, true] {
        return None
      }
    }
    match selected {
      None => selected = Some(policy.cid)
      Some(cid) => if cid != policy.cid { return None }
    }
  }
  selected
}
