///|
/// Product owner for one configured Local/DuckDB strategy Run on the native
/// target. The portable configured Host chooses the exact implementation;
/// this owner only connects that choice to synchronous Local execution or a
/// native DuckDB database and retains every common task owner.
struct NativeStandardStrategyRun {
  dispatch : @duckdb_standard_host.StrategyHostDispatch
  library : @native_duckdb.Library?
  runtimes : NativeStrategyComputeRun
  local_owners : Array[NativeStrategyLocalOwner]
  unfiled_local_owners : Array[NativeStrategyUnfiledLocalOwner]
  import_limits : NativeComputeImportLimits
  transfer_bytes : Int64
  database_memory_bytes : Int64
  database_path : String
  retained_profile : NativeStrategyRetainedOutputProfile?
  observe_phase : ((NativeStandardStrategyPhaseEvent) -> Unit)?
  resident_environments : Array[NativeResidentEnvironment]
  mut resident_fault : NativeResidentFault?
  mut resident_task_demand_bytes : Int64
  mut accepting : Bool
  mut complete : Bool
  mut dispatch_stopped : Bool
}

///|
/// Observation of existing synchronous physical boundaries. These events do
/// not authorize work, assert cancellation or confirm cleanup. A trusted
/// caller may supply a clock; the ordinary Host installs no observer.
pub(all) enum NativeStandardStrategyPhase {
  ResidentEnvironment(Int)
  ResidentInputImport(Int, Int)
  ResidentTask(Int)
} derive(Eq)

///|
pub(all) enum NativeStandardStrategyPhaseEvent {
  Begin(NativeStandardStrategyPhase)
  End(NativeStandardStrategyPhase, Bool)
}

///|
fn NativeStandardStrategyRun::observe_phase_event(
  self : NativeStandardStrategyRun,
  event : NativeStandardStrategyPhaseEvent,
) -> Unit {
  if self.observe_phase is Some(observe) {
    observe(event)
  }
}

///|
/// Physical observation of the Run's resident DuckDB environments. Counts are
/// product diagnostics; `temporary_views` and `tables` are read from each
/// still-open environment database between tasks (-1 when unavailable).
pub(all) struct NativeStandardResidentObservation {
  environments : Int
  imports : Int
  imported_rows : Int
  borrowed_inputs : Int
  /// Environments excluded from reuse because a transaction end was not
  /// confirmed; they are released only by destruction at Run release.
  unconfirmed_environments : Int
  /// Native allowance of each environment's most recent import attempt (the
  /// largest across environments), as presented to `begin_resident_transfer`.
  import_scratch_bytes : Int64
  /// Last resident task's whole execution demand checked against its envelope.
  task_demand_bytes : Int64
  temporary_views : Int64
  tables : Int64
} derive(Eq, Debug)

///|
pub(all) enum NativeStandardStrategyRunIssue {
  Closed
  InvalidSelection
  DuckDBUnavailable
  Dispatch(@duckdb_standard_host.DispatchIssue)
  Database(@native_duckdb.NativeDuckDBIssue)
  DuckDB(NativeStrategyComputeRunIssue)
  Local(NativeStrategyLocalIssue)
}

///|
/// One exact task completed by the configured standard Host. The selected
/// Connector remains private to the Host; remote and publication adapters
/// receive only the checked task index and its admitted output.
pub(all) struct NativeStandardStrategyTaskCompletion {
  task : Int
  output : @execution.CompletedOutput
  usage : NativeStandardStrategyTaskUsage?
  holding : NativeStandardStrategyTaskHolding?
}

///|
/// The sealed independent representation of this exact completed output.
pub(all) struct NativeStandardStrategyTaskHolding {
  rows : Int
  rows_cid : String
  bytes : Int64
}

///|
/// What a task's measurement covers. The two scopes are not interchangeable.
pub(all) enum NativeStandardStrategyMeasurementScope {
  /// Logical input-plus-output value measurement of a DuckDB attempt.
  InputOutputValues
  /// Work the bounded Local provider reported across its advances. No values
  /// are measured, so measurement bytes and nodes are zero.
  ProviderWork
}

