///|
/// Private installed Host configuration. Its Account Owner, not a Client
/// supplied grant or policy CID, evaluates authorization for each Program.
priv struct StoredRunConfiguration {
  borrow : @buffers.BufferBorrow
  account : @authorization.AdmittedAccountConfiguration
  tuple : @authorization.AccessTuple
  authority_scope_cid : String
  context_cid : String
  policy_cid : String
  run_namespace : String
}

///|
/// A handle owns the exact input loan before compilation can trap. This
/// record contains references and invocation custody, never durable Run state.
priv struct StoredRun {
  borrow : @buffers.BufferBorrow
  slot : @buffers.BufferSlot
  configuration : Int
  preparation : Int
  mut invoked : Bool
  mut restoration : Int?
  mut physical_start_reserved : Bool
  mut outcome : Result[@local_run.LocalRunPlan, @local_run.LocalRunIssue]?
}

///|
fn required_text(object : @decode.ObjectView, name : String) -> String? {
  match @decode.required(object, name) {
    Ok(cursor) =>
      match @decode.text(cursor) {
        Ok(value) => Some(value)
        Err(_) => None
      }
    Err(_) => None
  }
}

///|
#export_name("actql_run_install_configuration")
pub fn install_run_configuration(nonce : Int64, input : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.copies.get(input) is Some((slot, physical)) else {
    return -2
  }
  if value.next_handle == 2147483647 {
    return -4
  }
  guard input_cursor(value, slot) is Some(cursor) &&
    @decode.closed_object(cursor, [
      "account", "principal", "connection", "resource", "operation", "authority_scope_cid",
      "context_cid", "policy_cid", "namespace",
    ])
    is Ok(object) &&
    required_text(object, "account") is Some(account_wire) &&
    required_text(object, "principal") is Some(principal) &&
    required_text(object, "connection") is Some(connection) &&
    required_text(object, "resource") is Some(resource) &&
    required_text(object, "operation") is Some(operation) &&
    required_text(object, "authority_scope_cid") is Some(authority_scope_cid) &&
    required_text(object, "context_cid") is Some(context_cid) &&
    required_text(object, "policy_cid") is Some(policy_cid) &&
    required_text(object, "namespace") is Some(run_namespace) &&
    @authorization.admit_account_configuration_json(account_wire) is Ok(account) else {
    return -30
  }
  let handle = value.next_handle
  let borrow = match
    @buffers.borrow_buffer(value.pool, slot, () => {
      physical_reader_stop(physical, handle) == 0
    }) {
    Ok(borrow) => borrow
    Err(issue) => return issue_code(issue)
  }
  value.run_configurations[handle] = {
    borrow,
    account,
    tuple: { principal, connection, resource, operation, },
    authority_scope_cid,
    context_cid,
    policy_cid,
    run_namespace,
  }
  value.next_handle += 1
  handle
}

///|
/// The issued handle precedes compilation. Reservation neither accepts a
/// Submission nor invokes Source, Compute, Model, Effect or durable storage.
#export_name("actql_run_reserve")
pub fn reserve_run(
  nonce : Int64,
  configuration : Int,
  preparation : Int,
  input : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.run_configurations.contains(configuration) &&
    value.preparations.get(preparation) is Some(prepared) &&
    prepared.outcome is Some(Ok(_)) &&
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
  value.runs[handle] = {
    borrow,
    slot,
    configuration,
    preparation,
    invoked: false,
    restoration: None,
    physical_start_reserved: false,
    outcome: None,
  }
  value.next_handle += 1
  handle
}

///|
/// Compilation/readiness is not durable Run acceptance or physical start.
/// A interrupted invocation cannot silently recompile under the same handle.
#export_name("actql_run_prepare")
pub fn prepare_run(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.runs.get(handle) is Some(record) &&
    value.run_configurations.get(record.configuration) is Some(configuration) &&
    value.preparations.get(record.preparation) is Some(preparation) &&
    preparation.outcome is Some(Ok(input)) else {
    return -2
  }
  if record.restoration is Some(_) {
    return -3
  }
  if record.outcome is Some(_) {
    return 0
  }
  if record.invoked {
    return -33
  }
  record.invoked = true
  guard input_cursor(value, record.slot) is Some(cursor) &&
    @decode.closed_object(cursor, [
      "caller_request_id", "run_id", "created_at", "valid_until",
    ])
    is Ok(object) &&
    required_text(object, "caller_request_id") is Some(caller_request_id) &&
    required_text(object, "run_id") is Some(run_id) &&
    required_text(object, "created_at") is Some(created_at) &&
    required_text(object, "valid_until") is Some(valid_until) else {
    return -31
  }
  let prepared = @preparation.local_prepared_program(input)
  let permit = match
    @authorization.bind_dispatch_authorization(
      configuration.account,
      configuration.tuple,
      @authorization.Activation,
      @host.prepared_client_identity(prepared).program_definition_cid,
      configuration.context_cid,
    ) {
    Ok(value) => value
    Err(_) => {
      record.outcome = Some(Err(@local_run.AuthorizationMismatch))
      return 0
    }
  }
  let prepare = if @host.prepared_client_acquisition_count(prepared) == 0 {
    @local_run.prepare_source_free_local_run
  } else {
    @local_run.prepare_captured_source_local_run
  }
  record.outcome = Some(
    prepare(
      input,
      configuration.authority_scope_cid,
      caller_request_id,
      permit,
      configuration.account,
      configuration.tuple,
      configuration.context_cid,
      configuration.policy_cid,
      configuration.run_namespace,
      run_id,
      created_at,
      valid_until,
    ),
  )
  0
}

