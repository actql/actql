///|
/// Trusted installed physical binding, separate from authored input and Run
/// activation. Its immutable loan precedes any interrupted configuration.
priv struct StoredNativeSourceConfiguration {
  run : Int
  borrow : @buffers.BufferBorrow
  mut invoked : Bool
  mut attempt_reserved : Bool
  mut capacity : @resources.LedgerLimits?
  mut outcome : Result[
    @local_run.LocalNativeSourceConfiguration,
    @local_run.LocalNativeSourceIssue,
  ]?
}

///|
fn optional_text(
  object : @decode.ObjectView,
  name : String,
) -> Result[String?, Unit] {
  match @decode.field(object, name) {
    Missing => Ok(None)
    ExplicitNull => Err(())
    Present(cursor) =>
      match @decode.text(cursor) {
        Ok(text) => Ok(Some(text))
        Err(_) => Err(())
      }
  }
}

///|
fn required_int32(object : @decode.ObjectView, name : String) -> Int? {
  match @decode.required(object, name) {
    Ok(cursor) => @decode.int32(cursor).to_option()
    Err(_) => None
  }
}

///|
pub fn reserve_native_source_configuration(
  nonce : Int64,
  run : Int,
  input : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.runs.get(run) is Some(original) &&
    original.outcome is Some(Ok(_)) &&
    value.copies.get(input) is Some((slot, physical)) else {
    return -2
  }
  if value.next_handle == 2147483647 {
    return -4
  }
  if original.native_source_reserved {
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
  value.native_sources[handle] = {
    run,
    borrow,
    invoked: false,
    attempt_reserved: false,
    capacity: None,
    outcome: None,
  }
  original.native_source_reserved = true
  value.next_handle += 1
  handle
}

///|
/// Core derives the exact checked requirement and admits the Native receipt
/// contracts. Installed Source metadata, a Run permit and a read account are
/// not physical invocation, settlement or a verified Source capture.
pub fn configure_native_source(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.native_sources.get(handle) is Some(record) &&
    value.runs.get(record.run) is Some({ outcome: Some(Ok(plan)), .. }) else {
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
    @decode.closed_object(cursor, [
      "stage", "source_index", "registry", "values", "fragment", "ordered", "database_schema",
      "table", "query_contract", "evidence_contract", "two_receipt_contract", "read_account",
      "read_principal", "read_connection", "read_resource", "read_operation", "read_context_cid",
    ])
    is Ok(object) &&
    required_int32(object, "stage") is Some(stage) &&
    required_int32(object, "source_index") is Some(source_index) &&
    required_text(object, "registry") is Some(registry) &&
    registry == value.installed_sequences.registry &&
    required_text(object, "values") is Some(values) &&
    optional_text(object, "fragment") is Ok(fragment) &&
    optional_text(object, "ordered") is Ok(ordered) &&
    required_text(object, "database_schema") is Some(database_schema) &&
    required_text(object, "table") is Some(table) &&
    required_text(object, "query_contract") is Some(query_contract) &&
    required_text(object, "evidence_contract") is Some(evidence_contract) &&
    required_text(object, "two_receipt_contract") is Some(two_receipt_contract) &&
    required_text(object, "read_account") is Some(account_wire) &&
    @authorization.admit_account_configuration_json(account_wire) is Ok(account) &&
    required_text(object, "read_principal") is Some(principal) &&
    required_text(object, "read_connection") is Some(connection) &&
    required_text(object, "read_resource") is Some(resource) &&
    required_text(object, "read_operation") is Some(operation) &&
    required_text(object, "read_context_cid") is Some(context) else {
    return -31
  }
  record.outcome = Some(
    @local_run.configure_local_native_source(
      plan,
      stage,
      source_index,
      value.installed_sequences.contracts,
      values,
      fragment,
      ordered,
      database_schema,
      table,
      query_contract,
      evidence_contract,
      two_receipt_contract,
      { principal, connection, resource, operation, },
      account,
      context,
    ),
  )
  if record.outcome is Some(Ok(configuration)) {
    record.capacity = @local_host.single_captured_local_ledger_limits(
      @local_run.local_run_prepared(plan),
      @local_run.local_native_source_configuration(configuration),
      value.installed_sequences.contracts,
      values,
      fragment,
      ordered,
    )
  }
  0
}

///|
/// Read the existing checked inventory without physical Source acquisition.
/// It is a capacity request, not admission or evidence of successful execution.
pub fn native_source_capacity(
  nonce : Int64,
  handle : Int,
  field : Int,
) -> Int64 {
  guard selected(nonce) is Some(value) &&
    value.native_sources.get(handle) is Some(record) &&
    record.capacity is Some(capacity) else {
    return -2L
  }
  match field {
    0 => capacity.retained_bytes
    1 => capacity.execution_bytes
    2 => capacity.transfer_bytes
    _ => -3L
  }
}

///|
pub fn native_source_configured(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.native_sources.get(handle) is Some(record) else {
    return -2
  }
  match record.outcome {
    Some(Ok(_)) => 0
    Some(Err(_)) => -32
    None => -33
  }
}

///|
/// Private typed construction evidence, not a public Source-disclosure reason
/// or permission to dispatch. The original failed outcome remains unchanged.
pub fn native_source_configuration_issue(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.native_sources.get(handle) is Some(record) else {
    return -2
  }
  match record.outcome {
    None => -33
    Some(Ok(_)) => 0
    Some(Err(issue)) =>
      match issue {
        UnsupportedCapability => 1
        InvalidReadBinding => 2
        ForeignRunStart => 3
        AuthorizationMismatch => 4
        Requirement(_) => 5
        Configuration(issue) =>
          match issue {
            InvalidSource => 61
            InvalidContracts => 62
            Preparation => 63
            Registration => 64
            Candidate => 65
            Selection => 66
          }
        Host(_) => 7
      }
  }
}

///|
pub fn close_native_source_configuration(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.native_sources.get(handle) is Some(record) else {
    return -2
  }
  if value.native_attempts
    .values()
    .any(attempt => attempt.configuration == handle) {
    return -9
  }
  let result = status(@buffers.return_buffer_borrow(value.pool, record.borrow))
  if result == 0 {
    value.native_sources.remove(handle) |> ignore
  }
  result
}
