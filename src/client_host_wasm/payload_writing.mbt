///|
fn payload_physical_uint64(wire : String) -> UInt64? {
  if wire.length() == 0 || wire.length() > 20 {
    return None
  }
  let value : UInt64 = @string.from_str(wire) catch { _ => return None }
  if value.to_string() == wire {
    Some(value)
  } else {
    None
  }
}

///|
fn payload_physical_size(wire : String) -> Int64? {
  if wire.length() == 0 || wire.length() > 19 {
    return None
  }
  let value : Int64 = @string.from_str(wire) catch { _ => return None }
  if value >= 0L && value.to_string() == wire {
    Some(value)
  } else {
    None
  }
}

///|
/// One original Writing/Owned/Sealed transition and its uncertain physical CAS. The payload
/// Owner determines every state; this child only retains transport and custody.
priv struct StoredPayloadWriting {
  parent : Int
  kind : Int
  revision : Int
  slot : @buffers.BufferSlot
  mut transition : @payload.PublicationPayloadTransition?
  mut produced : Bool
  mut begun : Bool
  mut confirmed : Bool
  mut closing : Bool
}

///|
pub fn reserve_payload_writing(
  nonce : Int64,
  parent : Int,
  kind : Int,
  physical_ticket : Int,
  physical_copy_bytes : Int64,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.payload_records.get(parent)
    is Some({ confirmed: true, closing: false, record: Some(original), .. }) &&
    (
      (
        kind == 1 &&
        @payload.publication_payload_record_state(original) is Reserved
      ) ||
      (
        kind == 2 &&
        @payload.publication_payload_record_state(original) is Writing &&
        @payload.publication_payload_record_ownership(original) is None &&
        @payload.publication_payload_record_opaque_ownership(original) is None
      ) ||
      (
        kind == 3 &&
        @payload.publication_payload_record_state(original) is Writing &&
        @payload.publication_payload_record_ownership(original) is Some(_) &&
        @payload.publication_payload_record_generation(original) is None &&
        @payload.publication_payload_record_opaque_ownership(original) is None
      )
    ) else {
    return -2
  }
  if value.closing || value.runtime_closing {
    return -5
  }
  if physical_ticket <= 0 ||
    value.next_handle == 2147483647 ||
    value.payload_writings.values().any(record => record.parent == parent) ||
    value.payload_allocations.values().any(record => record.parent == parent) ||
    value.payload_reservations.values().any(record => record.parent == parent) ||
    value.copies.values().any(pair => pair.1 == physical_ticket) ||
    value.native_commands
    .values()
    .any(record => record.physical_ticket == physical_ticket) ||
    value.result_chunks
    .values()
    .any(record => record.physical_ticket == physical_ticket) ||
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
  value.payload_writings[handle] = {
    parent,
    kind,
    revision: @payload.publication_payload_record_revision(original),
    slot,
    transition: None,
    produced: false,
    begun: false,
    confirmed: false,
    closing: false,
  }
  value.copies[handle] = (slot, physical_ticket)
  value.next_handle += 1
  handle
}

