///|
priv struct StoredSavedEffectPublicationPreflight {
  source : Int
  mut capacity : @resources.CapacityReservation?
  mut prepared : @host.ClientEffectSavedFilePublication?
  mut publisher : Int?
  mut request_attempted : Bool
  mut request_allowed : Bool
}

///|
fn saved_effect_publish_account(
  configuration : StoredRunConfiguration,
) -> Bool {
  @authorization.evaluate_account(configuration.account, {
    ..configuration.tuple, resource: "run", operation: "publish",
  }) is @authorization.Allow(_)
}

///|
fn prepare_saved_effect_publication_preflight(
  value : Instance,
  record : StoredPublicationPreflight,
  origin : StoredSavedEffectPublicationPreflight,
  current : StoredRunConfiguration,
) -> Int {
  if value.closing || record.closing { return -5 }
  if record.invoked || record.pending {
    return if record.produced && saved_effect_publication_preflight_current(value, origin, current.account) == 0 {
      0
    } else { -33 }
  }
  record.invoked = true
  guard value.submissions.get(origin.source) is Some(source) &&
    source.append_plan is EffectFileCompletion(completion) &&
    value.run_configurations.get(source.configuration) is Some(configuration) &&
    physical_equal(configuration, current) &&
    saved_effect_publish_account(current) &&
    current.sdk is Some(sdk) &&
    current.host_current is Some(handle) &&
    value.host_currents.get(handle) is Some(adopted) &&
    adopted.generation is Some((device, inode)) else {
    return -32
  }
  let code = validate_saved_effect_file_completion(value, source, current)
  if code != 0 { return code }
  let borrow = match record.borrow {
    Ok(value) => value
    Err(issue) => return issue_code(issue)
  }
  guard input_cursor(value, borrow.slot) is Some(cursor) &&
    sdk_publication_preflight_clock(cursor) is Ok(clock) &&
    @host.client_publication_store_binding_body(
      current.run_namespace, sdk.store_authority_cid, device, inode,
    ) is Ok(binding) else {
    return -31
  }
  let count = completion.original.result_count()
  let quote = @host.client_protocol_metadata_construction_bytes(
    4096 + 1024 * count, 60L + 16L * count.to_int64(),
  )
  guard count > 0 && count <= value.workspace_slots &&
    quote is Some((bytes, _)) &&
    @resources.reserve_capacity(value.root, 0L, bytes) is Ok(capacity) else {
    return -4
  }
  origin.capacity = Some(capacity)
  record.pending = true
  let prepared = completion.original.prepare_publication(
    current.account, current.tuple, current.run_namespace, sdk.store_authority_cid, binding,
    clock.attempt_id, clock.fence_cid, clock.external_idempotency_key, clock.at,
    { max_wire_bytes: 1048576, max_nodes: 100000, max_depth: 64 },
  )
  record.pending = false
  guard prepared is Ok(prepared) else { return -32 }
  origin.prepared = Some(prepared)
  let code = validate_saved_effect_file_completion(value, source, current)
  if code != 0 { return code }
  let code = status(@buffers.supply_buffer_output(value.pool, record.slot, b""))
  if code == 0 { record.produced = true }
  code
}

///|
fn saved_effect_publication_preflight_current(
  value : Instance,
  origin : StoredSavedEffectPublicationPreflight,
  account : @authorization.AdmittedAccountConfiguration,
) -> Int {
  guard origin.prepared is Some(_) &&
    value.submissions.get(origin.source) is Some(source) &&
    value.run_configurations.get(source.configuration) is Some(configuration) &&
    physical_equal(configuration.account, account) &&
    saved_effect_publish_account(configuration) else {
    return -32
  }
  validate_saved_effect_file_completion(value, source, configuration)
}

