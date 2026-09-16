///|
#export_name("computeHostResidentInputReuse")
pub fn compute_host_resident_input_reuse(
  run : ComputeNodeRun,
  inputs : @duckdb_driver.DuckDBResidentInputs,
  port : Int,
) -> Bool raise NodeHostFailure {
  let input = compute_host_input_read(run, port)
  guard @duckdb_driver.resident_input_scan_reuse(inputs, port, input)
    is Some(evidence) else {
    return false
  }
  @duckdb_compute.reuse_duckdb_compute_input_identity(
    run.attempt,
    port,
    evidence,
  )
}

///|
#export_name("computeHostInputFileSql")
pub fn compute_host_input_file_sql(
  run : ComputeNodeRun,
  port : Int,
  wire : @execution.RowWireLimits,
  max_row_bytes : Int,
  max_sql_bytes : Int,
) -> (String, String)? {
  if run.closed {
    return None
  }
  @duckdb_compute.duckdb_compute_input_file_sql(
    run.attempt,
    port,
    wire,
    max_row_bytes,
    max_sql_bytes,
  )
}

///|
#export_name("computeHostInputRead")
pub fn compute_host_input_read(
  run : ComputeNodeRun,
  port : Int,
) -> @execution.ProducerRead raise NodeHostFailure {
  if run.closed {
    raise InvalidCommand
  }
  guard @duckdb.fixed_compute_import(
      @duckdb_compute.duckdb_compute_attempt_plan(run.attempt),
      port,
    )
    is Some(imported) else {
    raise InvalidCommand
  }
  @duckdb.fixed_import_input(imported)
}

///|
#export_name("computeHostInputPhysicalBegin")
pub fn compute_host_input_physical_begin(
  run : ComputeNodeRun,
  port : Int,
  fields : String,
) -> @duckdb.PhysicalResult raise NodeHostFailure {
  if run.closed {
    raise InvalidCommand
  }
  match
    @duckdb_compute.prepare_duckdb_compute_input_physical(
      run.attempt,
      port,
      transport_fields(run.transport, fields),
    ) {
    Ok(value) => value
    Err(issue) => raise Compute(issue)
  }
}

///|
#export_name("computeHostInputPhysicalAccept")
pub fn compute_host_input_physical_accept(
  run : ComputeNodeRun,
  port : Int,
  physical : @duckdb.PhysicalResult,
  rows : Int,
  data : String,
) -> Unit raise NodeHostFailure {
  if run.closed {
    raise InvalidCommand
  }
  match
    @duckdb_compute.verify_duckdb_compute_input_chunk(
      run.attempt,
      port,
      physical,
      rows,
      chunk_columns(run.transport, data),
    ) {
    Ok(_) => ()
    Err(issue) => raise Compute(issue)
  }
}

///|
#export_name("computeHostInputMaterial")
pub fn compute_host_input_material(
  input : @execution.ProducerRead,
) -> @execution.RetainedOutputMaterial? {
  @execution.producer_read_retained_material(input)
}

///|
#export_name("computeHostInputStreamBegin")
pub fn compute_host_input_stream_begin(
  run : ComputeNodeRun,
  port : Int,
  wire : @execution.RowWireLimits,
  max_batch_bytes : Int,
) -> Unit raise NodeHostFailure {
  if run.closed || max_batch_bytes > run.transport.max_bytes {
    raise InvalidCommand
  }
  match
    @duckdb_compute.begin_duckdb_compute_input_stream(
      run.attempt,
      port,
      wire,
      max_batch_bytes,
    ) {
    Ok(_) => ()
    Err(issue) => raise Compute(issue)
  }
}

///|
#export_name("computeHostInputStreamAppend")
pub fn compute_host_input_stream_append(
  run : ComputeNodeRun,
  port : Int,
  row : String,
  limits : @execution.RetainedRowDecodeLimits,
) -> String raise NodeHostFailure {
  if run.closed {
    raise InvalidCommand
  }
  let parameters = match
    @duckdb_compute.append_duckdb_compute_input_stream(run.attempt, port, row, {
      max_bytes: Int::min(limits.max_bytes, run.transport.max_bytes),
      max_nodes: Int::min(limits.max_nodes, run.transport.max_nodes),
      max_depth: limits.max_depth,
      max_text_bytes: Int::min(
        limits.max_text_bytes,
        run.transport.max_text_bytes,
      ),
    }) {
    Ok(values) => values
    Err(issue) => raise Compute(issue)
  }
  try {
    let writer = @encode.writer(
      run.transport.max_bytes,
      run.transport.max_nodes,
      5,
    )
    @encode.begin_array(writer)
    for parameter in parameters {
      @duckdb.emit_physical_parameter(parameter, writer)
    }
    @encode.end_array(writer)
    @encode.finish(writer)
  } catch {
    issue => raise Encoding(issue)
  }
}

///|
/// Validate an existing resident input without serializing unused SQL parameters.
/// This is not a readiness shortcut: finish still checks content and consumer
/// demand, measurement and join obligations through the same stream.
#export_name("computeHostInputStreamVerify")
pub fn compute_host_input_stream_verify(
  run : ComputeNodeRun,
  port : Int,
  row : String,
  limits : @execution.RetainedRowDecodeLimits,
) -> Unit raise NodeHostFailure {
  if run.closed {
    raise InvalidCommand
  }
  match
    @duckdb_compute.append_duckdb_compute_input_stream(
      run.attempt,
      port,
      row,
      {
        max_bytes: Int::min(limits.max_bytes, run.transport.max_bytes),
        max_nodes: Int::min(limits.max_nodes, run.transport.max_nodes),
        max_depth: limits.max_depth,
        max_text_bytes: Int::min(
          limits.max_text_bytes,
          run.transport.max_text_bytes,
        ),
      },
      materialize_parameters=false,
    ) {
    Ok(_) => ()
    Err(issue) => raise Compute(issue)
  }
}

///|
#export_name("computeHostInputStreamFinish")
pub fn compute_host_input_stream_finish(
  run : ComputeNodeRun,
  port : Int,
) -> Unit raise NodeHostFailure {
  if run.closed {
    raise InvalidCommand
  }
  match @duckdb_compute.finish_duckdb_compute_input_stream(run.attempt, port) {
    Ok(_) => ()
    Err(issue) => raise Compute(issue)
  }
}
