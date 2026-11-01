///|
/// One nonexecuting report invocation and its original input/output custody.
/// It never owns a checked Program, admission, Run or dispatch authority.
priv struct StoredClientCheck {
  environment : Int
  configuration : Int
  kind : Int
  borrow : Result[@buffers.BufferBorrow, @buffers.BufferIssue]
  slot : @buffers.BufferSlot
  mut invoked : Bool
  mut produced : Bool
  mut output_closed : Bool
}

///|
/// kind=0 exposes only public checking selections to the trusted Host's keyed
/// context encoder. kind=1 reports an exact captured request through Common.
pub fn reserve_client_check(
  nonce : Int64,
  environment : Int,
  configuration : Int,
  input : Int,
  kind : Int,
  physical_ticket : Int,
  physical_copy_bytes : Int64,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.environments.contains(environment) &&
    value.run_configurations.get(configuration) is Some(original) &&
    original.host_current is Some(_) &&
    value.copies.get(input) is Some((input_slot, physical)) else {
    return -2
  }
  if value.closing || value.runtime_closing {
    return -5
  }
  if (kind != 0 && kind != 1) ||
    physical_ticket <= 0 ||
    value.next_handle == 2147483647 ||
    value.copies.values().any(pair => pair.1 == physical_ticket) ||
    value.native_commands
    .values()
    .any(child => child.physical_ticket == physical_ticket) ||
    value.result_chunks
    .values()
    .any(child => child.physical_ticket == physical_ticket) ||
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
  value.client_checks[handle] = {
    environment,
    configuration,
    kind,
    borrow,
    slot,
    invoked: false,
    produced: false,
    output_closed: false,
  }
  value.copies[handle] = (slot, physical_ticket)
  value.next_handle += 1
  handle
}

///|
fn client_check_metadata(
  environment : StoredEnvironment,
  configuration : StoredRunConfiguration,
) -> String raise @encode.EncodeFailure {
  let (reason, outcome) = @preparation.client_program_check_reporting_schema_cids()
  let writer = @encode.writer(262144, 32, 4)
  @encode.begin_object(writer)
  for
    (key, text) in [
      ("compiler", @preparation.client_program_check_compiler_identity()),
      (
        "checking_context",
        @preparation.client_program_check_context_identity(
          environment.environment,
        ),
      ),
      ("reason_schema_cid", reason),
      ("outcome_schema_cid", outcome),
      ("audience", configuration.tuple.principal),
      ("connection", configuration.tuple.connection),
    ] {
    @encode.key(writer, key)
    @encode.string_value(writer, text)
  }
  @encode.end_object(writer)
  @encode.finish(writer)
}

///|
fn client_check_report(
  environment : @checked.CheckEnvironment,
  request : @decode.ObjectView,
) -> String? {
  guard required_text(request, "kind") is Some(kind) &&
    required_text(request, "scope") is Some(scope) &&
    required_text(request, "document") is Some(document) &&
    required_text(request, "format") is Some(format) &&
    required_text(request, "context") is Some(context) &&
    required_text(request, "revision") is Some(revision) &&
    required_text(request, "correlation") is Some(correlation) &&
    optional_text(request, "declarations") is Ok(declarations) &&
    optional_text(request, "parameters") is Ok(parameters) &&
    optional_text(request, "declarations_revision") is Ok(declarations_revision) &&
    optional_text(request, "parameters_revision") is Ok(parameters_revision) &&
    (scope == "bound_input" || scope == "template_only") &&
    !(scope == "template_only" && parameters is Some(_)) &&
    (declarations is Some(_)) == (declarations_revision is Some(_)) &&
    (parameters is Some(_)) == (parameters_revision is Some(_)) else {
    return None
  }
  let publication = try {
    let writer = @encode.writer(4096, 16, 4)
    @encode.begin_object(writer)
    @encode.key(writer, "environmentCid")
    @encode.string_value(writer, @checked.checking_environment_cid(environment))
    @encode.key(writer, "aliases")
    @encode.begin_array(writer)
    @encode.end_array(writer)
    @encode.end_object(writer)
    @encode.finish(writer)
  } catch {
    _ => return None
  }
  if kind == "program" && format == "json" && declarations is None {
    Some(
      @preparation.client_program_check_program(
        document,
        environment,
        publication,
        parameters,
        context,
        revision,
        parameters_revision,
        correlation,
        scope,
        None,
      ),
    )
  } else if kind == "text" {
    Some(
      @preparation.client_program_check_source(
        document,
        format,
        environment,
        publication,
        declarations,
        parameters,
        context,
        revision,
        declarations_revision,
        parameters_revision,
        correlation,
        scope,
        None,
      ),
    )
  } else {
    None
  }
}

///|
pub fn current_client_check(nonce : Int64, handle : Int, current : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.client_checks.get(handle) is Some(record) &&
    !record.output_closed &&
    value.run_configurations.get(record.configuration) is Some(configuration) &&
    configuration.host_current == Some(current) else {
    return -2
  }
  match run_configuration_current(value, configuration) {
    Ok(_) => 0
    Err(code) => code
  }
}

///|
pub fn produce_client_check(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.client_checks.get(handle) is Some(record) &&
    value.environments.get(record.environment) is Some(environment) &&
    value.run_configurations.get(record.configuration) is Some(configuration) else {
    return -2
  }
  if value.closing || value.runtime_closing || record.output_closed {
    return -5
  }
  if record.invoked {
    return -33
  }
  match run_configuration_current(value, configuration) {
    Ok(_) => ()
    Err(code) => return code
  }
  record.invoked = true
  let borrow = match record.borrow {
    Ok(borrow) => borrow
    Err(issue) => return issue_code(issue)
  }
  guard input_cursor(value, borrow.slot) is Some(cursor) else { return -31 }
  let wire = if record.kind == 0 {
    guard @decode.closed_object(cursor, []) is Ok(_) else { return -31 }
    client_check_metadata(environment, configuration) catch {
      _ => return -34
    }
  } else {
    guard @decode.closed_object(cursor, [
        "kind", "scope", "document", "format", "context", "revision", "correlation",
        "declarations", "parameters", "declarations_revision", "parameters_revision",
      ])
      is Ok(request) &&
      client_check_report(environment.environment, request) is Some(wire) else {
      return -31
    }
    wire
  }
  match run_configuration_current(value, configuration) {
    Ok(_) => ()
    Err(code) => return code
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
pub fn client_check_length(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.client_checks.get(handle) is Some(record) &&
    record.produced &&
    !record.output_closed else {
    return -33
  }
  @buffers.buffer_length(value.pool, record.slot).unwrap_or(-33)
}

///|
pub fn close_client_check(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.client_checks.get(handle) is Some(record) else {
    return -2
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
    value.client_checks.remove(handle) |> ignore
    value.copies.remove(handle) |> ignore
  }
  result
}
