///|
/// Native-only import bounds. Logical guards, output admission and completion
/// remain owned by the portable DuckDB Compute attempt.
pub(all) struct NativeComputeImportLimits {
  max_rows : Int
  max_cells : Int
  max_parameters : Int
  max_sql_bytes : Int
  max_batch_rows : Int
}

///|
/// Physical failures observed while executing one portable Compute attempt.
pub(all) enum NativeComputeExecutionIssue {
  RuntimeState
  InvalidLimits
  ImportCount
  ImportRows
  ImportColumns
  ImportCells
  ParameterCount
  Runtime(@native_duckdb.NativeDuckDBIssue)
  Parameter(NativeParameterBindingIssue)
  Query(@duckdb.NativeQueryIssue)
  Fields(@duckdb.PhysicalFieldsIssue)
  Columns(@duckdb.TransportColumnIssue)
  Compute(@duckdb_compute.DuckDBComputeIssue)
}

///|
/// Rollback is an independently observed cleanup fact. Its failure never
/// replaces the primary failure or proves that native access stopped.
pub(all) struct NativeComputeFailure {
  primary : NativeComputeExecutionIssue
  rollback : @native_duckdb.NativeDuckDBIssue?
}

///|
priv struct NativeComputeImportPlan {
  imported : @duckdb.FixedImport
  rows : Int
  columns : Int
  batch_rows : Int
  batch_sql : String
  tail_rows : Int
  tail_sql : String
}

///|
priv struct NativeComputeRuntimeAuthority {
  mut settled : @duckdb_compute.DuckDBComputeAttempt?
  mut live : Bool
}

///|
/// One native database and one portable Compute attempt. The environment owns
/// transaction and query resources; only the portable attempt may admit and
/// complete the logical output.
struct NativeComputeRuntime {
  attempt : @duckdb_compute.DuckDBComputeAttempt
  database : @native_duckdb.Database
  transport : @duckdb.TransportColumnLimits
  compute_limits : @duckdb_compute.DuckDBComputeLimits
  imports : Array[NativeComputeImportPlan]
  authority : NativeComputeRuntimeAuthority
  mut output : @execution.CompletedOutput?
  mut started : Bool
  mut database_closed : Bool
  mut closed : Bool
}

///|
fn native_compute_import_plans(
  compute : @duckdb.FixedCompute,
  transport : @duckdb.TransportColumnLimits,
  limits : NativeComputeImportLimits,
) -> Result[Array[NativeComputeImportPlan], NativeComputeExecutionIssue] {
  if limits.max_rows < 0 ||
    limits.max_cells < 0 ||
    limits.max_parameters < 1 ||
    limits.max_sql_bytes < 0 ||
    limits.max_batch_rows < 1 ||
    transport.max_columns < 1 ||
    transport.max_rows < 1 ||
    transport.max_bytes < 1 ||
    transport.max_nodes < 0 ||
    transport.max_text_bytes < 0 {
    return Err(InvalidLimits)
  }
  let count = @duckdb.fixed_compute_import_count(compute)
  if count < 1 || count > 2 {
    return Err(ImportCount)
  }
  let plans = []
  let mut cells = 0
  for port in 0..<count {
    guard @duckdb.fixed_compute_import(compute, port) is Some(imported) else {
      return Err(ImportCount)
    }
    let rows = @execution.producer_read_row_count(
      @duckdb.fixed_import_input(imported),
    )
    let columns = @duckdb.fixed_import_column_count(imported)
    if rows < 0 || rows > limits.max_rows {
      return Err(ImportRows)
    }
    if columns < 1 ||
      columns > limits.max_parameters ||
      columns > transport.max_columns {
      return Err(ImportColumns)
    }
    if cells > limits.max_cells || rows > (limits.max_cells - cells) / columns {
      return Err(ImportCells)
    }
    cells += rows * columns
    if rows == 0 {
      plans.push({
        imported,
        rows,
        columns,
        batch_rows: 0,
        batch_sql: "",
        tail_rows: 0,
        tail_sql: "",
      })
      continue
    }
    let requested = Int::min(
      rows,
      Int::min(limits.max_batch_rows, limits.max_parameters / columns),
    )
    let (batch_rows, batch_sql) = match
      @duckdb.fixed_import_batch_insert_sql(
        imported,
        requested,
        limits.max_parameters,
        limits.max_sql_bytes,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Query(issue))
    }
    let tail_rows = rows % batch_rows
    let tail_sql = if tail_rows == 0 {
      ""
    } else {
      match
        @duckdb.fixed_import_batch_insert_sql(
          imported,
          tail_rows,
          limits.max_parameters,
          limits.max_sql_bytes,
        ) {
        Ok((actual, sql)) if actual == tail_rows => sql
        Ok(_) => return Err(RuntimeState)
        Err(issue) => return Err(Query(issue))
      }
    }
    plans.push({
      imported,
      rows,
      columns,
      batch_rows,
      batch_sql,
      tail_rows,
      tail_sql,
    })
  }
  Ok(plans)
}

