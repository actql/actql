///|
/// Reserve the original source-free Run/start/configuration and input loan.
/// No Native Source, substitute capture, new Ledger or task activation is issued.
pub fn reserve_source_free_compute(
  nonce : Int64,
  run : Int,
  start : Int,
  input : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.runs.get(run) is Some(original) &&
    original.outcome is Some(Ok(_)) &&
    value.physical_starts.get(start)
    is Some({ run: original_run, outcome: Some(Ok(_)), .. }) &&
    original_run == run &&
    value.copies.get(input) is Some((slot, physical)) else {
    return -2
  }
  if value.closing || value.runtime_closing {
    return -5
  }
  if original.source_free_compute_reserved || value.next_handle == 2147483647 {
    return -3
  }
  let handle = value.next_handle
  let borrow = match
    @buffers.borrow_buffer(value.pool, slot, () => {
      physical_reader_stop(physical, handle) == 0
    }) {
    Err(issue) => return issue_code(issue)
    Ok(borrow) => borrow
  }
  value.computes[handle] = {
    origin: SourceFree(run, start),
    borrow,
    current_configuration: None,
    invoked: false,
    pending: false,
    closing: false,
    outcome: None,
    host: None,
    start: None,
    capture: None,
  }
  original.source_free_compute_reserved = true
  value.next_handle += 1
  handle
}

///|
/// The physical Host chooses an installed current configuration independently
/// of the original start facts. A completed invocation cannot be rebound.
pub fn configure_source_free_compute_current(
  nonce : Int64,
  handle : Int,
  current_configuration : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.computes.get(handle) is Some(record) &&
    record.origin is SourceFree(run, start) else {
    return -2
  }
  return configure_source_free_compute(
    value, record, run, start, current_configuration,
  )
}

///|
/// Bind existing Owners to their exact original start and installed root. The
/// current Account is checked again; task/publication preflight is still required.
fn configure_source_free_compute(
  value : Instance,
  record : StoredNativeCompute,
  run : Int,
  start : Int,
  current_configuration : Int,
) -> Int {
  let start_handle = start
  guard value.runs.get(run) is Some({ outcome: Some(Ok(plan)), .. }) &&
    value.physical_starts.get(start)
    is Some({ run: original_run, outcome: Some(Ok(start)), .. }) &&
    original_run == run &&
    value.run_configurations.get(current_configuration) is Some(current) else {
    return -2
  }
  if value.closing || value.runtime_closing || record.closing {
    return -5
  }
  if record.current_configuration is Some(original) &&
    original != current_configuration {
    return -3
  }
  match run_configuration_current(value, current) {
    Ok(_) => ()
    Err(code) => return code
  }
  guard value.physical_starts.get(start_handle) is Some(physical) else {
    return -2
  }
  if physical.sdk_step is Some(step) {
    let code = validate_sdk_start_claim(value, step, plan)
    if code != 0 {
      return code
    }
  }
  if record.outcome is Some(_) {
    return 0
  }
  if record.invoked {
    return -33
  }
  record.current_configuration = Some(current_configuration)
  record.invoked = true
  guard input_cursor(value, record.borrow.slot) is Some(cursor) &&
    @decode.closed_object(cursor, ["registry", "values", "fragment", "ordered"])
    is Ok(object) &&
    required_text(object, "registry") is Some(registry) &&
    registry == value.installed_sequences.registry &&
    required_text(object, "values") is Some(values) &&
    optional_text(object, "fragment") is Ok(fragment) &&
    optional_text(object, "ordered") is Ok(ordered) else {
    return -31
  }
  let subject = @host.prepared_client_identity(
      @local_run.local_run_prepared(plan),
    ).program_definition_cid
  let permit = match
    @authorization.bind_dispatch_authorization(
      current.account,
      current.tuple,
      Activation,
      subject,
      current.context_cid,
    ) {
    Ok(permit) => permit
    Err(_) => {
      record.outcome = Some(Err(@local_run.AuthorizationMismatch))
      return 0
    }
  }
  match
    @local_run.authorize_local_compute_configuration(
      plan,
      permit,
      current.account,
      current.tuple,
      current.context_cid,
    ) {
    Ok(_) => ()
    Err(issue) => {
      record.outcome = Some(Err(issue))
      return 0
    }
  }
  record.pending = true
  let host = match
    @local_run.configure_source_free_local_compute_on_ledger(
      plan,
      value.root,
      value.installed_sequences.contracts,
      values,
      fragment,
      ordered,
    ) {
    Ok(host) => host
    Err(issue) => {
      record.outcome = Some(Err(issue))
      record.pending = false
      return 0
    }
  }
  // Preserve the same Host and loan even when start binding or cleanup fails.
  record.host = Some(host)
  match @local_run.bind_local_compute_start(host, start) {
    Ok(start) => {
      record.start = Some(start)
      record.outcome = Some(Ok(()))
    }
    Err(issue) => record.outcome = Some(Err(issue))
  }
  record.pending = false
  0
}
