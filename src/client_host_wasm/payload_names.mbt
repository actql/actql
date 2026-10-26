///|
/// A bounded private name projection under the original current record. It
/// retains transport custody only and cannot acquire or install a physical file.
priv struct StoredPayloadNames {
  parent : Int
  revision : Int
  slot : @buffers.BufferSlot
  mut produced : Bool
  mut closing : Bool
}

///|
pub fn reserve_payload_names(
  nonce : Int64,
  parent : Int,
  physical_ticket : Int,
  physical_copy_bytes : Int64,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.payload_records.get(parent)
    is Some({ confirmed: true, closing: false, record: Some(original), .. }) &&
    (
      @payload.publication_payload_record_state(original) is Writing ||
      @payload.publication_payload_record_state(original) is Sealed
    ) &&
    @payload.publication_payload_record_ownership(original) is Some(_) &&
    @payload.publication_payload_record_opaque_ownership(original) is None else {
    return -2
  }
  if value.closing || value.runtime_closing {
    return -5
  }
  if physical_ticket <= 0 ||
    value.next_handle == 2147483647 ||
    value.payload_names.values().any(child => child.parent == parent) ||
    value.copies.values().any(pair => pair.1 == physical_ticket) ||
    value.native_commands
    .values()
    .any(child => child.physical_ticket == physical_ticket) ||
    value.result_chunks
    .values()
    .any(child => child.physical_ticket == physical_ticket) ||
    value.workspaces.values().any(pair => pair.0 == physical_ticket) {
    return -3
  }
  let slot = match
    @buffers.reserve_output_buffer(value.pool, 1024, physical_copy_bytes, () => {
      physical_input_cleanup(physical_ticket) == 0
    }) {
    Ok(slot) => slot
    Err(issue) => return issue_code(issue)
  }
  let handle = value.next_handle
  value.payload_names[handle] = {
    parent,
    revision: @payload.publication_payload_record_revision(original),
    slot,
    produced: false,
    closing: false,
  }
  value.copies[handle] = (slot, physical_ticket)
  value.next_handle += 1
  handle
}

///|
pub fn produce_payload_names(
  nonce : Int64,
  handle : Int,
  current_configuration : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.payload_names.get(handle) is Some(child) &&
    value.payload_records.get(child.parent) is Some(parent) &&
    parent.record is Some(original) else {
    return -2
  }
  if value.closing || value.runtime_closing || child.closing || parent.closing {
    return -5
  }
  if !parent.confirmed ||
    @payload.publication_payload_record_revision(original) != child.revision ||
    !payload_record_current(value, parent, current_configuration) {
    return -32
  }
  if child.produced {
    return 0
  }
  let names = match parent.source {
    LiveRequest =>
      @payload.publication_payload_filesystem_names_json(original).map_err(_ => {
        -32
      })
    SavedResult(_, _) => saved_payload_names_json(parent)
  }
  let wire = match names {
    Ok(wire) => wire
    Err(_) => return -32
  }
  let result = status(
    @buffers.supply_buffer_output(value.pool, child.slot, @utf8.encode(wire)),
  )
  if result == 0 {
    child.produced = true
  }
  result
}

///|
pub fn validate_payload_names(
  nonce : Int64,
  handle : Int,
  current_configuration : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.payload_names.get(handle) is Some(child) &&
    value.payload_records.get(child.parent) is Some(parent) &&
    parent.record is Some(original) else {
    return -2
  }
  if value.closing || value.runtime_closing || child.closing || parent.closing {
    return -5
  }
  if !child.produced {
    return -33
  }
  if parent.confirmed &&
    @payload.publication_payload_record_revision(original) == child.revision &&
    payload_record_current(value, parent, current_configuration) {
    0
  } else {
    -32
  }
}

///|
pub fn payload_names_length(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.payload_names.get(handle) is Some(child) else {
    return -2
  }
  if !child.produced || child.closing {
    return -33
  }
  @buffers.buffer_length(value.pool, child.slot).unwrap_or(-33)
}

///|
pub fn close_payload_names(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.payload_names.get(handle) is Some(child) else {
    return -2
  }
  child.closing = true
  let result = status(@buffers.close_buffer(value.pool, child.slot))
  if result == 0 {
    value.payload_names.remove(handle) |> ignore
    value.copies.remove(handle) |> ignore
  }
  result
}
