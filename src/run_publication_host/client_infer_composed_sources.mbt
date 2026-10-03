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
/// The original checked two-source closure consumed by JOIN before INFER.
/// This value binds capture provenance; it grants neither reads nor Model
/// dispatch and does not own a separate execution or authorization path.
pub struct ClientInferComposedSources {
  occurrence : ClientInferOccurrence
  inputs : Array[ClientInferSourceInput]
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
) -> Result[ClientInferComposedSources, ClientInferCallScopeIssue] {
  let owner = occurrence.owner
  let graph = owner.graph
  if !client_infer_occurrence_matches(occurrence, owner) ||
    @strategy.graph_captured_prefix(graph) != 2 ||
    occurrence.task != 2 ||
    captures.length() != 2 ||
    identities.length() != 2 ||
    requirements.length() != 2 ||
    logicals.length() != 2 ||
    evidence.length() != 2 {
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
  if incoming.length() != 2 {
    return Err(ForeignInput)
  }
  let pipeline = @lower.pipeline(
    @lower.bound_preparation(occurrence.preparation),
  )
  let inputs : Array[ClientInferSourceInput] = []
  let names : Array[String] = []
  for task in 0..<2 {
    let ports = incoming.filter(edge => edge.0 == task)
    guard ports.length() == 1 &&
      @pipeline.input_at(pipeline, ports[0].1) is Some((name, _)) else {
      return Err(ForeignInput)
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
  Ok({ occurrence, inputs, })
}

///|
pub fn client_infer_composed_sources_matches(
  value : ClientInferComposedSources,
  occurrence : ClientInferOccurrence,
) -> Bool {
  if !client_infer_occurrence_matches(value.occurrence, occurrence.owner) ||
    client_infer_occurrence_coordinates(value.occurrence) !=
    client_infer_occurrence_coordinates(occurrence) ||
    value.inputs.length() != 2 {
    return false
  }
  for task in 0..<2 {
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
  true
}

///|
pub fn client_infer_composed_source_observations(
  value : ClientInferComposedSources,
) -> Array[@publication.ModelSourceObservation] {
  value.inputs.map(input => input.observation)
}
