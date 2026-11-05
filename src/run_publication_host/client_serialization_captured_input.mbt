///|
/// A borrowed proof of the original acquisition, not another capture, ledger
/// or cleanup owner. The shared Source observation validator also serves Model
/// inputs; using it here makes no Model execution or egress claim.
pub struct ClientSerializationCapturedInput {
  owner : PreparedClientProgram
  task : Int
  step : Int
  source : @query.CapturedInputSource
  identity : @query.CapturedSourceRelationIdentity
  observation : @publication.ModelSourceObservation
  keyed : ClientKeyedLookupObservation?
  named_sources : Array[(String, @publication.ModelSourceObservation)]
}

///|
pub fn admit_client_serialization_captured_input(
  owner : PreparedClientProgram,
  component : ClientSerializationPlanGraph,
  source : @query.CapturedInputSource,
  identity : @query.CapturedSourceRelationIdentity,
  requirement : @planning.QueryRequirement,
  logical : @publication.RunEvidenceValue,
  source_evidence : @publication.RunEvidenceValue,
  authority_scope_cid : String,
  started_at : String,
  completed_at : String,
) -> Result[
  ClientSerializationCapturedInput,
  @publication.RunEvidenceValueIssue,
] {
  admit_client_serialization_captured_input_owned(
    owner,
    component,
    source,
    identity,
    requirement,
    logical,
    source_evidence,
    authority_scope_cid,
    started_at,
    completed_at,
    None,
  )
}

///|
/// Borrow the Source observation through the exact admitted Effect component.
/// Its retained private graph view is reused, never recreated or rechecked as
/// an Effect-free Program. The existing capture validator owns all evidence.
pub fn admit_client_effect_serialization_captured_input(
  run : ClientCompiledRun,
  owner : PreparedClientEffectComputation,
  source : @query.CapturedInputSource,
  identity : @query.CapturedSourceRelationIdentity,
  requirement : @planning.QueryRequirement,
  logical : @publication.RunEvidenceValue,
  source_evidence : @publication.RunEvidenceValue,
  authority_scope_cid : String,
  started_at : String,
  completed_at : String,
) -> Result[
  ClientSerializationCapturedInput,
  @publication.RunEvidenceValueIssue,
] {
  guard run.compilation is Effects(allowed) &&
    physical_equal(allowed.compilation.owner, owner) &&
    client_compiled_run_serialization(run) is Some(component) else {
    return Err(
      @publication.RunEvidenceReferenceMismatch("content_effect_owner"),
    )
  }
  admit_client_serialization_captured_input(
    run.owner,
    component,
    source,
    identity,
    requirement,
    logical,
    source_evidence,
    authority_scope_cid,
    started_at,
    completed_at,
  )
}

///|
/// Retain both original Source obligations. The opaque lookup observation is
/// bound to this exact left capture, key-set and Program; equal evidence JSON
/// from another lookup cannot replace it or authorize further provider I/O.
pub fn admit_client_keyed_serialization_captured_input(
  owner : PreparedClientProgram,
  component : ClientSerializationPlanGraph,
  source : @query.CapturedInputSource,
  identity : @query.CapturedSourceRelationIdentity,
  requirement : @planning.QueryRequirement,
  logical : @publication.RunEvidenceValue,
  source_evidence : @publication.RunEvidenceValue,
  keyed : ClientKeyedLookupObservation,
  authority_scope_cid : String,
  started_at : String,
  completed_at : String,
) -> Result[
  ClientSerializationCapturedInput,
  @publication.RunEvidenceValueIssue,
] {
  admit_client_serialization_captured_input_owned(
    owner,
    component,
    source,
    identity,
    requirement,
    logical,
    source_evidence,
    authority_scope_cid,
    started_at,
    completed_at,
    Some(keyed),
  )
}