///|
/// Product measurements for the completed task's actual implementation.
/// Logical obligations and ledger capacity remain separate accounting axes.
pub(all) struct NativeStandardStrategyTaskUsage {
  measurement_scope : NativeStandardStrategyMeasurementScope
  measurement_work : Int
  measurement_bytes : Int
  measurement_nodes : Int
  comparison_work : Int
  comparison_bytes : Int
  comparison_nodes : Int
}

///|
fn native_standard_task_usage(
  measured : (Int, Int, Int, Int, Int, Int),
) -> NativeStandardStrategyTaskUsage {
  {
    measurement_scope: InputOutputValues,
    measurement_work: measured.0,
    measurement_bytes: measured.1,
    measurement_nodes: measured.2,
    comparison_work: measured.3,
    comparison_bytes: measured.4,
    comparison_nodes: measured.5,
  }
}

///|
fn native_standard_task_holding(
  run : NativeStandardStrategyRun,
  output : @execution.CompletedOutput,
) -> NativeStandardStrategyTaskHolding? {
  guard native_standard_retained_result(run, output) is Some(source) &&
    source.file.sealed_content() is Some((rows_cid, bytes)) else {
    return None
  }
  Some({ rows: @execution.completed_row_count(output), rows_cid, bytes, })
}

///|
/// Failures from the standard native application boundary. A publication
/// commit failure returns the exact prepared owner so the caller can retry or
/// cancel without re-executing the Program.
pub(all) enum NativeStandardRunPublicationIssue {
  Strategy(NativeStandardStrategyRunIssue)
  RetainedConversion(Int, NativeComputeExecutionIssue)
  Preparation(@native_publication.NativeCapturedRunPublicationPreparationIssue)
  Publication(
    @native_publication.NativePreparedCapturedRunPublication,
    @native_publication.NativeRunPublicationIssue
  )
}

///|
pub fn open_native_standard_strategy_run(
  dispatch : @duckdb_standard_host.StrategyHostDispatch,
  import_limits : NativeComputeImportLimits,
  transfer_bytes : Int64,
  execution_bytes : Int64,
  library? : @native_duckdb.Library? = None,
  database_path? : String = "",
  retained_profile? : NativeStrategyRetainedOutputProfile,
  observe_phase? : (NativeStandardStrategyPhaseEvent) -> Unit,
) -> Result[NativeStandardStrategyRun, NativeStandardStrategyRunIssue] {
  if transfer_bytes < 0 || execution_bytes <= 0 {
    return Err(InvalidSelection)
  }
  if retained_profile is Some(profile) && profile.max_file_bytes <= 0L {
    return Err(InvalidSelection)
  }
  // Every realization this Host selects (Local, DuckDB, native) starts only
  // under a per-task activation grant held by the captured Run.
  @strategy.require_captured_task_activation(
    @duckdb_standard_host.dispatch_run(dispatch),
  )
  Ok({
    dispatch,
    library,
    runtimes: open_native_strategy_compute_run(),
    local_owners: [],
    unfiled_local_owners: [],
    import_limits,
    transfer_bytes,
    database_memory_bytes: execution_bytes,
    database_path,
    retained_profile,
    observe_phase,
    resident_environments: [],
    resident_fault: None,
    resident_task_demand_bytes: 0L,
    accepting: true,
    complete: false,
    dispatch_stopped: false,
  })
}

///|
fn NativeStandardStrategyRun::stop_dispatch(
  self : NativeStandardStrategyRun,
) -> Unit {
  if !self.dispatch_stopped {
    @duckdb_standard_host.stop_strategy_dispatch(self.dispatch)
    self.dispatch_stopped = true
  }
}

