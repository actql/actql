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
  RetainedFile(@retained_file.NativeRetainedTaskFileIssue)
  RowFrames(@publication.DurableResultRowFrameIssue)
  RetainedImport(@execution.CompletedImportIssue)
  ResidentImport(@duckdb.FixedImportStreamIssue)
}

///|
/// Selected native output holding. The file owner is created only after the
/// common task has admitted the exact attempt and its byte reservation.
priv struct NativeComputeRetainedOutput {
  file : @retained_file.NativeRetainedTaskFile
  wire : @execution.RowWireLimits
  max_batch_bytes : Int
  max_chunk_rows : Int
}

///|
/// Exact retained producer selected from a prior task in the same Run. No
/// pathname or caller-supplied CID is accepted by the consumer import.
struct NativeComputeRetainedInput {
  file : @retained_file.NativeRetainedTaskFile
  wire : @execution.RowWireLimits
  max_batch_bytes : Int
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
  port : Int
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
        port,
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
      port,
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
  attempt? : @duckdb_compute.DuckDBComputeAttempt,
  retained_source? : (@execution.ProducerRead) -> NativeComputeRetainedInput?,
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
  let input = @duckdb.fixed_import_input(plan.imported)
  if @execution.producer_read_retained_material(input) is Some(_) {
    guard attempt is Some(owner) &&
      retained_source is Some(resolve) &&
      resolve(input) is Some(source) else {
      return Err(RuntimeState)
    }
    return execute_native_compute_retained_import(
      database, owner, plan, source, max_bytes,
    )
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
/// Frame each row of one exact retained holding through a fresh bounded
/// reader. The reader verifies physical bytes before success; every decoded
/// row stays provisional until the caller's portable verifier finishes.
/// `reader_open` remains true only when a failed reader close left the
/// descriptor with the producer holding's cleanup owner.
fn read_native_retained_rows(
  source : NativeComputeRetainedInput,
  expected_rows : Int,
  reader_open : Ref[Bool],
  on_bytes : (Int) -> Result[Unit, NativeComputeExecutionIssue],
  on_row : (String) -> Result[Unit, NativeComputeExecutionIssue],
) -> Result[Unit, NativeComputeExecutionIssue] {
  if source.max_batch_bytes <= 0 ||
    source.file.stored_bytes() is None ||
    source.max_batch_bytes > source.wire.max_bytes {
    return Err(RuntimeState)
  }
  let frame_bytes = Int::min(65536, source.max_batch_bytes)
  let frames = match
    @publication.prepare_durable_result_row_frames(
      source.wire.max_bytes,
      expected_rows,
      Int::min(16777216, source.max_batch_bytes),
      source.wire.max_depth,
      frame_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(RowFrames(issue))
  }
  let reader = match source.file.open_reader() {
    Ok(value) => value
    Err(issue) => return Err(RetainedFile(issue))
  }
  reader_open.val = true
  let fail = fn(issue : NativeComputeExecutionIssue) {
    if reader.close() is Ok(_) {
      reader_open.val = false
    }
    Err(issue)
  }
  let mut rows = 0
  let mut eof = false
  while !eof {
    let chunk = match reader.next(frame_bytes) {
      Ok(value) => value
      Err(issue) => return fail(RetainedFile(issue))
    }
    match on_bytes(chunk.bytes.length()) {
      Ok(_) => ()
      Err(issue) => return fail(issue)
    }
    let decoded = match
      @publication.feed_durable_result_row_frames(frames, chunk.bytes) {
      Ok(value) => value
      Err(issue) => return fail(RowFrames(issue))
    }
    for row in decoded {
      if rows >= expected_rows {
        return fail(ImportRows)
      }
      match on_row(row) {
        Ok(_) => rows += 1
        Err(issue) => return fail(issue)
      }
    }
    eof = chunk.eof
  }
  let summary = match @publication.finish_durable_result_row_frames(frames) {
    Ok(value) => value
    Err(issue) => return fail(RowFrames(issue))
  }
  if summary.rows != expected_rows || rows != expected_rows {
    return fail(ImportRows)
  }
  match reader.finish() {
    Ok(_) => ()
    Err(issue) => return fail(RetainedFile(issue))
  }
  reader_open.val = false
  Ok(())
}

///|
/// A fresh bounded reader verifies physical bytes and the portable input
/// stream verifies exact content, demand, and logical work before query use.
/// Imported rows remain inside the uncommitted native transaction until both
/// verifiers finish.
fn execute_native_compute_retained_import(
  database : @native_duckdb.Database,
  attempt : @duckdb_compute.DuckDBComputeAttempt,
  plan : NativeComputeImportPlan,
  source : NativeComputeRetainedInput,
  max_bytes : Int,
) -> Result[Unit, NativeComputeExecutionIssue] {
  if source.max_batch_bytes <= 0 ||
    source.file.stored_bytes() is None ||
    source.max_batch_bytes > source.wire.max_bytes {
    return Err(RuntimeState)
  }
  match
    @duckdb_compute.begin_duckdb_compute_input_stream(
      attempt,
      plan.port,
      source.wire,
      source.max_batch_bytes,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Compute(issue))
  }
  let mut parameters : Array[@duckdb.PhysicalParameter] = []
  let mut batch_rows = 0
  match
    read_native_retained_rows(source, plan.rows, Ref(false), _ => Ok(()), row => {
      let values = match
        @duckdb_compute.append_duckdb_compute_input_stream(
          attempt,
          plan.port,
          row,
          {
            max_bytes: source.max_batch_bytes,
            max_nodes: source.wire.max_nodes,
            max_depth: source.wire.max_depth,
            max_text_bytes: source.max_batch_bytes,
          },
        ) {
        Ok(value) => value
        Err(issue) => return Err(Compute(issue))
      }
      if values.length() != plan.columns {
        return Err(ParameterCount)
      }
      for value in values {
        parameters.push(value)
      }
      batch_rows += 1
      if batch_rows == plan.batch_rows {
        match
          run_native_compute_command(
            database,
            plan.batch_sql,
            parameters,
            max_bytes,
          ) {
          Ok(_) => ()
          Err(issue) => return Err(issue)
        }
        parameters = []
        batch_rows = 0
      }
      Ok(())
    }) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  if batch_rows > 0 {
    match
      run_native_compute_command(database, plan.tail_sql, parameters, max_bytes) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  @duckdb_compute.finish_duckdb_compute_input_stream(attempt, plan.port).map_err(issue => {
      Compute(issue)
    },
  )
}

///|
/// Bounded publication conversion of this exact retained completion. The
/// original file remains the Run's holding; the returned cell copy carries
/// the same completed occurrence only after full physical and logical checks.
fn convert_native_retained_result_for_publication(
  output : @execution.CompletedOutput,
  source : NativeComputeRetainedInput,
  max_rows : Int,
  values : @execution.ValueLimits,
  wire : @execution.RowWireLimits,
  max_batch_bytes : Int,
) -> Result[@execution.CompletedOutput, NativeComputeExecutionIssue] {
  if source.max_batch_bytes <= 0 ||
    source.max_batch_bytes > source.wire.max_bytes ||
    max_batch_bytes <= 0 {
    return Err(RuntimeState)
  }
  let rows = @execution.completed_row_count(output)
  let conversion = match
    @execution.prepare_completed_output_import(
      output, max_rows, values, wire, max_batch_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(RetainedImport(issue))
  }
  let row_bytes = Int::min(source.max_batch_bytes, max_batch_bytes)
  let frame_bytes = Int::min(65536, row_bytes)
  let frames = match
    @publication.prepare_durable_result_row_frames(
      source.wire.max_bytes,
      rows,
      Int::min(16777216, row_bytes),
      source.wire.max_depth,
      frame_bytes,
    ) {
    Ok(value) => value
    Err(issue) => {
      @execution.cancel_completed_output_import(conversion) |> ignore
      return Err(RowFrames(issue))
    }
  }
  let reader = match source.file.open_reader() {
    Ok(value) => value
    Err(issue) => {
      @execution.cancel_completed_output_import(conversion) |> ignore
      return Err(RetainedFile(issue))
    }
  }
  let mut decoded_rows = 0
  let mut eof = false
  while !eof {
    let chunk = match reader.next(frame_bytes) {
      Ok(value) => value
      Err(issue) => {
        reader.close() |> ignore
        @execution.cancel_completed_output_import(conversion) |> ignore
        return Err(RetainedFile(issue))
      }
    }
    let decoded = match
      @publication.feed_durable_result_row_frames(frames, chunk.bytes) {
      Ok(value) => value
      Err(issue) => {
        reader.close() |> ignore
        @execution.cancel_completed_output_import(conversion) |> ignore
        return Err(RowFrames(issue))
      }
    }
    for row in decoded {
      match
        @execution.append_completed_output_import_wire(conversion, row, {
          max_bytes: row_bytes,
          max_nodes: source.wire.max_nodes,
          max_depth: source.wire.max_depth,
          max_text_bytes: row_bytes,
        }) {
        Ok(_) => decoded_rows += 1
        Err(issue) => {
          reader.close() |> ignore
          @execution.cancel_completed_output_import(conversion) |> ignore
          return Err(RetainedImport(issue))
        }
      }
    }
    eof = chunk.eof
  }
  let summary = match @publication.finish_durable_result_row_frames(frames) {
    Ok(value) => value
    Err(issue) => {
      reader.close() |> ignore
      @execution.cancel_completed_output_import(conversion) |> ignore
      return Err(RowFrames(issue))
    }
  }
  if summary.rows != rows || decoded_rows != rows {
    reader.close() |> ignore
    @execution.cancel_completed_output_import(conversion) |> ignore
    return Err(ImportRows)
  }
  match reader.finish() {
    Ok(_) => ()
    Err(issue) => {
      reader.close() |> ignore
      @execution.cancel_completed_output_import(conversion) |> ignore
      return Err(RetainedFile(issue))
    }
  }
  @execution.finish_completed_output_import(conversion).map_err(issue => {
    RetainedImport(issue)
  })
}

///|
/// `resident_read` replaces the fixed query with the connector-compiled read
/// of the already materialized resident result table. That read carries no
/// parameters; the same receiver, guards and holding admit its rows.
fn execute_native_compute_query(
  attempt : @duckdb_compute.DuckDBComputeAttempt,
  database : @native_duckdb.Database,
  transport : @duckdb.TransportColumnLimits,
  compute_limits : @duckdb_compute.DuckDBComputeLimits,
  retained? : NativeComputeRetainedOutput,
  resident_read? : String,
) -> Result[
  @execution.RetainedOutputHandle[@retained_file.NativeRetainedTaskFile]?,
  NativeComputeExecutionIssue,
] {
  let compute = @duckdb_compute.duckdb_compute_attempt_plan(attempt)
  if !@duckdb_compute.duckdb_compute_inputs_ready(attempt) {
    return Err(RuntimeState)
  }
  let fixed = @duckdb.fixed_compute_query(compute)
  let query = match
    database.prepare_stream_query(
      resident_read.unwrap_or(@duckdb.fixed_query_sql(fixed)),
      transport.max_columns,
      compute_limits.physical.max_rows.to_int64(),
      transport.max_rows,
      transport.max_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Runtime(issue))
  }
  let parameter_count = if resident_read is Some(_) {
    0
  } else {
    @duckdb.fixed_query_parameter_count(fixed)
  }
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
  let begun = match retained {
    Some(output) =>
      @duckdb_compute.begin_duckdb_compute_stream_result(
        attempt,
        fields,
        output.wire,
        output.max_batch_bytes,
        output.max_chunk_rows,
      )
    None => @duckdb_compute.begin_duckdb_compute_result(attempt, fields)
  }
  match begun {
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
        let received = match retained {
          Some(_) =>
            @duckdb_compute.receive_duckdb_compute_stream_chunk(
              attempt,
              chunk.row_count,
              columns,
            )
          None =>
            @duckdb_compute.receive_duckdb_compute_chunk(
              attempt,
              chunk.row_count,
              columns,
            )
        }
        match received {
          Ok(_) => ()
          Err(issue) => {
            query.close() |> ignore
            return Err(Compute(issue))
          }
        }
        if retained is Some(output) {
          while true {
            match @duckdb_compute.drain_duckdb_compute_stream_row(attempt) {
              Ok(Some(batch)) =>
                match output.file.append(batch) {
                  Ok(_) => ()
                  Err(issue) => {
                    query.close() |> ignore
                    return Err(RetainedFile(issue))
                  }
                }
              Ok(None) => break
              Err(issue) => {
                query.close() |> ignore
                return Err(Compute(issue))
              }
            }
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
  match retained {
    None =>
      @duckdb_compute.finish_duckdb_compute_result(attempt)
      .map(_ => None)
      .map_err(issue => Compute(issue))
    Some(output) => {
      let (receipt, tail) = match
        @duckdb_compute.finish_duckdb_compute_stream_result(attempt) {
        Ok(value) => value
        Err(issue) => return Err(Compute(issue))
      }
      match output.file.append(tail) {
        Ok(_) => ()
        Err(issue) => return Err(RetainedFile(issue))
      }
      let (cid, bytes, _, _) = @execution.output_stream_identity(receipt)
      match output.file.seal(cid, bytes) {
        Ok(_) => ()
        Err(issue) => return Err(RetainedFile(issue))
      }
      let handle = @execution.retain_admitted_output_stream(
        receipt,
        output.file,
        fn() { output.file.available() },
      )
      match
        @duckdb_compute.stage_retained_duckdb_compute_material(
          attempt,
          @execution.retained_output_material(handle),
        ) {
        Ok(_) => Ok(Some(handle))
        Err(issue) => Err(Compute(issue))
      }
    }
  }
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
