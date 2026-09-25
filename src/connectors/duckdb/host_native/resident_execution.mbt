///|
/// One run-owned native DuckDB database for the resource binding selected by
/// the portable strategy. Reservation, table ownership, borrowing, release and
/// settlement stay in the common resident environment; this owner holds only
/// the physical database and the cleanup facts that the database can confirm.
priv struct NativeResidentEnvironment {
  store : @duckdb_driver.DuckDBResidentStore
  mut database : @native_duckdb.Database?
  mut database_closed : Bool
  mut released : Bool
  /// Import reservations whose native end was not confirmed. Destroying the
  /// database is their stop confirmation.
  unsettled_transfers : Array[@strategy.ResidentTransfer]
  mut imports : Int
  mut imported_rows : Int
  mut borrowed_inputs : Int
  /// A task or import on this database ended without a confirmed rollback or
  /// commit. Its state is unknown, so no later task may borrow it; only its
  /// destruction at Run release confirms the stop.
  mut unconfirmed : Bool
  /// Allowance of the most recent import attempt (admitted or rejected).
  mut import_scratch_bytes : Int64
}

///|
/// A one-shot transaction-end failure for the next resident task. It exists
/// only so tests can observe the Host's handling of an unconfirmed stop.
priv enum NativeResidentFault {
  Rollback
  CommitAndRollback
}

///|
/// Physical borrow of one resident task. The task shares the environment
/// database but ends its own transaction and connection-local views.
priv struct NativeResidentTaskBinding {
  environment : NativeResidentEnvironment
  inputs : @duckdb_driver.DuckDBResidentInputs
  max_sql_bytes : Int
  /// Frame bound of any retained holding this task may re-read; enforced at
  /// use because the task reservation was sized from it.
  row_bytes : Int
  /// Whitebox-only seam; see `fail_next_native_resident_transaction_end`.
  fault : NativeResidentFault?
}

///|
/// Commands return at most one count row; this bounds that transport only.
const NATIVE_RESIDENT_COMMAND_BYTES : Int = 4096

///|
/// Per boxed value or container entry: the same entry convention the portable
/// DuckDB capacity calculations (`duckdb_task_retention_capacity`) use.
const NATIVE_RESIDENT_ENTRY_BYTES : Int64 = 256L

///|
/// One native retained-holding read: the reader's chunk (at most 64 KiB and at
/// most one frame), the row-frame decoder's partial frame, and the current
/// row's text held as a MoonBit string (at most 2 bytes per UTF-8 byte).
fn native_resident_storage_read_bytes(row_bytes : Int) -> Int64 {
  Int::min(65536, row_bytes).to_int64() +
  row_bytes.to_int64() +
  row_bytes.to_int64() * 2L
}

///|
/// Reservation ceiling for the native Host's own allocations while importing
/// one producer into a resident environment. It is a safe upper bound, not a
/// performance estimate, and is admitted by `begin_resident_transfer` before
/// any statement is compiled or any native work starts. `row_bytes` is the
/// frame bound of the producer's retained holding (`retained`), or for a
/// cell-backed producer the bound of one bound value. Engine memory is the
/// environment's separate shared reservation and is never counted here.
pub fn native_resident_import_scratch_bytes(
  limits : NativeComputeImportLimits,
  rows : Int,
  columns : Int,
  row_bytes : Int,
  retained : Bool,
) -> Int64? {
  if rows < 0 ||
    columns < 1 ||
    row_bytes < 1 ||
    limits.max_sql_bytes < 0 ||
    limits.max_batch_rows < 1 ||
    limits.max_parameters < columns {
    return None
  }
  let sql = limits.max_sql_bytes.to_int64()
  // The batch bound handed to the statement compiler.
  let batch_rows = Int::min(
    rows,
    Int::min(limits.max_batch_rows, limits.max_parameters / columns),
  ).to_int64()
  let row = row_bytes.to_int64()
  // CREATE, batch INSERT and tail INSERT stay live for the whole import as
  // MoonBit strings (2 bytes per admitted UTF-8 byte each), plus the UTF-8
  // copy the adapter hands DuckDB for the one executing statement.
  let statements = sql * 7L
  // One pending parameter batch: its boxed values.
  let containers = batch_rows * columns.to_int64() * NATIVE_RESIDENT_ENTRY_BYTES
  // Text decoded from the pending batch's rows (each row came from one frame
  // of at most `row_bytes` UTF-8 bytes); cell-backed values share storage.
  let payload = if retained { batch_rows * row * 2L } else { 0L }
  // UTF-8 copy of the one value being bound; a value never exceeds the frame
  // that carries it.
  let binding = row
  let storage = if retained {
    native_resident_storage_read_bytes(row_bytes)
  } else {
    0L
  }
  Some(statements + containers + payload + binding + storage)
}