///|
fn admit_client_serialization_captured_input_owned(
  owner : PreparedClientProgram,
  component : ClientSerializationPlanGraph,
  source : @query.CapturedInputSource,
  identity : @query.CapturedSourceRelationIdentity,
  requirement : @planning.QueryRequirement,
  logical : @publication.RunEvidenceValue,
  source_evidence : @publication.RunEvidenceValue,
  authority_scope_cid : String,
  started_at : String,
  completed_at : String,
  keyed : ClientKeyedLookupObservation?,
) -> Result[
  ClientSerializationCapturedInput,
  @publication.RunEvidenceValueIssue,
] {
  let task = component.task
  let step = component.step
  guard physical_equal(component.owner, owner) &&
    prepared_client_acquisition_count(owner) == 1 &&
    client_serialization_single_capture_shape(owner, task) &&
    client_captured_task_tuple_matches(owner, source, identity, requirement, 0) &&
    @planning.query_requirement_source_evidence_facts(requirement)
    is Some(facts) else {
    return Err(
      @publication.RunEvidenceReferenceMismatch("content_source_owner"),
    )
  }
  let keyed_sources : Array[(String, @publication.ModelSourceObservation)] = []
  match keyed {
    None =>
      if !client_single_direct_observation_covers_sources(owner) {
        return Err(
          @publication.RunEvidenceReferenceMismatch("content_source_coverage"),
        )
      }
    Some(keyed) => {
      let acquisition = keyed.lookup.left.acquisition
      guard acquisition.program is KeyedPure(original) &&
        physical_equal(original, owner) &&
        client_keyed_left_single_source_matches(keyed.lookup.left, source) &&
        client_keyed_acquisition_reaches_serialization(
          owner, acquisition, task, step,
        ) &&
        client_keyed_observation_covers_sources(owner, acquisition, requirement) &&
        client_keyed_lookup_observation_wires(keyed) is Some(_) &&
        @planning.keyed_source_evidence_facts(acquisition.facts) is Some(right) else {
        return Err(
          @publication.RunEvidenceReferenceMismatch(
            "content_keyed_source_owner",
          ),
        )
      }
      if @publication.admit_completed_source_observation_binding(
          keyed.source,
          keyed.input,
          right.source_ref,
          right.source_contract_cid,
          authority_scope_cid,
          right.source_data_policy_cid,
          100000,
          10000,
          100,
        )
        is Err(_) {
        return Err(
          @publication.RunEvidenceReferenceMismatch(
            "content_keyed_source_evidence",
          ),
        )
      }
      let subject = @checked.source_execution_subject(acquisition.check)
      guard @pipeline.input_at(
          @lower.pipeline(@lower.bound_preparation(acquisition.owner)),
          subject.input,
        )
        is Some((name, _)) &&
        name != @planning.query_requirement_site(requirement).1 else {
        return Err(
          @publication.RunEvidenceReferenceMismatch("content_source_names"),
        )
      }
      let observation = match
        @publication.admit_model_source_observation(
          keyed.source,
          keyed.input,
          right.source_ref,
          right.source_contract_cid,
          authority_scope_cid,
          right.source_data_policy_cid,
          started_at,
          completed_at,
        ) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      keyed_sources.push((name, observation))
    }
  }
  let values = @planning.query_source_evidence_fact_values(facts)
  if @publication.admit_completed_source_input_logical(
      logical,
      @query.captured_source_relation_logical_cid(identity),
      @query.captured_source_relation_schema_cid(identity),
      values[1],
      "{\"stable\":false,\"keys\":[]}",
      4096,
      128,
      16,
    )
    is Err(_) {
    return Err(
      @publication.RunEvidenceReferenceMismatch("content_source_input"),
    )
  }
  let observation = match
    @publication.admit_model_source_observation(
      source_evidence,
      logical,
      values[0],
      values[1],
      authority_scope_cid,
      values[3],
      started_at,
      completed_at,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let named_sources = [
    (@planning.query_requirement_site(requirement).1, observation),
  ]
  for item in keyed_sources {
    named_sources.push(item)
  }
  Ok({ owner, task, step, source, identity, observation, keyed, named_sources, })
}

///|
fn client_serialization_captured_input_matches(
  captured : ClientSerializationCapturedInput,
  run : ClientCompiledRun,
  input : ClientSerializationInput,
) -> Bool {
  guard client_compiled_run_serialization(run) is Some(component) else {
    return false
  }
  physical_equal(captured.owner, run.owner) &&
  captured.keyed
  .map(value => client_keyed_lookup_observation_wires(value) is Some(_))
  .unwrap_or(true) &&
  captured.task == component.task &&
  captured.step == component.step &&
  @lower.serialization_step(input.barrier) == captured.step &&
  physical_equal(
    @lower.serialization_owner(input.barrier),
    @lower.serialization_owner(component.barrier),
  ) &&
  @query.captured_source_relation_identity_matches_source(
    captured.identity,
    captured.source,
  )
}