///|
/// Execute one checked-ready task through the exact implementation selected by
/// the portable Host. `None` means the Run has no remaining task. Failure
/// stops admission but leaves task runtimes in this owner until explicit
/// cleanup confirms their release.
pub fn execute_next_native_standard_strategy_task(
  run : NativeStandardStrategyRun,
) -> Result[
  NativeStandardStrategyTaskCompletion?,
  NativeStandardStrategyRunIssue,
] {
  if !run.accepting {
    return Err(Closed)
  }
  let prepared = match
    @duckdb_standard_host.prepare_next_dispatch(run.dispatch) {
    Ok(value) => value
    Err(issue) => {
      run.accepting = false
      run.stop_dispatch()
      return Err(Dispatch(issue))
    }
  }
  guard prepared is Some(task) else {
    run.accepting = false
    run.complete = true
    run.stop_dispatch()
    return Ok(None)
  }
  let task_index = @duckdb_standard_host.dispatch_task(task)
  guard @duckdb_standard_host.dispatch_registration(task) is Some(selected) else {
    run.accepting = false
    run.stop_dispatch()
    return Err(InvalidSelection)
  }
  // In-process native compute over already captured inputs has no protected
  // scope: its data was admitted at Acquisition. This is the explicit,
  // evaluation-free coverage grant; remote dispatch and transfer stay gated at
  // their own boundaries.
  if @strategy.authorize_captured_task_activation(
      @duckdb_standard_host.dispatch_run(run.dispatch),
      task_index,
      @strategy.task_activation_covered(),
    )
    is Err(_) {
    run.accepting = false
    run.stop_dispatch()
    return Err(InvalidSelection)
  }
  if physical_equal(
      selected,
      @duckdb_standard_host.dispatch_local_registration(run.dispatch),
    ) {
    if run.retained_profile is Some(profile) {
      let operations = match @duckdb_standard_host.take_local_dispatch(task) {
        Ok(value) => value
        Err(issue) => {
          run.accepting = false
          run.stop_dispatch()
          return Err(Dispatch(issue))
        }
      }
      let owner = match
        start_native_strategy_local_owner(operations, profile, task_index) {
        Ok(value) => value
        Err(issue) => {
          run.unfiled_local_owners.push({
            operations,
            closed: false,
            settled: false,
          })
          run.accepting = false
          run.stop_dispatch()
          return Err(Local(issue))
        }
      }
      run.local_owners.push(owner)
      match
        execute_native_strategy_local_owner(owner, input => {
          for previous in run.local_owners {
            if native_strategy_local_input_source(previous, input)
              is Some(source) {
              return Some(source)
            }
          }
          native_strategy_retained_input(run.runtimes, input)
        }) {
        Ok(_) => ()
        Err(issue) => {
          run.accepting = false
          run.stop_dispatch()
          return Err(Local(issue))
        }
      }
    } else {
      match @duckdb_standard_host.execute_synchronous_dispatch(task) {
        Err(issue) => {
          run.accepting = false
          run.stop_dispatch()
          return Err(Dispatch(issue))
        }
        Ok(_) => ()
      }
    }
    guard @strategy.captured_task_target(
        @duckdb_standard_host.dispatch_run(run.dispatch),
        task_index,
      )
      is Some(target) &&
      @strategy.captured_task_output(
        @duckdb_standard_host.dispatch_run(run.dispatch),
        task_index,
        target,
      )
      is Some(output) else {
      run.accepting = false
      run.stop_dispatch()
      return Err(InvalidSelection)
    }
    // The bounded provider measures no values; its reported work is the
    // task's only measurement, scoped as such.
    let usage = if run.retained_profile is Some(_) {
      let last = run.local_owners[run.local_owners.length() - 1]
      match (last.operations.provider_work)() {
        Some(work) if work <= 2147483647L =>
          Some({
            measurement_scope: ProviderWork,
            measurement_work: work.to_int(),
            measurement_bytes: 0,
            measurement_nodes: 0,
            comparison_work: 0,
            comparison_bytes: 0,
            comparison_nodes: 0,
          })
        _ => None
      }
    } else {
      None
    }
    return Ok(
      Some({
        task: task_index,
        output,
        usage,
        holding: native_standard_task_holding(run, output),
      }),
    )
  }
  if !physical_equal(
      selected,
      @duckdb_standard_host.dispatch_duckdb_registration(run.dispatch),
    ) {
    run.accepting = false
    run.stop_dispatch()
    return Err(InvalidSelection)
  }
  let setup = match @duckdb_standard_host.take_native_dispatch(task) {
    Ok(value) => value
    Err(issue) => {
      run.accepting = false
      run.stop_dispatch()
      return Err(Dispatch(issue))
    }
  }
  // Residency is the portable strategy's selection for this exact task. The
  // environment is provisioned under its own reservation; the task's whole
  // execution demand is then admitted against its envelope before any input
  // is imported or any native work for the task starts.
  let resident = match @duckdb_standard_host.dispatch_resource_binding(task) {
    None => None
    Some(binding) => {
      let prepared = match
        prepare_native_resident_environment(run, task_index, binding) {
        Ok(env) =>
          match native_resident_task_allowance(run, setup, task_index) {
            Ok(bytes) =>
              match import_native_resident_inputs(run, env, task_index) {
                Ok(_) => Ok((env, bytes))
                Err(issue) => Err(issue)
              }
            Err(issue) => Err(issue)
          }
        Err(issue) => Err(issue)
      }
      match prepared {
        Ok(value) => Some(value)
        Err(issue) => {
          run.accepting = false
          run.stop_dispatch()
          return Err(issue)
        }
      }
    }
  }
  let additional_retained_source = fn(input) {
    for owner in run.local_owners {
      if native_strategy_local_input_source(owner, input) is Some(source) {
        return Some(source)
      }
    }
    None
  }
  if resident is Some((env, execution_bytes)) {
    let phase = ResidentTask(task_index)
    run.observe_phase_event(Begin(phase))
    let executed = match
      borrow_native_resident_inputs(run, env, setup, task_index) {
      Err(issue) => Err(issue)
      Ok(binding) =>
        execute_native_strategy_task(
          run.runtimes,
          setup,
          env.database.unwrap(),
          run.import_limits,
          run.transfer_bytes,
          execution_bytes,
          retained_profile?=run.retained_profile,
          additional_retained_source~,
          resident=binding,
        ).map_err(issue => DuckDB(issue))
    }
    run.observe_phase_event(End(phase, executed is Ok(_)))
    return match executed {
      Ok(output) =>
        Ok(
          Some({
            task: task_index,
            output,
            usage: native_strategy_compute_task_usage(run.runtimes, task_index).map(
              native_standard_task_usage,
            ),
            holding: native_standard_task_holding(run, output),
          }),
        )
      Err(issue) => {
        run.accepting = false
        run.stop_dispatch()
        Err(issue)
      }
    }
  }
  guard run.library is Some(library) else {
    run.accepting = false
    run.stop_dispatch()
    return Err(DuckDBUnavailable)
  }
  // The driver reserves this engine budget plus its separately measured
  // transport/receiving scratch through the common execution ledger.
  let database = match
    library.open_database(
      {
        memory_bytes: run.database_memory_bytes,
        threads: 1,
        external_access: false,
        read_only: false,
      },
      path=run.database_path,
    ) {
    Ok(value) => value
    Err(issue) => {
      run.accepting = false
      run.stop_dispatch()
      return Err(Database(issue))
    }
  }
  match
    execute_native_strategy_compute_task(
      run.runtimes,
      setup,
      database,
      run.import_limits,
      run.transfer_bytes,
      run.database_memory_bytes,
      retained_profile?=run.retained_profile,
      additional_retained_source~,
    ) {
    Ok(output) =>
      Ok(
        Some({
          task: task_index,
          output,
          usage: native_strategy_compute_task_usage(run.runtimes, task_index).map(
            native_standard_task_usage,
          ),
          holding: native_standard_task_holding(run, output),
        }),
      )
    Err(issue) => {
      run.accepting = false
      run.stop_dispatch()
      Err(DuckDB(issue))
    }
  }
}