///|
/// Reservation ceiling for the native Host's own allocations in one resident
/// task, admitted with the task's common reservation before its transaction
/// starts. Transport frame decoding and receiver admission are not counted:
/// the portable `duckdb_stream_scratch_capacity`/`duckdb_task_scratch_capacity`
/// term already charges the same frames to this reservation. Engine memory is
/// the environment's shared reservation.
pub fn native_resident_task_scratch_bytes(
  limits : NativeComputeImportLimits,
  inputs : Int,
  max_tables : Int,
  query_parameters : Int,
  retained_row_bytes : Int?,
) -> Int64? {
  if inputs < 0 ||
    max_tables < 0 ||
    query_parameters < 0 ||
    limits.max_sql_bytes < 0 {
    return None
  }
  let sql = limits.max_sql_bytes.to_int64()
  // Retained until the transaction ends: one DROP VIEW per input and the
  // cleanup DROP TABLE for each table the portable cleanup may retire (at most
  // the environment's table slots), 2 bytes per UTF-8 byte each. At a time:
  // one scan/demand statement (2) and the executing UTF-8 copy (1).
  let statements = (inputs.to_int64() * 2L + max_tables.to_int64() * 2L + 3L) *
    sql
  // Bound parameters of the result CREATE; the values stay the fixed query's.
  let parameters = query_parameters.to_int64() * NATIVE_RESIDENT_ENTRY_BYTES
  // Fallback re-verification of one retained input from its holding.
  let storage = match retained_row_bytes {
    Some(row_bytes) if row_bytes > 0 =>
      native_resident_storage_read_bytes(row_bytes)
    Some(_) => return None
    None => 0L
  }
  Some(statements + parameters + storage)
}

///|
/// Whitebox test seam: make the next resident task transaction on this Run
/// report a failed rollback (and, with `commit`, first a failed commit) so the
/// Host's unconfirmed-stop handling can be exercised against real DuckDB. The
/// real rollback still runs; only its confirmation is withheld.
#internal(test_seam, "whitebox fault seam for resident transaction ends")
pub fn fail_next_native_resident_transaction_end(
  run : NativeStandardStrategyRun,
  commit : Bool,
) -> Unit {
  run.resident_fault = Some(if commit { CommitAndRollback } else { Rollback })
}

///|
fn native_resident_environment_binding_matches(
  env : NativeResidentEnvironment,
  binding : @connector.ResourceBinding,
) -> Bool {
  match
    @strategy.resident_environment_resource_binding(
      @duckdb_driver.resident_store_environment(env.store),
    ) {
    Some(owned) => physical_equal(owned, binding)
    None => false
  }
}

///|
/// Destroying the database is the only physical stop confirmation for work
/// whose own transaction end could not be observed.
fn close_native_resident_database(env : NativeResidentEnvironment) -> Unit {
  if env.database_closed {
    return
  }
  if env.database is Some(database) {
    database.close()
  }
  env.database = None
  env.database_closed = true
}

