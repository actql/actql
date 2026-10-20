///|
fn sdk_terminal_issue(
  issue : @local_run.LocalSDKDeliveryTerminalIssue[Int],
) -> Int {
  match issue {
    Current(issue) => sdk_payload_codec_issue(issue)
    Observation(Observation(code))
    | Observation(Store(Observation(code)))
    | Query(code) => code
    Observation(Store(Preparation(Preflight(_)))) => -35
    Observation(MissingOriginal)
    | Observation(MissingAttempt)
    | MissingOriginal
    | UnresolvedOriginal => -41
    Encoding(CapacityExceeded) | CapacityExceeded => -4
    _ => -32
  }
}

///|
fn sdk_terminal_observe(
  value : Instance,
  first : StoredPublicationCommitExport,
  context : OriginalSDKReadContext,
) -> Int {
  guard first.sdk_payload_terminal is Some(terminal) &&
    first.state_borrow is Some(input) &&
    input_cursor(value, input.slot) is Some(cursor) &&
    @decode.closed_object(cursor, [
      "result_name", "format", "attempt_id", "observed_at",
    ])
    is Ok(request) &&
    required_text(request, "attempt_id") is Some(attempt_id) else {
    return -33
  }
  match
    terminal.observe_for_source(
      context.source,
      context.current.account,
      context.finite,
      context.sdk.read,
      context.sdk.adoption_cid,
      context.owner,
      context.view,
      context.result_name,
      context.format,
      attempt_id,
      8,
      (table, key) => {
        sdk_run_journal_port(value, context.current, 1, table, key)
      },
      context.check_current,
    ) {
    Ok(_) => 0
    Err(issue) => sdk_terminal_issue(issue)
  }
}

///|
/// Observe actual same-Store terminal evidence only. This call does not write,
/// retry, read payload, issue a candidate or change original Run state.
#export_name("actql_publication_commit_export_observe_sdk_terminal")
pub fn observe_publication_sdk_terminal(
  nonce : Int64,
  first_handle : Int,
  current_configuration : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.commit_exports.get(first_handle) is Some(first) &&
    first.projection is Some(SDKReadDeliveryStorage(_, run)) else {
    return -2
  }
  if first.pending {
    return -5
  }
  let context = match
    original_sdk_read_context(value, first, run, current_configuration) {
    Ok(context) => context
    Err(code) => return code
  }
  let source = sdk_payload_record_current(
    value, first, context, current_configuration,
  )
  if source != 0 {
    return source
  }
  let code = sdk_terminal_observe(value, first, context)
  if code != 0 {
    return code
  }
  sdk_payload_finish_current(value, first, context, current_configuration)
}

///|
/// Propose the original three terminal CAS rows before physical COMMIT. Cached
/// revalidation after those writes observes full evidence inside that actual
/// transaction; it remains precommit validation, never a durable ACK.
#export_name("actql_publication_commit_export_produce_sdk_terminal_storage")
pub fn produce_publication_sdk_terminal_storage(
  nonce : Int64,
  handle : Int,
  first_handle : Int,
  clock_input : Int,
  current_configuration : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.commit_exports.get(handle) is Some(output) &&
    value.commit_exports.get(first_handle) is Some(first) &&
    first.sdk_payload_outcome is Some(Ok(encoding)) &&
    first.projection is Some(SDKReadDeliveryStorage(_, run)) &&
    value.copies.get(clock_input) is Some((clock_slot, physical)) else {
    return -2
  }
  if output.publication != first.publication || handle == first_handle {
    return -3
  }
  if output.pending || output.closing || output.output_closed {
    return -5
  }
  let projection = SDKTerminalStorage(first_handle)
  if output.projection is Some(original) && original != projection {
    return -33
  }
  let context = match
    original_sdk_read_context(value, first, run, current_configuration) {
    Ok(context) => context
    Err(code) => return code
  }
  let source = sdk_payload_record_current(
    value, first, context, current_configuration,
  )
  if source != 0 {
    return source
  }
  let previous = sdk_payload_return_previous_clock(value, output, clock_input)
  if previous != 0 {
    return previous
  }
  if output.produced {
    let observed = sdk_terminal_observe(value, first, context)
    if observed != 0 {
      return observed
    }
    return sdk_payload_finish_current(
      value, first, context, current_configuration,
    )
  }
  if output.invoked {
    return -33
  }
  let clock = match
    @buffers.borrow_buffer(value.pool, clock_slot, () => {
      physical_reader_stop(physical, handle) == 0
    }) {
    Ok(clock) => clock
    Err(issue) => return issue_code(issue)
  }
  output.sdk_payload_tick_borrow = Some(clock)
  output.sdk_payload_clock_input = Some(clock_input)
  output.pending = true
  output.invoked = true
  output.projection = Some(projection)
  output.sdk_payload_parent = Some(first_handle)
  let code = sdk_terminal_prepare_output(
    value, output, first, context, encoding, clock,
  )
  let stopped = status(@buffers.return_buffer_borrow(value.pool, clock))
  if stopped == 0 {
    output.sdk_payload_tick_borrow = None
  }
  output.pending = false
  if stopped != 0 {
    return stopped
  }
  if code != 0 {
    return code
  }
  sdk_payload_finish_current(value, first, context, current_configuration)
}

///|
fn sdk_terminal_prepare_output(
  value : Instance,
  output : StoredPublicationCommitExport,
  first : StoredPublicationCommitExport,
  context : OriginalSDKReadContext,
  encoding : @local_run.LocalSDKPayloadEncoding,
  clock : @buffers.BufferBorrow,
) -> Int {
  guard first.state_borrow is Some(original_input) &&
    input_cursor(value, original_input.slot) is Some(cursor) &&
    @decode.closed_object(cursor, [
      "result_name", "format", "attempt_id", "observed_at",
    ])
    is Ok(request) &&
    required_text(request, "attempt_id") is Some(attempt_id) &&
    input_cursor(value, clock.slot) is Some(tick) &&
    @decode.closed_object(tick, ["observed_at"]) is Ok(observed) &&
    required_text(observed, "observed_at") is Some(at) else {
    return -30
  }
  let terminal = match
    encoding.prepare_terminal_for_source(
      context.source,
      context.current.account,
      context.finite,
      context.sdk.read,
      context.sdk.adoption_cid,
      context.owner,
      context.view,
      context.result_name,
      context.format,
      attempt_id,
      at,
      8,
      (table, key) => {
        sdk_run_journal_port(value, context.current, 1, table, key)
      },
      context.check_current,
    ) {
    Ok(terminal) => terminal
    Err(issue) => return sdk_terminal_issue(issue)
  }
  first.sdk_payload_terminal = Some(terminal)
  let packet = match
    terminal.storage_from_store(
      (table, key) => {
        sdk_run_journal_port(value, context.current, 1, table, key)
      },
      context.check_current,
    ) {
    Ok(packet) => packet
    Err(issue) => return sdk_terminal_issue(issue)
  }
  let code = status(
    @buffers.supply_buffer_output(value.pool, output.slot, @utf8.encode(packet)),
  )
  if code == 0 {
    output.produced = true
  }
  code
}
