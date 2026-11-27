///|
/// Original checked intent and retention custody before Compute activation.
/// This child is neither a task grant nor a physical publication permission.
priv struct StoredPublicationPreflight {
  origin : StoredPublicationPreflightOrigin
  borrow : Result[@buffers.BufferBorrow, @buffers.BufferIssue]
  slot : @buffers.BufferSlot
  mut invoked : Bool
  mut pending : Bool
  mut closing : Bool
  mut produced : Bool
  mut output_closed : Bool
}

///|
priv enum StoredPublicationPreflightOrigin {
  ComputePublicationPreflight(StoredComputePublicationPreflight)
  FilePublicationPreflight(StoredFilePublicationPreflight)
  SavedEffectPublicationPreflight(StoredSavedEffectPublicationPreflight)
}

///|
priv struct StoredComputePublicationPreflight {
  source : Int
  compute : Int
  mut prepared : @local_run.LocalPublicationPreflight?
  mut capacity : (@resources.Ledger, @resources.CapacityReservation, Int64)?
}

///|
priv struct StoredFilePublicationPreflight {
  start : Int
  work : StoredSDKFileCaptureWork
  mut prepared : @local_run.LocalCapturedTaskPublicationPreflight[Ref[Int], Int]?
  mut capacity : (@resources.Ledger, @resources.CapacityReservation)?
  mut request_started : Bool
  mut request_failure : Int?
  mut request_publisher : Int?
  mut capture_started : Bool
}

///|
fn stored_publication_preflight_prepared(
  record : StoredPublicationPreflight,
) -> Bool {
  match record.origin {
    ComputePublicationPreflight(compute) => compute.prepared is Some(_)
    FilePublicationPreflight(file) => file.prepared is Some(_)
    SavedEffectPublicationPreflight(effect) => effect.prepared is Some(_)
  }
}