///|
/// Confirmed release of the environment after its database is destroyed and
/// every borrowing task has settled. A failure keeps this owner retryable.
fn release_native_resident_environment(
  graph : @strategy.CapturedDAG,
  env : NativeResidentEnvironment,
) -> Result[Bool, @resources.LedgerIssue] {
  if env.released {
    return Ok(true)
  }
  close_native_resident_database(env)
  let pending = []
  for transfer in env.unsettled_transfers {
    match @strategy.settle_resident_transfer(graph, transfer, true) {
      Ok(_) => ()
      Err(_) => pending.push(transfer)
    }
  }
  env.unsettled_transfers.clear()
  for transfer in pending {
    env.unsettled_transfers.push(transfer)
  }
  if !pending.is_empty() {
    return Ok(false)
  }
  match @duckdb_driver.close_resident_store(graph, env.store, true) {
    Ok(_) => {
      env.released = true
      Ok(true)
    }
    Err(issue) => Err(issue)
  }
}

///|
fn run_native_resident_query(
  database : @native_duckdb.Database,
  sql : String,
  transport : @duckdb.TransportColumnLimits,
  max_rows : Int64,
  begin : (Array[(String, @duckdb.PhysicalType)]) -> Result[
    @duckdb.PhysicalResult,
    @duckdb_compute.DuckDBComputeIssue,
  ],
  accept : (@duckdb.PhysicalResult, Int, Array[@decode.Cursor]) -> Result[
    Unit,
    @duckdb_compute.DuckDBComputeIssue,
  ],
) -> Result[Unit, NativeComputeExecutionIssue] {
  let query = match
    database.prepare_stream_query(
      sql,
      transport.max_columns,
      max_rows,
      transport.max_rows,
      transport.max_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Runtime(issue))
  }
  let fail = fn(issue : NativeComputeExecutionIssue) {
    query.close() |> ignore
    Err(issue)
  }
  if query.parameter_count() != 0 {
    return fail(ParameterCount)
  }
  match query.execute() {
    Ok(_) => ()
    Err(issue) => return fail(Runtime(issue))
  }
  let fields = match query.fields_json() {
    Ok(text) =>
      match @duckdb.decode_physical_fields(text, transport) {
        Ok(value) => value
        Err(issue) => return fail(Fields(issue))
      }
    Err(issue) => return fail(Runtime(issue))
  }
  let physical = match begin(fields) {
    Ok(value) => value
    Err(issue) => return fail(Compute(issue))
  }
  while true {
    match query.next() {
      Ok(Some(chunk)) => {
        let columns = match
          @duckdb.decode_transport_columns(chunk.columns_json, transport) {
          Ok(value) => value
          Err(issue) => return fail(Columns(issue))
        }
        match accept(physical, chunk.row_count, columns) {
          Ok(_) => ()
          Err(issue) => return fail(Compute(issue))
        }
      }
      Ok(None) => break
      Err(issue) => return fail(Runtime(issue))
    }
  }
  if !query.close() {
    return Err(RuntimeState)
  }
  Ok(())
}

