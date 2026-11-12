///|
priv enum ClientInferSourceOriginal {
  Query(@planning.QueryRequirement)
  Whole(@acquisition.SourceAcquisition)
}

///|
struct ClientInferSourceInput {
  name : String
  source : @query.CapturedInputSource
  identity : @query.CapturedSourceRelationIdentity
  original : ClientInferSourceOriginal
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
  admit_client_infer_composed_sources_owned(
    occurrence,
    captures,
    identities,
    requirements.map(requirement => {
      ClientInferSourceOriginal::Query(requirement)
    }),
    logicals,
    evidence,
    authority_scope_cid,
    started_at,
    completed_at,
    keyed~,
  )
}

///|
pub fn admit_client_infer_composed_whole_sources(
  occurrence : ClientInferOccurrence,
  captures : Array[@query.CapturedInputSource],
  identities : Array[@query.CapturedSourceRelationIdentity],
  originals : Array[@acquisition.SourceAcquisition],
  logicals : Array[@publication.RunEvidenceValue],
  evidence : Array[@publication.RunEvidenceValue],
  authority_scope_cid : String,
  started_at : String,
  completed_at : String,
  keyed? : ClientKeyedLookupObservation? = None,
) -> Result[ClientInferComposedSources, ClientInferCallScopeIssue] {
  admit_client_infer_composed_sources_owned(
    occurrence,
    captures,
    identities,
    originals.map(original => ClientInferSourceOriginal::Whole(original)),
    logicals,
    evidence,
    authority_scope_cid,
    started_at,
    completed_at,
    keyed~,
  )
}

