///|
struct NativeStreamNodeReceipt {
  owner : Ref[Bool]
  receipt : @execution.AdmittedOutputStreamReceipt
}

///|
#export_name("nativeHostStreamPrepare")
pub fn native_host_stream_prepare(
  run : NativeNodeRun,
  max_batch_bytes : Int,
) -> Unit raise NodeHostFailure {
  if !run.stream_owner.val || run.streaming_output {
    raise InvalidCommand
  }
  match
    @duckdb_query.stream_duckdb_native_output(
      native_host_attempt(run),
      run.limits.output_rows,
      run.limits.retention,
      run.limits.completion.receipts,
      max_batch_bytes,
      run.limits.transport.max_rows,
    ) {
    Ok(_) => run.streaming_output = true
    Err(issue) => raise Host(Attempt(issue))
  }
}

///|
#export_name("nativeHostStreamDrain")
pub fn native_host_stream_drain(
  run : NativeNodeRun,
) -> String? raise NodeHostFailure {
  match @duckdb_query.drain_duckdb_native_output(native_host_attempt(run)) {
    Ok(text) => text
    Err(issue) => raise Host(Attempt(issue))
  }
}

///|
#export_name("nativeHostStreamFinish")
pub fn native_host_stream_finish(
  run : NativeNodeRun,
) -> (NativeStreamNodeReceipt, String)? raise NodeHostFailure {
  match
    @duckdb_query.finish_duckdb_native_output_stream(native_host_attempt(run)) {
    Ok(Some((receipt, tail))) =>
      Some(({ owner: run.stream_owner, receipt, }, tail))
    Ok(None) => None
    Err(issue) => raise Host(Attempt(issue))
  }
}

///|
#export_name("nativeHostStreamIdentity")
pub fn native_host_stream_identity(
  token : NativeStreamNodeReceipt,
) -> (String, Int, Int, Int) {
  @execution.output_stream_identity(token.receipt)
}

///|
#export_name("nativeHostStreamRetain")
pub fn native_host_stream_retain(
  run : NativeNodeRun,
  token : NativeStreamNodeReceipt,
  available : () -> Bool,
) -> @execution.RetainedOutputHandle[NativeStreamNodeReceipt] raise NodeHostFailure {
  if !run.stream_owner.val || !physical_equal(run.stream_owner, token.owner) {
    raise InvalidCommand
  }
  let (_, bytes, _, _) = @execution.output_stream_identity(token.receipt)
  if run.physical is Some(p) {
    if p.closed ||
      p.completed ||
      p.sealed_file_bytes is Some(_) ||
      bytes < 0 ||
      bytes.to_int64() > p.file_capacity {
      raise Physical(InvalidCharge)
    }
  }
  let handle = @execution.retain_admitted_output_stream(
    token.receipt,
    token,
    available,
  )
  match
    @duckdb_query.stage_duckdb_native_output_material(
      native_host_attempt(run),
      @execution.retained_output_material(handle),
    ) {
    Ok(_) => {
      // The installed transport has sealed this exact receipt's immutable
      // body before attaching its live binding. Do not reduce the reservation
      // yet: failed completion still owns the complete cleanup responsibility.
      if run.physical is Some(p) {
        p.sealed_file_bytes = Some(bytes.to_int64())
      }
      handle
    }
    Err(issue) => raise Host(Evidence(issue))
  }
}

///|
#export_name("nativeHostStreamReadable")
pub fn native_host_stream_readable(
  handle : @execution.RetainedOutputHandle[NativeStreamNodeReceipt],
  input : @execution.ProducerRead,
) -> Bool {
  @execution.retained_producer_payload(handle, input) is Some(_)
}

///|
#export_name("nativeHostStreamMaterial")
pub fn native_host_stream_material(
  handle : @execution.RetainedOutputHandle[NativeStreamNodeReceipt],
) -> @execution.RetainedOutputMaterial {
  @execution.retained_output_material(handle)
}