///|
fn install_saved_effect_preflight_publisher(
  value : Instance,
  child : StoredPublisher,
  origin : StoredSavedEffectPublicationPreflight,
  current_handle : Int,
  current : StoredRunConfiguration,
) -> Int {
  guard origin.prepared is Some(prepared) &&
    origin.publisher is None &&
    child.borrow is Ok(borrow) &&
    input_cursor(value, borrow.slot) is Some(cursor) &&
    @decode.closed_object(cursor, []) is Ok(_) else {
    return -32
  }
  let code = saved_effect_publication_preflight_current(value, origin, current.account)
  if code != 0 { return code }
  let (request, attempt, store) = prepared.contracts()
  child.configuration = current_handle
  child.unknown = false
  match @publication.install_publication_publisher_port(
    request, attempt, store,
    () => publisher_current(value, child),
    fact => publisher_authorize(child, fact),
  ) {
    Ok(port) => {
      child.port = Some(port)
      child.store = store
      0
    }
    Err(issue) => publisher_check_status(child, Err(issue))
  }
}

///|
fn authorize_saved_effect_preflight_request(
  value : Instance,
  handle : Int,
  child : StoredPublisher,
  origin : StoredSavedEffectPublicationPreflight,
  port : @publication.PublicationPublisherPort,
  current : StoredRunConfiguration,
) -> Int {
  guard origin.prepared is Some(prepared) else { return -33 }
  if origin.request_attempted {
    guard origin.request_allowed && origin.publisher == Some(handle) else { return -33 }
  } else {
    guard origin.publisher is None else { return -33 }
    origin.request_attempted = true
  }
  let code = saved_effect_publication_preflight_current(value, origin, current.account)
  if code != 0 { return code }
  let (request, attempt, store) = prepared.contracts()
  let code = publisher_check_status(child, port.check(request, attempt, store, @publication.Request, None))
  if code != 0 { return code }
  let code = saved_effect_publication_preflight_current(value, origin, current.account)
  if code == 0 {
    origin.publisher = Some(handle)
    origin.request_allowed = true
  }
  code
}

///|
fn select_saved_effect_publication(
  value : Instance,
  source : Int,
) -> (Int, StoredSavedEffectPublicationPreflight)? {
  let mut selected = None
  for handle, preflight in value.publication_preflights {
    if preflight.closing || !preflight.produced { continue }
    guard preflight.origin is SavedEffectPublicationPreflight(original) &&
      original.source == source && original.request_allowed &&
      original.prepared is Some(_) && original.publisher is Some(publisher) &&
      value.publishers.get(publisher) is Some({ closing: false, .. }) else {
      continue
    }
    if selected is Some(_) { return None }
    selected = Some((handle, original))
  }
  selected
}

///|
fn prepare_saved_effect_publication(
  value : Instance,
  record : StoredPublication,
  effect : StoredSavedEffectPublicationPreflight,
  account : @authorization.AdmittedAccountConfiguration,
) -> Int {
  if value.closing || record.closing { return -5 }
  let checked = saved_effect_publication_preflight_current(value, effect, account)
  if checked != 0 { return checked }
  if record.prepared { return 0 }
  if record.invoked { return -33 }
  record.invoked = true
  guard record.borrow is Ok(borrow) &&
    input_cursor(value, borrow.slot) is Some(cursor) &&
    @decode.closed_object(cursor, ["results", "max_work", "max_workspace_slots"]) is Ok(object) &&
    @decode.required(object, "results") is Ok(results) &&
    @decode.elements(results) is Ok(handles) &&
    handles.is_empty() &&
    required_int32(object, "max_work") is Some(max_work) && max_work > 0 &&
    required_int32(object, "max_workspace_slots") is Some(max_workspace) && max_workspace > 0 &&
    effect.prepared is Some(original) && effect.request_allowed else {
    return -31
  }
  let (_, receipt, captured) = original.original_evidence()
  record.max_work = max_work.to_int64()
  record.max_workspace = max_workspace
  record.receipt = Some(receipt)
  record.captured = Some(captured)
  let checked = saved_effect_publication_preflight_current(value, effect, account)
  if checked != 0 { return checked }
  let code = status(@buffers.supply_buffer_output(value.pool, record.slot, b""))
  if code == 0 { record.produced = true }
  code
}

