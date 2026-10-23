///|
/// The distinct Model purpose borrows one actual managed Run. Its original
/// Scope must be installed before either Source creates an ordinary child;
/// it cannot be reconstructed after captures from equal aggregate usage.
pub fn begin_installed_mock_model_managed_run(
  admission : @resources.NodeManagedRunAdmission[
    @publication_host.PreparedClientProgram,
  ],
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : @publication_host.ClientInferPlanGraph,
  bootstrap_retained_bytes : Int64,
  bootstrap_execution_bytes : Int64,
  max_reservations : Int,
  max_holdings : Int,
  max_delegations : Int,
) -> Result[
  (ClientInstalledManagedRun, @publication_host.ClientModelReadScope),
  ClientInstalledManagedRunIssue,
] {
  match
    @resources.check_node_local_mock_model_run_preparation(admission, prepared) {
    Err(issue) => return Err(Resource(issue))
    Ok(_) => ()
  }
  let identity = @publication_host.prepared_client_identity(prepared)
  if identity.program_definition_cid !=
    @publication_host.client_request_program_cid(request) ||
    identity.parameter_values_cid !=
    @publication_host.client_request_parameters_cid(request) ||
    !@publication_host.client_compiled_run_matches(compiled, prepared) ||
    !@publication_host.client_compiled_run_has_infer(compiled, plan) ||
    @publication_host.check_client_compiled_run_definition(compiled, definition)
    is Err(_) {
    return Err(ForeignOriginal)
  }
  let graph = @publication_host.prepared_client_graph(prepared)
  let captured = @strategy.graph_captured_prefix(graph)
  if !(captured == 2 ||
    (captured == 0 && @strategy.graph_source_free_inputs_complete(graph))) ||
    !@publication_host.prepared_client_serialization_occurrences(prepared).is_empty() {
    return Err(Unsupported)
  }
  // This finite route binds one compiler-retained local-Mock component. It
  // does not admit a generic/async Provider or a composition by CID equality.
  guard @publication_host.prepared_client_composed_infer_occurrences(prepared)
    is Some(infers) &&
    infers.length() == 1 else {
    return Err(Unsupported)
  }
  let ledger = match @resources.start_node_managed_run_admission(admission) {
    Err(issue) => return Err(Resource(issue))
    Ok(value) => value
  }
  let value = new_installed_managed_run(admission, prepared, request, ledger)
  let bootstrap = match
    @resources.reserve_node_managed_run_read_bootstrap(
      admission, prepared, ledger, bootstrap_retained_bytes, bootstrap_execution_bytes,
    ) {
    Err(issue) => return Err(Resource(issue))
    Ok(value) => value
  }
  let scope = match
    @publication_host.begin_client_model_read_scope(
      compiled, definition, plan, ledger, bootstrap, max_reservations, max_holdings,
      max_delegations,
    ) {
    Err(issue) => return Err(ModelRead(issue))
    Ok(scope) => scope
  }
  // Admission and bootstrap already remain reachable from the Host's
  // retained partial carrier if this final current/park fence refuses.
  match require_installed_managed_run(value) {
    Err(issue) => Err(issue)
    Ok(_) => Ok((value, scope))
  }
}
