///|
/// Completed restoration installs an exact non-entering registration. Runtime
/// restores saved custody; this entry cannot re-execute Source or Compute.
fn open_resident_completed_runtime(
  journal : @journal.Journal,
  execution : ResidentExecution,
  materials : @host.ClientRunMaterials,
  binding : @remote.RemoteInputBinding,
  request : @remote.DispatchRequest,
  current_time : () -> String,
  input_max_bytes : Int64,
) -> Result[(@runtime.NativeRemoteRuntime, String?), ResidentExecutionFailure] {
  guard resident_linear_task_index(materials, request) is Some(task) else {
    return Err(failed(Refused(@resident.UnsupportedTask)))
  }
  if task == 0 {
    return open_resident_attempt_runtime(
      journal,
      execution,
      materials,
      binding,
      request,
      current_time,
      None,
    )
  }
  if resident_retained_task_route(materials, request, binding, input_max_bytes)
    is Err(_) {
    return Err(failed(Refused(@resident.ForeignSource)))
  }
  let scope = @remote.dispatch_request_task_scope(request)
  let factory = match
    @output.register_native_remote_standard_dispatch_run_factory(
      request,
      binding,
      () => {
        Err(
          @output.reject_native_remote_standard_input(
            "completed-restoration-only",
          ).unwrap(),
        )
      },
    ) {
    Ok(value) => value
    Err(issue) => return Err(failed(Source(Standard(issue))))
  }
  let executor = match
    @output.install_native_remote_standard_bound_task_executor(
      scope.0,
      scope.1,
      task,
      factory,
      execution.limits.output,
    ) {
    Ok(value) => value
    Err(issue) => return Err(failed(Source(Standard(issue))))
  }
  let graph = @host.prepared_client_graph(materials.prepared)
  let result_definition_cid = if @strategy.graph_result_task(graph, 0) ==
    Some(task) {
    let definition = match
      @publication.prepare_result_definition(
        @host.prepared_client_identity(materials.prepared).program_definition_cid,
        @strategy.graph_result_name(graph, 0).unwrap(),
      ) {
      Ok(value) => value
      Err(_) => return Err(failed(Refused(@resident.UnsupportedTask)))
    }
    Some(
      @publication.publication_contract_identity(
        @publication.result_definition_contract(definition),
      ),
    )
  } else {
    None
  }
  match
    @output.open_native_remote_standard_site_runtime(
      execution.site,
      execution.active_runtime,
      execution.operation_capability_cid,
      execution.issuer_capability_cid,
      [executor],
      journal,
      execution.bundles,
      execution.budgets,
    ) {
    Ok(runtime) => Ok((runtime, result_definition_cid))
    Err(issue) => Err(failed(Source(Standard(issue))))
  }
}