///|
fn run_native_compute_command(
  database : @native_duckdb.Database,
  sql : String,
  parameters : Array[@duckdb.PhysicalParameter],
  max_bytes : Int,
) -> Result[Unit, NativeComputeExecutionIssue] {
  let query = match database.prepare_stream_query(sql, 1, 1L, 1, max_bytes) {
    Ok(value) => value
    Err(issue) => return Err(Runtime(issue))
  }
  if query.parameter_count() != parameters.length() {
    query.close() |> ignore
    return Err(ParameterCount)
  }
  for index, parameter in parameters {
    match bind_native_parameter(query, index, parameter) {
      Ok(_) => ()
      Err(issue) => {
        query.close() |> ignore
        return Err(Parameter(issue))
      }
    }
  }
  match query.execute() {
    Ok(_) => ()
    Err(issue) => {
      query.close() |> ignore
      return Err(Runtime(issue))
    }
  }
  let mut finished = false
  while !finished {
    match query.next() {
      Ok(Some(_)) => ()
      Ok(None) => finished = true
      Err(issue) => {
        query.close() |> ignore
        return Err(Runtime(issue))
      }
    }
  }
  if !query.close() {
    return Err(RuntimeState)
  }
  Ok(())
}

///|
fn execute_native_compute_import(
  database : @native_duckdb.Database,
  plan : NativeComputeImportPlan,
  max_bytes : Int,
) -> Result[Unit, NativeComputeExecutionIssue] {
  match
    run_native_compute_command(
      database,
      @duckdb.fixed_import_create_sql(plan.imported),
      [],
      max_bytes,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let mut row = 0
  while row < plan.rows {
    let remaining = plan.rows - row
    let batch_rows = if remaining < plan.batch_rows {
      plan.tail_rows
    } else {
      plan.batch_rows
    }
    if batch_rows < 1 {
      return Err(RuntimeState)
    }
    let sql = if batch_rows == plan.batch_rows {
      plan.batch_sql
    } else {
      plan.tail_sql
    }
    let parameters = []
    for offset in 0..<batch_rows {
      for column in 0..<plan.columns {
        match
          @duckdb.fixed_import_parameter(plan.imported, row + offset, column) {
          Ok(parameter) => parameters.push(parameter)
          Err(issue) => return Err(Query(Parameter(issue)))
        }
      }
    }
    match run_native_compute_command(database, sql, parameters, max_bytes) {
      Ok(_) => row += batch_rows
      Err(issue) => return Err(issue)
    }
  }
  Ok(())
}

///|
fn execute_native_compute_query(
  attempt : @duckdb_compute.DuckDBComputeAttempt,
  database : @native_duckdb.Database,
  transport : @duckdb.TransportColumnLimits,
  compute_limits : @duckdb_compute.DuckDBComputeLimits,
) -> Result[Unit, NativeComputeExecutionIssue] {
  let compute = @duckdb_compute.duckdb_compute_attempt_plan(attempt)
  if !@duckdb_compute.duckdb_compute_inputs_ready(attempt) {
    return Err(RuntimeState)
  }
  let fixed = @duckdb.fixed_compute_query(compute)
  let query = match
    database.prepare_stream_query(
      @duckdb.fixed_query_sql(fixed),
      transport.max_columns,
      compute_limits.physical.max_rows.to_int64(),
      transport.max_rows,
      transport.max_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Runtime(issue))
  }
  let parameter_count = @duckdb.fixed_query_parameter_count(fixed)
  if query.parameter_count() != parameter_count {
    query.close() |> ignore
    return Err(ParameterCount)
  }
  for index in 0..<parameter_count {
    guard @duckdb.fixed_query_parameter(fixed, index) is Some(parameter) else {
      query.close() |> ignore
      return Err(ParameterCount)
    }
    match bind_native_parameter(query, index, parameter) {
      Ok(_) => ()
      Err(issue) => {
        query.close() |> ignore
        return Err(Parameter(issue))
      }
    }
  }
  match query.execute() {
    Ok(_) => ()
    Err(issue) => {
      query.close() |> ignore
      return Err(Runtime(issue))
    }
  }
  let fields = match query.fields_json() {
    Ok(text) =>
      match @duckdb.decode_physical_fields(text, transport) {
        Ok(value) => value
        Err(issue) => {
          query.close() |> ignore
          return Err(Fields(issue))
        }
      }
    Err(issue) => {
      query.close() |> ignore
      return Err(Runtime(issue))
    }
  }
  match @duckdb_compute.begin_duckdb_compute_result(attempt, fields) {
    Ok(_) => ()
    Err(issue) => {
      query.close() |> ignore
      return Err(Compute(issue))
    }
  }
  let mut finished = false
  while !finished {
    match query.next() {
      Ok(Some(chunk)) => {
        let columns = match
          @duckdb.decode_transport_columns(chunk.columns_json, transport) {
          Ok(value) => value
          Err(issue) => {
            query.close() |> ignore
            return Err(Columns(issue))
          }
        }
        match
          @duckdb_compute.receive_duckdb_compute_chunk(
            attempt,
            chunk.row_count,
            columns,
          ) {
          Ok(_) => ()
          Err(issue) => {
            query.close() |> ignore
            return Err(Compute(issue))
          }
        }
      }
      Ok(None) => finished = true
      Err(issue) => {
        query.close() |> ignore
        return Err(Runtime(issue))
      }
    }
  }
  if !query.close() {
    return Err(RuntimeState)
  }
  @duckdb_compute.finish_duckdb_compute_result(attempt).map_err(issue => {
    Compute(issue)
  })
}

