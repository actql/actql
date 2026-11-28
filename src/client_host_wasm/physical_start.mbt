///|
/// Immutable physical fact loan and the existing Owner's result for one exact
/// Run. This invocation custody is not a durable admission or recovery record.
priv struct StoredPhysicalStart {
  run : Int
  current_configuration : Int
  borrow : @buffers.BufferBorrow
  mut invoked : Bool
  mut outcome : Result[
    @local_run.LocalRunPhysicalStart,
    @local_run.LocalRunIssue,
  ]?
  sdk_step : Int?
  mut file_managed : StoredSDKFileManaged?
  mut model_file : StoredPortableModelFileWork?
  mut mock_managed : @local_host.ClientInstalledManagedRun?
  mut mock_effect_compute : StoredMockEffectCompute?
  mut mock_effect_compute_started : Bool
}

///|
fn required_boolean(object : @decode.ObjectView, name : String) -> Bool? {
  match @decode.required(object, name) {
    Ok(cursor) => @decode.boolean(cursor).to_option()
    Err(_) => None
  }
}

///|
/// Inspect retained physical journal facts before the Host's atomic dispatch
/// reservation. This pure projection neither stores a reservation nor permits
/// Source or Compute. The separate physical-start Owner remains mandatory.
pub fn dispatch_action(
  nonce : Int64,
  run : Int,
  current_configuration : Int,
  input : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.runs.get(run) is Some({ outcome: Some(Ok(plan)), .. }) &&
    value.run_configurations.get(current_configuration) is Some(current) &&
    value.copies.get(input) is Some((slot, _)) else {
    return -2
  }
  if value.closing || value.runtime_closing {
    return -5
  }
  guard input_cursor(value, slot) is Some(cursor) &&
    @decode.closed_object(cursor, [
      "request", "definition_cid", "reserved", "physically_unstarted", "cancellation_requested",
      "pre_start_failure_confirmed",
    ])
    is Ok(object) &&
    required_text(object, "request") is Some(wire) &&
    @host.admit_client_request_identity_record_wire(wire) is Ok(request) &&
    required_text(object, "definition_cid") is Some(definition_cid) &&
    required_boolean(object, "reserved") is Some(reserved) &&
    required_boolean(object, "physically_unstarted") is Some(_) &&
    required_boolean(object, "cancellation_requested") is Some(_) &&
    required_boolean(object, "pre_start_failure_confirmed") is Some(_) else {
    return -31
  }
  match run_configuration_current(value, current) {
    Ok(_) => ()
    Err(code) => return code
  }
  let subject = @host.prepared_client_identity(
      @local_run.local_run_prepared(plan),
    ).program_definition_cid
  let permit = match
    @authorization.bind_dispatch_authorization(
      current.account,
      current.tuple,
      @authorization.Activation,
      subject,
      current.context_cid,
    ) {
    Ok(permit) => permit
    Err(_) => return -32
  }
  match
    @local_run.prepare_local_run_start(
      plan,
      request,
      definition_cid,
      reserved,
      permit,
      current.account,
      current.tuple,
      current.context_cid,
    ) {
    Ok(@host.ReserveDispatch) => 1
    Ok(@host.ReconcileReservedDispatch) => 2
    Err(_) => -32
  }
}

///|
/// The physical Host retains custody before Owner evaluation can be interrupted.
/// It supplies journal facts; neither authored input nor a Client controls them.
pub fn reserve_physical_start(
  nonce : Int64,
  run : Int,
  current_configuration : Int,
  input : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.runs.get(run) is Some(original) &&
    original.outcome is Some(Ok(_)) &&
    value.run_configurations.contains(current_configuration) &&
    value.copies.get(input) is Some((slot, physical)) else {
    return -2
  }
  if value.next_handle == 2147483647 {
    return -4
  }
  if value.run_configurations[current_configuration].sdk is Some(_) {
    // SDK start facts must come from the original Store/Owner projection.
    return -3
  }
  // One original pre-I/O start invocation. An unknown or rejected result does
  // not permit another handle to bypass the retained invocation.
  if original.physical_start_reserved {
    return -3
  }
  let handle = value.next_handle
  let borrow = match
    @buffers.borrow_buffer(value.pool, slot, () => {
      physical_reader_stop(physical, handle) == 0
    }) {
    Ok(borrow) => borrow
    Err(issue) => return issue_code(issue)
  }
  value.physical_starts[handle] = {
    run,
    current_configuration,
    borrow,
    invoked: false,
    outcome: None,
    sdk_step: None,
    file_managed: None,
    model_file: None,
    mock_managed: None,
    mock_effect_compute: None,
    mock_effect_compute_started: false,
  }
  original.physical_start_reserved = true
  value.next_handle += 1
  handle
}