///|
/// Execute every checked-ready task through the one-task boundary available to
/// remote dispatch adapters. There is no second selection or completion path.
pub fn execute_native_standard_strategy_run(
  run : NativeStandardStrategyRun,
) -> Result[Unit, NativeStandardStrategyRunIssue] {
  while true {
    match execute_next_native_standard_strategy_task(run) {
      Ok(Some(_)) => continue
      Ok(None) => return Ok(())
      Err(issue) => return Err(issue)
    }
  } nobreak {
    Err(InvalidSelection)
  }
}

///|
fn native_standard_retained_result(
  run : NativeStandardStrategyRun,
  output : @execution.CompletedOutput,
) -> NativeComputeRetainedInput? {
  if native_strategy_retained_result(run.runtimes, output) is Some(source) {
    return Some(source)
  }
  for owner in run.local_owners {
    if native_strategy_local_result_source(owner, output) is Some(source) {
      return Some(source)
    }
  }
  None
}

///|
/// Consume an exact completed task through a fresh verified file reader.
/// The bounded projection is shared with formal publication and never adopts
/// a caller-provided path or a matching CID from another occurrence.
pub fn read_native_standard_task_output(
  run : NativeStandardStrategyRun,
  task : Int,
  max_rows : Int,
  values : @execution.ValueLimits,
  wire : @execution.RowWireLimits,
  max_batch_bytes : Int,
) -> Result[@execution.CompletedOutput, NativeStandardRunPublicationIssue] {
  let captured = @duckdb_standard_host.dispatch_run(run.dispatch)
  guard @strategy.captured_task_target(captured, task) is Some(target) &&
    @strategy.captured_task_output(captured, task, target) is Some(output) else {
    return Err(Strategy(InvalidSelection))
  }
  match native_standard_retained_result(run, output) {
    None =>
      if run.retained_profile is Some(_) {
        Err(Strategy(InvalidSelection))
      } else {
        Ok(output)
      }
    Some(source) =>
      convert_native_retained_result_for_publication(
        output, source, max_rows, values, wire, max_batch_bytes,
      ).map_err(issue => RetainedConversion(task, issue))
  }
}