///|
pub fn produce_payload_writing(
  nonce : Int64,
  handle : Int,
  input : Int,
  current_configuration : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.payload_writings.get(handle) is Some(record) &&
    value.payload_records.get(record.parent) is Some(parent) &&
    parent.record is Some(original) else {
    return -2
  }
  if value.closing || value.runtime_closing || record.closing || parent.closing {
    return -5
  }
  if !parent.confirmed ||
    !payload_record_current(value, parent, current_configuration) {
    return -32
  }
  if @payload.publication_payload_record_revision(original) !=
    record.revision + (if record.confirmed { 1 } else { 0 }) {
    return -32
  }
  if record.produced {
    return 0
  }
  if record.transition is None {
    let prepared = if record.kind == 1 {
      // Writing has no physical allocation yet. SDK values cannot stand in
      // for the original Reserved record or authorize a file allocation.
      if input != 0 {
        return -31
      }
      @payload.prepare_publication_payload_writing(original)
    } else {
      let fields = if record.kind == 2 {
        ["store_authority_cid", "material_generation_cid", "device", "inode"]
      } else {
        [
          "store_authority_cid", "material_generation_cid", "device", "inode", "size",
          "physical_digest",
        ]
      }
      guard value.copies.get(input) is Some((slot, _)) &&
        input_cursor(value, slot) is Some(cursor) &&
        @decode.closed_object(cursor, fields) is Ok(object) &&
        required_text(object, "store_authority_cid") is Some(store) &&
        required_text(object, "material_generation_cid") is Some(material) &&
        required_text(object, "device") is Some(device_wire) &&
        required_text(object, "inode") is Some(inode_wire) &&
        payload_physical_uint64(device_wire) is Some(device) &&
        payload_physical_uint64(inode_wire) is Some(inode) else {
        return -31
      }
      let request = @payload.publication_payload_record_request(original)
      if store != @payload.publication_payload_request_store_authority(request) ||
        material != @payload.publication_payload_material_identity(request) {
        return -32
      }
      if record.kind == 2 {
        // Exact physical identity from the trusted Host; not a durable write.
        @payload.prepare_publication_payload_owned(original, { device, inode, })
      } else {
        guard required_text(object, "size") is Some(size_wire) &&
          payload_physical_size(size_wire) is Some(size) &&
          required_text(object, "physical_digest") is Some(physical_digest) else {
          return -31
        }
        // The physical Host observed the stopped, flushed original descriptor.
        // Only the existing payload Owner checks identity, bounds and sealing.
        @payload.prepare_publication_payload_sealed(
          original,
          { device, inode, size, },
          physical_digest,
        )
      }
    }
    match prepared {
      Err(_) => return -32
      Ok(transition) => record.transition = Some(transition)
    }
  }

  let wire = match
    @payload.publication_payload_transition_durable_json(
      record.transition.unwrap(),
    ) {
    Ok(wire) => wire
    Err(_) => return -34
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
pub fn validate_payload_writing(
  nonce : Int64,
  handle : Int,
  current_configuration : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.payload_writings.get(handle) is Some(record) &&
    value.payload_records.get(record.parent) is Some(parent) &&
    parent.record is Some(original) else {
    return -2
  }
  if value.closing || value.runtime_closing || record.closing || parent.closing {
    return -5
  }
  if !record.produced {
    return -33
  }
  if @payload.publication_payload_record_revision(original) ==
    record.revision + (if record.confirmed { 1 } else { 0 }) &&
    payload_record_current(value, parent, current_configuration) {
    0
  } else {
    -32
  }
}

///|
pub fn begin_payload_writing(
  nonce : Int64,
  handle : Int,
  current_configuration : Int,
) -> Int {
  let result = validate_payload_writing(nonce, handle, current_configuration)
  if result != 0 {
    return result
  }
  let record = selected(nonce).unwrap().payload_writings.get(handle).unwrap()
  if record.begun {
    return -33
  }
  record.begun = true
  0
}

///|
pub fn confirm_payload_writing(
  nonce : Int64,
  handle : Int,
  input : Int,
  current_configuration : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.payload_writings.get(handle) is Some(record) &&
    record.transition is Some(transition) &&
    value.payload_records.get(record.parent) is Some(parent) &&
    value.copies.get(input) is Some((slot, _)) else {
    return -2
  }
  if !record.produced || !record.begun {
    return -33
  }
  // An uncertain physical write keeps this original child even during close.
  // Rechecking current authorization is required before resolving that write.
  if !payload_record_current(
      value,
      parent,
      current_configuration,
      pending_confirmation=true,
    ) {
    return -32
  }
  guard input_cursor(value, slot) is Some(cursor) &&
    @decode.closed_object(cursor, [
      "store_authority_cid", "material_generation_cid", "physical_revision", "record_json",
    ])
    is Ok(object) &&
    required_text(object, "store_authority_cid") is Some(store) &&
    required_text(object, "material_generation_cid") is Some(material) &&
    required_int32(object, "physical_revision") is Some(revision) &&
    required_text(object, "record_json") is Some(wire) else {
    return -31
  }
  let durable = match
    @payload.admit_durable_publication_payload_record(@utf8.encode(wire)) {
    Ok(durable) => durable
    Err(_) => return -31
  }
  let committed = if record.confirmed {
    @payload.confirm_committed_publication_payload_transition(
      transition,
      store,
      material,
      revision.to_int64(),
      durable,
    )
  } else {
    match
      @payload.commit_observed_publication_payload_transition(
        transition,
        store,
        material,
        revision.to_int64(),
        durable,
      ) {
      Ok(original) => Ok(original)
      Err(_) =>
        @payload.confirm_committed_publication_payload_transition(
          transition,
          store,
          material,
          revision.to_int64(),
          durable,
        )
    }
  }
  match committed {
    Err(_) => -32
    Ok(_) => {
      record.confirmed = true
      0
    }
  }
}

///|
pub fn payload_writing_length(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.payload_writings.get(handle) is Some(record) else {
    return -2
  }
  if !record.produced || record.closing {
    return -33
  }
  @buffers.buffer_length(value.pool, record.slot).unwrap_or(-33)
}

///|
pub fn close_payload_writing(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.payload_writings.get(handle) is Some(record) else {
    return -2
  }
  record.closing = true
  if record.begun && !record.confirmed {
    return -9
  }
  let result = status(@buffers.close_buffer(value.pool, record.slot))
  if result == 0 {
    value.payload_writings.remove(handle) |> ignore
    value.copies.remove(handle) |> ignore
  }
  result
}
