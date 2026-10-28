///|
/// Original checked intent and retention custody before Compute activation.
/// This child is neither a task grant nor a physical publication permission.
priv struct StoredPublicationPreflight {
  source : Int
  compute : Int
  borrow : Result[@buffers.BufferBorrow, @buffers.BufferIssue]
  slot : @buffers.BufferSlot
  mut invoked : Bool
  mut pending : Bool
  mut closing : Bool
  mut produced : Bool
  mut output_closed : Bool
  mut preflight : @local_run.LocalPublicationPreflight?
}

///|
fn compute_publication_preflight(
  value : Instance,
  compute : Int,
) -> (Int, StoredPublicationPreflight)? {
  for handle, record in value.publication_preflights {
    if record.compute == compute {
      return Some((handle, record))
    }
  }
  None
}

///|
fn stored_preflight_current(
  value : Instance,
  record : StoredPublicationPreflight,
  account : @authorization.AdmittedAccountConfiguration,
  pending_confirmation? : Bool = false,
) -> Bool {
  record.produced &&
  stored_preflight_original_current(
    value,
    record,
    account,
    pending_confirmation~,
  )
}

///|
pub fn reserve_publication_preflight(
  nonce : Int64,
  source : Int,
  input : Int,
  physical_ticket : Int,
  physical_copy_bytes : Int64,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.run_invocations.get(source)
    is Some(
      { closing: false, produced: true, invocation: Some(_), compute, .. }
    ) &&
    value.computes.get(compute) is Some({ closing: false, host: Some(_), .. }) &&
    value.copies.get(input) is Some((input_slot, physical)) else {
    return -2
  }
  if value.closing || value.runtime_closing {
    return -5
  }
  if compute_publication_preflight(value, compute) is Some(_) ||
    physical_ticket <= 0 ||
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
    Ok(slot) => slot
    Err(issue) => return issue_code(issue)
  }
  let handle = value.next_handle
  let borrow = @buffers.borrow_buffer(value.pool, input_slot, () => {
    physical_reader_stop(physical, handle) == 0
  })
  value.publication_preflights[handle] = {
    source,
    compute,
    borrow,
    slot,
    invoked: false,
    pending: false,
    closing: false,
    produced: false,
    output_closed: false,
    preflight: None,
  }
  value.copies[handle] = (slot, physical_ticket)
  value.next_handle += 1
  handle
}

