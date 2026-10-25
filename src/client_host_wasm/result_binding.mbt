///|
/// A child loan on one original publication Result. Its existing buffer Owner
/// retains input/output custody; this table is not a Store or Run state machine.
priv struct StoredResultBinding {
  publication : Int
  index : Int
  borrow : Result[@buffers.BufferBorrow, @buffers.BufferIssue]
  slot : @buffers.BufferSlot
  mut invoked : Bool
  mut produced : Bool
  mut closing : Bool
  mut output_closed : Bool
}

///|
pub fn reserve_result_binding(
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
  value.result_bindings[handle] = {
    publication,
    index,
    borrow,
    slot,
    invoked: false,
    produced: false,
    closing: false,
    output_closed: false,
  }
  value.copies[handle] = (slot, physical_ticket)
  value.next_handle += 1
  handle
}

///|
/// Admit only physical observations against the original nominal Result and
/// current Run/Source authority. Success is encoding, never a Store commit.
pub fn produce_result_binding(
  nonce : Int64,
  handle : Int,
  current_configuration : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.result_bindings.get(handle) is Some(record) &&
    value.publications.get(record.publication) is Some(parent) &&
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
    return 0
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
      "material_generation_cid", "store_authority_cid", "byte_count", "physical_sha256",
    ])
    is Ok(object) &&
    required_text(object, "material_generation_cid") is Some(generation) &&
    required_text(object, "store_authority_cid") is Some(authority) &&
    required_int32(object, "byte_count") is Some(bytes) &&
    required_text(object, "physical_sha256") is Some(digest) else {
    return -31
  }
  let binding = match
    @local_run.issue_local_result_durable_binding(
      parent.publications[record.index],
      current.account,
      generation,
      authority,
      bytes,
      digest,
      65536,
      4096,
      64,
    ) {
    Ok(binding) => binding
    Err(_) => return -32
  }
  let code = status(
    @buffers.supply_buffer_output(
      value.pool,
      record.slot,
      @utf8.encode(@publication.publication_contract_json(binding)),
    ),
  )
  if code == 0 {
    record.produced = true
  }
  code
}

///|
pub fn result_binding_length(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.result_bindings.get(handle) is Some(record) else {
    return -2
  }
  match @buffers.buffer_length(value.pool, record.slot) {
    Some(length) => length
    None => -33
  }
}

///|
pub fn close_result_binding(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.result_bindings.get(handle) is Some(record) else {
    return -2
  }
  record.closing = true
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
    value.result_bindings.remove(handle) |> ignore
    value.copies.remove(handle) |> ignore
  }
  code
}
