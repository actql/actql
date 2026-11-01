///|
/// Existing Core materials codec admission, not recovery state or an IO grant.
/// The original immutable input loan survives a trap or failed physical stop.
priv struct StoredRestoration {
  borrow : @buffers.BufferBorrow
  mut invoked : Bool
  mut expected_definition_cid : String?
  mut outcome : Result[@host.ClientTaskRunMaterials, @local_run.LocalRunIssue]?
  mut sdk_configuration : Int?
  mut sdk_submission : Int?
  mut saved_original : @host.ClientSavedTaskMaterials?
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
    sdk_configuration: None,
    sdk_submission: None,
    saved_original: None,
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
/// Select and decode only the task material read with the actual saved Run.
/// The input is the same RunRef loan used by the completed lookup. It carries
/// no claimed material, expected CID, policy, preparation or retry authority.
pub fn restore_sdk_material(
  nonce : Int64,
  handle : Int,
  configuration_handle : Int,
  submission : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.restorations.get(handle) is Some(record) &&
    value.run_configurations.get(configuration_handle) is Some(configuration) &&
    configuration.sdk is Some(_) &&
    value.submissions.get(submission) is Some(lookup) &&
    lookup.configuration == configuration_handle &&
    (lookup.kind == 5 || lookup.kind == 8) &&
    lookup.produced &&
    !lookup.output_closed &&
    lookup.borrow is Ok(borrow) &&
    physical_equal(borrow.slot, record.borrow.slot) else {
    return -2
  }
  if (
      record.sdk_configuration is Some(original) &&
      original != configuration_handle
    ) ||
    (record.sdk_submission is Some(original) && original != submission) {
    return -3
  }
  match run_configuration_current(value, configuration) {
    Ok(_) => ()
    Err(code) => return code
  }
  if record.outcome is Some(Err(_)) {
    return 0
  }
  if record.outcome is Some(Ok(_)) {
    return match sdk_restoration_snapshot(value, record) {
      Ok(_) => 0
      Err(code) => code
    }
  }
  if record.invoked {
    return -33
  }
  record.sdk_configuration = Some(configuration_handle)
  record.sdk_submission = Some(submission)
  record.invoked = true
  let snapshot = match observe_submission_lookup(value, lookup, configuration) {
    Ok(Some(snapshot)) => snapshot
    Ok(None) => return -42
    Err(code) => return code
  }
  guard @host.client_saved_submission_record(snapshot).run_admission
    is Some((_, definition_cid, _)) &&
    @host.client_saved_submission_task_materials_original(snapshot)
    is Some(wire) else {
    return -42
  }
  record.expected_definition_cid = Some(definition_cid)
  let restored = match
    @local_run.restore_local_run_materials(wire, definition_cid) {
    Ok(value) => value
    Err(issue) => {
      record.outcome = Some(Err(issue))
      return 0
    }
  }
  let original = match
    @host.bind_client_saved_submission_task_materials(snapshot, restored) {
    Ok(value) => value
    Err(_) => return -35
  }
  // Canonical material admission may do bounded work, but it cannot let a
  // concurrently changed original row supply this completed invocation.
  match
    observe_submission_lookup(
      value,
      lookup,
      configuration,
      original=Some(snapshot),
    ) {
    Ok(Some(_)) => ()
    Ok(None) => return -42
    Err(code) => return code
  }
  record.saved_original = Some(original)
  record.outcome = Some(Ok(restored))
  0
}

///|
/// Reobserve actual current rows while keeping the same admitted material and
/// immutable request/intent/definition. Legitimate control revisions may move;
/// current and every nested original still pass their existing full reader.
fn sdk_restoration_snapshot(
  value : Instance,
  record : StoredRestoration,
) -> Result[@host.ClientSavedSubmissionSnapshot, Int] {
  guard record.sdk_configuration is Some(configuration_handle) &&
    value.run_configurations.get(configuration_handle) is Some(configuration) &&
    configuration.sdk is Some(_) &&
    record.sdk_submission is Some(submission) &&
    value.submissions.get(submission) is Some(lookup) &&
    lookup.configuration == configuration_handle &&
    (lookup.kind == 5 || lookup.kind == 8) &&
    lookup.produced &&
    !lookup.output_closed &&
    record.saved_original is Some(original) &&
    record.outcome is Some(Ok(materials)) else {
    return Err(-2)
  }
  let snapshot = match observe_submission_lookup(value, lookup, configuration) {
    Ok(Some(snapshot)) => snapshot
    Ok(None) => return Err(-42)
    Err(code) => return Err(code)
  }
  let actual = match
    @host.bind_client_saved_submission_task_materials(snapshot, materials) {
    Ok(value) => value
    Err(_) => return Err(-35)
  }
  if @host.client_submitted_intent_wire(
      @host.client_saved_task_materials_intent(actual),
    ) !=
    @host.client_submitted_intent_wire(
      @host.client_saved_task_materials_intent(original),
    ) {
    return Err(-45)
  }
  guard @host.client_saved_submission_run_row(
      @host.client_saved_task_materials_snapshot(original),
    )
    is Some(before) &&
    @host.client_saved_submission_run_row(snapshot) is Some(after) &&
    @host.decode_client_run_journal_row_with_observation_originals(before.body)
    is Ok((before_run, before_policy, before_observation)) &&
    @host.decode_client_run_journal_row_with_observation_originals(after.body)
    is Ok((after_run, after_policy, after_observation)) else {
    return Err(-35)
  }
  if before_run.publication_policy_originals !=
    after_run.publication_policy_originals ||
    before_policy != after_policy ||
    before_observation != after_observation {
    return Err(-35)
  }
  Ok(snapshot)
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
  if value.runs.values().any(run => run.restoration == Some(handle)) ||
    value.preparations
    .values()
    .any(preparation => preparation.restoration == Some(handle)) {
    return -9
  }
  let result = status(@buffers.return_buffer_borrow(value.pool, record.borrow))
  if result == 0 {
    value.restorations.remove(handle) |> ignore
  }
  result
}
