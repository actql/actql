///|
/// One physical allocation allowance, not Run admission or a Source permit.
pub fn reserve_workspace(nonce : Int64, ticket : Int, bytes : Int64) -> Int {
  guard selected(nonce) is Some(value) else { return -1 }
  if value.closing {
    return -5
  }
  if ticket <= 0 ||
    value.next_handle == 2147483647 ||
    value.workspaces.length() >= value.workspace_slots ||
    value.workspaces.values().any(pair => pair.0 == ticket) ||
    value.copies.values().any(pair => pair.1 == ticket) ||
    value.result_chunks.values().any(chunk => chunk.physical_ticket == ticket) ||
    value.native_commands
    .values()
    .any(command => command.physical_ticket == ticket) {
    return -3
  }
  let handle = value.next_handle
  match
    @buffers.reserve_workspace(
      value.root,
      bytes,
      () => physical_reader_stop(ticket, handle) == 0,
      () => physical_input_cleanup(ticket) == 0,
    ) {
    Err(issue) => issue_code(issue)
    Ok(loan) => {
      value.workspaces[handle] = (ticket, loan)
      value.next_handle += 1
      handle
    }
  }
}

///|
pub fn close_workspace(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.workspaces.get(handle) is Some((_, loan)) else {
    return -2
  }
  let result = status(@buffers.close_workspace(loan))
  if result == 0 {
    value.workspaces.remove(handle) |> ignore
  }
  result
}

///|
/// Includes fixed live Wasm memory, transfer reservations and physical workspace.
pub fn root_reserved(nonce : Int64) -> Int64 {
  match selected(nonce) {
    None => -1L
    Some(value) => @resources.ledger_usage(value.root).reserved_execution_bytes
  }
}