///|
/// Restore the original request and codec-retained Run under current installed
/// authorization. This does not reserve a durable dispatch or start a task.
#export_name("actql_run_restore")
pub fn restore_run(nonce : Int64, handle : Int, materials : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.runs.get(handle) is Some(record) &&
    value.run_configurations.get(record.configuration) is Some(configuration) &&
    value.preparations.get(record.preparation) is Some(preparation) &&
    preparation.outcome is Some(Ok(input)) &&
    value.restorations.get(materials) is Some(restoration) &&
    restoration.outcome is Some(Ok(restored)) &&
    restoration.expected_definition_cid is Some(definition_cid) else {
    return -2
  }
  if (record.restoration is Some(previous) && previous != materials) ||
    (record.invoked && record.restoration is None) {
    return -3
  }
  if record.outcome is Some(_) {
    return 0
  }
  if record.invoked {
    return -33
  }
  record.restoration = Some(materials)
  record.invoked = true
  guard @buffers.buffer_wire(value.pool, record.slot) is Some(bytes) else {
    return -5
  }
  let request_wire = @utf8.decode(bytes) catch { _ => return -12 }
  guard @host.admit_client_request_identity_record_wire(request_wire)
    is Ok(retained_request) else {
    return -31
  }
  let permit = match
    @authorization.bind_dispatch_authorization(
      configuration.account,
      configuration.tuple,
      @authorization.Activation,
      @host.prepared_client_identity(@preparation.local_prepared_program(input)).program_definition_cid,
      configuration.context_cid,
    ) {
    Ok(permit) => permit
    Err(_) => {
      record.outcome = Some(Err(@local_run.AuthorizationMismatch))
      return 0
    }
  }
  let restore = if @host.prepared_client_acquisition_count(
      @preparation.local_prepared_program(input),
    ) ==
    0 {
    @local_run.restore_source_free_local_run_from_materials
  } else {
    @local_run.restore_captured_source_local_run_from_materials
  }
  record.outcome = Some(
    restore(
      input,
      restored,
      definition_cid,
      retained_request,
      configuration.authority_scope_cid,
      permit,
      configuration.account,
      configuration.tuple,
      configuration.context_cid,
      configuration.policy_cid,
    ),
  )
  0
}

///|
/// Private readiness codes are not public diagnostic classifications.
#export_name("actql_run_prepared")
pub fn run_prepared(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) && value.runs.get(handle) is Some(record) else {
    return -2
  }
  match record.outcome {
    Some(Ok(_)) => 0
    Some(Err(_)) => -32
    None => -33
  }
}

///|
#export_name("actql_run_close")
pub fn close_run(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) && value.runs.get(handle) is Some(record) else {
    return -2
  }
  if value.materials.values().any(material => material.run == handle) ||
    value.physical_starts.values().any(start => start.run == handle) ||
    value.native_sources.values().any(source => source.run == handle) {
    return -9
  }
  let result = status(@buffers.return_buffer_borrow(value.pool, record.borrow))
  if result == 0 {
    value.runs.remove(handle) |> ignore
  }
  result
}

///|
#export_name("actql_run_close_configuration")
pub fn close_run_configuration(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.run_configurations.get(handle) is Some(record) else {
    return -2
  }
  if value.runs.values().any(run => run.configuration == handle) ||
    value.physical_starts
    .values()
    .any(start => start.current_configuration == handle) {
    return -9
  }
  let result = status(@buffers.return_buffer_borrow(value.pool, record.borrow))
  if result == 0 {
    value.run_configurations.remove(handle) |> ignore
  }
  result
}
