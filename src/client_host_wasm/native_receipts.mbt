///|
/// One physical event is evaluated once against the current read account. The
/// existing metadata/receipt/completion Owners decide all logical progression.
/// An interrupted event keeps its attempt pending; another chunk cannot hide it.
pub fn accept_native_event(
  nonce : Int64,
  handle : Int,
  kind : Int,
  input : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.native_attempts.get(handle) is Some(record) &&
    record.outcome is Some(Ok(host)) &&
    value.native_sources.get(record.configuration)
    is Some({ outcome: Some(Ok(configuration)), .. }) &&
    value.copies.get(input) is Some((slot, physical)) else {
    return -2
  }
  if record.closing {
    return -5
  }
  if record.event_pending || record.failed || record.observation is Some(_) {
    return -33
  }
  if record.event_borrow is Some(_) {
    return -9
  }
  let borrow = match
    @buffers.borrow_buffer(value.pool, slot, () => {
      physical_reader_stop(physical, handle) == 0
    }) {
    Ok(borrow) => borrow
    Err(issue) => return issue_code(issue)
  }
  record.event_borrow = Some(borrow)
  record.event_pending = true
  let outcome = apply_native_event(
    value, slot, record, host, configuration, kind,
  )
  record.event_pending = false
  if outcome != 0 {
    record.failed = true
    @native_host.abort_native_host(host)
  }
  outcome
}

///|
/// Observe physical input-stop for this already evaluated event. Retrying
/// this retirement never evaluates metadata/chunks or completion again.
pub fn close_native_event(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.native_attempts.get(handle) is Some(record) else {
    return -2
  }
  if record.event_pending {
    return -33
  }
  match record.event_borrow {
    None => 0
    Some(borrow) => {
      let retired = status(@buffers.return_buffer_borrow(value.pool, borrow))
      if retired == 0 {
        record.event_borrow = None
      }
      retired
    }
  }
}

///|
fn apply_native_event(
  value : Instance,
  slot : @buffers.BufferSlot,
  record : StoredNativeAttempt,
  host : @native_host.NativeHostRun,
  configuration : @local_run.LocalNativeSourceConfiguration,
  kind : Int,
) -> Int {
  let keys = match kind {
    1 => ["read_account", "rows", "fields", "columns"]
    2 | 3 => ["read_account", "fields"]
    4 => ["read_account", "rows", "columns"]
    5 | 6 => ["read_account"]
    _ => return -31
  }
  guard input_cursor(value, slot) is Some(cursor) &&
    @decode.closed_object(cursor, keys) is Ok(object) &&
    required_text(object, "read_account") is Some(wire) &&
    @authorization.admit_account_configuration_json(wire) is Ok(current) else {
    return -31
  }
  guard @local_run.authorize_local_native_source(configuration, current)
    is Ok(_) else {
    return -32
  }
  let limits = @native_host.configured_native_host_limits(
    @local_run.local_native_source_configuration(configuration),
  )
  match kind {
    1 => {
      guard required_int32(object, "rows") is Some(rows) &&
        required_text(object, "fields") is Some(fields_wire) &&
        required_text(object, "columns") is Some(columns_wire) &&
        @duckdb.decode_physical_fields(fields_wire, limits.transport)
        is Ok(fields) &&
        @duckdb.decode_transport_columns(columns_wire, limits.transport)
        is Ok(columns) else {
        return -31
      }
      match @native_host.native_host_metadata(host, rows, fields, columns) {
        Ok(_) => 0
        Err(_) => -32
      }
    }
    2 | 3 => {
      guard required_text(object, "fields") is Some(wire) &&
        @duckdb.decode_physical_fields(wire, limits.transport) is Ok(fields) else {
        return -31
      }
      match
        @native_host.begin_native_host_receipt(
          host,
          if kind == 2 {
            @duckdb.ValidationScan
          } else {
            @duckdb.NativeResult
          },
          fields,
        ) {
        Ok(_) => 0
        Err(_) => -32
      }
    }
    4 => {
      guard required_int32(object, "rows") is Some(rows) &&
        required_text(object, "columns") is Some(wire) &&
        @duckdb.decode_transport_columns(wire, limits.transport) is Ok(columns) else {
        return -31
      }
      match @native_host.accept_native_host_chunk(host, rows, columns) {
        Ok(_) => 0
        Err(_) => -32
      }
    }
    5 =>
      match @native_host.finish_native_host_receipt(host) {
        Ok(_) => 0
        Err(_) => -32
      }
    6 =>
      match @native_host.complete_native_host(host, limits.completion) {
        Ok(observation) => {
          record.observation = Some(observation)
          0
        }
        Err(_) => -32
      }
    _ => -31
  }
}

///|
/// Receipt completion and exact physical settlement, not a Run outcome.
pub fn native_source_completed(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.native_attempts.get(handle) is Some(record) else {
    return -2
  }
  if record.closing {
    return -5
  }
  if record.failed {
    return -32
  }
  if record.event_pending {
    return -33
  }
  match record.observation {
    Some(_) => 0
    None => -33
  }
}
