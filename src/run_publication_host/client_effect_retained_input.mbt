///|
pub(all) enum ClientEffectRetainedInputIssue {
  Binding(ClientEffectCompiledRunIssue)
  Edge(ClientRetainedInputIssue)
  Input(ClientRetainedTaskInputIssue)
  Dispatch(ClientEffectSourceDispatchIssue)
  ForeignConsumer
}

///|
/// The Effect Run binds before resolving its checked consumer edge. The
/// private compilation view never escapes as an Effect-free Program, and all
/// physical Transfer/borrow/cleanup responsibility stays with existing owners.
pub fn prepare_client_effect_retained_input_edge(
  allowed : ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
) -> Result[ClientRetainedInputEdge, ClientEffectRetainedInputIssue] {
  let compilation = allowed.compilation
  let bound = match
    bind_client_effect_compiled_run(compilation.owner, allowed, definition) {
    Ok(value) => value
    Err(issue) => return Err(Binding(issue))
  }
  if @strategy.prepare_retained_effect_task_projection(bound.checked) is Err(_) {
    return Err(ForeignConsumer)
  }
  resolve_client_retained_input_edge(
    compilation.compiled.owner,
    @publication.publication_contract_identity(definition),
    1,
    0,
  ).map_err(issue => Edge(issue))
}

///|
/// Dispatch the checked consumer only after the existing receiver holding and
/// current authorization have admitted its original producer occurrence.
pub fn prepare_client_effect_retained_task_dispatch(
  allowed : ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
  request : ClientRequestIdentity,
  task_attempt : Int,
  dispatch_id : String,
  selected : ClientValuesSiteSelection,
  input : ClientRetainedTaskInput,
  current : ClientRetainedInputCurrent,
) -> Result[@remote.DispatchRequest, ClientEffectRetainedInputIssue] {
  match validate_client_retained_task_input_current(input, current) {
    Ok(_) => ()
    Err(issue) => return Err(Input(issue))
  }
  let edge = match
    prepare_client_effect_retained_input_edge(allowed, definition) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if client_retained_input_edge_projection(edge) !=
    client_retained_input_edge_projection(input.producer.edge) ||
    client_retained_input_edge_schema_cid(edge) !=
    client_retained_input_edge_schema_cid(input.producer.edge) {
    return Err(ForeignConsumer)
  }
  let scope = @remote.dispatch_request_execution_scope(input.producer.request)
  if selected.site_key != scope[0] ||
    selected.site_generation.to_string() != scope[1] ||
    !(current.site_binding_current)(
      selected.site_key,
      scope[1],
      selected.runtime_bundle_cid,
    ) ||
    client_request_authority_scope_cid(request) != (current.authority)() {
    return Err(ForeignConsumer)
  }
  let dispatch = match
    client_effect_checked_task_dispatch(
      allowed,
      definition,
      request,
      1,
      task_attempt,
      dispatch_id,
      selected,
      input.binding,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Dispatch(issue))
  }
  match validate_client_retained_task_input_current(input, current) {
    Ok(_) => Ok(dispatch)
    Err(issue) => Err(Input(issue))
  }
}
