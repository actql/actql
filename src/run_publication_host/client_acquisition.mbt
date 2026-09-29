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