///|
fn compute_publication_preflight(
  value : Instance,
  compute : Int,
) -> (Int, StoredPublicationPreflight)? {
  for handle, record in value.publication_preflights {
    if record.origin is ComputePublicationPreflight(original) &&
      original.compute == compute {
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
    value.copies.get(input) is Some((input_slot, physical)) else {
    return -2
  }
  if value.closing || value.runtime_closing {
    return -5
  }
  let origin : StoredPublicationPreflightOrigin = if value.run_invocations.get(
      source,
    )
    is Some(
      { closing: false, produced: true, invocation: Some(_), compute, .. }
    ) &&
    value.computes.get(compute) is Some({ closing: false, host: Some(_), .. }) {
    if compute_publication_preflight(value, compute) is Some(_) {
      return -3
    }
    ComputePublicationPreflight({
      source,
      compute,
      prepared: None,
      capacity: None,
    })
  } else if value.submissions.get(source)
    is Some(
      {
        append_plan: EffectFileCompletion(_),
        produced: true,
        output_closed: false,
        ..
      }
    ) {
    if value.publication_preflights
      .values()
      .any(record => {
        record.origin is SavedEffectPublicationPreflight(original) &&
        original.source == source
      }) {
      return -3
    }
    SavedEffectPublicationPreflight({
      source,
      capacity: None,
      prepared: None,
      publisher: None,
      request_attempted: false,
      request_allowed: false,
    })
  } else {
    guard value.physical_starts.get(source)
      is Some({ file_managed: Some(managed), .. }) &&
      !managed.closing &&
      managed.capture_work is Some(work) &&
      work.invocation_ready &&
      !work.closing &&
      !work.failed else {
      return -2
    }
    if file_publication_preflight(value, work) {
      return -3
    }
    FilePublicationPreflight({
      start: source,
      work,
      prepared: None,
      capacity: None,
      request_started: false,
      request_failure: None,
      request_publisher: None,
      capture_started: false,
    })
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
  let wire_limit = if origin is SavedEffectPublicationPreflight(_) ||
    publication_has_model_source(value, source) {
    0
  } else {
    1048576
  }
  let slot = match
    @buffers.reserve_output_buffer(
      value.pool,
      wire_limit,
      physical_copy_bytes,
      () => physical_input_cleanup(physical_ticket) == 0,
    ) {
    Ok(slot) => slot
    Err(issue) => return issue_code(issue)
  }
  let handle = value.next_handle
  let borrow = @buffers.borrow_buffer(value.pool, input_slot, () => {
    physical_reader_stop(physical, handle) == 0
  })
  value.publication_preflights[handle] = {
    origin,
    borrow,
    slot,
    invoked: false,
    pending: false,
    closing: false,
    produced: false,
    output_closed: false,
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
    value.run_configurations.get(current_configuration) is Some(current) else {
    return -2
  }
  match record.origin {
    ComputePublicationPreflight(origin) =>
      prepare_compute_publication_preflight(value, record, origin, current)
    FilePublicationPreflight(origin) =>
      prepare_file_publication_preflight(value, record, origin, current)
    SavedEffectPublicationPreflight(origin) =>
      prepare_saved_effect_publication_preflight(value, record, origin, current)
  }
}

///|
fn prepare_compute_publication_preflight(
  value : Instance,
  record : StoredPublicationPreflight,
  origin : StoredComputePublicationPreflight,
  current : StoredRunConfiguration,
) -> Int {
  guard value.run_invocations.get(origin.source)
    is Some({ closing: false, invocation: Some(invocation), .. }) &&
    value.computes.get(origin.compute) is Some(compute) &&
    !compute.closing &&
    stored_compute_original_run(value, compute)
    is Some({ outcome: Some(Ok(plan)), .. } as original_run) else {
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
  let limits : @local_run.LocalPublicationIntentLimits = {
    max_results: value.workspace_slots,
    max_wire_bytes: 1048576,
    max_nodes: 100000,
    max_depth: 64,
  }
  let input = match
    publication_preflight_input(
      value, compute, original_run, plan, cursor, origin, limits,
    ) {
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
      limits,
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
  origin.prepared = Some(preflight)
  record.pending = false
  if origin.capacity is Some((ledger, reservation, retained)) &&
    @resources.shrink_capacity_reservation(ledger, reservation, retained, 0L)
    is Err(_) {
    return -4
  }
  if !stored_preflight_original_current(value, record, current.account) {
    return -32
  }
  if publication_has_model_source(value, origin.source) {
    let result = status(
      @buffers.supply_buffer_output(value.pool, record.slot, b""),
    )
    if result == 0 {
      record.produced = true
    }
    return result
  }
  let (request, attempt) = @local_run.local_publication_preflight_contracts(
    preflight,
  )
  supply_publication_preflight(value, record, request, attempt)
}

///|
fn supply_publication_preflight(
  value : Instance,
  record : StoredPublicationPreflight,
  request : @publication.PublicationContract,
  attempt : @publication.PublicationContract,
) -> Int {
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
  let origin = match record.origin {
    ComputePublicationPreflight(origin) => origin
    SavedEffectPublicationPreflight(origin) =>
      return !record.closing &&
        saved_effect_publication_preflight_current(value, origin, account) == 0
    FilePublicationPreflight(origin) =>
      return !record.closing &&
        !pending_confirmation &&
        file_publication_preflight_current(value, origin, account) == 0
  }
  guard origin.prepared is Some(preflight) &&
    value.run_invocations.get(origin.source) is Some(source) &&
    source.produced &&
    value.computes.get(origin.compute) is Some(compute) else {
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
  if record.pending ||
    !record.produced ||
    !stored_publication_preflight_prepared(record) {
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
  if record.origin is FilePublicationPreflight(file) &&
    file_preflight_read_active(value, file) {
    return -9
  }
  // A Model task starts before its publication preflight exists. The
  // completed invocation still borrows the task, so retire this exact
  // downstream preflight first. Ordinary tasks keep their prior dependency.
  let task_borrow = if record.origin is ComputePublicationPreflight(original) {
    let completed_model_source = value.run_invocations.get(original.source)
      is Some(
        {
          compute,
          source_free: true,
          produced: true,
          model_issuance: Some(_),
          ..
        }
      ) &&
      compute == original.compute &&
      value.computes.get(compute) is Some({ host: Some(host), .. }) &&
      @local_run.local_compute_model_run(host) is Some(_)
    !completed_model_source &&
    value.tasks.values().any(child => child.compute == original.compute)
  } else {
    false
  }
  if value.publishers.values().any(child => child.parent == handle) ||
    value.publications.values().any(child => child.preflight == handle) ||
    value.result_exports
    .values()
    .any(child => child.origin is FileNamedResult(file) && file.parent == handle) ||
    task_borrow {
    return -9
  }
  if !record.output_closed {
    let result = status(@buffers.close_buffer(value.pool, record.slot))
    if result != 0 {
      return result
    }
    record.output_closed = true
  }
  if record.origin is FilePublicationPreflight(file) {
    let settled = retire_file_publication_preflight(file)
    if settled != 0 {
      return settled
    }
  }
  if record.origin is ComputePublicationPreflight(compute) &&
    compute.capacity is Some((ledger, reservation, _)) {
    compute.prepared = None
    if @resources.settle_capacity(ledger, reservation) is Err(_) {
      return -4
    }
    compute.capacity = None
  }
  if record.origin is SavedEffectPublicationPreflight(effect) &&
    effect.capacity is Some(capacity) {
    if @resources.settle_capacity(value.root, capacity) is Err(_) {
      return -4
    }
    effect.capacity = None
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
    value.publication_preflights.get(handle) is Some(record) &&
    stored_publication_preflight_prepared(record) &&
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
  match record.origin {
    ComputePublicationPreflight({ prepared: Some(preflight), .. }) =>
      @local_run.local_publication_preflight_count(preflight)
    FilePublicationPreflight({ prepared: Some(preflight), .. }) =>
      @local_run.local_captured_task_publication_preflight_count(preflight)
    SavedEffectPublicationPreflight({ prepared: Some(preflight), .. }) =>
      preflight.result_count()
    _ => -2
  }
}
