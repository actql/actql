///|
/// The native acquisition runner uses the same portable Host attempt and
/// Connector admission as the Node Host. Runtime errors report only physical
/// observations and cannot issue completion evidence themselves.
pub(all) enum NativeAcquisitionExecutionIssue {
  RuntimeState
  InvalidLimits
  ParameterCount
  MetadataShape
  Runtime(@native_duckdb.NativeDuckDBIssue)
  Parameter(NativeParameterBindingIssue)
  Fields(@duckdb.PhysicalFieldsIssue)
  Columns(@duckdb.TransportColumnIssue)
  Host(@duckdb_host.NativeHostIssue)
}

///|
/// A failed physical acquisition preserves a rollback observation separately
/// from the primary failure. A failed rollback never becomes proof that source
/// access stopped.
pub(all) struct NativeAcquisitionFailure {
  primary : NativeAcquisitionExecutionIssue
  rollback : @native_duckdb.NativeDuckDBIssue?
}

///|
fn prepare_native_query(
  database : @native_duckdb.Database,
  sql : String,
  parameters : Array[@duckdb.PhysicalParameter],
  limits : @duckdb_host.NativeHostLimits,
  max_rows : Int,
) -> Result[
  (@native_duckdb.Query, Array[(String, @duckdb.PhysicalType)]),
  NativeAcquisitionExecutionIssue,
] {
  if max_rows < 0 ||
    limits.transport.max_columns < 0 ||
    limits.transport.max_rows < 1 ||
    limits.transport.max_bytes < 1 {
    return Err(InvalidLimits)
  }
  let query = match
    database.prepare_stream_query(
      sql,
      limits.transport.max_columns,
      max_rows.to_int64(),
      limits.transport.max_rows,
      limits.transport.max_bytes,
    ) {
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
  let fields = match query.fields_json() {
    Ok(text) =>
      match @duckdb.decode_physical_fields(text, limits.transport) {
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
  Ok((query, fields))
}

///|
fn decode_native_chunk(
  chunk : @native_duckdb.NativeDuckDBChunk,
  limits : @duckdb_host.NativeHostLimits,
) -> Result[Array[@decode.Cursor], NativeAcquisitionExecutionIssue] {
  match @duckdb.decode_transport_columns(chunk.columns_json, limits.transport) {
    Ok(value) => Ok(value)
    Err(issue) => Err(Columns(issue))
  }
}

///|
fn execute_native_metadata(
  run : @duckdb_host.NativeHostRun,
  database : @native_duckdb.Database,
  limits : @duckdb_host.NativeHostLimits,
) -> Result[Unit, NativeAcquisitionExecutionIssue] {
  let scan = @duckdb_host.native_host_scan(run)
  let parameters = []
  for index in 0..<2 {
    guard @duckdb.native_scan_metadata_parameter(scan, index) is Some(parameter) else {
      return Err(ParameterCount)
    }
    parameters.push(parameter)
  }
  let (query, fields) = match
    prepare_native_query(
      database,
      @duckdb.native_scan_metadata_sql(scan),
      parameters,
      limits,
      1,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let outcome = match query.next() {
    Ok(Some(chunk)) => {
      let accepted = match decode_native_chunk(chunk, limits) {
        Ok(columns) =>
          @duckdb_host.native_host_metadata(
            run,
            chunk.row_count,
            fields,
            columns,
          ).map_err(issue => Host(issue))
        Err(issue) => Err(issue)
      }
      match accepted {
        Ok(_) =>
          match query.next() {
            Ok(None) => Ok(())
            _ => Err(MetadataShape)
          }
        Err(issue) => Err(issue)
      }
    }
    Ok(None) => Err(MetadataShape)
    Err(issue) => Err(Runtime(issue))
  }
  query.close() |> ignore
  outcome
}

///|
fn execute_native_receipt(
  run : @duckdb_host.NativeHostRun,
  database : @native_duckdb.Database,
  limits : @duckdb_host.NativeHostLimits,
  role : @duckdb.NativeReceiptRole,
  sql : String,
  parameters : Array[@duckdb.PhysicalParameter],
) -> Result[Unit, NativeAcquisitionExecutionIssue] {
  let (query, fields) = match
    prepare_native_query(
      database,
      sql,
      parameters,
      limits,
      limits.physical.max_rows,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match @duckdb_host.begin_native_host_receipt(run, role, fields) {
    Ok(_) => ()
    Err(issue) => {
      query.close() |> ignore
      return Err(Host(issue))
    }
  }
  let mut finished = false
  while !finished {
    match query.next() {
      Ok(Some(chunk)) => {
        let columns = match decode_native_chunk(chunk, limits) {
          Ok(value) => value
          Err(issue) => {
            query.close() |> ignore
            return Err(issue)
          }
        }
        match
          @duckdb_host.accept_native_host_chunk(run, chunk.row_count, columns) {
          Ok(_) => ()
          Err(issue) => {
            query.close() |> ignore
            return Err(Host(issue))
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
  query.close() |> ignore
  @duckdb_host.finish_native_host_receipt(run).map_err(issue => Host(issue))
}

///|
/// Execute the three physical commands required by one admitted native
/// acquisition and commit through the portable Host's exact issuer. The
/// caller retains the database and Host run for output binding and cleanup.
fn execute_native_acquisition(
  run : @duckdb_host.NativeHostRun,
  database : @native_duckdb.Database,
  limits : @duckdb_host.NativeHostLimits,
  confirm_settlement : () -> Unit,
) -> Result[@duckdb_query.DuckDBNativeObservation, NativeAcquisitionFailure] {
  match database.begin_transaction() {
    Err(issue) => return Err({ primary: Runtime(issue), rollback: None, })
    Ok(_) => ()
  }
  let result = match execute_native_metadata(run, database, limits) {
    Err(issue) => Err(issue)
    Ok(_) => {
      let scan = @duckdb_host.native_host_scan(run)
      match
        execute_native_receipt(
          run,
          database,
          limits,
          @duckdb.ValidationScan,
          @duckdb.native_scan_sql(scan),
          [],
        ) {
        Err(issue) => Err(issue)
        Ok(_) => {
          let query = @duckdb.native_scan_query(scan)
          execute_native_receipt(
            run,
            database,
            limits,
            @duckdb.NativeResult,
            @duckdb.native_query_sql(query),
            [@duckdb.native_query_parameter(query)],
          )
        }
      }
    }
  }
  match result {
    Err(issue) => {
      let rollback = match database.rollback_transaction() {
        Ok(_) => None
        Err(cleanup) => Some(cleanup)
      }
      @duckdb_host.abort_native_host(run)
      Err({ primary: issue, rollback, })
    }
    Ok(_) => {
      match database.commit_transaction() {
        Err(issue) => {
          let rollback = match database.rollback_transaction() {
            Ok(_) => None
            Err(cleanup) => Some(cleanup)
          }
          @duckdb_host.abort_native_host(run)
          return Err({ primary: Runtime(issue), rollback, })
        }
        Ok(_) => ()
      }
      confirm_settlement()
      match @duckdb_host.complete_native_host(run, limits.completion) {
        Ok(value) => Ok(value)
        Err(issue) => {
          @duckdb_host.abort_native_host(run)
          Err({ primary: Host(issue), rollback: None, })
        }
      }
    }
  }
}

///|
priv struct NativeRuntimeAuthority {
  mut settled : @duckdb_query.DuckDBNativeAttempt?
  mut live : Bool
}

///|
/// Standard native ownership of one admitted Host attempt and one DuckDB
/// connection. The verifier is private to this runtime and cannot be replaced
/// by a caller callback.
struct NativeAcquisitionRuntime {
  host : @duckdb_host.NativeHostRun
  database : @native_duckdb.Database
  limits : @duckdb_host.NativeHostLimits
  authority : NativeRuntimeAuthority
  mut observation : @duckdb_query.DuckDBNativeObservation?
  mut closed : Bool
}

///|
pub fn start_native_acquisition_runtime(
  setup : @duckdb_host.NativeHostConfiguration,
  nonce : String,
  database : @native_duckdb.Database,
) -> Result[NativeAcquisitionRuntime, @duckdb_host.NativeHostIssue] {
  let authority : NativeRuntimeAuthority = { settled: None, live: true, }
  let host = match
    @duckdb_host.start_configured_native_host(setup, nonce, attempt => {
      authority.live &&
      authority.settled is Some(settled) &&
      physical_equal(settled, attempt)
    }) {
    Ok(value) => value
    Err(issue) => {
      database.close()
      return Err(issue)
    }
  }
  Ok({
    host,
    database,
    limits: @duckdb_host.configured_native_host_limits(setup),
    authority,
    observation: None,
    closed: false,
  })
}

///|
pub fn execute_native_acquisition_runtime(
  runtime : NativeAcquisitionRuntime,
) -> Result[@duckdb_query.DuckDBNativeObservation, NativeAcquisitionFailure] {
  if runtime.closed || runtime.observation is Some(_) {
    return Err({ primary: RuntimeState, rollback: None, })
  }
  execute_native_acquisition(runtime.host, runtime.database, runtime.limits, () => {
    runtime.authority.settled = Some(
      @duckdb_host.native_host_attempt(runtime.host),
    )
  }).map(observation => {
    runtime.observation = Some(observation)
    observation
  })
}

///|
pub fn native_acquisition_runtime_output(
  runtime : NativeAcquisitionRuntime,
) -> Result[@duckdb_query.DuckDBNativeOutput, @duckdb_host.NativeHostIssue] {
  if runtime.closed {
    return Err(@duckdb_host.InvalidState)
  }
  guard runtime.observation is Some(observation) else {
    return Err(@duckdb_host.InvalidState)
  }
  @duckdb_host.native_host_output(
    runtime.host,
    observation,
    runtime.limits.output_rows,
    runtime.limits.retention,
  )
}

///|
pub fn close_native_acquisition_runtime(
  runtime : NativeAcquisitionRuntime,
) -> Unit {
  if runtime.closed {
    return
  }
  runtime.closed = true
  runtime.authority.live = false
  @duckdb_host.close_native_host(runtime.host)
  runtime.database.close()
}