///|
/// Execute the configured checked Program, persist every declared Named
/// Result, and commit the formal Run publication. Connector selection remains
/// in the portable Host, while all publication progression remains in the
/// portable publication owner. The retained strategy owner stays live until
/// the caller explicitly closes it after downstream use.
pub fn execute_and_publish_native_standard_strategy_run(
  run : NativeStandardStrategyRun,
  service : @native_publication.NativeRunPublicationService,
  context : @native_publication.NativeEffectFreeRunContext,
  results : Array[@native_publication.NativeCapturedResultPublicationContext],
  intent : @native_publication.NativeRunPublicationIntent,
  occurrence : @native_publication.NativeRunPublicationOccurrence,
  export_limits : @publication_host.PublicationOutputExportLimits,
) -> Result[
  @native_publication.NativeRunPublicationResult,
  NativeStandardRunPublicationIssue,
] {
  match execute_native_standard_strategy_run(run) {
    Ok(_) => ()
    Err(issue) => return Err(Strategy(issue))
  }
  let captured = @duckdb_standard_host.dispatch_run(run.dispatch)
  let graph = @strategy.captured_dag_graph(captured)
  let converted : Array[@execution.CompletedOutput?] = []
  for result in 0..<@strategy.graph_result_count(graph) {
    guard @strategy.graph_result_task(graph, result) is Some(task) &&
      @strategy.captured_task_target(captured, task) is Some(target) &&
      @strategy.captured_task_output(captured, task, target) is Some(output) else {
      return Err(Strategy(InvalidSelection))
    }
    match native_standard_retained_result(run, output) {
      None => converted.push(None)
      Some(_) =>
        match
          read_native_standard_task_output(
            run,
            task,
            export_limits.max_rows,
            export_limits.values,
            export_limits.payload_wire,
            export_limits.max_batch_bytes,
          ) {
          Ok(value) => converted.push(Some(value))
          Err(issue) => return Err(issue)
        }
    }
  }
  let prepared = match
    @native_publication.prepare_captured_effect_free_run_publication_native(
      service,
      captured,
      context,
      results,
      intent,
      occurrence,
      export_limits,
      converted_outputs=converted,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Preparation(issue))
  }
  match prepared.commit() {
    Ok(value) => Ok(value)
    Err(issue) => Err(Publication(prepared, issue))
  }
}

///|
pub fn native_standard_strategy_run_complete(
  run : NativeStandardStrategyRun,
) -> Bool {
  run.complete
}

