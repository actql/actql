///|
/// One original Reserved transition and its uncertain physical CAS. The payload
/// Owner determines every state; this child only retains transport and custody.
priv struct StoredPayloadReservation {
  parent : Int
  slot : @buffers.BufferSlot
  mut transition : @payload.PublicationPayloadTransition?
  mut produced : Bool
  mut begun : Bool
  mut confirmed : Bool
  mut closing : Bool
}

///|
pub fn reserve_payload_reservation(
  nonce : Int64,
  parent : Int,
  physical_ticket : Int,
  physical_copy_bytes : Int64,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.payload_records.get(parent)
    is Some({ confirmed: true, closing: false, record: Some(original), .. }) &&
    @payload.publication_payload_record_state(original) is Intent else {
    return -2
  }
  if value.closing || value.runtime_closing {
    return -5
  }
  if physical_ticket <= 0 ||
    value.next_handle == 2147483647 ||
    value.payload_reservations.values().any(record => record.parent == parent) ||
    value.payload_writings.values().any(record => record.parent == parent) ||
    value.payload_allocations.values().any(record => record.parent == parent) ||
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
  value.payload_reservations[handle] = {
    parent,
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
pub fn produce_payload_reservation(
  nonce : Int64,
  handle : Int,
  input : Int,
  current_configuration : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.payload_reservations.get(handle) is Some(record) &&
    value.payload_records.get(record.parent) is Some(parent) &&
    parent.record is Some(original) &&
    value.copies.get(input) is Some((slot, _)) else {
    return -2
  }
  if value.closing || value.runtime_closing || record.closing || parent.closing {
    return -5
  }
  if !parent.confirmed ||
    !payload_record_current(value, parent, current_configuration) {
    return -32
  }
  if record.produced {
    return 0
  }
  if record.transition is None {
    // These are actual trusted Host capacity observations, not SDK authority.
    // The original request's bounded max_bytes is an Int32; wider amounts refuse.
    guard input_cursor(value, slot) is Some(cursor) &&
      @decode.closed_object(cursor, [
        "store_authority_cid", "material_generation_cid", "capacity_namespace", "reserved_bytes",
        "reserved_objects",
      ])
      is Ok(object) &&
      required_text(object, "store_authority_cid") is Some(store) &&
      required_text(object, "material_generation_cid") is Some(material) &&
      required_text(object, "capacity_namespace") is Some(capacity_namespace) &&
      required_int32(object, "reserved_bytes") is Some(bytes) &&
      required_int32(object, "reserved_objects") is Some(objects) else {
      return -31
    }
    match
      @payload.prepare_observed_publication_payload_reserved(
        original,
        store,
        capacity_namespace,
        material,
        bytes.to_int64(),
        objects.to_int64(),
      ) {
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
pub fn validate_payload_reservation(
  nonce : Int64,
  handle : Int,
  current_configuration : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.payload_reservations.get(handle) is Some(record) &&
    value.payload_records.get(record.parent) is Some(parent) else {
    return -2
  }
  if value.closing || record.closing || parent.closing {
    return -5
  }
  if !record.produced {
    return -33
  }
  if payload_record_current(value, parent, current_configuration) {
    0
  } else {
    -32
  }
}

///|
pub fn begin_payload_reservation(
  nonce : Int64,
  handle : Int,
  current_configuration : Int,
) -> Int {
  let result = validate_payload_reservation(
    nonce, handle, current_configuration,
  )
  if result != 0 {
    return result
  }
  let record = selected(nonce).unwrap().payload_reservations
    .get(handle)
    .unwrap()
  if record.begun {
    return -33
  }
  record.begun = true
  0
}

///|
pub fn confirm_payload_reservation(
  nonce : Int64,
  handle : Int,
  input : Int,
  current_configuration : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.payload_reservations.get(handle) is Some(record) &&
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
pub fn payload_reservation_length(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.payload_reservations.get(handle) is Some(record) else {
    return -2
  }
  if !record.produced || record.closing {
    return -33
  }
  @buffers.buffer_length(value.pool, record.slot).unwrap_or(-33)
}

///|
pub fn close_payload_reservation(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.payload_reservations.get(handle) is Some(record) else {
    return -2
  }
  record.closing = true
  if record.begun && !record.confirmed {
    return -9
  }
  let result = status(@buffers.close_buffer(value.pool, record.slot))
  if result == 0 {
    value.payload_reservations.remove(handle) |> ignore
    value.copies.remove(handle) |> ignore
  }
  result
}
