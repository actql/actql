///|
/// Invocation custody only. Epoch authentication and durable clock custody
/// belong to the physical Host; Run admission remains a separate Owner call.
priv struct StoredSubmissionProjection {
  configuration : Int
  kind : Int
  borrow : Result[@buffers.BufferBorrow, @buffers.BufferIssue]
  slot : @buffers.BufferSlot
  mut saved_result : StoredSavedResultRead?
  mut saved_snapshot : @host.ClientSavedSubmissionSnapshot?
  mut append_plan : @host.ClientSubmittedJournalAppendPlan?
  mut failure_preparation : Int?
  mut failure_plan : (@host.ClientJournalPhysicalRow, Bytes)?
  mut invoked : Bool
  mut produced : Bool
  mut output_closed : Bool
}

///|
fn required_number(object : @decode.ObjectView, name : String) -> Double? {
  match @decode.required(object, name) {
    Ok(cursor) => @decode.finite_number(cursor).to_option()
    Err(_) => None
  }
}

///|
pub fn reserve_submission_projection(
  nonce : Int64,
  configuration : Int,
  input : Int,
  kind : Int,
  physical_ticket : Int,
  physical_copy_bytes : Int64,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.run_configurations.contains(configuration) &&
    value.copies.get(input) is Some((input_slot, physical)) else {
    return -2
  }
  if value.closing || value.runtime_closing {
    return -5
  }
  if (
      kind != 1 &&
      kind != 2 &&
      kind != 3 &&
      kind != 4 &&
      kind != 5 &&
      kind != 6 &&
      kind != 7 &&
      kind != 8 &&
      kind != 9
    ) ||
    physical_ticket <= 0 ||
    value.next_handle == 2147483647 ||
    value.copies.values().any(pair => pair.1 == physical_ticket) ||
    value.native_commands
    .values()
    .any(command => command.physical_ticket == physical_ticket) ||
    value.result_chunks
    .values()
    .any(chunk => chunk.physical_ticket == physical_ticket) ||
    value.workspaces.values().any(pair => pair.0 == physical_ticket) {
    return -3
  }
  let handle = value.next_handle
  let slot = match
    @buffers.reserve_output_buffer(
      value.pool,
      if kind >= 3 && kind <= 9 {
        1048576
      } else {
        4096
      },
      physical_copy_bytes,
      () => physical_input_cleanup(physical_ticket) == 0,
    ) {
    Ok(slot) => slot
    Err(issue) => return issue_code(issue)
  }
  // Preserve output custody even when acquiring its input loan fails. The
  // producer returns that failure; only explicit close retires the output.
  let borrow = @buffers.borrow_buffer(value.pool, input_slot, () => {
    physical_reader_stop(physical, handle) == 0
  })
  value.submissions[handle] = {
    configuration,
    kind,
    borrow,
    slot,
    saved_result: None,
    saved_snapshot: None,
    append_plan: None,
    failure_preparation: None,
    failure_plan: None,
    invoked: false,
    produced: false,
    output_closed: false,
  }
  value.copies[handle] = (slot, physical_ticket)
  value.next_handle += 1
  handle
}

///|
pub fn produce_submission_projection(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.submissions.get(handle) is Some(record) &&
    value.run_configurations.get(record.configuration) is Some(configuration) else {
    return -2
  }
  if record.kind == 9 {
    return produce_submission_preparation_failure(value, record, configuration)
  }
  if record.kind == 3 {
    return produce_submission_append(value, record, configuration)
  }
  if record.kind >= 4 && record.kind <= 8 {
    return produce_submission_lookup(value, record, configuration)
  }
  if record.produced {
    return 0
  }
  if record.invoked {
    return -33
  }
  if value.closing || value.runtime_closing || record.output_closed {
    return -5
  }
  match run_configuration_current(value, configuration) {
    Ok(_) => ()
    Err(code) => return code
  }
  record.invoked = true
  let borrow = match record.borrow {
    Ok(borrow) => borrow
    Err(issue) => return issue_code(issue)
  }
  guard @authorization.evaluate_account(
      configuration.account,
      configuration.tuple,
    )
    is @authorization.Allow(_) else {
    return -32
  }
  let fields = if record.kind == 1 {
    ["authority_scope_cid", "epoch_nonce", "not_before", "expires_at"]
  } else {
    [
      "authority_scope_cid", "epoch_nonce", "not_before", "expires_at", "caller_nonce",
      "now",
    ]
  }
  guard input_cursor(value, borrow.slot) is Some(cursor) &&
    @decode.closed_object(cursor, fields) is Ok(object) &&
    required_text(object, "authority_scope_cid") is Some(scope) &&
    required_text(object, "epoch_nonce") is Some(epoch_nonce) &&
    required_number(object, "not_before") is Some(not_before) &&
    required_number(object, "expires_at") is Some(expires_at) else {
    return -31
  }
  if scope != configuration.authority_scope_cid {
    return -32
  }
  let epoch = match
    @host.prepare_submission_epoch(scope, epoch_nonce, not_before, expires_at) {
    Ok(epoch) => epoch
    Err(_) => return -31
  }
  let identity = if record.kind == 2 {
    guard required_text(object, "caller_nonce") is Some(caller_nonce) &&
      required_number(object, "now") is Some(now) &&
      @host.submission_request_id(epoch, caller_nonce) is Ok(request_id) &&
      @host.submission_epoch_validity(epoch, now) is Ok(validity) else {
      return -31
    }
    Some(
      (
        request_id,
        match validity {
          @identity.Admissible => "admissible"
          @identity.NotYetValid => "not_yet_valid"
          @identity.Expired => "expired"
        },
      ),
    )
  } else {
    None
  }
  let writer = @encode.writer(4096, 8, 1) catch { _ => return -34 }
  let wire = try {
    @encode.begin_object(writer)
    @encode.key(writer, "epoch_cid")
    @encode.string_value(writer, @host.submission_epoch_cid(epoch))
    @encode.key(writer, "epoch_wire")
    @encode.string_value(writer, @host.submission_epoch_wire(epoch))
    if identity is Some((request_id, validity)) {
      @encode.key(writer, "request_id")
      @encode.string_value(writer, request_id)
      @encode.key(writer, "validity")
      @encode.string_value(writer, validity)
    }
    @encode.end_object(writer)
    @encode.finish(writer)
  } catch {
    _ => return -34
  }
  let result = status(
    @buffers.supply_buffer_output(value.pool, record.slot, @utf8.encode(wire)),
  )
  if result == 0 {
    record.produced = true
  }
  result
}