///|
pub fn native_standard_strategy_run_task_count(
  run : NativeStandardStrategyRun,
) -> Int {
  native_strategy_compute_run_task_count(run.runtimes) +
  run.local_owners.length() +
  run.unfiled_local_owners.length()
}

///|
/// Stop new dispatch and release all retained common task owners. A false
/// result or error keeps the owner retryable; it is never inferred as cleanup.
pub fn close_native_standard_strategy_run(
  run : NativeStandardStrategyRun,
) -> Result[Bool, NativeStrategyComputeCleanupIssue] {
  run.accepting = false
  run.stop_dispatch()
  let mut pending = false
  let mut first : NativeStrategyComputeCleanupIssue? = None
  // The Run's end is the only point at which a resident database stops.
  // Destroying it first confirms the stop of any task or import whose own
  // transaction end could not be observed.
  for env in run.resident_environments {
    close_native_resident_database(env)
  }
  for owner in run.unfiled_local_owners {
    match close_native_strategy_unfiled_local_owner(owner) {
      Ok(_) => ()
      Err(issue) => {
        pending = true
        if first is None {
          first = Some(issue)
        }
      }
    }
  }
  for offset in 0..<run.local_owners.length() {
    let owner = run.local_owners[run.local_owners.length() - offset - 1]
    match close_native_strategy_local_owner(owner) {
      Ok(true) => ()
      Ok(false) => pending = true
      Err(issue) => {
        pending = true
        if first is None {
          first = Some(issue)
        }
      }
    }
  }
  match close_native_strategy_compute_run(run.runtimes) {
    Ok(true) => ()
    Ok(false) => pending = true
    Err(issue) => {
      pending = true
      if first is None {
        first = Some(issue)
      }
    }
  }
  // Borrowers returned at task settlement; only now can the shared capacity
  // and its remaining table allocations settle.
  let graph = @duckdb_standard_host.dispatch_run(run.dispatch)
  for env in run.resident_environments {
    match release_native_resident_environment(graph, env) {
      Ok(true) => ()
      Ok(false) => pending = true
      Err(issue) => {
        pending = true
        if first is None {
          first = Some(Ledger(issue))
        }
      }
    }
  }
  match first {
    Some(issue) => Err(issue)
    None => Ok(!pending)
  }
}

///|
/// Reuse the Run's environment for the selected resource binding or provision
/// it once: the common reservation is taken first, the native database is
/// opened with exactly the reserved engine bytes, and only that confirmation
/// makes it usable. A failed provision keeps its release owner in the Run.
fn prepare_native_resident_environment(
  run : NativeStandardStrategyRun,
  task : Int,
  binding : @connector.ResourceBinding,
) -> Result[NativeResidentEnvironment, NativeStandardStrategyRunIssue] {
  for env in run.resident_environments {
    if !env.released &&
      native_resident_environment_binding_matches(env, binding) {
      // A database whose last transaction end was not confirmed is never
      // borrowed again; it waits for destruction at Run release.
      if env.database_closed || env.database is None || env.unconfirmed {
        return Err(InvalidSelection)
      }
      return Ok(env)
    }
  }
  let phase = ResidentEnvironment(task)
  run.observe_phase_event(Begin(phase))
  let prepared = create_native_resident_environment(run, task)
  run.observe_phase_event(End(phase, prepared is Ok(_)))
  prepared
}

