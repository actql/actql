///|
pub fn reuse_duckdb_compute_input_identity(
  value : DuckDBComputeAttempt,
  port : Int,
  evidence : @execution.RetainedScanReuse,
) -> Bool {
  guard value.live &&
    value.receiving is None &&
    value.input_streams.get(port) is Some(Some(stream)) else {
    return false
  }
  @duckdb.reuse_fixed_import_identity(stream, evidence)
}

///|
pub fn reuse_duckdb_compute_input_values(
  value : DuckDBComputeAttempt,
  port : Int,
) -> Bool {
  guard value.live &&
    value.receiving is None &&
    value.input_streams.get(port) is Some(Some(stream)) else {
    return false
  }
  @duckdb.reuse_fixed_import_values(stream)
}

///|
pub fn duckdb_compute_input_file_sql(
  value : DuckDBComputeAttempt,
  port : Int,
  wire : @execution.RowWireLimits,
  max_row_bytes : Int,
  max_sql_bytes : Int,
) -> (String, String)? {
  guard value.live &&
    value.receiving is None &&
    @duckdb.fixed_compute_import(value.compute, port) is Some(imported) else {
    return None
  }
  // Compile without starting consumer measurement/join streams. Two-input
  // execution must still begin and finish each stream in its original order.
  let capacity = @connector.fixed_compute_request_capacity(value.request)
  guard @duckdb.prepare_fixed_import_stream(
      imported,
      capacity.max_rows,
      value.limits.retention,
      wire,
      max_row_bytes,
    )
    is Ok(stream) else {
    return None
  }
  @duckdb.fixed_import_file_sql(stream, max_row_bytes, max_sql_bytes)
}

///|
/// Readiness before native query execution, not an SQL transport receipt.
pub fn prepare_duckdb_compute_input_physical(
  value : DuckDBComputeAttempt,
  port : Int,
  fields : Array[(String, @duckdb.PhysicalType)],
) -> Result[@duckdb.PhysicalResult, DuckDBComputeIssue] {
  guard value.live &&
    value.receiving is None &&
    value.input_streams.get(port) is Some(Some(stream)) else {
    return Err(InvalidState)
  }
  @duckdb.prepare_fixed_import_physical(
    stream,
    fields,
    value.limits.physical,
    value.limits.metadata_work,
  ).map_err(issue => InputStream(issue))
}

///|
pub fn verify_duckdb_compute_input_chunk(
  value : DuckDBComputeAttempt,
  port : Int,
  physical : @duckdb.PhysicalResult,
  rows : Int,
  columns : Array[@decode.Cursor],
) -> Result[Unit, DuckDBComputeIssue] {
  guard value.live &&
    value.receiving is None &&
    value.input_streams.get(port) is Some(Some(stream)) else {
    return Err(InvalidState)
  }
  match @duckdb.verify_fixed_import_chunk(stream, physical, rows, columns) {
    Ok(_) => Ok(())
    Err(issue) => {
      abort_duckdb_compute_attempt(value)
      Err(InputStream(issue))
    }
  }
}

///|
pub fn duckdb_compute_inputs_ready(value : DuckDBComputeAttempt) -> Bool {
  value.live &&
  @execution.fixed_producer_inputs_measured(value.measurement) &&
  @duckdb.fixed_compute_join_validation_matches(
    value.compute,
    value.join_validation,
  )
}

