///|
priv struct StoredPayloadAllocation {
  parent : Int
  kind : Int
  slot : @buffers.BufferSlot
  mut write : @payload.PublicationPayloadAllocationWrite?
  mut produced : Bool
  mut begun : Bool
  mut confirmed : Bool
  mut closing : Bool
}

///|
fn allocation_nullable_text(
  object : @decode.ObjectView,
  name : String,
) -> Result[String?, Unit] {
  match @decode.field(object, name) {
    Missing => Err(())
    ExplicitNull => Ok(None)
    Present(cursor) =>
      @decode.text(cursor).map(value => Some(value)).map_err(_ => ())
  }
}

///|
fn allocation_physical_revision(wire : String) -> Int64? {
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
pub fn reserve_payload_allocation(
  nonce : Int64,
  parent : Int,
  kind : Int,
  physical_ticket : Int,
  physical_copy_bytes : Int64,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.payload_records.get(parent)
    is Some({ confirmed: true, closing: false, record: Some(original), .. }) &&
    (kind == 1 || kind == 2) &&
    @payload.publication_payload_record_state(original) is Writing &&
    @payload.publication_payload_record_ownership(original) is None &&
    @payload.publication_payload_record_opaque_ownership(original) is None else {
    return -2
  }
  if value.closing || value.runtime_closing {
    return -5
  }
  if physical_ticket <= 0 ||
    value.next_handle == 2147483647 ||
    value.payload_allocations.values().any(child => child.parent == parent) ||
    value.payload_writings.values().any(child => child.parent == parent) ||
    value.payload_reservations.values().any(child => child.parent == parent) ||
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
    @buffers.reserve_output_buffer(value.pool, 65536, physical_copy_bytes, () => {
      physical_input_cleanup(physical_ticket) == 0
    }) {
    Ok(slot) => slot
    Err(issue) => return issue_code(issue)
  }
  let handle = value.next_handle
  value.payload_allocations[handle] = {
    parent,
    kind,
    slot,
    write: None,
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
pub fn produce_payload_allocation(
  nonce : Int64,
  handle : Int,
  input : Int,
  current_configuration : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.payload_allocations.get(handle) is Some(child) &&
    value.payload_records.get(child.parent) is Some(parent) &&
    parent.record is Some(original) &&
    value.copies.get(input) is Some((slot, _)) else {
    return -2
  }
  if value.closing || value.runtime_closing || child.closing || parent.closing {
    return -5
  }
  if !parent.confirmed ||
    !payload_record_current(value, parent, current_configuration) {
    return -32
  }
  if child.write is Some(write) &&
    @payload.validate_publication_payload_allocation_write(write) is Err(_) {
    return -32
  }
  if child.produced {
    return 0
  }
  if child.write is None {
    let fields = [
      "store_authority_cid", "namespace", "material_generation_cid", "physical_revision",
      "allocation_body",
    ]
    if child.kind == 2 {
      fields.push("device")
      fields.push("inode")
    }
    guard input_cursor(value, slot) is Some(cursor) &&
      @decode.closed_object(cursor, fields) is Ok(object) &&
      required_text(object, "store_authority_cid") is Some(store) &&
      required_text(object, "namespace") is Some(storage_namespace) &&
      required_text(object, "material_generation_cid") is Some(material) &&
      allocation_nullable_text(object, "physical_revision") is Ok(revision_wire) &&
      allocation_nullable_text(object, "allocation_body") is Ok(body_wire) else {
      return -31
    }
    let request = @payload.publication_payload_record_request(original)
    if store != @payload.publication_payload_request_store_authority(request) ||
      storage_namespace != @payload.publication_payload_allocation_namespace() ||
      material != @payload.publication_payload_material_identity(request) {
      return -32
    }
    let previous = match (revision_wire, body_wire) {
      (None, None) => None
      (Some(revision), Some(body)) => {
        guard allocation_physical_revision(revision) is Some(physical_revision) else {
          return -31
        }
        match
          @payload.admit_observed_publication_payload_allocation(
            request,
            store,
            storage_namespace,
            material,
            physical_revision,
            @utf8.encode(body),
          ) {
          Ok(observation) => Some(observation)
          Err(_) => return -32
        }
      }
      _ => return -31
    }
    // These observations come from the original trusted Host. Nullable fields
    // express an actual not-found read, never an SDK absence/permission claim.
    let prepared = if child.kind == 1 {
      @payload.prepare_publication_payload_allocation_intent_write(
        original, previous,
      )
    } else {
      guard previous is Some(intent) &&
        required_text(object, "device") is Some(device_wire) &&
        required_text(object, "inode") is Some(inode_wire) &&
        payload_physical_uint64(device_wire) is Some(device) &&
        payload_physical_uint64(inode_wire) is Some(inode) else {
        return -31
      }
      @payload.prepare_publication_payload_allocation_ownership_write(
        original,
        intent,
        { device, inode, },
      )
    }
    match prepared {
      Err(_) => return -32
      Ok(write) => child.write = Some(write)
    }
  }
  let wire = match
    @payload.publication_payload_allocation_write_json(child.write.unwrap()) {
    Ok(wire) => wire
    Err(_) => return -34
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
pub fn validate_payload_allocation(
  nonce : Int64,
  handle : Int,
  current_configuration : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.payload_allocations.get(handle) is Some(child) &&
    value.payload_records.get(child.parent) is Some(parent) else {
    return -2
  }
  if value.closing || value.runtime_closing || child.closing || parent.closing {
    return -5
  }
  if !child.produced {
    return -33
  }
  if payload_record_current(value, parent, current_configuration) &&
    child.write is Some(write) &&
    @payload.validate_publication_payload_allocation_write(write) is Ok(_) {
    0
  } else {
    -32
  }
}

///|
pub fn begin_payload_allocation(
  nonce : Int64,
  handle : Int,
  current_configuration : Int,
) -> Int {
  let result = validate_payload_allocation(nonce, handle, current_configuration)
  if result != 0 {
    return result
  }
  let child = selected(nonce).unwrap().payload_allocations.get(handle).unwrap()
  if child.begun {
    return -33
  }
  child.begun = true
  0
}

///|
pub fn confirm_payload_allocation(
  nonce : Int64,
  handle : Int,
  input : Int,
  current_configuration : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.payload_allocations.get(handle) is Some(child) &&
    child.write is Some(write) &&
    value.payload_records.get(child.parent) is Some(parent) &&
    value.copies.get(input) is Some((slot, _)) else {
    return -2
  }
  if !child.produced || !child.begun {
    return -33
  }
  // Pending physical CAS can be observed during close, but still needs the
  // original current authority and exact bytes; closure grants no permission.
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
      "store_authority_cid", "namespace", "material_generation_cid", "physical_revision",
      "allocation_body",
    ])
    is Ok(object) &&
    required_text(object, "store_authority_cid") is Some(store) &&
    required_text(object, "namespace") is Some(storage_namespace) &&
    required_text(object, "material_generation_cid") is Some(material) &&
    required_text(object, "physical_revision") is Some(revision_wire) &&
    allocation_physical_revision(revision_wire) is Some(revision) &&
    required_text(object, "allocation_body") is Some(body) else {
    return -31
  }
  let observed = match
    @payload.admit_observed_publication_payload_allocation(
      @payload.publication_payload_allocation_write_request(write),
      store,
      storage_namespace,
      material,
      revision,
      @utf8.encode(body),
    ) {
    Ok(observed) => observed
    Err(_) => return -32
  }
  match
    @payload.confirm_observed_publication_payload_allocation_write(
      write, observed,
    ) {
    Err(_) => -32
    Ok(_) => {
      child.confirmed = true
      0
    }
  }
}

///|
pub fn payload_allocation_length(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.payload_allocations.get(handle) is Some(child) else {
    return -2
  }
  if !child.produced || child.closing {
    return -33
  }
  @buffers.buffer_length(value.pool, child.slot).unwrap_or(-33)
}

///|
pub fn close_payload_allocation(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.payload_allocations.get(handle) is Some(child) else {
    return -2
  }
  child.closing = true
  if child.begun && !child.confirmed {
    return -9
  }
  let result = status(@buffers.close_buffer(value.pool, child.slot))
  if result == 0 {
    value.payload_allocations.remove(handle) |> ignore
    value.copies.remove(handle) |> ignore
  }
  result
}
