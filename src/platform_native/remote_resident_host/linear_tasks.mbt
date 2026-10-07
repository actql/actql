///|
/// This installed Native profile composes one acquisition and a linear chain
/// of single-input tasks. Other legal DAG shapes need their own custody
/// composition; checked graph admission alone does not install that support.
fn resident_linear_graph(graph : @strategy.CheckedDAG) -> Bool {
  let count = @strategy.graph_task_count(graph)
  if count < 1 ||
    @strategy.graph_program_has_effects(graph) ||
    @strategy.graph_result_count(graph) != 1 ||
    @strategy.graph_result_task(graph, 0) != Some(count - 1) ||
    @strategy.graph_task_target(graph, 0) is Some(_) ||
    @strategy.graph_data_count(graph) != count - 1 {
    return false
  }
  let incoming = Array::make(count, false)
  for index in 0..<@strategy.graph_data_count(graph) {
    guard @strategy.graph_data_at(graph, index) is Some(edge) else {
      return false
    }
    let consumer = @strategy.data_edge_consumer(edge)
    if consumer < 1 ||
      consumer >= count ||
      incoming[consumer] ||
      @strategy.data_edge_producer(edge) != consumer - 1 ||
      @strategy.data_edge_input(edge) != 0 {
      return false
    }
    incoming[consumer] = true
  }
  for task in 1..<count {
    if !incoming[task] ||
      @strategy.graph_task_input_count(graph, task) != Some(1) ||
      @strategy.graph_task_target(graph, task) is None {
      return false
    }
  }
  for index in 0..<@strategy.graph_control_count(graph) {
    guard @strategy.graph_control_at(graph, index) is Some(edge) else {
      return false
    }
    let consumer = @strategy.control_edge_consumer(edge)
    if consumer < 1 ||
      consumer >= count ||
      @strategy.control_edge_predecessor(edge) != consumer - 1 {
      return false
    }
  }
  true
}

///|
fn resident_prepared_task_index(
  prepared : @host.PreparedClientProgram,
  task_key : String,
) -> Int? {
  let graph = @host.prepared_client_graph(prepared)
  if @host.prepared_client_acquisition_count(prepared) != 1 ||
    @host.prepared_client_result_count(prepared) != 1 ||
    !resident_linear_graph(graph) {
    return None
  }
  for task in 0..<@strategy.graph_task_count(graph) {
    guard @host.issue_prepared_client_task_fragment(
        prepared,
        task,
        @host.client_standard_values_sequence_limits(),
        1000000,
        100000,
        100,
      )
      is Ok(fragment) else {
      return None
    }
    if @host.client_task_fragment_node_id(fragment) == task_key {
      return Some(task)
    }
  }
  None
}

///|
fn resident_linear_task_index(
  materials : @host.ClientRunMaterials,
  request : @remote.DispatchRequest,
) -> Int? {
  guard materials.compilation is @host.Tasks(compilation) &&
    @host.bind_client_task_run(
      materials.prepared,
      compilation,
      materials.admission,
      materials.run_definition,
    )
    is Ok(_) else {
    return None
  }
  let (definition, task_key) = @remote.dispatch_request_task_scope(request)
  if definition !=
    @publication.publication_contract_identity(materials.run_definition) {
    return None
  }
  resident_prepared_task_index(materials.prepared, task_key)
}

///|
fn resident_retained_task_route(
  materials : @host.ClientRunMaterials,
  request : @remote.DispatchRequest,
  binding : @remote.RemoteInputBinding,
  max_referenced_bytes : Int64,
) -> Result[@host.ClientRetainedTaskRoute, ResidentHostIssue] {
  guard materials.compilation is @host.Tasks(compilation) &&
    resident_linear_task_index(materials, request) is Some(task) &&
    task > 0 else {
    return Err(Refused(@resident.UnsupportedTask))
  }
  let edge = match
    @host.prepare_client_retained_input_edge(
      materials.prepared,
      compilation,
      materials.admission,
      materials.run_definition,
      task,
      0,
    ) {
    Ok(value) => value
    Err(_) => return Err(Refused(@resident.ForeignSource))
  }
  @host.admit_client_retained_task_route(
    binding, edge, request, 1048576, 65536, 1048576, max_referenced_bytes,
  ).map_err(_ => Refused(@resident.ForeignSource))
}

///|
/// Rebuild historical completed-task material. This does not grant a new
/// consumer dispatch admission or replace its live incoming Transfer owner.
fn admit_resident_chain_materials(
  admission : ResidentRunAdmission,
  request : @remote.DispatchRequest,
  body : String,
  binding : @remote.RemoteInputBinding,
  at : String,
) -> Result[@host.ClientRunMaterials, @resident.ResidentDispatchRefusal] {
  let materials = match rebuild_materials(admission, request, body) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match resident_linear_task_index(materials, request) {
    Some(task) if task > 0 => {
      guard admission.source is Some((source_ref, source_contract_cid)) &&
        @host.prepared_client_source_evidence_facts(materials.prepared, 0, 0)
        is Some(facts) else {
        return Err(@resident.ForeignSource)
      }
      let source = @planning.query_source_evidence_fact_values(facts)
      if source[0] != source_ref ||
        source[1] != source_contract_cid ||
        resident_retained_task_route(
          materials, request, binding, 9223372036854775807L,
        )
        is Err(_) {
        return Err(@resident.ForeignSource)
      }
      match @resident.check_resident_materials_current(materials, at) {
        Ok(_) => Ok(materials)
        Err(issue) => Err(issue)
      }
    }
    _ => admit_materials(admission, request, body, binding, at)
  }
}

///|
/// Non-authorizing routing: the selected live holder must still re-admit the
/// consumer against its actual journal, Transfer custody and current grants.
pub fn resident_retained_consumer_producer_identity(
  admission : ResidentRunAdmission,
  dispatch : @remote.RemotePollDispatch,
  at : String,
) -> Result[String, ResidentHostIssue] {
  let request = @remote.remote_poll_dispatch_request(dispatch)
  let binding = @remote.remote_poll_dispatch_input_binding(dispatch)
  guard @remote.remote_poll_dispatch_run_materials(dispatch) is Some(body) else {
    return Err(EnvelopeMissing)
  }
  let materials = match
    admit_resident_chain_materials(admission, request, body, binding, at) {
    Ok(value) => value
    Err(issue) => return Err(Refused(issue))
  }
  let route = match
    resident_retained_task_route(
      materials, request, binding, 9223372036854775807L,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok(
    @remote.dispatch_request_identity(
      @host.client_retained_task_route_producer_dispatch(route),
    ),
  )
}
