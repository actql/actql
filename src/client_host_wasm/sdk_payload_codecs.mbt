///|
fn sdk_payload_codec_issue(
  issue : @local_run.LocalSDKReadPayloadCodecIssue[Int],
) -> Int {
  match issue {
    Observation(code)
    | Store(Observation(code))
    | Original(Observation(code))
    | Original(Store(Observation(code))) => code
    Store(Preparation(Preflight(_)))
    | Original(Store(Preparation(Preflight(_)))) => -35
    Store(Preparation(Expired)) | Original(Store(Preparation(Expired))) => -42
    Store(Preparation(Codec(CapacityExceeded)))
    | Original(Store(Preparation(Codec(CapacityExceeded)))) => -4
    Original(MissingOriginal) | Original(MissingAttempt) => -41
    _ => -32
  }
}

///|
fn original_sdk_payload_codecs(
  value : Instance,
  record : StoredPublicationCommitExport,
  context : OriginalSDKReadContext,
  clock : @buffers.BufferBorrow,
) -> Result[@local_run.LocalSDKPayloadEncoding, Int] {
  guard record.sdk_delivery_first is Some(first) &&
    record.state_borrow is Some(original_input) &&
    input_cursor(value, original_input.slot) is Some(request_cursor) &&
    @decode.closed_object(request_cursor, [
      "result_name", "format", "attempt_id", "observed_at",
    ])
    is Ok(request) &&
    required_text(request, "result_name") == Some(context.result_name) &&
    required_text(request, "format") == Some(context.format) &&
    required_text(request, "attempt_id") is Some(attempt_id) &&
    input_cursor(value, clock.slot) is Some(clock_cursor) &&
    @decode.closed_object(clock_cursor, ["observed_at"]) is Ok(clock_object) &&
    required_text(clock_object, "observed_at") is Some(observed_at) else {
    return Err(-30)
  }
  @local_run.prepare_local_sdk_payload_encoding_for_source(
    context.source,
    context.current.account,
    context.finite,
    context.sdk.read,
    context.sdk.adoption_cid,
    context.owner,
    context.view,
    first,
    context.result_name,
    context.format,
    attempt_id,
    observed_at,
    8,
    65536,
    65536,
    (table, key) => sdk_run_journal_port(value, context.current, 1, table, key),
    context.check_current,
  ).map_err(issue => {
    match issue {
      Codecs(issue) => sdk_payload_codec_issue(issue)
      Encoding(CapacityExceeded) => -4
      Encoding(_) => -32
    }
  })
}

///|
/// Connect the existing codecs to the genuine retained first preparation.
/// The Host supplies one fresh physical clock snapshot under its same-Store
/// read frame. No payload opens, source re-execution, sink confirmation or
/// Store/Run ACK occurs. Caller workspace is funded before first preparation.
#export_name("actql_publication_commit_export_prepare_sdk_payload_codecs")
pub fn prepare_publication_sdk_payload_codecs(
  nonce : Int64,
  handle : Int,
  clock_input : Int,
  current_configuration : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.commit_exports.get(handle) is Some(record) &&
    record.sdk_delivery_first is Some(_) &&
    record.projection is Some(SDKReadDeliveryStorage(_, run)) &&
    value.copies.get(clock_input) is Some((clock_slot, physical)) else {
    return -2
  }
  if !record.output_closed || !record.produced || record.pending {
    return -33
  }
  let context = match
    original_sdk_read_context(value, record, run, current_configuration) {
    Ok(context) => context
    Err(code) => return code
  }
  if record.sdk_payload_tick_borrow is Some(original_borrow) {
    if record.sdk_payload_clock_input != Some(clock_input) {
      return -33
    }
    // Retry only the original stop/return. No Store requery, new clock loan,
    // codec reset or renewed preparation occurs.
    record.pending = true
    let stopped = status(
      @buffers.return_buffer_borrow(value.pool, original_borrow),
    )
    record.pending = false
    if stopped != 0 {
      return stopped
    }
    record.sdk_payload_tick_borrow = None
    match (context.check_current)() {
      Err(code) => return code
      Ok(_) => ()
    }
  }
  if record.sdk_payload_outcome is Some(outcome) {
    // A cached constructor retains the same codecs; it never restarts rows,
    // rewrites the original grant or resets sink progress.
    return match outcome {
      Ok(_) => 0
      Err(code) => code
    }
  }
  if record.sdk_payload_invoked {
    return -33
  }
  record.sdk_payload_invoked = true
  let borrow = match
    @buffers.borrow_buffer(value.pool, clock_slot, () => {
      physical_reader_stop(physical, handle) == 0
    }) {
    Ok(borrow) => borrow
    Err(issue) => return issue_code(issue)
  }
  record.sdk_payload_tick_borrow = Some(borrow)
  record.sdk_payload_clock_input = Some(clock_input)
  // Reentry close cannot return these loans while current/Store callbacks
  // or the physical stop callback are executing under the original Owner.
  record.pending = true
  let prepared = original_sdk_payload_codecs(value, record, context, borrow)
  record.sdk_payload_outcome = Some(prepared)
  let stopped = status(@buffers.return_buffer_borrow(value.pool, borrow))
  if stopped == 0 {
    record.sdk_payload_tick_borrow = None
  }
  record.pending = false
  if stopped != 0 {
    return stopped
  }
  match prepared {
    Err(code) => code
    Ok(_) =>
      match (context.check_current)() {
        Err(code) => code
        Ok(_) => 0
      }
  }
}
