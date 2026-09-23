///|
/// Connector-private bridge token: no path, caller CID or raw success flag can
/// be substituted for the owned receipt emitted by the installed data receiver.
struct ComputeStreamNodeReceipt {
  owner : Ref[Bool]
  receipt : @execution.AdmittedOutputStreamReceipt
}

///|
#export_name("computeHostStreamMaterial")
pub fn compute_host_stream_material(
  handle : @execution.RetainedOutputHandle[ComputeStreamNodeReceipt],
) -> @execution.RetainedOutputMaterial {
  @execution.retained_output_material(handle)
}

///|
#export_name("computeHostStreamBegin")
pub fn compute_host_stream_begin(
  run : ComputeNodeRun,
  fields : String,
  wire : @execution.RowWireLimits,
  max_batch_bytes : Int,
) -> Unit raise NodeHostFailure {
  if run.closed || max_batch_bytes > run.transport.max_bytes {
    raise InvalidCommand
  }
  match
    @duckdb_compute.begin_duckdb_compute_stream_result(
      run.attempt,
      transport_fields(run.transport, fields),
      wire,
      max_batch_bytes,
      run.transport.max_rows,
    ) {
    Ok(_) => ()
    Err(issue) => raise Compute(issue)
  }
}

///|
#export_name("computeHostStreamAccept")
pub fn compute_host_stream_accept(
  run : ComputeNodeRun,
  rows : Int,
  data : String,
) -> Unit raise NodeHostFailure {
  if run.closed {
    raise InvalidCommand
  }
  match
    @duckdb_compute.receive_duckdb_compute_stream_chunk(
      run.attempt,
      rows,
      chunk_columns(run.transport, data),
    ) {
    Ok(_) => ()
    Err(issue) => raise Compute(issue)
  }
}

///|
/// Bound the bridge return independently of the caller's storage-frame limit.
/// The existing stream checks and abort ownership apply to each row.
#export_name("computeHostStreamDrain")
pub fn compute_host_stream_drain(
  run : ComputeNodeRun,
) -> Array[String] raise NodeHostFailure {
  if run.closed {
    raise InvalidCommand
  }
  let result : Array[String] = []
  for _ in 0..<8 {
    match @duckdb_compute.drain_duckdb_compute_stream_row(run.attempt) {
      Ok(Some(row)) => result.push(row)
      Ok(None) => break
      Err(issue) => raise Compute(issue)
    }
  }
  result
}

///|
#export_name("computeHostStreamFinish")
pub fn compute_host_stream_finish(
  run : ComputeNodeRun,
) -> (ComputeStreamNodeReceipt, String) raise NodeHostFailure {
  if run.closed {
    raise InvalidCommand
  }
  match @duckdb_compute.finish_duckdb_compute_stream_result(run.attempt) {
    Ok((receipt, tail)) => ({ owner: run.stream_owner, receipt, }, tail)
    Err(issue) => raise Compute(issue)
  }
}

///|
#export_name("computeHostStreamReadable")
pub fn compute_host_stream_readable(
  handle : @execution.RetainedOutputHandle[ComputeStreamNodeReceipt],
  input : @execution.ProducerRead,
) -> Bool {
  @execution.retained_producer_payload(handle, input) is Some(_)
}

///|
#export_name("computeHostStreamIdentity")
pub fn compute_host_stream_identity(
  token : ComputeStreamNodeReceipt,
) -> (String, Int, Int, Int) {
  @execution.output_stream_identity(token.receipt)
}

///|
/// Trusted Store wiring. The standard entry supplies a verified file-holding
/// availability check, never a callback obtained from execution options.
#export_name("computeHostStreamRetain")
pub fn compute_host_stream_retain(
  run : ComputeNodeRun,
  token : ComputeStreamNodeReceipt,
  available : () -> Bool,
) -> @execution.RetainedOutputHandle[ComputeStreamNodeReceipt] raise NodeHostFailure {
  if run.closed || !physical_equal(run.stream_owner, token.owner) {
    raise InvalidCommand
  }
  let handle = @execution.retain_admitted_output_stream(
    token.receipt,
    token,
    available,
  )
  match
    @duckdb_compute.stage_retained_duckdb_compute_material(
      run.attempt,
      @execution.retained_output_material(handle),
    ) {
    Ok(_) => handle
    Err(issue) => raise Compute(issue)
  }
}