///|
fn admit_client_infer_composed_sources_owned(
  occurrence : ClientInferOccurrence,
  captures : Array[@query.CapturedInputSource],
  identities : Array[@query.CapturedSourceRelationIdentity],
  originals : Array[ClientInferSourceOriginal],
  logicals : Array[@publication.RunEvidenceValue],
  evidence : Array[@publication.RunEvidenceValue],
  authority_scope_cid : String,
  started_at : String,
  completed_at : String,
  keyed? : ClientKeyedLookupObservation? = None,
) -> Result[ClientInferComposedSources, ClientInferCallScopeIssue] {
  let owner = occurrence.owner
  let graph = owner.graph
  let whole = originals.any(original => original is Whole(_))
  let direct = select_client_direct_acquisition_occurrences(owner, 1000000).to_option()
  let count = if whole {
    direct.map(client_direct_acquisition_occurrence_count).unwrap_or(0)
  } else {
    @strategy.graph_captured_prefix(graph)
  }
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
    !whole &&
    client_infer_prefix_owner_for_input(owner, 0, occurrence.step, true)
    is Some(_)
  let same_unit = keyed_unit || direct_unit
  if !client_infer_occurrence_matches(occurrence, owner) ||
    count < 1 ||
    (!whole && !same_unit && occurrence.task < count) ||
    captures.length() != count ||
    identities.length() != count ||
    originals.length() != count ||
    logicals.length() != count ||
    evidence.length() != count {
    return Err(ForeignInput)
  }
  let incoming : Array[(Int, Int)] = []
  for index in 0..<(if whole { 0 } else { @strategy.graph_data_count(graph) }) {
    guard @strategy.graph_data_at(graph, index) is Some(edge) else {
      return Err(ForeignInput)
    }
    if @strategy.data_edge_consumer(edge) == occurrence.task {
      incoming.push(
        (@strategy.data_edge_producer(edge), @strategy.data_edge_input(edge)),
      )
    }
  }
  // Whole declarations are resolved per checked port below. A mixed Unit's
  // one imported Result plus one inline Source is not two graph data edges.
  if !whole && incoming.length() != (if same_unit { 0 } else { count }) {
    return Err(ForeignInput)
  }
  let pipeline = @lower.pipeline(
    @lower.bound_preparation(occurrence.preparation),
  )
  let inputs : Array[ClientInferSourceInput] = []
  let names : Array[String] = []
  for task in 0..<count {
    let source_task = match originals[task] {
      Query(_) => task
      Whole(_) => {
        guard direct is Some(direct) &&
          client_direct_acquisition_occurrence_at(direct, task)
          is Some((_, _, producer)) else {
          return Err(ForeignInput)
        }
        producer
      }
    }
    let ports = incoming.filter(edge => edge.0 == source_task)
    let (name, facts) = match originals[task] {
      Query(requirement) => {
        let name = if same_unit {
          @planning.query_requirement_site(requirement).1
        } else {
          guard ports.length() == 1 &&
            @pipeline.input_at(pipeline, ports[0].1) is Some((name, _)) else {
            return Err(ForeignInput)
          }
          name
        }
        guard @planning.query_requirement_source_evidence_facts(requirement)
          is Some(facts) else {
          return Err(ForeignInput)
        }
        (name, facts)
      }
      Whole(original) => {
        guard direct is Some(direct) &&
          client_direct_acquisition_occurrence_at(direct, task)
          is Some((stage, input, _)) &&
          client_source_acquisition_matches_program(
            owner, stage, input, original,
          ) &&
          @planning.source_acquisition_evidence_facts(original) is Some(facts) else {
          return Err(ForeignInput)
        }
        let name = match
          model_effect_source_port_name(
            @strategy.graph_program(owner.graph),
            occurrence.stage,
            Whole(original),
          ) {
          Some(name) => name
          None => return Err(ForeignInput)
        }
        if source_task != occurrence.task {
          // An ordinary checked Stage edge names this exact producer. A keyed
          // prefix adds its existing completed lookup proof to the same edge;
          // the direct path retains its separate no-keyed-obligation check.
          if keyed is Some(observed) &&
            !client_composed_keyed_lookup_has_source_producer(
              observed.lookup,
              occurrence,
              captures,
              task,
            ) {
            return Err(ForeignInput)
          }
        }
        (name, facts)
      }
    }
    if names.contains(name) ||
      !client_infer_source_tuple_matches(
        owner,
        captures[task],
        identities[task],
        originals[task],
        task,
      ) {
      return Err(ForeignInput)
    }
    names.push(name)
    let source_ref = facts.source_ref
    let source_contract = facts.source_contract_cid
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
      original: originals[task],
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
      let composed = client_composed_keyed_lookup_sources_match(
        value.lookup,
        occurrence,
        captures,
      )
      guard (
          composed ||
          (
            count == 1 &&
            client_keyed_acquisition_matches_program(acquisition, owner) &&
            client_keyed_left_single_source_matches(
              value.lookup.left,
              inputs[0].source,
            )
          )
        ) &&
        client_keyed_acquisition_coordinates(acquisition)
        is Some((stage, task, join)) &&
        stage == occurrence.stage &&
        task == occurrence.task &&
        join < occurrence.step &&
        (
          composed ||
          (match inputs[0].original {
            Query(requirement) =>
              client_keyed_observation_covers_sources(
                owner, acquisition, requirement,
              )
            Whole(_) => false
          })
        ) &&
        client_keyed_lookup_observation_wires(value) is Some(_) &&
        @planning.keyed_source_evidence_facts(acquisition.facts) is Some(facts) else {
        return Err(ForeignInput)
      }
      let subject = @checked.source_execution_subject(acquisition.check)
      let source_input = if composed {
        client_composed_keyed_lookup_input_slot(value.lookup, occurrence).unwrap()
      } else {
        subject.input
      }
      guard @pipeline.input_at(pipeline, source_input) is Some((name, _)) &&
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
// Resolve only the existing full captured-prefix boundary. A downstream Model
// retains this provenance while Local supplies its actual completed Result
// input; the Source closure is never a substitute for that producer port.
fn client_infer_composed_source_origin(
  occurrence : ClientInferOccurrence,
) -> ClientInferOccurrence? {
  if !client_infer_occurrence_matches(occurrence, occurrence.owner) {
    return None
  }
  if client_infer_composed_source_boundary(occurrence) {
    return Some(occurrence)
  }
  guard prepared_client_composed_infer_occurrences(occurrence.owner)
    is Some(originals) else {
    return None
  }
  let candidates = originals.filter(original => {
    (
      original.task < occurrence.task ||
      (original.task == occurrence.task && original.step < occurrence.step)
    ) &&
    client_infer_composed_source_boundary(original) &&
    client_infer_composed_source_precedes(original, occurrence)
  })
  match candidates {
    [original] => Some(original)
    _ => None
  }
}

///|
fn client_infer_composed_source_boundary(
  occurrence : ClientInferOccurrence,
) -> Bool {
  let graph = occurrence.owner.graph
  if select_client_direct_acquisition_occurrences(occurrence.owner, 1000000)
    is Ok(direct) {
    let count = client_direct_acquisition_occurrence_count(direct)
    let same_task = count > 0 &&
      Array::makei(count, slot => slot).all(slot => {
        client_direct_acquisition_occurrence_at(direct, slot).map(coordinate => {
          coordinate.2 == occurrence.task
        }) ==
        Some(true)
      })
    if same_task {
      guard prepared_client_composed_infer_occurrences(occurrence.owner)
        is Some(models) else {
        return false
      }
      return !models.any(previous => {
        previous.task == occurrence.task &&
        previous.step < occurrence.step &&
        client_infer_composed_source_precedes(previous, occurrence)
      })
    }
    if count != @strategy.graph_captured_prefix(graph) {
      let program = @strategy.graph_program(graph)
      if count == 0 ||
        !direct.checks.all(check => {
          model_effect_checked_source_port_name(
            program,
            occurrence.stage,
            check,
          )
          is Some(_)
        }) {
        return false
      }
      guard prepared_client_composed_infer_occurrences(occurrence.owner)
        is Some(models) else {
        return false
      }
      return !models.any(previous => {
        previous.task < occurrence.task &&
        direct.checks.all(check => {
          model_effect_checked_source_port_name(program, previous.stage, check)
          is Some(_)
        }) &&
        client_infer_composed_source_precedes(previous, occurrence)
      })
    }
  }
  let count = @strategy.graph_captured_prefix(graph)
  if count < 1 || occurrence.task < count {
    return false
  }
  let incoming : Array[Int] = []
  for index in 0..<@strategy.graph_data_count(graph) {
    guard @strategy.graph_data_at(graph, index) is Some(edge) else {
      return false
    }
    if @strategy.data_edge_consumer(edge) == occurrence.task {
      incoming.push(@strategy.data_edge_producer(edge))
    }
  }
  incoming.length() == count &&
  Array::makei(count, task => task).all(task => {
    incoming.filter(producer => producer == task).length() == 1
  })
}

///|
fn client_infer_composed_source_precedes(
  original : ClientInferOccurrence,
  occurrence : ClientInferOccurrence,
) -> Bool {
  if !client_infer_occurrence_matches(original, occurrence.owner) ||
    original.task >= occurrence.task {
    return false
  }
  let graph = occurrence.owner.graph
  let reached = [original.task]
  let mut cursor = 0
  while cursor < reached.length() {
    let producer = reached[cursor]
    cursor += 1
    for index in 0..<@strategy.graph_data_count(graph) {
      guard @strategy.graph_data_at(graph, index) is Some(edge) else {
        return false
      }
      if @strategy.data_edge_producer(edge) == producer {
        let consumer = @strategy.data_edge_consumer(edge)
        if consumer == occurrence.task {
          return true
        }
        if consumer < occurrence.task && !reached.contains(consumer) {
          reached.push(consumer)
        }
      }
    }
  }
  false
}

///|
// The existing checked inheritance relation, without Source-current callbacks.
// Scope admission owns live tuple validation; publication only borrows this
// original Program/occurrence correspondence and its retained observations.
fn client_infer_composed_source_origin_matches(
  original : ClientInferOccurrence,
  occurrence : ClientInferOccurrence,
) -> Bool {
  client_infer_occurrence_matches(original, occurrence.owner) &&
  client_infer_occurrence_matches(occurrence, occurrence.owner) &&
  (
    client_infer_occurrence_coordinates(original) ==
    client_infer_occurrence_coordinates(occurrence) ||
    client_infer_composed_source_origin(occurrence).map(source => {
      client_infer_occurrence_coordinates(source) ==
      client_infer_occurrence_coordinates(original)
    }) ==
    Some(true)
  )
}

///|
pub fn client_infer_composed_sources_matches(
  value : ClientInferComposedSources,
  occurrence : ClientInferOccurrence,
) -> Bool {
  let original = value.occurrence
  if !client_infer_composed_source_origin_matches(original, occurrence) ||
    value.inputs.length() !=
    (if value.inputs.any(input => input.original is Whole(_)) {
      select_client_direct_acquisition_occurrences(occurrence.owner, 1000000)
      .to_option()
      .map(client_direct_acquisition_occurrence_count)
      .unwrap_or(0)
    } else {
      @strategy.graph_captured_prefix(occurrence.owner.graph)
    }) ||
    value.inputs.is_empty() {
    return false
  }
  for task in 0..<value.inputs.length() {
    let input = value.inputs[task]
    if !client_infer_source_tuple_matches(
        occurrence.owner,
        input.source,
        input.identity,
        input.original,
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
      let composed = client_composed_keyed_lookup_sources_match(
        keyed.lookup,
        original,
        value.inputs.map(input => input.source),
      )
      if (
          !composed &&
          (
            value.inputs.length() != 1 ||
            !client_keyed_acquisition_matches_program(
              acquisition,
              occurrence.owner,
            ) ||
            !client_keyed_left_single_source_matches(
              keyed.lookup.left,
              value.inputs[0].source,
            )
          )
        ) ||
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
  // The inherited closure is provenance only. Local must supply the actual
  // downstream Result; an earlier lookup cannot replace that input or run again.
  if client_infer_occurrence_coordinates(value.occurrence) !=
    client_infer_occurrence_coordinates(occurrence) {
    return None
  }
  value.keyed.map(entry => entry.1.lookup)
}

///|
/// Borrow only the admitted same-Unit acquisition, with its original Program.
/// The input kernel selects the retained prefix after that capture; this does
/// not issue reads, regenerate the prefix or transfer Source custody. This
/// immutable projection invokes no Source-current callback; the existing
/// composed admission and captured producer binding own those boundaries.
pub fn client_infer_composed_direct_source(
  value : ClientInferComposedSources,
  occurrence : ClientInferOccurrence,
) -> (PreparedClientProgram, @query.CapturedInputSource)? {
  guard value.keyed is None &&
    value.inputs.length() == 1 &&
    occurrence.task == 0 &&
    @strategy.graph_task_count(occurrence.owner.graph) == 1 &&
    @strategy.graph_captured_prefix(occurrence.owner.graph) == 1 &&
    client_infer_occurrence_matches(value.occurrence, occurrence.owner) &&
    client_infer_occurrence_coordinates(value.occurrence) ==
    client_infer_occurrence_coordinates(occurrence) &&
    client_acquired_infer_prefix_owner(occurrence.owner, 0, occurrence.step)
    is Some(_) else {
    return None
  }
  Some((occurrence.owner, value.inputs[0].source))
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

///|
fn client_infer_source_tuple_matches(
  owner : PreparedClientProgram,
  source : @query.CapturedInputSource,
  identity : @query.CapturedSourceRelationIdentity,
  original : ClientInferSourceOriginal,
  slot : Int,
) -> Bool {
  match original {
    Query(requirement) =>
      client_captured_task_tuple_matches(
        owner, source, identity, requirement, slot,
      )
    Whole(acquisition) => {
      guard select_client_direct_acquisition_occurrences(owner, 1000000)
        is Ok(direct) &&
        client_direct_acquisition_occurrence_at(direct, slot)
        is Some((stage, input, task)) &&
        client_source_acquisition_matches_program(
          owner, stage, input, acquisition,
        ) &&
        @strategy.graph_task_owner(owner.graph, task) is Some(preparation) else {
        return false
      }
      @query.captured_source_matches(
        source,
        @checked.source_identity(@strategy.graph_program(owner.graph)),
        preparation,
      ) &&
      @query.captured_source_matches_input_acquisition(source, acquisition) &&
      @query.captured_source_relation_identity_matches_source(identity, source)
    }
  }
}
