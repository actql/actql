///|
fn sdk_payload_encoding_issue(
  issue : @local_run.LocalSDKPayloadEncodingIssue,
) -> Int {
  match issue {
    CapacityExceeded => -4
    Sink(DeliverySinkChunkOutstanding)
    | Sink(DeliverySinkClosed)
    | Sink(DeliverySinkSourceIncomplete) => -33
    _ => -32
  }
}

///|
// One synchronous read-only observation retains complete originals before and
// after its nested queries. Every nested decision still calls fresh current.
// No result escapes this frame or advances an encoder before the final fence.
fn sdk_payload_read_current_frame(
  original_current : () -> Result[Unit, Int],
  current : () -> Result[Unit, Int],
  observe : (() -> Result[Unit, Int]) -> Result[Unit, Int],
) -> Result[Unit, Int] {
  match original_current() {
    Err(code) => return Err(code)
    Ok(_) => ()
  }
  match observe(current) {
    Err(code) => return Err(code)
    Ok(_) => ()
  }
  original_current()
}

///|
// Reobserve complete mutable originals before issuing a dependent read. A
// final frame refusal cannot undo IO already issued after an original changed.
// This private transport returns physical DATA, never a Source or permission.
fn sdk_payload_read_original_row(
  original_current : () -> Result[Unit, Int],
  read : () -> Result[@host.ClientJournalPhysicalRow?, Int],
) -> Result[@host.ClientJournalPhysicalRow?, Int] {
  match original_current() {
    Err(code) => return Err(code)
    Ok(_) => ()
  }
  read()
}

///|
// Only the same freshly constructed Saved context selects this private path.
// These are live owner/Account/Host checks, never a remembered successful check.
// The enclosing read-only frame separately reobserves all saved Store rows.
fn sdk_payload_saved_read_current(
  value : Instance,
  first : StoredPublicationCommitExport,
  context : OriginalSDKReadContext,
  current_configuration : Int,
) -> Result[Unit, Int] {
  if value.publications.contains(first.publication) {
    return Err(-32)
  }
  if value.closing || value.runtime_closing || first.closing {
    return Err(-5)
  }
  guard saved_result_export_parent(value, first.publication)
    is Some((parent, saved)) &&
    parent.configuration == current_configuration &&
    value.run_configurations.get(current_configuration) is Some(current) &&
    physical_equal(current, context.current) &&
    saved.source is Some(source) &&
    physical_equal(source, context.source) &&
    saved.finite is Some(finite) &&
    physical_equal(finite, context.finite) &&
    saved.owner is Some(owner) &&
    physical_equal(owner, context.owner) &&
    saved.view is Some(view) &&
    physical_equal(view, context.view) &&
    saved.result_name == context.result_name else {
    return Err(-32)
  }
  match saved_result_read_current(value, parent, current, saved.result_name) {
    Err(code) => return Err(code)
    Ok(_) => ()
  }
  match
    @local_run.validate_local_sdk_read_source_current(
      source,
      current.account,
      saved.result_name,
    ) {
    Err(Preflight(_)) => return Err(-35)
    Err(_) => return Err(-32)
    Ok(_) => ()
  }
  match run_configuration_current(value, current) {
    Err(code) => return Err(code)
    Ok(_) => ()
  }
  if value.closing ||
    value.runtime_closing ||
    first.closing ||
    parent.output_closed {
    Err(-5)
  } else {
    Ok(())
  }
}

///|
fn sdk_payload_access_current(
  value : Instance,
  first : StoredPublicationCommitExport,
  context : OriginalSDKReadContext,
  clock : @buffers.BufferBorrow,
  current_configuration : Int,
) -> Result[Unit, Int] {
  let source_current = sdk_payload_record_current(
    value, first, context, current_configuration,
  )
  if source_current != 0 {
    return Err(source_current)
  }
  guard first.sdk_delivery_first is Some(original) &&
    first.state_borrow is Some(input) &&
    input_cursor(value, input.slot) is Some(request_cursor) &&
    @decode.closed_object(request_cursor, [
      "result_name", "format", "attempt_id", "observed_at",
    ])
    is Ok(request) &&
    required_text(request, "result_name") == Some(context.result_name) &&
    required_text(request, "format") == Some(context.format) &&
    required_text(request, "attempt_id") is Some(attempt_id) &&
    input_cursor(value, clock.slot) is Some(clock_cursor) &&
    @decode.closed_object(clock_cursor, ["observed_at"]) is Ok(observed) &&
    required_text(observed, "observed_at") is Some(at) else {
    return Err(-30)
  }
  let observe = (read, current) => {
    @local_run.validate_local_sdk_payload_encoding_source_current(
      context.source,
      context.current.account,
      context.finite,
      context.sdk.read,
      context.sdk.adoption_cid,
      context.owner,
      context.view,
      original,
      context.result_name,
      context.format,
      attempt_id,
      at,
      8,
      read,
      current,
    ).map_err(sdk_payload_codec_issue)
  }
  if value.publications.contains(first.publication) {
    // The Live caller keeps its original callback selection and work.
    observe(
      (table, key) => {
        sdk_run_journal_port(value, context.current, 1, table, key)
      },
      context.check_current,
    )
  } else {
    sdk_payload_read_current_frame(
      context.check_current,
      () => {
        sdk_payload_saved_read_current(
          value, first, context, current_configuration,
        )
      },
      current => {
        observe(
          (table, key) => {
            sdk_payload_read_original_row(context.check_current, () => {
              sdk_run_journal_port(value, context.current, 1, table, key)
            })
          },
          current,
        )
      },
    )
  }
}

