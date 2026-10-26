///|
/// Pre-reserved Core SQL/parameter projection. A command is neither physical
/// dispatch, a durable invocation record nor permission to repeat a query.
priv struct StoredNativeCommand {
  attempt : Int
  kind : Int
  slot : @buffers.BufferSlot?
  physical_ticket : Int
  reservation_issue : Int
  account : @buffers.BufferBorrow
  mut invoked : Bool
  mut produced : Bool
  mut cleaned : Bool
  mut closing : Bool
}

///|
pub fn reserve_native_command(
  nonce : Int64,
  attempt : Int,
  kind : Int,
  account_input : Int,
  physical_ticket : Int,
  physical_copy_bytes : Int64,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.native_attempts.get(attempt) is Some(record) &&
    record.outcome is Some(Ok(_)) &&
    !record.closing &&
    !record.failed &&
    !record.event_pending &&
    record.observation is None &&
    value.copies.get(account_input) is Some((input, physical)) else {
    return -2
  }
  if kind < 1 ||
    kind > 3 ||
    physical_ticket <= 0 ||
    value.next_handle == 2147483647 ||
    value.copies.values().any(pair => pair.1 == physical_ticket) ||
    value.workspaces.values().any(pair => pair.0 == physical_ticket) ||
    value.result_chunks
    .values()
    .any(chunk => chunk.physical_ticket == physical_ticket) ||
    value.native_commands
    .values()
    .any(command => command.physical_ticket == physical_ticket) {
    return -3
  }
  let handle = value.next_handle
  let account = match
    @buffers.borrow_buffer(value.pool, input, () => {
      physical_reader_stop(physical, handle) == 0
    }) {
    Ok(borrow) => borrow
    Err(issue) => return issue_code(issue)
  }
  let reserved = @buffers.reserve_output_buffer(
    value.pool,
    100000,
    physical_copy_bytes,
    () => physical_input_cleanup(physical_ticket) == 0,
  )
  let (slot, reservation_issue) = match reserved {
    Ok(slot) => {
      value.copies[handle] = (slot, physical_ticket)
      (Some(slot), 0)
    }
    Err(issue) => (None, issue_code(issue))
  }
  // Even a refused output reservation returns its issued custody handle:
  // the account loan and registered physical output still require retirement.
  value.native_commands[handle] = {
    attempt,
    kind,
    slot,
    physical_ticket,
    reservation_issue,
    account,
    invoked: false,
    produced: false,
    cleaned: false,
    closing: false,
  }
  value.next_handle += 1
  handle
}

///|
pub fn produce_native_command(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.native_commands.get(handle) is Some(command) &&
    value.native_attempts.get(command.attempt) is Some(record) &&
    record.outcome is Some(Ok(host)) &&
    !record.closing &&
    !record.failed &&
    !record.event_pending &&
    record.observation is None &&
    value.native_sources.get(record.configuration)
    is Some({ outcome: Some(Ok(configuration)), .. }) else {
    return -2
  }
  if command.closing {
    return -5
  }
  if command.produced {
    return 0
  }
  if command.reservation_issue != 0 {
    return command.reservation_issue
  }
  if command.invoked {
    return -33
  }
  command.invoked = true
  guard command.slot is Some(slot) &&
    input_cursor(value, command.account.slot) is Some(cursor) &&
    @decode.closed_object(cursor, ["read_account"]) is Ok(object) &&
    required_text(object, "read_account") is Some(wire) &&
    @authorization.admit_account_configuration_json(wire) is Ok(current) else {
    return -31
  }
  guard @local_run.authorize_local_native_source(configuration, current)
    is Ok(_) else {
    return -32
  }
  let scan = @native_host.native_host_scan(host)
  let sql = match command.kind {
    1 => @duckdb.native_scan_metadata_sql(scan)
    2 => @duckdb.native_scan_sql(scan)
    3 => @duckdb.native_query_sql(@duckdb.native_scan_query(scan))
    _ => return -31
  }
  let parameters : Array[@duckdb.PhysicalParameter] = []
  if command.kind == 1 {
    for index in 0..<2 {
      guard @duckdb.native_scan_metadata_parameter(scan, index)
        is Some(parameter) else {
        return -32
      }
      parameters.push(parameter)
    }
  } else if command.kind == 3 {
    parameters.push(
      @duckdb.native_query_parameter(@duckdb.native_scan_query(scan)),
    )
  }
  let wire = try {
    let output = @encode.writer(100000, 1000, 8)
    @encode.begin_object(output)
    @encode.key(output, "sql")
    @encode.string_value(output, sql)
    @encode.key(output, "parameters")
    @encode.begin_array(output)
    for parameter in parameters {
      @duckdb.emit_physical_parameter(parameter, output)
    }
    @encode.end_array(output)
    @encode.end_object(output)
    @utf8.encode(@encode.finish(output))
  } catch {
    _ => return -34
  }
  let result = status(@buffers.supply_buffer_output(value.pool, slot, wire))
  if result == 0 {
    command.produced = true
  }
  result
}

///|
pub fn native_command_length(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.native_commands.get(handle)
    is Some({ produced: true, slot: Some(slot), .. }) else {
    return -2
  }
  @buffers.buffer_length(value.pool, slot).unwrap_or(-33)
}

///|
pub fn close_native_command(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.native_commands.get(handle) is Some(command) else {
    return -2
  }
  command.closing = true
  if !command.cleaned {
    let cleaned = match command.slot {
      Some(slot) => status(@buffers.close_buffer(value.pool, slot))
      None =>
        if physical_input_cleanup(command.physical_ticket) == 0 {
          0
        } else {
          -9
        }
    }
    if cleaned != 0 {
      return cleaned
    }
    command.cleaned = true
  }
  // Keep the account borrow and descriptor quota while output cleanup is pending.
  let stopped = status(
    @buffers.return_buffer_borrow(value.pool, command.account),
  )
  if stopped != 0 {
    return stopped
  }
  value.native_commands.remove(handle) |> ignore
  value.copies.remove(handle) |> ignore
  0
}
