///|
struct ClientInferSourceInput {
  name : String
  source : @query.CapturedInputSource
  identity : @query.CapturedSourceRelationIdentity
  requirement : @planning.QueryRequirement
  logical : @publication.RunEvidenceValue
  observation : @publication.ModelSourceObservation
}

///|
/// The original checked Source closure consumed by an INFER Unit. Independent
/// components can borrow the same saved producer; each retains its exact port.
/// This value binds capture provenance; it grants neither reads nor Model
/// dispatch and does not own a separate execution or authorization path.
pub struct ClientInferComposedSources {
  occurrence : ClientInferOccurrence
  inputs : Array[ClientInferSourceInput]
  keyed : (
    String,
    ClientKeyedLookupObservation,
    @publication.ModelSourceObservation,
  )?
}

///|
pub fn admit_client_infer_composed_sources(
  occurrence : ClientInferOccurrence,
  captures : Array[@query.CapturedInputSource],
  identities : Array[@query.CapturedSourceRelationIdentity],
  requirements : Array[@planning.QueryRequirement],
  logicals : Array[@publication.RunEvidenceValue],
  evidence : Array[@publication.RunEvidenceValue],
  authority_scope_cid : String,
  started_at : String,
  completed_at : String,
  keyed? : ClientKeyedLookupObservation? = None,
) -> Result[ClientInferComposedSources, ClientInferCallScopeIssue] {
  let owner = occurrence.owner
  let graph = owner.graph
  let count = @strategy.graph_captured_prefix(graph)
  // A single keyed Unit retains the acquired prefix and its Model suffix in
  // one checked owner. The lookup proves both Source selections; it is not an
  // imported Stage edge or permission to reuse an unrelated capture.
  let keyed_unit = keyed is Some(_) &&
    count == 1 &&
    occurrence.task == 0 &&
    @strategy.graph_task_count(graph) == 1
  // The existing acquired-prefix owner also admits Source and INFER in one
  // Unit. It has no inter-task edge; its original Query tuple and evidence
  // below still bind the same checked input before any Model operation.
  let direct_unit = count == 1 &&
    occurrence.task == 0 &&
    @strategy.graph_task_count(graph) == 1 &&
    client_infer_prefix_owner_for_input(owner, 0, occurrence.step, true)
    is Some(_)
  let same_unit = keyed_unit || direct_unit
  if !client_infer_occurrence_matches(occurrence, owner) ||
    count < 1 ||
    count > 2 ||
    (!same_unit && occurrence.task < count) ||
    captures.length() != count ||
    identities.length() != count ||
    requirements.length() != count ||
    logicals.length() != count ||
    evidence.length() != count {
    return Err(ForeignInput)
  }
  let incoming : Array[(Int, Int)] = []
  for index in 0..<@strategy.graph_data_count(graph) {
    guard @strategy.graph_data_at(graph, index) is Some(edge) else {
      return Err(ForeignInput)
    }
    if @strategy.data_edge_consumer(edge) == occurrence.task {
      incoming.push(
        (@strategy.data_edge_producer(edge), @strategy.data_edge_input(edge)),
      )
    }
  }
  if incoming.length() != (if same_unit { 0 } else { count }) {
    return Err(ForeignInput)
  }
  let pipeline = @lower.pipeline(
    @lower.bound_preparation(occurrence.preparation),
  )
  let inputs : Array[ClientInferSourceInput] = []
  let names : Array[String] = []
  for task in 0..<count {
    let ports = incoming.filter(edge => edge.0 == task)
    let name = if same_unit {
      @planning.query_requirement_site(requirements[task]).1
    } else {
      guard ports.length() == 1 &&
        @pipeline.input_at(pipeline, ports[0].1) is Some((name, _)) else {
        return Err(ForeignInput)
      }
      name
    }
    if names.contains(name) ||
      !client_captured_task_tuple_matches(
        owner,
        captures[task],
        identities[task],
        requirements[task],
        task,
      ) {
      return Err(ForeignInput)
    }
    names.push(name)
    let requirement = requirements[task]
    guard @planning.query_requirement_source_evidence_facts(requirement)
      is Some(facts) else {
      return Err(ForeignInput)
    }
    let (source_ref, source_contract) = @planning.query_requirement_source(
      requirement,
    )
    if @publication.admit_completed_source_input_logical(
        logicals[task],
        @query.captured_source_relation_logical_cid(identities[task]),
        @query.captured_source_relation_schema_cid(identities[task]),
        source_contract,
        "{\"stable\":false,\"keys\":[]}",
        100000,
        10000,
        100,
      )
      is Err(_) {
      return Err(ForeignInput)
    }
    let observation = match
      @publication.admit_model_source_observation(
        evidence[task],
        logicals[task],
        source_ref,
        source_contract,
        authority_scope_cid,
        facts.source_data_policy_cid,
        started_at,
        completed_at,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Evidence(issue))
    }
    inputs.push({
      name,
      source: captures[task],
      identity: identities[task],
      requirement,
      logical: logicals[task],
      observation,
    })
  }
  let keyed_input = match keyed {
    None => {
      // A Direct capture cannot silently discharge a keyed Source obligation.
      match select_client_single_keyed_acquisition(owner) {
        Ok(None) => ()
        _ => return Err(ForeignInput)
      }
      None
    }
    Some(value) => {
      let acquisition = value.lookup.left.acquisition
      guard count == 1 &&
        client_keyed_acquisition_matches_program(acquisition, owner) &&
        physical_equal(value.lookup.left.source, inputs[0].source) &&
        client_keyed_acquisition_coordinates(acquisition)
        is Some((stage, task, join)) &&
        stage == occurrence.stage &&
        task == occurrence.task &&
        join < occurrence.step &&
        client_keyed_observation_covers_sources(
          owner,
          acquisition,
          inputs[0].requirement,
        ) &&
        client_keyed_lookup_observation_wires(value) is Some(_) &&
        @planning.keyed_source_evidence_facts(acquisition.facts) is Some(facts) else {
        return Err(ForeignInput)
      }
      let subject = @checked.source_execution_subject(acquisition.check)
      guard @pipeline.input_at(pipeline, subject.input) is Some((name, _)) &&
        !names.contains(name) else {
        return Err(ForeignInput)
      }
      let observation = match
        @publication.admit_model_source_observation(
          value.source,
          value.input,
          facts.source_ref,
          facts.source_contract_cid,
          authority_scope_cid,
          facts.source_data_policy_cid,
          started_at,
          completed_at,
        ) {
        Ok(observation) => observation
        Err(issue) => return Err(Evidence(issue))
      }
      Some((name, value, observation))
    }
  }
  Ok({ occurrence, inputs, keyed: keyed_input, })
}