///|
pub fn submission_projection_length(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.submissions.get(handle) is Some(record) else {
    return -2
  }
  if record.output_closed {
    return -5
  }
  if record.kind == 3 ||
    record.kind == 4 ||
    record.kind == 5 ||
    record.kind == 6 ||
    record.kind == 7 ||
    record.kind == 8 {
    guard value.run_configurations.get(record.configuration)
      is Some(configuration) else {
      return -2
    }
    let current = if record.kind == 4 ||
      record.kind == 5 ||
      record.kind == 6 ||
      record.kind == 7 ||
      record.kind == 8 {
      submission_lookup_current(value, record, configuration)
    } else {
      submission_append_current(value, record, configuration)
    }
    match current {
      Ok(_) => ()
      Err(code) => return code
    }
  }
  match @buffers.buffer_length(value.pool, record.slot) {
    Some(length) => length
    None => -33
  }
}

///|
/// Retire the consumed transport; the original reference/intent input borrow
/// remains available to internal same-Store observation until full close.
pub fn retire_submission_output(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.submissions.get(handle) is Some(record) &&
    record.kind == 3 &&
    record.produced &&
    record.append_plan is Some(_) else {
    return -2
  }
  if value.commit_exports.values().any(child => child.publication == handle) ||
    value.payload_records.values().any(child => child.request == handle) {
    return -9
  }
  if record.output_closed {
    return 0
  }
  let code = status(@buffers.close_buffer(value.pool, record.slot))
  if code != 0 {
    return code
  }
  record.output_closed = true
  value.copies.remove(handle) |> ignore
  0
}

///|
pub fn close_submission_projection(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.submissions.get(handle) is Some(record) else {
    return -2
  }
  if value.commit_exports.values().any(child => child.publication == handle) ||
    value.payload_records.values().any(child => child.request == handle) {
    return -9
  }
  if value.runs.values().any(run => run.sdk_submission == Some(handle)) ||
    value.restorations
    .values()
    .any(restoration => restoration.sdk_submission == Some(handle)) {
    return -9
  }
  if !record.output_closed {
    let result = status(@buffers.close_buffer(value.pool, record.slot))
    if result != 0 {
      return result
    }
    record.output_closed = true
  }
  let closed = close_saved_result_read(record)
  if closed != 0 {
    return closed
  }
  let result = match record.borrow {
    Ok(borrow) => status(@buffers.return_buffer_borrow(value.pool, borrow))
    Err(_) => 0
  }
  if result == 0 {
    value.submissions.remove(handle) |> ignore
    value.copies.remove(handle) |> ignore
  }
  result
}

///|
/// The trusted serialized Host calls this only after the original synchronous
/// Wasm invocation has unwound, before terminal child-first cleanup. A trap
/// cannot run the pending=false continuation. These flags exclude a live call;
/// they are not physical stop, transaction, buffer, or parent acknowledgments.
/// Spend normal entry first, then retire only this saved parent's call latches.
pub fn begin_submission_cleanup(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.submissions.get(handle) is Some(parent) &&
    parent.kind == 6 else {
    return -2
  }
  value.closing = true
  for record in value.payload_records.values() {
    if record.source is SavedResult(actual, _) && physical_equal(actual, parent) {
      record.closing = true
      record.pending = false
    }
  }
  for record in value.commit_exports.values() {
    if record.publication == handle {
      record.closing = true
      record.pending = false
    }
  }
  0
}
