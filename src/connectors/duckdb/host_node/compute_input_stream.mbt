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