///|
fn prepare_saved_effect_commit(
  value : Instance,
  record : StoredPublication,
  effect : StoredSavedEffectPublicationPreflight,
  account : @authorization.AdmittedAccountConfiguration,
  inputs : Array[@decode.Cursor],
  committed_at : String,
) -> Result[
  (@publication.PublicationContract, @publication.PublicationCommitPreparation),
  Int,
] {
  guard effect.prepared is Some(original) &&
    record.saved_effect_commit_capacity is None else { return Err(-33) }
  let code = saved_effect_publication_preflight_current(value, effect, account)
  if code != 0 { return Err(code) }
  // The immutable bindings belong to the already confirmed payload children.
  // Prepay the candidate/index and its own bounded check before constructing.
  let count = inputs.length().to_int64()
  let mut bytes = 4096L
  let mut nodes = 128L
  for ordinal, cursor in inputs {
    guard @decode.text(cursor) is Ok(wire) &&
      sdk_file_original_payload_binding(value, record, ordinal, wire) is Some(binding) &&
      @publication.publication_contract_wire_usage(binding) is Some((used, fields, _)) else {
      return Err(-35)
    }
    bytes += used.to_int64()
    nodes += fields.to_int64()
  }
  let (manifest, receipt, _) = original.original_evidence()
  let (request, attempt, _) = original.contracts()
  for contract in [manifest, receipt, request, attempt] {
    guard @publication.publication_contract_wire_usage(contract) is Some((used, fields, _)) else {
      return Err(-35)
    }
    bytes += used.to_int64()
    nodes += fields.to_int64()
  }
  guard bytes <= 2147483647L &&
    @host.client_protocol_metadata_construction_bytes(
      bytes.to_int(), nodes + 32L * count, copies=4,
    ) is Some((working, _)) &&
    @resources.reserve_capacity(value.root, 0L, working) is Ok(capacity) else {
    return Err(-4)
  }
  record.saved_effect_commit_capacity = Some(capacity)
  let bindings = Array(capacity=inputs.length())
  for ordinal, cursor in inputs {
    guard @decode.text(cursor) is Ok(wire) &&
      sdk_file_original_payload_binding(value, record, ordinal, wire) is Some(binding) else {
      return Err(-35)
    }
    bindings.push(binding)
  }
  original.prepare_commit(bindings, committed_at, record.max_workspace).map_err(_ => -32)
}

///|
fn authorize_saved_effect_publication(
  value : Instance,
  handle : Int,
  child : StoredPublisher,
  origin : StoredSavedEffectPublicationPreflight,
  port : @publication.PublicationPublisherPort,
  configuration : Int,
  current : StoredRunConfiguration,
  stage : Int,
  publication : Int,
) -> Int {
  guard stage == 1 || stage == 2 else { return -3 }
  guard origin.prepared is Some(prepared) &&
    origin.publisher == Some(handle) && origin.request_allowed &&
    value.publications.get(publication) is Some(record) &&
    record.saved_effect is Some(selected) && physical_equal(origin, selected) &&
    record.preflight == child.parent && record.commit_finished &&
    !record.closing && !record.commit_failed &&
    record.commit_index is Some(index) else {
    return -35
  }
  let code = saved_effect_publication_preflight_current(value, origin, current.account)
  if code != 0 { return code }
  let selection : @publication.PublicationPublisherStage = if stage == 1 {
    guard record.commit is Some(commit) && record.commit_view is Some(view) &&
      commit.view_contract(view, 7) is Ok(retained) && physical_equal(index, retained) else {
      return -35
    }
    @publication.Commit
  } else {
    guard record.observation_checked &&
      record.observation_publisher == Some(handle) &&
      record.observation_index is Some(observed) &&
      same_sdk_file_binding(index, observed) else { return -35 }
    @publication.ReturnCommitted
  }
  let (request, attempt, store) = prepared.contracts()
  child.configuration = configuration
  child.unknown = false
  let code = publisher_check_status(child, port.check(request, attempt, store, selection, Some(index)))
  if code != 0 { return code }
  saved_effect_publication_preflight_current(value, origin, current.account)
}