///|
fn create_native_resident_environment(
  run : NativeStandardStrategyRun,
  task : Int,
) -> Result[NativeResidentEnvironment, NativeStandardStrategyRunIssue] {
  let graph = @duckdb_standard_host.dispatch_run(run.dispatch)
  guard run.library is Some(library) else { return Err(DuckDBUnavailable) }
  let environment = match
    @strategy.begin_resident_environment(graph, task, run.database_memory_bytes) {
    Ok(value) => value
    Err(issue) => return Err(DuckDB(Start(Strategy(issue))))
  }
  let env : NativeResidentEnvironment = {
    store: @duckdb_driver.prepare_resident_store(environment),
    database: None,
    database_closed: false,
    released: false,
    unsettled_transfers: [],
    imports: 0,
    imported_rows: 0,
    borrowed_inputs: 0,
    unconfirmed: false,
    import_scratch_bytes: 0L,
  }
  run.resident_environments.push(env)
  // An in-memory database: resident tables are run-private and are never
  // written into a source or caller-supplied database file.
  match
    library.open_database({
      memory_bytes: run.database_memory_bytes,
      threads: 1,
      external_access: false,
      read_only: false,
    }) {
    Ok(database) => env.database = Some(database)
    Err(issue) => {
      release_native_resident_environment(graph, env) |> ignore
      return Err(Database(issue))
    }
  }
  match
    @strategy.confirm_resident_environment(
      graph,
      environment,
      run.database_memory_bytes,
    ) {
    Ok(_) => Ok(env)
    Err(issue) => {
      release_native_resident_environment(graph, env) |> ignore
      Err(DuckDB(Start(Strategy(issue))))
    }
  }
}

///|
/// Import only producers that are not already committed tables of this exact
/// environment generation. A committed resident table is reused as is.
fn import_native_resident_inputs(
  run : NativeStandardStrategyRun,
  env : NativeResidentEnvironment,
  task : Int,
) -> Result[Unit, NativeStandardStrategyRunIssue] {
  let graph = @duckdb_standard_host.dispatch_run(run.dispatch)
  guard @duckdb_standard_host.dispatch_resident_inputs(run.dispatch, task)
    is Some(inputs) else {
    return Err(InvalidSelection)
  }
  let environment = @duckdb_driver.resident_store_environment(env.store)
  let frame_bytes = match run.retained_profile {
    Some(profile) => profile.max_batch_bytes
    None => 1
  }
  for input in inputs {
    let (producer, bytes, entries, names) = input
    if @strategy.resident_table_at(graph, environment, producer) is Some(_) {
      env.borrowed_inputs += 1
      continue
    }
    let phase = ResidentInputImport(task, producer)
    run.observe_phase_event(Begin(phase))
    let imported = import_native_resident_table(
      graph,
      env,
      producer,
      bytes,
      entries,
      names,
      run.import_limits,
      run.transfer_bytes,
      frame_bytes,
      storage => native_standard_retained_storage(run, producer, storage),
    )
    run.observe_phase_event(End(phase, imported is Ok(_)))
    match imported {
      Ok(_) => ()
      Err(issue) => return Err(DuckDB(issue))
    }
  }
  Ok(())
}

///|
fn borrow_native_resident_inputs(
  run : NativeStandardStrategyRun,
  env : NativeResidentEnvironment,
  setup : @duckdb_driver.StrategyComputeHostConfiguration,
  task : Int,
) -> Result[NativeResidentTaskBinding, NativeStandardStrategyRunIssue] {
  let graph = @duckdb_standard_host.dispatch_run(run.dispatch)
  guard @duckdb_standard_host.dispatch_resident_inputs(run.dispatch, task)
    is Some(inputs) &&
    inputs.length() > 0 else {
    return Err(InvalidSelection)
  }
  let environment = @duckdb_driver.resident_store_environment(env.store)
  let tables = []
  for input in inputs {
    guard @strategy.resident_table_at(graph, environment, input.0)
      is Some(table) else {
      return Err(InvalidSelection)
    }
    tables.push(table)
  }
  let (_, _, entries, names) = inputs[inputs.length() - 1]
  match
    @duckdb_driver.borrow_configured_resident_inputs(
      setup,
      env.store,
      tables,
      entries,
      names,
      run.import_limits.max_sql_bytes,
    ) {
    Ok(borrowed) => {
      let fault = run.resident_fault
      run.resident_fault = None
      Ok({
        environment: env,
        inputs: borrowed,
        max_sql_bytes: run.import_limits.max_sql_bytes,
        row_bytes: native_resident_row_bytes(run),
        fault,
      })
    }
    Err(issue) => Err(DuckDB(Start(Strategy(issue))))
  }
}

///|
/// Frame bound of any retained holding a resident task may re-read. The task
/// enforces it at use because its reservation is sized from it.
fn native_resident_row_bytes(run : NativeStandardStrategyRun) -> Int {
  match run.retained_profile {
    Some(profile) => profile.max_batch_bytes
    None => 1
  }
}