///|
pub fn prepare_publication_preflight(
  nonce : Int64,
  handle : Int,
  current_configuration : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.publication_preflights.get(handle) is Some(record) &&
    value.run_invocations.get(record.source)
    is Some({ closing: false, invocation: Some(invocation), .. }) &&
    value.computes.get(record.compute) is Some(compute) &&
    !compute.closing &&
    stored_compute_original_run(value, compute)
    is Some({ outcome: Some(Ok(plan)), .. } as original_run) &&
    value.run_configurations.get(current_configuration) is Some(current) else {
    return -2
  }
  if value.closing || record.closing {
    return -5
  }
  if record.produced {
    return if stored_preflight_current(value, record, current.account) {
      0
    } else {
      -32
    }
  }
  if record.invoked || record.pending {
    return -33
  }
  record.invoked = true
  let borrow = match record.borrow {
    Ok(borrow) => borrow
    Err(issue) => return issue_code(issue)
  }
  match run_configuration_current(value, current) {
    Ok(_) => ()
    Err(code) => return code
  }
  guard input_cursor(value, borrow.slot) is Some(cursor) else { return -31 }
  let input = match
    publication_preflight_input(value, compute, original_run, plan, cursor) {
    Ok(input) => input
    Err(code) => return code
  }
  // Original parents and input stay retained even if an Owner call traps.
  record.pending = true
  let intent = match
    @local_run.prepare_local_publication_intent(
      plan,
      input.namespace_id,
      input.policy,
      input.target,
      input.requested_at,
      input.attempt_id,
      input.fence,
      input.idempotency,
      input.started_at,
      {
        max_results: value.workspace_slots,
        max_wire_bytes: 1048576,
        max_nodes: 100000,
        max_depth: 64,
      },
    ) {
    Ok(intent) => intent
    Err(_) => {
      record.pending = false
      return -32
    }
  }
  let preflight = match
    @local_run.check_local_publication_preflight(
      intent,
      invocation,
      current.account,
      input.retentions,
    ) {
    Ok(preflight) => preflight
    Err(_) => {
      record.pending = false
      return -32
    }
  }
  record.preflight = Some(preflight)
  record.pending = false
  if !stored_preflight_original_current(value, record, current.account) {
    return -32
  }
  let (request, attempt) = @local_run.local_publication_preflight_contracts(
    preflight,
  )
  let writer = @encode.writer(1048576, 3, 1) catch { _ => return -34 }
  let wire = try {
    @encode.begin_object(writer)
    for (name, contract) in [("request", request), ("attempt", attempt)] {
      @encode.key(writer, name)
      @encode.string_value(
        writer,
        @publication.publication_contract_json(contract),
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
fn stored_preflight_original_current(
  value : Instance,
  record : StoredPublicationPreflight,
  account : @authorization.AdmittedAccountConfiguration,
  pending_confirmation? : Bool = false,
) -> Bool {
  guard record.preflight is Some(preflight) &&
    value.run_invocations.get(record.source) is Some(source) &&
    source.produced &&
    value.computes.get(record.compute) is Some(compute) else {
    return false
  }
  // Parent close seals new work before it waits for retained children. Only
  // confirmation of an already-begun original write may use that custody.
  if !pending_confirmation {
    if record.closing || source.closing || compute.closing {
      return false
    }
    if compute.current_configuration is Some(handle) {
      guard value.run_configurations.get(handle) is Some(current) &&
        run_configuration_current(value, current) is Ok(_) else {
        return false
      }
    }
  }
  @local_run.validate_local_publication_preflight_current(preflight, account)
  is Ok(_)
}

///|
pub fn publication_preflight_length(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.publication_preflights.get(handle) is Some(record) else {
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
pub fn retire_publication_preflight_output(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.publication_preflights.get(handle) is Some(record) else {
    return -2
  }
  if record.pending || !record.produced || record.preflight is None {
    return -33
  }
  if record.output_closed {
    return 0
  }
  // Only the transient projection retires. Original semantic evidence, Source
  // custody and the exact input borrow remain until full preflight close.
  let code = status(@buffers.close_buffer(value.pool, record.slot))
  if code == 0 {
    record.output_closed = true
    value.copies.remove(handle) |> ignore
  }
  code
}

///|
pub fn close_publication_preflight(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.publication_preflights.get(handle) is Some(record) else {
    return -2
  }
  record.closing = true
  if record.pending {
    return -33
  }
  if value.publishers.values().any(child => child.parent == handle) ||
    value.publications.values().any(child => child.preflight == handle) ||
    value.tasks.values().any(child => child.compute == record.compute) {
    return -9
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
    value.publication_preflights.remove(handle) |> ignore
    value.copies.remove(handle) |> ignore
  }
  result
}

///|
/// Original checked inventory size, not a caller subset or publication result.
pub fn publication_preflight_result_count(
  nonce : Int64,
  handle : Int,
  current_configuration : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    !value.closing &&
    !value.runtime_closing &&
    value.publication_preflights.get(handle)
    is Some({ preflight: Some(preflight), .. } as record) &&
    value.run_configurations.get(current_configuration) is Some(current) else {
    return -2
  }
  match run_configuration_current(value, current) {
    Ok(_) => ()
    Err(code) => return code
  }
  if !stored_preflight_current(value, record, current.account) {
    return -32
  }
  @local_run.local_publication_preflight_count(preflight)
}
