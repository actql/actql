///|
/// Keep the Local child and acquisition run together before and after capture.
/// This is composition of existing owners, not a second execution state machine.
struct ClientBroadResidual {
  run : @duckdb_host.BroadHostRun
  residual : ClientQueryResidual
}

///|
pub fn prepare_client_broad_residual(
  run : @duckdb_host.BroadHostRun,
  max_name_bytes : Int,
) -> Result[ClientBroadResidual, ClientQueryResidualIssue] {
  let (query, receipt, live, guards, limits) = match
    @duckdb_host.prepare_broad_host_residual_input(run) {
    Ok(value) => value
    Err(issue) => return Err(Acquisition(issue))
  }
  prepare_client_query_residual(
    query,
    receipt,
    live,
    limits.execution,
    {
      max_work: limits.guards.max_work,
      max_bytes: limits.guards.max_bytes,
      max_nodes: limits.guards.max_nodes,
      max_depth: limits.guards.max_depth,
    },
    guards.max_rows,
    guards.max_value_bytes,
    max_name_bytes~,
  ).map(residual => { run, residual, })
}

///|
pub fn client_broad_residual_execution(
  owner : ClientBroadResidual,
) -> @local.ManagedProviderExecution {
  client_query_residual_execution(owner.residual)
}

///|
pub fn complete_client_broad_residual(
  owner : ClientBroadResidual,
) -> Result[@duckdb_query.DuckDBBroadObservation, @duckdb_host.BroadHostIssue] {
  @duckdb_host.complete_broad_host_bounded_residual(
    owner.run,
    owner.residual.receipt,
    fn(query, receipt, guards, limits) {
      verified_client_query_residual(
        owner.residual,
        query,
        receipt,
        guards,
        limits,
      )
    },
    fn() {
      @local.cleanup_managed_provider(client_broad_residual_execution(owner))
    },
  )
}

///|
pub fn cleanup_client_broad_residual(
  owner : ClientBroadResidual,
) -> Result[Bool, @connector.FixedComputeIssue] {
  let child = client_broad_residual_execution(owner)
  if !@local.managed_provider_stopped(child) {
    return Ok(false)
  }
  // Revoke the acquisition only after stop. Cleanup also covers a failed Local
  // child that never reached adoption by the capture owner.
  match @duckdb_host.cleanup_broad_host_residual(owner.run) {
    Ok(true) => @local.cleanup_managed_provider(child)
    other => other
  }
}
