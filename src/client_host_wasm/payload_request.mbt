///|
/// A bounded request projection pins the original Result and its exact input
/// borrow. No physical payload transition, publisher permission or Store state
/// is represented by this private handle.
priv struct StoredPayloadRequest {
  publication : Int
  index : Int
  borrow : Result[@buffers.BufferBorrow, @buffers.BufferIssue]
  slot : @buffers.BufferSlot
  mut request : @payload.PublicationPayloadRequest?
  mut invoked : Bool
  mut produced : Bool
  mut closing : Bool
  mut output_closed : Bool
  mut replay : @host.PublicationOutputReplay?
  mut replay_ended : Bool
  mut replay_issue : StoredPayloadReplayIssue?
}

///|
pub fn reserve_payload_request(
  nonce : Int64,
  publication : Int,
  index : Int,
  input : Int,
  physical_ticket : Int,
  physical_copy_bytes : Int64,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.publications.get(publication)
    is Some({ closing: false, produced: true, publications, .. }) &&
    index >= 0 &&
    index < publications.length() &&
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
    @buffers.reserve_output_buffer(value.pool, 65536, physical_copy_bytes, () => {
      physical_input_cleanup(physical_ticket) == 0
    }) {
    Ok(slot) => slot
    Err(issue) => return issue_code(issue)
  }
  let handle = value.next_handle
  let borrow = @buffers.borrow_buffer(value.pool, input_slot, () => {
    physical_reader_stop(physical, handle) == 0
  })
  value.payload_requests[handle] = {
    publication,
    index,
    borrow,
    slot,
    request: None,
    invoked: false,
    produced: false,
    closing: false,
    output_closed: false,
    replay: None,
    replay_ended: false,
    replay_issue: None,
  }
  value.copies[handle] = (slot, physical_ticket)
  value.next_handle += 1
  handle
}

///|
pub fn produce_payload_request(
  nonce : Int64,
  handle : Int,
  current_configuration : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.payload_requests.get(handle) is Some(record) &&
    value.publications.get(record.publication) is Some(parent) &&
    value.publication_preflights.get(parent.preflight)
    is Some({ preflight: Some(preflight), .. }) &&
    value.run_configurations.get(current_configuration) is Some(current) else {
    return -2
  }
  if value.closing || record.closing || parent.closing {
    return -5
  }
  if !parent.produced || !publication_current(value, parent, current.account) {
    return -32
  }
  if record.produced {
    return if record.request is Some(_) { 0 } else { -33 }
  }
  if record.invoked {
    return -33
  }
  record.invoked = true
  let borrow = match record.borrow {
    Ok(borrow) => borrow
    Err(issue) => return issue_code(issue)
  }
  guard input_cursor(value, borrow.slot) is Some(cursor) &&
    @decode.closed_object(cursor, [
      "store_authority_cid", "material_generation_cid", "max_payload_bytes",
    ])
    is Ok(object) &&
    required_text(object, "store_authority_cid") is Some(store) &&
    required_text(object, "material_generation_cid") is Some(material) &&
    required_int32(object, "max_payload_bytes") is Some(max_bytes) &&
    max_bytes > 0 else {
    return -31
  }
  let request = match
    @local_run.prepare_local_preflight_payload_request(
      preflight,
      record.index,
      parent.publications[record.index],
      current.account,
      store,
      material,
      max_bytes.to_int64(),
    ) {
    Ok(request) => request
    Err(_) => return -32
  }
  let wire = match @payload.publication_payload_request_json(request) {
    Ok(wire) => wire
    Err(_) => return -34
  }
  // Keep the original typed intent for the later physical payload Owner.
  // A copied wire or a newly decoded request cannot replace this custody.
  record.request = Some(request)
  let code = status(
    @buffers.supply_buffer_output(value.pool, record.slot, @utf8.encode(wire)),
  )
  if code == 0 {
    record.produced = true
  }
  code
}

///|
pub fn payload_request_length(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.payload_requests.get(handle) is Some(record) else {
    return -2
  }
  if !record.produced || record.closing {
    return -33
  }
  match @buffers.buffer_length(value.pool, record.slot) {
    Some(length) => length
    None => -33
  }
}

///|
pub fn close_payload_request(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.payload_requests.get(handle) is Some(record) else {
    return -2
  }
  record.closing = true
  if value.payload_chunks.values().any(chunk => chunk.request == handle) ||
    value.payload_records.values().any(record => record.request == handle) {
    return -9
  }
  if record.replay is Some(replay) {
    replay.cancel()
  }
  if !record.output_closed {
    let code = status(@buffers.close_buffer(value.pool, record.slot))
    if code != 0 {
      return code
    }
    record.output_closed = true
  }
  let code = match record.borrow {
    Ok(borrow) => status(@buffers.return_buffer_borrow(value.pool, borrow))
    Err(_) => 0
  }
  if code == 0 {
    value.payload_requests.remove(handle) |> ignore
    value.copies.remove(handle) |> ignore
  }
  code
}