///|
/// Size the task's native allowance and admit the task's whole execution
/// demand (native allowance, the connector's receiver scratch, and the shared
/// engine reservation) against its selected envelope before any import or
/// native work. Common admission repeats the same check at start.
fn native_resident_task_allowance(
  run : NativeStandardStrategyRun,
  setup : @duckdb_driver.StrategyComputeHostConfiguration,
  task : Int,
) -> Result[Int64, NativeStandardStrategyRunIssue] {
  let graph = @duckdb_standard_host.dispatch_run(run.dispatch)
  guard @duckdb_standard_host.dispatch_resident_inputs(run.dispatch, task)
    is Some(inputs) &&
    @duckdb_driver.configured_compute_plan(
      @duckdb_driver.configured_strategy_compute_configuration(setup),
    )
    is Some(plan) else {
    return Err(InvalidSelection)
  }
  let retained = match
    @duckdb_driver.configured_strategy_output_file_bytes(setup) {
    Some(bytes) => bytes > 0L
    None => false
  }
  guard native_resident_task_scratch_bytes(
      run.import_limits,
      inputs.length(),
      @resources.ledger_limits(@strategy.captured_dag_ledger(graph)).holdings,
      @duckdb.fixed_query_parameter_count(@duckdb.fixed_compute_query(plan)),
      run.retained_profile.map(profile => profile.max_batch_bytes),
    )
    is Some(native) &&
    @duckdb_driver.configured_strategy_scratch_capacity(setup, retained~)
    is Some(receiver) &&
    @strategy.strategy_task_envelope(graph, task) is Some(envelope) else {
    return Err(InvalidSelection)
  }
  let demand = native + receiver + run.database_memory_bytes
  run.resident_task_demand_bytes = demand
  if demand > envelope.execution_bytes {
    return Err(DuckDB(Start(Strategy(Physical(InvalidCharge)))))
  }
  Ok(native)
}

///|
/// The exact retained holding of a completed producer whose storage is being
/// copied into the environment. Selection is by producer occurrence, never by
/// content identity or path.
fn native_standard_retained_storage(
  run : NativeStandardStrategyRun,
  producer : Int,
  storage : @execution.ProducerStorage,
) -> NativeComputeRetainedInput? {
  let graph = @duckdb_standard_host.dispatch_run(run.dispatch)
  guard @strategy.captured_task_target(graph, producer) is Some(target) &&
    @strategy.captured_task_output(graph, producer, target) is Some(output) &&
    @execution.producer_storage_matches_output(storage, output) else {
    return None
  }
  native_standard_retained_result(run, output)
}

///|
pub fn native_standard_strategy_run_resident_observation(
  run : NativeStandardStrategyRun,
) -> NativeStandardResidentObservation {
  let mut imports = 0
  let mut imported_rows = 0
  let mut borrowed_inputs = 0
  let mut temporary_views = 0L
  let mut tables = 0L
  for env in run.resident_environments {
    imports += env.imports
    imported_rows += env.imported_rows
    borrowed_inputs += env.borrowed_inputs
    if env.database is Some(database) && !env.database_closed {
      match
        database.query_i64(
          "SELECT count(*) FROM duckdb_views() WHERE temporary AND NOT internal",
        ) {
        Ok(count) if temporary_views >= 0L => temporary_views += count
        _ => temporary_views = -1L
      }
      match
        database.query_i64(
          "SELECT count(*) FROM duckdb_tables() WHERE NOT internal",
        ) {
        Ok(count) if tables >= 0L => tables += count
        _ => tables = -1L
      }
    }
  }
  {
    environments: run.resident_environments.length(),
    imports,
    imported_rows,
    borrowed_inputs,
    unconfirmed_environments: run.resident_environments
    .filter(env => env.unconfirmed)
    .length(),
    import_scratch_bytes: run.resident_environments.fold(init=0L, (bytes, env) => {
      Int64::max(bytes, env.import_scratch_bytes)
    }),
    task_demand_bytes: run.resident_task_demand_bytes,
    temporary_views,
    tables,
  }
}