///|
/// Prepare one native fixed Compute without opening a second policy path. All
/// import shapes and SQL batches are bounded before the transaction starts.
pub fn start_native_compute_runtime(
  setup : @duckdb_driver.ComputeHostConfiguration,
  database : @native_duckdb.Database,
  import_limits : NativeComputeImportLimits,
) -> Result[NativeComputeRuntime, NativeComputeExecutionIssue] {
  let authority : NativeComputeRuntimeAuthority = { settled: None, live: true, }
  let attempt = match
    @duckdb_driver.start_configured_compute_host(setup, current => {
      authority.live &&
      authority.settled is Some(settled) &&
      physical_equal(settled, current)
    }) {
    Ok(value) => value
    Err(issue) => {
      database.close()
      return Err(Compute(issue))
    }
  }
  let transport = @duckdb_driver.configured_compute_transport(setup)
  let imports = match
    native_compute_import_plans(
      @duckdb_compute.duckdb_compute_attempt_plan(attempt),
      transport,
      import_limits,
    ) {
    Ok(value) => value
    Err(issue) => {
      @duckdb_compute.abort_duckdb_compute_attempt(attempt)
      authority.live = false
      database.close()
      return Err(issue)
    }
  }
  Ok({
    attempt,
    database,
    transport,
    compute_limits: @duckdb_driver.configured_compute_limits(setup),
    imports,
    authority,
    output: None,
    started: false,
    database_closed: false,
    closed: false,
  })
}

///|
/// Execute, settle and complete one fixed Compute. Transaction commit is a
/// physical settlement fact; it becomes common completion only through the
/// exact portable verifier installed at start.
pub fn execute_native_compute_runtime(
  runtime : NativeComputeRuntime,
) -> Result[@execution.CompletedOutput, NativeComputeFailure] {
  if runtime.closed || runtime.started {
    return Err({ primary: RuntimeState, rollback: None, })
  }
  runtime.started = true
  match runtime.database.begin_transaction() {
    Err(issue) => {
      runtime.database.close()
      runtime.database_closed = true
      return Err({ primary: Runtime(issue), rollback: None, })
    }
    Ok(_) => ()
  }
  let mut failure : NativeComputeExecutionIssue? = None
  for plan in runtime.imports {
    if failure is None {
      match
        execute_native_compute_import(
          runtime.database,
          plan,
          runtime.transport.max_bytes,
        ) {
        Ok(_) => ()
        Err(issue) => failure = Some(issue)
      }
    }
  }
  if failure is None {
    match
      execute_native_compute_query(
        runtime.attempt,
        runtime.database,
        runtime.transport,
        runtime.compute_limits,
      ) {
      Ok(_) => ()
      Err(issue) => failure = Some(issue)
    }
  }
  if failure is Some(primary) {
    let rollback = match runtime.database.rollback_transaction() {
      Ok(_) => None
      Err(issue) => Some(issue)
    }
    @duckdb_compute.abort_duckdb_compute_attempt(runtime.attempt)
    runtime.database.close()
    runtime.database_closed = true
    return Err({ primary, rollback, })
  }
  match runtime.database.commit_transaction() {
    Err(issue) => {
      let rollback = match runtime.database.rollback_transaction() {
        Ok(_) => None
        Err(cleanup) => Some(cleanup)
      }
      @duckdb_compute.abort_duckdb_compute_attempt(runtime.attempt)
      runtime.database.close()
      runtime.database_closed = true
      return Err({ primary: Runtime(issue), rollback, })
    }
    Ok(_) => ()
  }
  runtime.database.close()
  runtime.database_closed = true
  runtime.authority.settled = Some(runtime.attempt)
  match @duckdb_compute.complete_duckdb_compute_attempt(runtime.attempt) {
    Ok(output) => {
      runtime.output = Some(output)
      Ok(output)
    }
    Err(issue) => {
      @duckdb_compute.abort_duckdb_compute_attempt(runtime.attempt)
      Err({ primary: Compute(issue), rollback: None, })
    }
  }
}

///|
pub fn native_compute_runtime_output(
  runtime : NativeComputeRuntime,
) -> Result[@execution.CompletedOutput, NativeComputeExecutionIssue] {
  if runtime.closed {
    return Err(RuntimeState)
  }
  match runtime.output {
    Some(output) => Ok(output)
    None => Err(RuntimeState)
  }
}

///|
pub fn close_native_compute_runtime(runtime : NativeComputeRuntime) -> Unit {
  if runtime.closed {
    return
  }
  runtime.closed = true
  runtime.authority.live = false
  @duckdb_compute.close_duckdb_compute_attempt(runtime.attempt)
  if !runtime.database_closed {
    runtime.database.close()
    runtime.database_closed = true
  }
}
