///|
/// Exact acquired input identity, not execution or egress permission. The
/// captured source remains owned by the Host until its model consumer stops.
pub struct ClientInferCapturedInput {
  owner : PreparedClientProgram
  step : Int
  source : @query.CapturedInputSource
  identity : @query.CapturedSourceRelationIdentity
  logical : @publication.RunEvidenceValue
  name : String
  observation : @publication.ModelSourceObservation
}

///|
pub fn admit_client_infer_captured_input(
  owner : PreparedClientProgram,
  step : Int,
  source : @query.CapturedInputSource,
  identity : @query.CapturedSourceRelationIdentity,
  requirement : @planning.QueryRequirement,
  logical : @publication.RunEvidenceValue,
  observation : @publication.ModelSourceObservation,
) -> Result[ClientInferCapturedInput, ClientInferCallScopeIssue] {
  guard client_acquired_infer_prefix_owner(owner, 0, step) is Some(prefix) &&
    @query.captured_source_matches(
      source,
      @checked.source_identity(@strategy.graph_program(owner.graph)),
      prefix,
    ) &&
    @query.captured_source_matches_query(
      source,
      @planning.query_material_owner(
        @planning.query_requirement_material(requirement),
      ),
    ) &&
    @query.captured_source_relation_identity_matches_source(identity, source) &&
    @publication.model_source_observation_matches_input(observation, logical) else {
    return Err(ForeignInput)
  }
  guard @publication.admit_completed_source_input_logical(
      logical,
      @query.captured_source_relation_logical_cid(identity),
      @query.captured_source_relation_schema_cid(identity),
      @planning.query_requirement_source(requirement).1,
      "{\"stable\":false,\"keys\":[]}",
      4096,
      128,
      16,
    )
    is Ok(_) else {
    return Err(ForeignInput)
  }
  Ok({
    owner,
    step,
    source,
    identity,
    logical,
    observation,
    name: @planning.query_requirement_site(requirement).1,
  })
}

///|
pub fn client_infer_captured_input_observation(
  input : ClientInferCapturedInput,
) -> @publication.ModelSourceObservation {
  input.observation
}

///|
/// Retain the live acquisition owner while restoring only its saved evidence.
/// The replay execution separately verifies the saved Run and call scope.
pub fn restore_client_infer_captured_input(
  input : ClientInferCapturedInput,
  source : @publication.RunEvidenceValue,
  observation : @publication.RunEvidenceValue,
) -> Result[ClientInferCapturedInput, ClientInferCallScopeIssue] {
  let restored = match
    @publication.restore_model_source_observation(
      input.observation,
      source,
      observation,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Evidence(issue))
  }
  Ok({
    owner: input.owner,
    step: input.step,
    source: input.source,
    identity: input.identity,
    logical: input.logical,
    name: input.name,
    observation: restored,
  })
}

///|
pub fn client_infer_captured_input_source(
  input : ClientInferCapturedInput,
  owner : PreparedClientProgram,
  step : Int,
) -> @query.CapturedInputSource? {
  guard physical_equal(input.owner, owner) &&
    input.step == step &&
    @query.captured_source_relation_identity_matches_source(
      input.identity,
      input.source,
    ) else {
    return None
  }
  Some(input.source)
}
