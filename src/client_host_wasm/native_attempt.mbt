///|
/// Issued invocation custody, not a second Source/Run lifecycle. All receipt
/// and completion decisions stay inside the existing Native attempt Owner.
priv struct StoredNativeAttempt {
  configuration : Int
  start : Int
  borrow : @buffers.BufferBorrow
  mut invoked : Bool
  mut closing : Bool
  mut event_pending : Bool
  mut compute_reserved : Bool
  mut capacity : @resources.Reservation?
  mut event_borrow : @buffers.BufferBorrow?
  mut failed : Bool
  mut observation : @native_acquisition.DuckDBNativeObservation?
  exact_attempt : Ref[@native_acquisition.DuckDBNativeAttempt?]
  mut outcome : Result[
    @native_host.NativeHostRun,
    @local_run.LocalNativeSourceIssue,
  ]?
}

///|
/// Reserve before construction can trap or before any physical query is sent.
pub fn reserve_native_attempt(
  nonce : Int64,
  configuration : Int,
  start : Int,
  input : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.native_sources.get(configuration) is Some(source) &&
    source.outcome is Some(Ok(_)) &&
    value.physical_starts.get(start) is Some(original) &&
    original.run == source.run &&
    original.outcome is Some(Ok(_)) &&
    value.copies.get(input) is Some((slot, physical)) else {
    return -2
  }
  if value.next_handle == 2147483647 {
    return -4
  }
  if source.attempt_reserved {
    return -3
  }
  let handle = value.next_handle
  let borrow = match
    @buffers.borrow_buffer(value.pool, slot, () => {
      physical_reader_stop(physical, handle) == 0
    }) {
    Ok(borrow) => borrow
    Err(issue) => return issue_code(issue)
  }
  value.native_attempts[handle] = {
    configuration,
    start,
    borrow,
    invoked: false,
    closing: false,
    event_pending: false,
    compute_reserved: false,
    capacity: None,
    event_borrow: None,
    failed: false,
    observation: None,
    exact_attempt: Ref(None),
    outcome: None,
  }
  source.attempt_reserved = true
  value.next_handle += 1
  handle
}

///|
/// The current read Account Owner, not Run activation or a caller boolean,
/// authorizes the exact installed physical binding and checked requirement.
pub fn start_native_attempt(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.native_attempts.get(handle) is Some(record) &&
    value.native_sources.get(record.configuration)
    is Some({ outcome: Some(Ok(configuration)), .. }) &&
    value.physical_starts.get(record.start)
    is Some({ outcome: Some(Ok(start)), .. }) else {
    return -2
  }
  if record.closing {
    return -5
  }
  if record.outcome is Some(_) {
    return 0
  }
  if record.invoked {
    return -33
  }
  record.invoked = true
  guard input_cursor(value, record.borrow.slot) is Some(cursor) &&
    @decode.closed_object(cursor, ["read_account", "attempt_nonce"])
    is Ok(object) &&
    required_text(object, "read_account") is Some(wire) &&
    @authorization.admit_account_configuration_json(wire) is Ok(current) &&
    required_text(object, "attempt_nonce") is Some(attempt_nonce) else {
    return -31
  }
  let permit = match
    @local_run.authorize_local_native_source(configuration, current) {
    Ok(permit) => permit
    Err(issue) => {
      record.outcome = Some(Err(issue))
      return 0
    }
  }
  // Reserve the existing bounded buffered receiver and materialization
  // envelope before construction or any physical dispatch. Failed or unknown
  // invocations retain this same reservation until stop and cleanup complete.
  guard @native_host.configured_native_capacity(
      @local_run.local_native_source_configuration(configuration),
    )
    is Some(capacity) else {
    return -4
  }
  match
    @resources.reserve_attempt(
      value.root,
      0L,
      capacity.retained_bytes,
      capacity.execution_bytes,
    ) {
    Ok(reservation) => {
      record.capacity = Some(reservation)
      // Crossing the physical start boundary spends this original attempt,
      // including zero-transfer starts. Cleanup returns bytes, not this use.
      match @resources.consume_reserved_attempt(value.root, reservation) {
        Ok(_) => ()
        Err(_) => return -4
      }
    }
    Err(_) => return -4
  }
  let exact = record.exact_attempt
  let outcome = @local_run.start_local_native_source(
    configuration,
    start,
    permit,
    current,
    attempt_nonce,
    attempt => {
      exact.val is Some(expected) &&
      physical_equal(expected, attempt) &&
      physical_native_settled(handle) == 0
    },
  )
  match outcome {
    Ok(host) => {
      let scan = @native_host.native_host_scan(host)
      let parameter = @duckdb.native_query_parameter(
        @duckdb.native_scan_query(scan),
      )
      let type_id = @duckdb.physical_parameter_type_id(parameter)
      if type_id != "BOOLEAN" && type_id != "DOUBLE" && type_id != "VARCHAR" {
        @native_host.close_native_host(host)
        record.outcome = Some(Err(@local_run.UnsupportedCapability))
        return 0
      }
      exact.val = Some(@native_host.native_host_attempt(host))
    }
    Err(_) => ()
  }
  record.outcome = Some(outcome)
  0
}

///|
pub fn native_attempt_started(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.native_attempts.get(handle) is Some(record) else {
    return -2
  }
  if record.closing {
    return -5
  }
  match record.outcome {
    Some(Ok(_)) => 0
    Some(Err(_)) => -32
    None => -33
  }
}

///|
/// Physical stop and actual cleanup are separate from settlement. A failed
/// acknowledgement retains this same attempt and all parent loans for retry.
pub fn close_native_attempt(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.native_attempts.get(handle) is Some(record) else {
    return -2
  }
  record.closing = true
  if value.native_commands.values().any(command => command.attempt == handle) ||
    value.computes
    .values()
    .any(compute => compute.origin is Captured(attempt) && attempt == handle) {
    return -9
  }
  if physical_native_stopped(handle) != 0 {
    return -9
  }
  match record.outcome {
    Some(Ok(host)) => @native_host.close_native_host(host)
    _ => ()
  }
  if physical_native_cleaned(handle) != 0 {
    return -9
  }
  match record.event_borrow {
    Some(borrow) => {
      let retired = status(@buffers.return_buffer_borrow(value.pool, borrow))
      if retired != 0 {
        return retired
      }
      record.event_borrow = None
    }
    None => ()
  }
  if record.capacity is Some(capacity) {
    match @resources.settle_reservation(value.root, capacity) {
      Err(_) => return -10
      Ok(_) => record.capacity = None
    }
  }
  let result = status(@buffers.return_buffer_borrow(value.pool, record.borrow))
  if result == 0 {
    value.native_attempts.remove(handle) |> ignore
  }
  result
}