///|
/// Establish one borrowed resident input exactly as the Node resident Host
/// does: reuse the verified identity/value/demand evidence of this immutable
/// generation when the portable verifier accepts it, otherwise scan the table
/// or, without a scan plan, re-verify the independent holding. No rows are
/// imported; cell-backed inputs are already admitted by the attempt.
fn verify_native_resident_input(
  runtime : NativeStrategyComputeRuntime,
  binding : NativeResidentTaskBinding,
  attempt : @duckdb_compute.DuckDBComputeAttempt,
  port : Int,
  retained_source : ((@execution.ProducerRead) -> NativeComputeRetainedInput?)?,
) -> Result[Unit, NativeComputeExecutionIssue] {
  let plan = @duckdb_compute.duckdb_compute_attempt_plan(attempt)
  guard @duckdb.fixed_compute_import(plan, port) is Some(imported) else {
    return Err(ImportCount)
  }
  let input = @duckdb.fixed_import_input(imported)
  if @execution.producer_read_retained_material(input) is None {
    return Ok(())
  }
  guard retained_source is Some(resolve) && resolve(input) is Some(source) else {
    return Err(RuntimeState)
  }
  // The task reservation was sized from `binding.row_bytes`.
  if source.max_batch_bytes > runtime.transport.max_bytes ||
    source.max_batch_bytes > binding.row_bytes {
    return Err(InvalidLimits)
  }
  let read = @duckdb_driver.resident_inputs_read_plans(binding.inputs).get(port)
  let scan = match read {
    Some(read) =>
      match
        @duckdb_compute.duckdb_resident_scan_sql(read, binding.max_sql_bytes) {
        Ok(sql) => Some(sql)
        Err(_) => None
      }
    None => None
  }
  match
    @duckdb_compute.begin_duckdb_compute_input_stream(
      attempt,
      port,
      source.wire,
      source.max_batch_bytes,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Compute(issue))
  }
  let finish = fn() {
    @duckdb_compute.finish_duckdb_compute_input_stream(attempt, port).map_err(issue => {
      Compute(issue)
    })
  }
  guard scan is Some(scan_sql) else {
    match
      read_native_retained_rows(
        source,
        @execution.producer_read_row_count(input),
        Ref(false),
        _ => Ok(()),
        row => {
          @duckdb_compute.append_duckdb_compute_input_stream(
            attempt,
            port,
            row,
            {
              max_bytes: source.max_batch_bytes,
              max_nodes: source.wire.max_nodes,
              max_depth: source.wire.max_depth,
              max_text_bytes: source.max_batch_bytes,
            },
            materialize_parameters=false,
          )
          .map(_ => ())
          .map_err(issue => Compute(issue))
        },
      ) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    return finish()
  }
  let max_rows = @execution.producer_read_row_count(input).to_int64()
  let identity_reused = match
    @duckdb_driver.resident_input_scan_reuse(binding.inputs, port, input) {
    Some(evidence) =>
      @duckdb_compute.reuse_duckdb_compute_input_identity(
        attempt, port, evidence,
      )
    None => false
  }
  let demand_column = @duckdb_compute.duckdb_compute_input_demand_column(
    attempt, port,
  )
  let demand_sql = match (demand_column, read) {
    (Some(column), Some(read)) =>
      match
        @duckdb_compute.duckdb_resident_demand_scan_sql(
          read,
          column,
          binding.max_sql_bytes,
        ) {
        Ok(sql) => Some(sql)
        Err(_) => None
      }
    _ => None
  }
  if identity_reused &&
    (demand_column is None || demand_sql is Some(_)) &&
    @duckdb_compute.reuse_duckdb_compute_input_values(attempt, port) {
    // Canonical per-value facts of the same reused generation discharge the
    // demand exactly; limits that need a failure position keep the scan.
    if demand_sql is Some(sql) &&
      !@duckdb_compute.reuse_duckdb_compute_input_demand(attempt, port) {
      match
        run_native_resident_query(
          runtime.database,
          sql,
          runtime.transport,
          max_rows,
          fields => {
            @duckdb_compute.prepare_duckdb_compute_input_demand_physical(
              attempt, port, fields,
            )
          },
          (physical, rows, columns) => {
            @duckdb_compute.verify_duckdb_compute_input_demand_chunk(
              attempt, port, physical, rows, columns,
            )
          },
        ) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
    }
    return finish()
  }
  match
    run_native_resident_query(
      runtime.database,
      scan_sql,
      runtime.transport,
      max_rows,
      fields => {
        @duckdb_compute.prepare_duckdb_compute_input_physical(
          attempt, port, fields,
        )
      },
      (physical, rows, columns) => {
        @duckdb_compute.verify_duckdb_compute_input_chunk(
          attempt, port, physical, rows, columns,
        )
      },
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  finish()
}

