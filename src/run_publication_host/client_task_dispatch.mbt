///|
pub(all) enum ClientTaskDispatchIssue {
  Binding(ClientTaskRunBindingIssue)
  Fragment(ClientTaskFragmentIssue)
  ForeignRequest
  UnsupportedTask
  InvalidInputBinding
  Protocol(@remote.DispatchIssue)
}

///|
/// Project one checked task's logical input before physical Site selection.
/// A Source binding contains only the checked Source identity. Paths, tables
/// and connection credentials remain trusted Site configuration.
pub fn prepare_client_task_input_binding(
  prepared : PreparedClientProgram,
  task : Int,
) -> Result[@remote.RemoteInputBinding, ClientTaskDispatchIssue] {
  let graph = prepared_client_graph(prepared)
  if task < 0 || task >= @strategy.graph_task_count(graph) {
    return Err(UnsupportedTask)
  }
  let body = if task < prepared_client_acquisition_count(prepared) {
    // The initial resident composition supports exactly one checked Source.
    // Other acquisition shapes must install their actual held-input binding;
    // they are never collapsed into one dispatch because they share a Site.
    if prepared_client_acquisition_count(prepared) != 1 || task != 0 {
      return Err(UnsupportedTask)
    }
    guard prepared_client_source_evidence_facts(prepared, 0, 0) is Some(facts) else {
      return Err(UnsupportedTask)
    }
    let fields = @planning.query_source_evidence_fact_values(facts)
    let writer = @encode.writer(8192, 3, 1) catch {
      _ => return Err(InvalidInputBinding)
    }
    try {
      @encode.begin_object(writer)
      @encode.key(writer, "source_contract_cid")
      @encode.string_value(writer, fields[1])
      @encode.key(writer, "source_ref")
      @encode.string_value(writer, fields[0])
      @encode.end_object(writer)
      @encode.finish(writer)
    } catch {
      _ => return Err(InvalidInputBinding)
    }
  } else {
    if @strategy.graph_task_input_count(graph, task) != Some(0) {
      return Err(UnsupportedTask)
    }
    "{}"
  }
  @remote.prepare_remote_input_binding(body, 8192).map_err(issue => {
    Protocol(issue)
  })
}

///|
/// Derive the exact task key and input from the original checked Run. This
/// issues no execution authority and performs no I/O: the existing durable
/// Coordinator must atomically retain the full envelope before any send.
pub fn prepare_client_task_dispatch(
  prepared : PreparedClientProgram,
  compilation : ClientTaskCompilation,
  admission : @publication.RunPublicationAdmission,
  definition : @publication.PublicationContract,
  request : ClientRequestIdentity,
  task : Int,
  task_attempt : Int,
  dispatch_id : String,
  selected : ClientValuesSiteSelection,
) -> Result[@remote.DispatchRequest, ClientTaskDispatchIssue] {
  client_task_dispatch_with_input(
    prepared,
    compilation,
    admission,
    definition,
    request,
    task,
    task_attempt,
    dispatch_id,
    selected,
    () => prepare_client_task_input_binding(prepared, task),
  )
}

///|
fn client_task_dispatch_with_input(
  prepared : PreparedClientProgram,
  compilation : ClientTaskCompilation,
  admission : @publication.RunPublicationAdmission,
  definition : @publication.PublicationContract,
  request : ClientRequestIdentity,
  task : Int,
  task_attempt : Int,
  dispatch_id : String,
  selected : ClientValuesSiteSelection,
  load_input : () -> Result[@remote.RemoteInputBinding, ClientTaskDispatchIssue],
) -> Result[@remote.DispatchRequest, ClientTaskDispatchIssue] {
  let binding = match
    bind_client_task_run(prepared, compilation, admission, definition) {
    Ok(value) => value
    Err(issue) => return Err(Binding(issue))
  }
  let identity = prepared_client_identity(prepared)
  if client_request_program_cid(request) != identity.program_definition_cid ||
    client_request_parameters_cid(request) != identity.parameter_values_cid ||
    client_request_input_cid(request) != source_free_caller_input_intent_cid() {
    return Err(ForeignRequest)
  }
  if client_task_compilation_infer(compilation) is Some(_) {
    return Err(UnsupportedTask)
  }
  let input = match load_input() {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let fragment = match
    issue_prepared_client_task_fragment(
      prepared,
      task,
      client_standard_values_sequence_limits(),
      1000000,
      100000,
      100,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Fragment(issue))
  }
  @remote.prepare_dispatch_request(
    client_request_authority_scope_cid(request),
    client_task_run_binding_definition_cid(binding),
    client_task_fragment_node_id(fragment),
    task_attempt,
    dispatch_id,
    selected.site_key,
    selected.site_generation,
    selected.runtime_bundle_cid,
    selected.connector_registration,
    selected.connector_revision,
    selected.strategy_revision,
    @remote.remote_input_binding_cid(input),
    selected.obligations_cid,
    selected.budget_cid,
    selected.evidence_issuer_capability_cid,
    selected.grant_cid,
  ).map_err(issue => Protocol(issue))
}