///|
pub fn begin_duckdb_compute_input_stream(
  value : DuckDBComputeAttempt,
  port : Int,
  wire : @execution.RowWireLimits,
  max_batch_bytes : Int,
) -> Result[Unit, DuckDBComputeIssue] {
  if value.stream_transport is Some(bound) &&
    (max_batch_bytes <= 0 || max_batch_bytes > bound.max_bytes) {
    return Err(InvalidState)
  }
  if !value.live ||
    value.receiving is Some(_) ||
    port < 0 ||
    port >= value.input_streams.length() ||
    value.input_streams[port] is Some(_) {
    return Err(InvalidState)
  }
  let imported = @duckdb.fixed_compute_import(value.compute, port).unwrap()
  let capacity = @connector.fixed_compute_request_capacity(value.request)
  let stream = match
    @duckdb.prepare_fixed_import_stream(
      imported,
      capacity.max_rows,
      value.limits.retention,
      wire,
      max_batch_bytes,
    ) {
    Ok(stream) => stream
    Err(issue) => return Err(InputStream(issue))
  }
  match @duckdb.attach_fixed_import_measurement(stream, value.measurement) {
    Ok(_) => ()
    Err(issue) => return Err(InputStream(issue))
  }
  if value.join_stream is Some(join) {
    match @duckdb.attach_fixed_import_join(stream, join) {
      Ok(_) => ()
      Err(issue) => {
        @duckdb.cancel_fixed_import_stream(stream) |> ignore
        abort_duckdb_compute_attempt(value)
        return Err(InputStream(issue))
      }
    }
  }
  if @duckdb.fixed_compute_query(value.compute) is FilterSelect(_) {
    match
      @duckdb.attach_fixed_import_demand(
        stream,
        value.compute,
        capacity.max_value_bytes,
        value.limits.demand,
      ) {
      Ok(_) => ()
      Err(issue) => {
        @duckdb.cancel_fixed_import_stream(stream) |> ignore
        abort_duckdb_compute_attempt(value)
        return Err(InputStream(issue))
      }
    }
  }
  value.input_streams[port] = Some(stream)
  Ok(())
}

///|
pub fn append_duckdb_compute_input_stream(
  value : DuckDBComputeAttempt,
  port : Int,
  row : String,
  limits : @execution.RetainedRowDecodeLimits,
  materialize_parameters? : Bool = true,
) -> Result[Array[@duckdb.PhysicalParameter], DuckDBComputeIssue] {
  guard value.live &&
    value.receiving is None &&
    value.input_streams.get(port) is Some(Some(stream)) else {
    return Err(InvalidState)
  }
  let limits = match value.stream_transport {
    None => limits
    Some(bound) =>
      {
        ..limits,
        max_bytes: Int::min(limits.max_bytes, bound.max_bytes),
        max_nodes: Int::min(limits.max_nodes, bound.max_nodes),
        max_text_bytes: Int::min(limits.max_text_bytes, bound.max_text_bytes),
      }
  }
  match
    @duckdb.append_fixed_import_stream(
      stream,
      row,
      limits,
      materialize_parameters~,
    ) {
    Ok(parameters) => Ok(parameters)
    Err(issue) => {
      abort_duckdb_compute_attempt(value)
      Err(InputStream(issue))
    }
  }
}

///|
pub fn finish_duckdb_compute_input_stream(
  value : DuckDBComputeAttempt,
  port : Int,
) -> Result[Unit, DuckDBComputeIssue] {
  guard value.live &&
    value.receiving is None &&
    value.input_streams.get(port) is Some(Some(stream)) else {
    return Err(InvalidState)
  }
  match @duckdb.finish_fixed_import_stream(stream) {
    Err(issue) => {
      abort_duckdb_compute_attempt(value)
      return Err(InputStream(issue))
    }
    Ok(_) => ()
  }
  if @duckdb.fixed_compute_query(value.compute) is FilterSelect(_) {
    value.input_demand = @duckdb.fixed_import_verified_demand(stream)
    if value.input_demand is None {
      abort_duckdb_compute_attempt(value)
      return Err(InvalidState)
    }
  }
  if @execution.fixed_producer_inputs_measured(value.measurement) &&
    value.join_stream is Some(join) {
    match @execution.finish_fixed_join_stream(join) {
      Ok(validation) => value.join_validation = Some(validation)
      Err(issue) => {
        abort_duckdb_compute_attempt(value)
        return Err(JoinValidation(issue))
      }
    }
  }
  Ok(())
}