///|
/// One resident task transaction: verify borrowed inputs, map them through
/// connection-local views, materialize the result table, stream it through
/// the same receiver into the independent holding, drop the views and retire
/// last-use inputs, then commit. Only after the commit is the task settled,
/// the resident output confirmed and the common completion crossed. The
/// shared database stays open for later tasks.
fn execute_native_resident_transaction(
  runtime : NativeStrategyComputeRuntime,
  binding : NativeResidentTaskBinding,
  retained : NativeComputeRetainedOutput?,
  retained_source : ((@execution.ProducerRead) -> NativeComputeRetainedInput?)?,
) -> Result[@execution.CompletedOutput, NativeStrategyComputeFailure] {
  let database = runtime.database
  let attempt = @duckdb_driver.captured_duckdb_attempt(runtime.task)
  if binding.environment.database_closed {
    let settlement = dispose_native_strategy_task(runtime)
    return Err({ primary: Physical(RuntimeState), rollback: None, settlement, })
  }
  runtime.physical_active = true
  match database.begin_transaction() {
    Err(issue) => {
      // No transaction was opened on the shared connection.
      runtime.physical_active = false
      let settlement = dispose_native_strategy_task(runtime)
      return Err({
        primary: Physical(Runtime(issue)),
        rollback: None,
        settlement,
      })
    }
    Ok(_) => ()
  }
  let mut failure : NativeComputeExecutionIssue? = None
  let plan = @duckdb_compute.duckdb_compute_attempt_plan(attempt)
  for port in 0..<@duckdb.fixed_compute_import_count(plan) {
    if failure is None {
      match
        verify_native_resident_input(
          runtime, binding, attempt, port, retained_source,
        ) {
        Ok(_) => ()
        Err(issue) => failure = Some(issue)
      }
    }
  }
  let view_drops : Array[String] = []
  for read in @duckdb_driver.resident_inputs_read_plans(binding.inputs) {
    if failure is None {
      match
        @duckdb_compute.duckdb_resident_read_drop_sql(
          read,
          binding.max_sql_bytes,
        ) {
        Err(issue) => failure = Some(Query(issue))
        Ok(drop) =>
          match
            run_native_compute_command(
              database,
              @duckdb_compute.duckdb_resident_read_sql(read),
              [],
              NATIVE_RESIDENT_COMMAND_BYTES,
            ) {
            Ok(_) => view_drops.push(drop)
            Err(issue) => failure = Some(issue)
          }
      }
    }
  }
  if failure is None {
    match @duckdb_driver.captured_duckdb_query(runtime.graph, runtime.task) {
      None => failure = Some(RuntimeState)
      Some(query) => {
        let fixed = @duckdb.fixed_compute_query(plan)
        let parameters : Array[@duckdb.PhysicalParameter] = []
        for index in 0..<@duckdb.fixed_query_parameter_count(fixed) {
          match @duckdb.resident_query_parameter(query, index) {
            Some(parameter) => parameters.push(parameter)
            None => failure = Some(ParameterCount)
          }
        }
        if failure is None {
          match
            run_native_compute_command(
              database,
              @duckdb.resident_query_create_sql(query),
              parameters,
              NATIVE_RESIDENT_COMMAND_BYTES,
            ) {
            Ok(_) => ()
            Err(issue) => failure = Some(issue)
          }
        }
        if failure is None {
          match
            execute_native_compute_query(
              attempt,
              database,
              runtime.transport,
              runtime.compute_limits,
              retained?,
              resident_read=@duckdb.resident_query_read_sql(query),
            ) {
            Ok(output) => runtime.retained_output = output
            Err(issue) => failure = Some(issue)
          }
        }
      }
    }
  }
  // Views are connection-local and would otherwise outlive this task on the
  // shared connection. Remove them inside the same transaction.
  for drop in view_drops {
    if failure is None {
      match
        run_native_compute_command(
          database,
          drop,
          [],
          NATIVE_RESIDENT_COMMAND_BYTES,
        ) {
        Ok(_) => ()
        Err(issue) => failure = Some(issue)
      }
    }
  }
  if failure is None {
    match
      @duckdb_driver.captured_duckdb_cleanup_sql(runtime.graph, runtime.task) {
      Err(_) => failure = Some(RuntimeState)
      Ok(statements) =>
        for statement in statements {
          if failure is None {
            match
              run_native_compute_command(
                database,
                statement,
                [],
                NATIVE_RESIDENT_COMMAND_BYTES,
              ) {
              Ok(_) => ()
              Err(issue) => failure = Some(issue)
            }
          }
        }
    }
  }
  // The real rollback always runs; the whitebox seam only withholds its
  // confirmation so an unconfirmed stop can be exercised.
  let rollback_task = fn() {
    let observed = match database.rollback_transaction() {
      Ok(_) => None
      Err(issue) => Some(issue)
    }
    match (observed, binding.fault) {
      (None, Some(_)) =>
        Some(@native_duckdb.Query("injected rollback failure (test seam)"))
      _ => observed
    }
  }
  // A confirmed rollback ends this task's transaction, views and tables.
  // Otherwise the task keeps its reservation, the database is not reused, and
  // only its destruction at Run release confirms the stop.
  let end_failed = fn(
    primary : NativeStrategyComputeIssue,
    rollback : @native_duckdb.NativeDuckDBIssue?,
  ) {
    runtime.physical_active = rollback is Some(_)
    if rollback is Some(_) {
      binding.environment.unconfirmed = true
    }
    let settlement = dispose_native_strategy_task(runtime)
    Err({ primary, rollback, settlement, })
  }
  if failure is Some(primary) {
    return end_failed(Physical(primary), rollback_task())
  }
  let committed = match binding.fault {
    Some(CommitAndRollback) =>
      Err(@native_duckdb.Query("injected commit failure (test seam)"))
    _ => database.commit_transaction()
  }
  match committed {
    Err(issue) => return end_failed(Physical(Runtime(issue)), rollback_task())
    Ok(_) => ()
  }
  // Task completion is separate from the database lifetime: the committed
  // transaction ended this task's native work while the environment stays open.
  runtime.physical_active = false
  runtime.authority.settled = Some(attempt)
  let execution = @duckdb_driver.captured_duckdb_execution(runtime.task)
  match @strategy.settle_task_execution(runtime.graph, execution, true) {
    Err(issue) => {
      let settlement = dispose_native_strategy_task(runtime)
      return Err({ primary: Settlement(issue), rollback: None, settlement, })
    }
    Ok(_) => ()
  }
  match @strategy.confirm_captured_resident_output(runtime.graph, execution) {
    Err(issue) => {
      let settlement = dispose_native_strategy_task(runtime)
      return Err({ primary: Strategy(issue), rollback: None, settlement, })
    }
    Ok(_) => ()
  }
  match
    @duckdb_driver.complete_captured_duckdb_task(runtime.graph, runtime.task) {
    Err(issue) => {
      let settlement = dispose_native_strategy_task(runtime)
      return Err({ primary: Strategy(issue), rollback: None, settlement, })
    }
    Ok(_) => ()
  }
  let target = @duckdb.fixed_query_target(@duckdb.fixed_compute_query(plan))
  guard @strategy.captured_task_output(
      runtime.graph,
      runtime.task_index,
      target,
    )
    is Some(output) else {
    let settlement = dispose_native_strategy_task(runtime)
    return Err({ primary: MissingOutput, rollback: None, settlement, })
  }
  runtime.output = Some(output)
  Ok(output)
}

