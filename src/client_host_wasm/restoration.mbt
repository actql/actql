///|
/// Existing Core materials codec admission, not recovery state or an IO grant.
/// The original immutable input loan survives a trap or failed physical stop.
priv struct StoredRestoration {
  borrow : @buffers.BufferBorrow
  mut invoked : Bool
  mut expected_definition_cid : String?
  mut outcome : Result[@host.ClientTaskRunMaterials, @local_run.LocalRunIssue]?
}

///|
pub fn reserve_restoration(nonce : Int64, input : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.copies.get(input) is Some((slot, physical)) else {
    return -2
  }
  if value.next_handle == 2147483647 {
    return -4
  }
  let handle = value.next_handle
  let borrow = match
    @buffers.borrow_buffer(value.pool, slot, () => {
      physical_reader_stop(physical, handle) == 0
    }) {
    Ok(borrow) => borrow
    Err(issue) => return issue_code(issue)
  }
  value.restorations[handle] = {
    borrow,
    invoked: false,
    expected_definition_cid: None,
    outcome: None,
  }
  value.next_handle += 1
  handle
}

///|
/// The trusted physical adapter supplies its retained original definition CID.
/// Decoding a caller's strings supplies no authority, lifetime extension or
/// permission to restart completed acquisition or Compute.
pub fn restore_material(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.restorations.get(handle) is Some(record) else {
    return -2
  }
  if record.outcome is Some(_) {
    return 0
  }
  if record.invoked {
    return -33
  }
  record.invoked = true
  guard input_cursor(value, record.borrow.slot) is Some(cursor) &&
    @decode.closed_object(cursor, ["materials", "expected_run_definition_cid"])
    is Ok(object) &&
    required_text(object, "materials") is Some(wire) &&
    required_text(object, "expected_run_definition_cid") is Some(cid) else {
    return -31
  }
  record.expected_definition_cid = Some(cid)
  record.outcome = Some(@local_run.restore_local_run_materials(wire, cid))
  0
}

///|
pub fn material_restored(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.restorations.get(handle) is Some(record) else {
    return -2
  }
  match record.outcome {
    Some(Ok(_)) => 0
    Some(Err(_)) => -32
    None => -33
  }
}

///|
pub fn close_restoration(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.restorations.get(handle) is Some(record) else {
    return -2
  }
  if value.runs.values().any(run => run.restoration == Some(handle)) {
    return -9
  }
  let result = status(@buffers.return_buffer_borrow(value.pool, record.borrow))
  if result == 0 {
    value.restorations.remove(handle) |> ignore
  }
  result
}
