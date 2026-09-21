///|
/// One exact bounded application occurrence prepared for a native Remote Site.
/// The standard strategy Run and its Captured DAG output holdings remain one
/// owner even though remote input custody can end earlier.
struct NativeRemoteApplicationRun {
  captured : @strategy.CapturedDAG
  strategy : @native_host.NativeStandardStrategyRun
  mut outputs_closed : Bool
}

///|
/// Failures from the bounded application composition boundary. Physical
/// Connector execution still reports through the standard strategy owner.
pub(all) enum NativeRemoteApplicationRunIssue {
  InvalidConfiguration
  Ledger(@resources.LedgerIssue)
  Capture(@strategy.RunIssue)
  Strategy(@native_host.NativeStandardStrategyRunIssue)
}

///|
/// Opens one fresh application occurrence from an already verified physical
/// input source. Program checking and strategy construction are reused from
/// the portable application builder; this native package adds no parser,
/// planner, or completion rule.
pub fn open_native_remote_application_run(
  app : @application.Application,
  source : @query.CapturedInputSource,
  ledger_limits : @resources.LedgerLimits,
  native_fixed_ms : Int64,
  resident : Bool,
  import_limits : @native_host.NativeComputeImportLimits,
  transfer_bytes : Int64,
  execution_bytes : Int64,
  library? : @native_duckdb.Library? = None,
  database_path? : String = "",
) -> Result[NativeRemoteApplicationRun, NativeRemoteApplicationRunIssue] {
  if native_fixed_ms < 0L || transfer_bytes < 0L || execution_bytes < 0L {
    return Err(InvalidConfiguration)
  }
  let ledger = match @resources.create_ledger(ledger_limits) {
    Ok(value) => value
    Err(issue) => return Err(Ledger(issue))
  }
  let captured = match
    @strategy.open_captured_dag(
      @application.application_graph(app),
      source,
      ledger,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Capture(issue))
  }
  let dispatch = @application.application_strategy_dispatch(
    app, captured, native_fixed_ms, resident,
  ) catch {
    _ => return Err(InvalidConfiguration)
  }
  let strategy = match
    @native_host.open_native_standard_strategy_run(
      dispatch,
      import_limits,
      transfer_bytes,
      execution_bytes,
      library~,
      database_path~,
    ) {
    Ok(value) => value
    Err(issue) => {
      @strategy.stop_captured_dag(captured)
      return Err(Strategy(issue))
    }
  }
  Ok({ captured, strategy, outputs_closed: false, })
}

///|
/// Binds this exact application occurrence into the common remote standard
/// owner. The returned owner releases captured outputs after strategy stop and
/// releases the physical input independently.
pub fn bind_native_remote_application_run(
  run : NativeRemoteApplicationRun,
  finish_input_owner : () -> Bool,
) -> @remote_standard.NativeRemoteStandardRunOwner {
  @remote_standard.prepare_native_remote_standard_captured_run_owner(
    run.strategy,
    () => run.finish_outputs(),
    finish_input_owner,
  )
}

///|
fn NativeRemoteApplicationRun::finish_outputs(
  self : NativeRemoteApplicationRun,
) -> Bool {
  if self.outputs_closed {
    return true
  }
  let graph = @strategy.captured_dag_graph(self.captured)
  for task = @strategy.graph_task_count(graph) - 1; task > 0; task = task - 1 {
    @strategy.close_captured_task_output(self.captured, task)
  }
  let usage = @resources.ledger_usage(
    @strategy.captured_dag_ledger(self.captured),
  )
  if usage.reserved_execution_bytes != 0L ||
    usage.reserved_retention_bytes != 0L ||
    usage.held_bytes != 0L {
    return false
  }
  self.outputs_closed = true
  true
}
