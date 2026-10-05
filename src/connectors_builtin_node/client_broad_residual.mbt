///|
/// The selected Client/Local assembly owns the bounded residual after DuckDB
/// acquisition. The connector transport bridge retains no Local dependency.
pub(all) suberror ClientBroadResidualNodeIssue {
  Preparation(@client_local_host.ClientQueryResidualIssue)
  Local(@connector.FixedComputeIssue)
  Acquisition(@duckdb_host.BroadHostIssue)
  Stopped
}

///|
#export_name("clientBroadResidualPrepare")
pub fn client_broad_residual_prepare(
  run : @duckdb_host.BroadHostRun,
  max_name_bytes : Int,
) -> @client_local_host.ClientBroadResidual raise ClientBroadResidualNodeIssue {
  match @client_local_host.prepare_client_broad_residual(run, max_name_bytes) {
    Ok(owner) => owner
    Err(issue) => raise Preparation(issue)
  }
}

///|
#export_name("clientBroadResidualAdvance")
pub fn client_broad_residual_advance(
  owner : @client_local_host.ClientBroadResidual,
  quantum : Int,
) -> Bool raise ClientBroadResidualNodeIssue {
  match
    @local.advance_managed_provider(
      @client_local_host.client_broad_residual_execution(owner),
      quantum,
    ) {
    Ok(Continue(..)) => false
    Ok(Complete(_, ..)) => true
    Ok(Stopped(..)) => raise Stopped
    Ok(Failed(issue, ..)) | Err(issue) => raise Local(issue)
    Ok(Waiting(..)) | Ok(Settling(_, ..)) => {
      @local.cancel_managed_provider(
        @client_local_host.client_broad_residual_execution(owner),
      )
      |> ignore
      raise Local(ComputeUnsupported)
    }
    Ok(CarrierComplete(_, ..)) => raise Local(ComputeUnsupported)
  }
}

///|
#export_name("clientBroadResidualCancel")
pub fn client_broad_residual_cancel(
  owner : @client_local_host.ClientBroadResidual,
) -> Bool {
  @local.cancel_managed_provider(
    @client_local_host.client_broad_residual_execution(owner),
  )
}

///|
#export_name("clientBroadResidualStopped")
pub fn client_broad_residual_stopped(
  owner : @client_local_host.ClientBroadResidual,
) -> Bool {
  @local.managed_provider_stopped(
    @client_local_host.client_broad_residual_execution(owner),
  )
}

///|
#export_name("clientBroadResidualComplete")
pub fn client_broad_residual_complete(
  owner : @client_local_host.ClientBroadResidual,
) -> @duckdb_query.DuckDBBroadObservation raise ClientBroadResidualNodeIssue {
  match @client_local_host.complete_client_broad_residual(owner) {
    Ok(value) => value
    Err(issue) => raise Acquisition(issue)
  }
}

///|
#export_name("clientBroadResidualCleanup")
pub fn client_broad_residual_cleanup(
  owner : @client_local_host.ClientBroadResidual,
) -> Bool raise ClientBroadResidualNodeIssue {
  match @client_local_host.cleanup_client_broad_residual(owner) {
    Ok(done) => done
    Err(issue) => raise Local(issue)
  }
}