///|
/// Import one completed producer into the environment as a committed,
/// immutable resident table. Its exact storage is the admitted producer
/// output; a retained holding is re-read through a fresh verified reader and
/// the portable import stream before commit. Common transfer settlement is
/// confirmed only by the native transaction end.
fn import_native_resident_table(
  graph : @strategy.CapturedDAG,
  env : NativeResidentEnvironment,
  producer : Int,
  table_bytes : Int64,
  entries : Int,
  names : Int,
  limits : NativeComputeImportLimits,
  transfer_bytes : Int64,
  frame_bytes : Int,
  resolve : (@execution.ProducerStorage) -> NativeComputeRetainedInput?,
) -> Result[Unit, NativeStrategyComputeRunIssue] {
  guard env.database is Some(database) && !env.database_closed else {
    return Err(Start(Physical(RuntimeState)))
  }
  let handle = match
    @duckdb_driver.prepare_resident_table(
      graph,
      env.store,
      producer,
      table_bytes,
      entries,
      names,
      limits.max_sql_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Start(Strategy(issue)))
  }
  let cancel = fn(issue : NativeStrategyComputeIssue) {
    match @strategy.cancel_resident_table_preparation(graph, handle) {
      Ok(_) => Err(Start(issue))
      Err(ledger) => Err(Start(Settlement(ledger)))
    }
  }
  guard @duckdb_driver.bind_resident_table(env.store, handle) is Some(table) &&
    @duckdb_driver.resident_table_import(table) is Some(imported) else {
    return cancel(Physical(RuntimeState))
  }
  let rows = @duckdb.resident_import_row_count(imported)
  let columns = @duckdb.resident_import_column_count(imported)
  if rows < 0 || rows > limits.max_rows {
    return cancel(Physical(ImportRows))
  }
  if columns < 1 || columns > limits.max_parameters {
    return cancel(Physical(ImportColumns))
  }
  if rows > limits.max_cells / columns {
    return cancel(Physical(ImportCells))
  }
  // Only lookups happen before the reservation: the exact holding and its
  // frame bound, which sizes the allowance.
  let storage = @duckdb.resident_import_storage(imported)
  let source = match @execution.producer_storage_retained_material(storage) {
    None => None
    Some(_) =>
      match resolve(storage) {
        Some(source) if source.max_batch_bytes > 0 &&
          source.max_batch_bytes <= source.wire.max_bytes &&
          source.max_batch_bytes <= frame_bytes => Some(source)
        Some(_) => return cancel(Physical(InvalidLimits))
        None => return cancel(Physical(RuntimeState))
      }
  }
  let scratch = match
    native_resident_import_scratch_bytes(
      limits,
      rows,
      columns,
      source.map(value => value.max_batch_bytes).unwrap_or(frame_bytes),
      source is Some(_),
    ) {
    Some(value) => value
    None => return cancel(Physical(InvalidLimits))
  }
  env.import_scratch_bytes = scratch
  let transfer = match
    @strategy.begin_resident_transfer(graph, handle, transfer_bytes, scratch) {
    Ok(value) => value
    Err(issue) => return cancel(Strategy(issue))
  }
  let reader_open = Ref(false)
  let fail = fn(
    primary : NativeComputeExecutionIssue,
    rollback : @native_duckdb.NativeDuckDBIssue?,
    started : Bool,
  ) {
    @strategy.abort_resident_transfer(graph, transfer) |> ignore
    let confirmed = !started || (rollback is None && !reader_open.val)
    if !confirmed {
      env.unconfirmed = true
    }
    let settlement = match
      @strategy.settle_resident_transfer(graph, transfer, confirmed) {
      Ok(_) => None
      Err(issue) => Some(issue)
    }
    if !confirmed || settlement is Some(_) {
      env.unsettled_transfers.push(transfer)
    }
    Err(Execution({ primary: Physical(primary), rollback, settlement, }))
  }
  // Statements are compiled only under the admitted reservation.
  let (batch_rows, batch_sql) = if rows == 0 {
    (0, "")
  } else {
    match
      @duckdb.resident_import_batch_insert_sql(
        imported,
        Int::min(
          rows,
          Int::min(limits.max_batch_rows, limits.max_parameters / columns),
        ),
        limits.max_parameters,
        limits.max_sql_bytes,
      ) {
      Ok(value) => value
      Err(issue) => return fail(Query(issue), None, false)
    }
  }
  let tail_rows = if batch_rows == 0 { 0 } else { rows % batch_rows }
  let tail_sql = if tail_rows == 0 {
    ""
  } else {
    match
      @duckdb.resident_import_batch_insert_sql(
        imported,
        tail_rows,
        limits.max_parameters,
        limits.max_sql_bytes,
      ) {
      Ok((actual, sql)) if actual == tail_rows => sql
      Ok(_) => return fail(RuntimeState, None, false)
      Err(issue) => return fail(Query(issue), None, false)
    }
  }
  match database.begin_transaction() {
    Err(issue) => return fail(Runtime(issue), None, false)
    Ok(_) => ()
  }
  let mut failure : NativeComputeExecutionIssue? = None
  match
    run_native_compute_command(
      database,
      @duckdb.resident_import_create_sql(imported),
      [],
      NATIVE_RESIDENT_COMMAND_BYTES,
    ) {
    Ok(_) => ()
    Err(issue) => failure = Some(issue)
  }
  let mut parameters : Array[@duckdb.PhysicalParameter] = []
  let mut pending_rows = 0
  let append = fn(
    values : Array[@duckdb.PhysicalParameter],
  ) -> Result[Unit, NativeComputeExecutionIssue] {
    if values.length() != columns {
      return Err(ParameterCount)
    }
    for value in values {
      parameters.push(value)
    }
    pending_rows += 1
    if pending_rows == batch_rows {
      match
        run_native_compute_command(
          database,
          batch_sql,
          parameters,
          NATIVE_RESIDENT_COMMAND_BYTES,
        ) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
      parameters = []
      pending_rows = 0
    }
    Ok(())
  }
  if failure is None {
    match source {
      None =>
        for row in 0..<rows {
          if failure is None {
            let values = []
            for column in 0..<columns {
              match @duckdb.resident_import_parameter(imported, row, column) {
                Ok(value) => values.push(value)
                Err(issue) =>
                  if failure is None {
                    failure = Some(Query(Parameter(issue)))
                  }
              }
            }
            if failure is None {
              match append(values) {
                Ok(_) => ()
                Err(issue) => failure = Some(issue)
              }
            }
          }
        }
      Some(source) =>
        if source.max_batch_bytes > source.wire.max_bytes ||
          source.max_batch_bytes > frame_bytes {
          failure = Some(InvalidLimits)
        } else {
          match
            @duckdb.prepare_resident_import_stream(
              imported,
              rows,
              {
                max_nodes: source.wire.max_nodes,
                max_text_bytes: source.wire.max_bytes,
                max_depth: source.wire.max_depth,
                max_work: source.wire.max_order_work,
              },
              source.wire,
              source.max_batch_bytes,
            ) {
            Err(issue) => failure = Some(ResidentImport(issue))
            Ok(stream) => {
              let read = read_native_retained_rows(
                source,
                rows,
                reader_open,
                bytes => {
                  @strategy.charge_resident_transfer(
                    graph,
                    transfer,
                    bytes.to_int64(),
                  ).map_err(_ => RuntimeState)
                },
                row => {
                  match
                    @duckdb.append_resident_import_stream(stream, row, {
                      max_bytes: source.max_batch_bytes,
                      max_nodes: Int::min(
                        source.wire.max_nodes,
                        source.max_batch_bytes,
                      ),
                      max_depth: Int::min(64, source.wire.max_depth),
                      max_text_bytes: source.max_batch_bytes,
                    }) {
                    Ok(values) => append(values)
                    Err(issue) => Err(ResidentImport(issue))
                  }
                },
              )
              match read {
                Err(issue) => {
                  @duckdb.cancel_resident_import_stream(stream) |> ignore
                  failure = Some(issue)
                }
                Ok(_) =>
                  match @duckdb.finish_resident_import_stream(stream) {
                    Ok(_) => ()
                    Err(issue) => failure = Some(ResidentImport(issue))
                  }
              }
            }
          }
        }
    }
  }
  if failure is None && pending_rows > 0 {
    match
      run_native_compute_command(
        database,
        tail_sql,
        parameters,
        NATIVE_RESIDENT_COMMAND_BYTES,
      ) {
      Ok(_) => ()
      Err(issue) => failure = Some(issue)
    }
  }
  if failure is Some(primary) {
    let rollback = match database.rollback_transaction() {
      Ok(_) => None
      Err(issue) => Some(issue)
    }
    return fail(primary, rollback, true)
  }
  match database.commit_transaction() {
    Err(issue) => {
      let rollback = match database.rollback_transaction() {
        Ok(_) => None
        Err(cleanup) => Some(cleanup)
      }
      return fail(Runtime(issue), rollback, true)
    }
    Ok(_) => ()
  }
  match @strategy.settle_resident_transfer(graph, transfer, true) {
    Err(issue) => {
      env.unsettled_transfers.push(transfer)
      return Err(
        Execution({
          primary: Settlement(issue),
          rollback: None,
          settlement: Some(issue),
        }),
      )
    }
    Ok(_) => ()
  }
  match @strategy.complete_resident_transfer(graph, transfer) {
    Err(issue) => return Err(Start(Strategy(issue)))
    Ok(_) => ()
  }
  env.imports += 1
  env.imported_rows += rows
  Ok(())
}