///|
/// Read the exact retained request and physical facts once. Only the existing
/// common Run start Owner decides whether they permit physical work.
pub fn confirm_physical_start(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.physical_starts.get(handle) is Some(record) else {
    return -2
  }
  if sdk_file_physical_claim(value, record) is Some((step, claim)) {
    return adopt_sdk_file_physical_start(value, handle, record, step, claim)
  }
  if mock_effect_physical_claim(value, record) is Some((step, claim)) {
    return adopt_mock_effect_physical_start(value, record, step, claim)
  }
  guard value.runs.get(record.run) is Some({ outcome: Some(Ok(plan)), .. }) &&
    value.run_configurations.get(record.current_configuration) is Some(current) else {
    return -2
  }
  if record.sdk_step is Some(step) {
    return validate_sdk_start_claim(value, step, plan)
  }
  if record.outcome is Some(_) {
    return 0
  }
  if record.invoked {
    return -33
  }
  match run_configuration_current(value, current) {
    Ok(_) => ()
    Err(code) => return code
  }
  record.invoked = true
  guard input_cursor(value, record.borrow.slot) is Some(cursor) &&
    @decode.closed_object(cursor, [
      "request", "definition_cid", "reserved", "physically_unstarted", "cancellation_requested",
      "pre_start_failure_confirmed",
    ])
    is Ok(object) &&
    required_text(object, "request") is Some(wire) &&
    @host.admit_client_request_identity_record_wire(wire) is Ok(request) &&
    required_text(object, "definition_cid") is Some(definition_cid) &&
    required_boolean(object, "reserved") is Some(reserved) &&
    required_boolean(object, "physically_unstarted") is Some(unstarted) &&
    required_boolean(object, "cancellation_requested") is Some(cancelled) &&
    required_boolean(object, "pre_start_failure_confirmed") is Some(failed) else {
    return -31
  }
  let subject = @host.prepared_client_identity(
      @local_run.local_run_prepared(plan),
    ).program_definition_cid
  let permit = match
    @authorization.bind_dispatch_authorization(
      current.account,
      current.tuple,
      @authorization.Activation,
      subject,
      current.context_cid,
    ) {
    Ok(permit) => permit
    Err(_) => {
      record.outcome = Some(Err(@local_run.AuthorizationMismatch))
      return 0
    }
  }
  record.outcome = Some(
    @local_run.confirm_local_run_physical_start(
      plan,
      request,
      definition_cid,
      reserved,
      unstarted,
      cancelled,
      failed,
      permit,
      current.account,
      current.tuple,
      current.context_cid,
    ),
  )
  0
}

///|
/// Private readiness only: zero does not prove a durable acceptance or dispatch.
pub fn physical_start_ready(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.physical_starts.get(handle) is Some(record) else {
    return -2
  }
  if sdk_file_physical_claim(value, record) is Some((step, claim)) {
    return check_sdk_file_physical_start(value, handle, record, step, claim)
  }
  if mock_effect_physical_claim(value, record) is Some((step, claim)) {
    return check_mock_effect_physical_start(value, record, step, claim)
  }
  if record.sdk_step is Some(step) {
    guard value.runs.get(record.run) is Some({ outcome: Some(Ok(plan)), .. }) else {
      return -2
    }
    let code = validate_sdk_start_claim(value, step, plan)
    if code != 0 {
      return code
    }
  }
  match record.outcome {
    Some(Ok(_)) => 0
    Some(Err(_)) => -32
    None => -33
  }
}

///|
pub fn close_physical_start(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.physical_starts.get(handle) is Some(record) else {
    return -2
  }
  if record.file_managed is Some({ capture_work: Some(work), .. }) &&
    file_publication_preflight(value, work) {
    return -9
  }
  if record.file_managed is Some({ source: { capture: Some(source), .. }, .. }) &&
    value.original_metadata.contains(source) {
    return -9
  }
  if record.model_file is Some({ source: { capture: Some(source), .. }, .. }) &&
    value.original_metadata.contains(source) {
    return -9
  }
  if value.native_attempts.values().any(attempt => attempt.start == handle) ||
    value.computes
    .values()
    .any(compute => compute.origin is SourceFree(_, start) && start == handle) {
    return -9
  }
  if value.original_metadata
    .values()
    .any(child => {
      match child.project {
        Some(MockEffectCapture(capture)) => capture.start == handle
        Some(MockEffectReviewRead(start)) => start == handle
        Some(MockEffectWaiting(waiting)) => waiting.start == handle
        _ => false
      }
    }) {
    return -9
  }
  let retired = retire_mock_effect_physical_start(value, record)
  if retired != 0 {
    return retired
  }
  let file_retired = retire_sdk_file_physical_start(value, record)
  if file_retired != 0 {
    return file_retired
  }
  let model_retired = retire_portable_model_file_source(record)
  if model_retired != 0 {
    return model_retired
  }
  let result = status(@buffers.return_buffer_borrow(value.pool, record.borrow))
  if result == 0 {
    value.physical_starts.remove(handle) |> ignore
  }
  result
}