///|
pub fn client_infer_composed_sources_matches(
  value : ClientInferComposedSources,
  occurrence : ClientInferOccurrence,
) -> Bool {
  if !client_infer_occurrence_matches(value.occurrence, occurrence.owner) ||
    client_infer_occurrence_coordinates(value.occurrence) !=
    client_infer_occurrence_coordinates(occurrence) ||
    value.inputs.length() !=
    @strategy.graph_captured_prefix(occurrence.owner.graph) ||
    value.inputs.is_empty() ||
    value.inputs.length() > 2 {
    return false
  }
  for task in 0..<value.inputs.length() {
    let input = value.inputs[task]
    if !client_captured_task_tuple_matches(
        occurrence.owner,
        input.source,
        input.identity,
        input.requirement,
        task,
      ) {
      return false
    }
  }
  match value.keyed {
    None =>
      match select_client_single_keyed_acquisition(occurrence.owner) {
        Ok(None) => ()
        _ => return false
      }
    Some((_, keyed, _)) => {
      let acquisition = keyed.lookup.left.acquisition
      if value.inputs.length() != 1 ||
        !client_keyed_acquisition_matches_program(acquisition, occurrence.owner) ||
        !physical_equal(keyed.lookup.left.source, value.inputs[0].source) ||
        client_keyed_lookup_observation_wires(keyed) is None {
        return false
      }
    }
  }
  true
}

///|
pub fn client_infer_composed_source_observations(
  value : ClientInferComposedSources,
) -> Array[@publication.ModelSourceObservation] {
  client_infer_composed_named_source_observations(value).map(input => input.1)
}

///|
/// Borrow the same live lookup whose observation was admitted above. This
/// grants no acquisition and transfers no custody to the Model input owner.
pub fn client_infer_composed_keyed_lookup(
  value : ClientInferComposedSources,
  occurrence : ClientInferOccurrence,
) -> ClientKeyedLookupInput? {
  if !client_infer_composed_sources_matches(value, occurrence) {
    return None
  }
  value.keyed.map(entry => entry.1.lookup)
}

///|
fn client_infer_composed_named_source_observations(
  value : ClientInferComposedSources,
) -> Array[(String, @publication.ModelSourceObservation)] {
  let inputs = value.inputs.map(input => (input.name, input.observation))
  if value.keyed is Some((name, _, observation)) {
    inputs.push((name, observation))
  }
  inputs
}
