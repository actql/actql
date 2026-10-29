///|
/// Original first-adoption metadata and its input/output loans only.
/// This record does not adopt a Host, issue authority or represent durable state.
priv struct StoredBootstrap {
  input : Int
  borrow : Result[@buffers.BufferBorrow, @buffers.BufferIssue]
  slot : @buffers.BufferSlot
  mut invoked : Bool
  mut produced : Bool
  mut output_closed : Bool
  mut sdk_profile : Bool?
}

///|
pub fn reserve_bootstrap(
  nonce : Int64,
  input : Int,
  physical_ticket : Int,
  physical_copy_bytes : Int64,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.copies.get(input) is Some((input_slot, physical)) else {
    return -2
  }
  if value.closing || value.runtime_closing {
    return -5
  }
  if physical_ticket <= 0 ||
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
  let slot = match
    @buffers.reserve_output_buffer(value.pool, 1048576, physical_copy_bytes, () => {
      physical_input_cleanup(physical_ticket) == 0
    }) {
    Ok(value) => value
    Err(issue) => return issue_code(issue)
  }
  let handle = value.next_handle
  let borrow = @buffers.borrow_buffer(value.pool, input_slot, () => {
    physical_reader_stop(physical, handle) == 0
  })
  value.bootstraps[handle] = {
    input,
    borrow,
    slot,
    invoked: false,
    produced: false,
    output_closed: false,
    sdk_profile: None,
  }
  value.copies[handle] = (slot, physical_ticket)
  value.next_handle += 1
  handle
}

///|
pub fn produce_bootstrap(nonce : Int64, handle : Int) -> Int {
  produce_bootstrap_profile(nonce, handle, false)
}

///|
pub fn produce_sdk_bootstrap(nonce : Int64, handle : Int) -> Int {
  produce_bootstrap_profile(nonce, handle, true)
}

///|
fn produce_bootstrap_profile(nonce : Int64, handle : Int, sdk : Bool) -> Int {
  guard selected(nonce) is Some(value) &&
    value.bootstraps.get(handle) is Some(record) else {
    return -2
  }
  if value.closing || value.runtime_closing || record.output_closed {
    return -5
  }
  if record.sdk_profile is Some(previous) && previous != sdk {
    return -3
  }
  if record.produced {
    return 0
  }
  if record.invoked {
    return -33
  }
  record.invoked = true
  record.sdk_profile = Some(sdk)
  let borrow = match record.borrow {
    Ok(value) => value
    Err(issue) => return issue_code(issue)
  }
  guard input_cursor(value, borrow.slot) is Some(cursor) &&
    @decode.closed_object(cursor, ["configuration_root", "observed_at"])
    is Ok(object) &&
    required_text(object, "configuration_root") is Some(root) &&
    required_text(object, "observed_at") is Some(at) else {
    return -31
  }
  let (originals, extra) = if sdk {
    match @host.client_local_product_sdk_bootstrap_originals(root, at) {
      Ok(value) => (value.original, Some((value.profile, value.read)))
      Err(_) => return -31
    }
  } else {
    match @host.client_local_product_bootstrap_originals(root, at) {
      Ok(value) => (value, None)
      Err(_) => return -31
    }
  }
  let wire = try {
    let writer = @encode.writer(1048576, 32, 2)
    @encode.begin_object(writer)
    for
      (key, bytes) in [
        ("account", originals.common.account),
        ("retention_dependencies", originals.common.retention_dependencies),
        ("retention_policy", originals.common.retention_policy),
        ("store", originals.common.store),
        ("result_policy", originals.common.result_policy),
      ] {
      @encode.key(writer, key)
      @encode.string_value(writer, @utf8.decode(bytes))
    }
    for
      (key, text) in [
        ("environment", originals.environment),
        ("compute", originals.compute),
      ] {
      @encode.key(writer, key)
      @encode.string_value(writer, text)
    }
    if extra is Some((profile, read)) {
      @encode.key(writer, "run_policy_profile")
      @encode.string_value(
        writer,
        @host.client_local_run_policy_profile_wire(profile),
      )
      @encode.key(writer, "sdk_read")
      @encode.string_value(
        writer,
        @publication.local_sdk_result_read_selection_wire(read),
      )
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
pub fn bootstrap_length(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.bootstraps.get(handle) is Some(record) &&
    record.produced &&
    !record.output_closed else {
    return -33
  }
  match @buffers.buffer_length(value.pool, record.slot) {
    Some(length) => length
    None => -33
  }
}

///|
pub fn close_bootstrap(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.bootstraps.get(handle) is Some(record) else {
    return -2
  }
  if !record.output_closed {
    let result = status(@buffers.close_buffer(value.pool, record.slot))
    if result != 0 {
      return result
    }
    record.output_closed = true
  }
  let result = match record.borrow {
    Ok(borrow) => status(@buffers.return_buffer_borrow(value.pool, borrow))
    Err(_) => 0
  }
  if result == 0 {
    value.bootstraps.remove(handle) |> ignore
    value.copies.remove(handle) |> ignore
  }
  result
}