///|
/// A failed physical stop keeps the same clock loan. Retrying it does not
/// advance payload framing, reset sink progress or issue a replacement receipt.
fn sdk_payload_return_previous_clock(
  value : Instance,
  output : StoredPublicationCommitExport,
  clock_input : Int,
) -> Int {
  if output.sdk_payload_tick_borrow is Some(original) {
    if output.sdk_payload_clock_input != Some(clock_input) {
      return -33
    }
    output.pending = true
    let code = status(@buffers.return_buffer_borrow(value.pool, original))
    output.pending = false
    if code != 0 {
      return code
    }
    output.sdk_payload_tick_borrow = None
  }
  0
}

///|
/// Validate original current/availability and sink backpressure before the
/// physical caller advances its descriptor. Chunk production checks again.
pub fn prepare_publication_sdk_payload_input(
  nonce : Int64,
  first_handle : Int,
  clock_input : Int,
  current_configuration : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.commit_exports.get(first_handle) is Some(first) &&
    first.sdk_payload_outcome is Some(Ok(encoding)) &&
    first.projection is Some(SDKReadDeliveryStorage(_, run)) &&
    value.copies.get(clock_input) is Some((slot, physical)) else {
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
  let previous_stop = sdk_payload_return_previous_clock(
    value, first, clock_input,
  )
  if previous_stop != 0 {
    return previous_stop
  }
  let clock = match
    @buffers.borrow_buffer(value.pool, slot, () => {
      physical_reader_stop(physical, first_handle) == 0
    }) {
    Ok(clock) => clock
    Err(issue) => return issue_code(issue)
  }
  first.sdk_payload_tick_borrow = Some(clock)
  first.sdk_payload_clock_input = Some(clock_input)
  first.pending = true
  let result = match
    sdk_payload_access_current(
      value, first, context, clock, current_configuration,
    ) {
    Err(code) => code
    Ok(_) =>
      match encoding.prepare_input() {
        Ok(_) => 0
        Err(issue) => sdk_payload_encoding_issue(issue)
      }
  }
  let stopped = status(@buffers.return_buffer_borrow(value.pool, clock))
  if stopped == 0 {
    first.sdk_payload_tick_borrow = None
  }
  first.pending = false
  if stopped != 0 {
    return stopped
  }
  if result != 0 {
    return result
  }
  sdk_payload_finish_current(value, first, context, current_configuration)
}

///|
fn sdk_payload_owned_bytes(
  value : Instance,
  raw : @buffers.BufferBorrow,
) -> Result[Bytes, Int] {
  guard @buffers.buffer_length(value.pool, raw.slot) is Some(length) else {
    return Err(-33)
  }
  if length > 65536 {
    return Err(-4)
  }
  let bytes : Array[Byte] = []
  for index in 0..<length {
    guard @buffers.buffer_byte(value.pool, raw.slot, index) is Some(byte) else {
      return Err(-33)
    }
    bytes.push(byte)
  }
  Ok(Bytes::from_array(bytes))
}

///|
/// Feed one bounded physical input to existing framing/serialization/sink
/// Owners. These bytes are offered, not sink-confirmed or durably delivered.
pub fn produce_publication_sdk_payload_chunk(
  nonce : Int64,
  handle : Int,
  first_handle : Int,
  input : Int,
  clock_input : Int,
  eof : Int,
  current_configuration : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.commit_exports.get(handle) is Some(output) &&
    value.commit_exports.get(first_handle) is Some(first) &&
    first.sdk_payload_outcome is Some(Ok(encoding)) &&
    first.projection is Some(SDKReadDeliveryStorage(_, run)) &&
    value.copies.get(input) is Some((raw_slot, raw_physical)) &&
    value.copies.get(clock_input) is Some((clock_slot, clock_physical)) else {
    return -2
  }
  if handle == first_handle ||
    output.publication != first.publication ||
    (eof != 0 && eof != 1) {
    return -3
  }
  if output.closing || output.output_closed || output.pending {
    return -5
  }
  let projection = SDKPayloadChunk(first_handle, input, eof)
  if output.projection is Some(original) && original != projection {
    return -33
  }
  let context = match
    original_sdk_read_context(value, first, run, current_configuration) {
    Ok(context) => context
    Err(code) => return code
  }
  let previous_stop = sdk_payload_return_previous_clock(
    value, output, clock_input,
  )
  if previous_stop != 0 {
    return previous_stop
  }
  let clock = match
    @buffers.borrow_buffer(value.pool, clock_slot, () => {
      physical_reader_stop(clock_physical, handle) == 0
    }) {
    Ok(clock) => clock
    Err(issue) => return issue_code(issue)
  }
  output.sdk_payload_tick_borrow = Some(clock)
  output.sdk_payload_clock_input = Some(clock_input)
  output.pending = true
  let access = sdk_payload_access_current(
    value, first, context, clock, current_configuration,
  )
  let result = match access {
    Err(code) => code
    Ok(_) =>
      if output.produced {
        0
      } else if output.invoked {
        -33
      } else {
        output.invoked = true
        output.projection = Some(projection)
        output.sdk_payload_parent = Some(first_handle)
        let raw = @buffers.borrow_buffer(value.pool, raw_slot, () => {
          physical_reader_stop(raw_physical, handle) == 0
        })
        match raw {
          Err(issue) => issue_code(issue)
          Ok(raw) => {
            output.state_borrow = Some(raw)
            match sdk_payload_owned_bytes(value, raw) {
              Err(code) => code
              Ok(bytes) =>
                match encoding.feed(bytes, eof == 1) {
                  Err(issue) => sdk_payload_encoding_issue(issue)
                  Ok(encoded) => {
                    let code = status(
                      @buffers.supply_buffer_output(
                        value.pool,
                        output.slot,
                        encoded,
                      ),
                    )
                    if code == 0 {
                      output.produced = true
                    }
                    code
                  }
                }
            }
          }
        }
      }
  }
  let stopped = status(@buffers.return_buffer_borrow(value.pool, clock))
  if stopped == 0 {
    output.sdk_payload_tick_borrow = None
  }
  output.pending = false
  if stopped != 0 {
    return stopped
  }
  if result != 0 {
    return result
  }
  sdk_payload_finish_current(value, first, context, current_configuration)
}

///|
/// Record physical acceptance of this exact offered chunk through the existing
/// sink Owner. This is not a new read/publisher permit or durable Store receipt.
pub fn confirm_publication_sdk_payload_chunk(
  nonce : Int64,
  handle : Int,
) -> Int64 {
  guard selected(nonce) is Some(value) &&
    value.commit_exports.get(handle) is Some(output) &&
    output.produced &&
    !output.closing &&
    output.projection is Some(SDKPayloadChunk(first_handle, _, _)) &&
    output.sdk_payload_parent == Some(first_handle) &&
    value.commit_exports.get(first_handle) is Some(first) &&
    first.sdk_payload_outcome is Some(Ok(encoding)) else {
    return -2L
  }
  if output.sdk_payload_confirmed is Some(original) {
    return original
  }
  // Only this actual owned produced slot proves an empty output. Do not
  // convert a generic NoOutstandingChunk refusal into an acknowledgement.
  let progress = match @buffers.buffer_length(value.pool, output.slot) {
    Some(0) => encoding.observe_empty_output()
    Some(_) => encoding.confirm_chunk()
    None => return -33L
  }
  match progress {
    Err(issue) => sdk_payload_encoding_issue(issue).to_int64()
    Ok(confirmed) => {
      output.sdk_payload_confirmed = Some(confirmed)
      confirmed
    }
  }
}

///|
/// Explicit physical sink completion projects the original receipt only.
/// Its later actual same-Store CAS/adoption and SDK marker are separate steps.
pub fn produce_publication_sdk_payload_receipt(
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
  if handle == first_handle || output.publication != first.publication {
    return -3
  }
  if output.closing || output.output_closed || output.pending {
    return -5
  }
  let projection = SDKPayloadReceipt(first_handle)
  if output.projection is Some(original) && original != projection {
    return -33
  }
  let context = match
    original_sdk_read_context(value, first, run, current_configuration) {
    Ok(context) => context
    Err(code) => return code
  }
  let previous_stop = sdk_payload_return_previous_clock(
    value, output, clock_input,
  )
  if previous_stop != 0 {
    return previous_stop
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
  let result = match
    sdk_payload_access_current(
      value, first, context, clock, current_configuration,
    ) {
    Err(code) => code
    Ok(_) =>
      if output.produced {
        0
      } else if output.invoked {
        -33
      } else {
        output.invoked = true
        output.projection = Some(projection)
        output.sdk_payload_parent = Some(first_handle)
        match encoding.confirm_finished() {
          Err(issue) => sdk_payload_encoding_issue(issue)
          Ok(receipt) => {
            let code = status(
              @buffers.supply_buffer_output(
                value.pool,
                output.slot,
                @utf8.encode(@publication.publication_contract_json(receipt)),
              ),
            )
            if code == 0 {
              output.produced = true
            }
            code
          }
        }
      }
  }
  let stopped = status(@buffers.return_buffer_borrow(value.pool, clock))
  if stopped == 0 {
    output.sdk_payload_tick_borrow = None
  }
  output.pending = false
  if stopped != 0 {
    return stopped
  }
  if result != 0 {
    return result
  }
  sdk_payload_finish_current(value, first, context, current_configuration)
}
