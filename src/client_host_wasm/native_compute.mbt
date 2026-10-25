///|
/// Invocation custody around existing captured and source-free Compute Hosts.
/// Configuration is not activation, task success or Result publication.
priv enum ComputeOrigin {
  Captured(Int)
  SourceFree(Int, Int)
}

///|
priv struct StoredNativeCompute {
  origin : ComputeOrigin
  borrow : @buffers.BufferBorrow
  mut current_configuration : Int?
  mut invoked : Bool
  mut pending : Bool
  mut closing : Bool
  mut outcome : Result[Unit, @local_run.LocalComputeIssue]?
  mut host : @local_run.LocalComputeHost?
  mut start : @local_run.LocalComputeStart?
  mut capture : @native_host.NativeHostSourceCapture?
}

///|
fn stored_compute_original_run(
  value : Instance,
  compute : StoredNativeCompute,
) -> StoredRun? {
  match compute.origin {
    Captured(attempt) => {
      guard value.native_attempts.get(attempt) is Some(original) &&
        value.native_sources.get(original.configuration) is Some(source) else {
        return None
      }
      value.runs.get(source.run)
    }
    SourceFree(run, start) => {
      guard value.physical_starts.get(start)
        is Some({ run: original_run, outcome: Some(Ok(_)), .. }) &&
        original_run == run else {
        return None
      }
      value.runs.get(run)
    }
  }
}

///|
#export_name("actql_compute_reserve")
pub fn reserve_native_compute(nonce : Int64, attempt : Int, input : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.native_attempts.get(attempt) is Some(original) &&
    original.outcome is Some(Ok(_)) &&
    original.observation is Some(_) &&
    !original.failed &&
    !original.event_pending &&
    !original.closing &&
    value.copies.get(input) is Some((slot, physical)) else {
    return -2
  }
  if value.closing {
    return -5
  }
  if original.compute_reserved || value.next_handle == 2147483647 {
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
    origin: Captured(attempt),
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
  original.compute_reserved = true
  value.next_handle += 1
  handle
}

///|
#export_name("actql_compute_configure")
pub fn configure_native_compute(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.computes.get(handle) is Some(record) &&
    record.origin is Captured(attempt) &&
    value.native_attempts.get(attempt) is Some(original) &&
    original.outcome is Some(Ok(native)) &&
    original.observation is Some(observation) &&
    value.native_sources.get(original.configuration)
    is Some({ run, outcome: Some(Ok(configuration)), .. }) &&
    value.runs.get(run) is Some({ outcome: Some(Ok(plan)), .. }) &&
    value.physical_starts.get(original.start)
    is Some({ outcome: Some(Ok(start)), .. }) else {
    return -2
  }
  if value.closing || record.closing || original.closing {
    return -5
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
      "read_account", "registry", "values", "fragment", "ordered",
    ])
    is Ok(object) &&
    required_text(object, "read_account") is Some(account_wire) &&
    @authorization.admit_account_configuration_json(account_wire) is Ok(current) &&
    required_text(object, "registry") is Some(registry) &&
    registry == value.installed_sequences.registry &&
    required_text(object, "values") is Some(values) &&
    optional_text(object, "fragment") is Ok(fragment) &&
    optional_text(object, "ordered") is Ok(ordered) else {
    return -31
  }
  guard @local_run.authorize_local_native_source(configuration, current)
    is Ok(_) else {
    record.outcome = Some(Err(@local_run.AuthorizationMismatch))
    return 0
  }
  record.pending = true
  let limits = @native_host.configured_native_host_limits(
    @local_run.local_native_source_configuration(configuration),
  )
  // This installed ABI receives bounded non-streaming receipts. Use the
  // matching existing capture owner, not a retained-stream material that
  // was never staged. The original attempt retains its capacity throughout
  // every Compute and Result consumer.
  let capture = match
    @native_host.capture_native_host_source(
      native,
      observation,
      false,
      limits.output_rows,
      limits.retention,
      limits.output_entries,
      limits.output_name_bytes,
    ) {
    Ok(capture) => capture
    Err(_) => {
      record.outcome = Some(Err(@local_run.Configuration))
      record.pending = false
      return 0
    }
  }
  let source = match @native_host.native_host_source_capture_source(capture) {
    Ok(source) => source
    Err(_) => {
      record.outcome = Some(Err(@local_run.Configuration))
      record.pending = false
      return 0
    }
  }
  record.capture = Some(capture)
  let host = match
    @local_run.configure_captured_source_local_compute_on_ledger(
      plan,
      source,
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
  // Keep the Host even if binding or later cleanup is interrupted.
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

///|
#export_name("actql_compute_configured")
pub fn native_compute_configured(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.computes.get(handle) is Some(record) else {
    return -2
  }
  if record.closing {
    return -5
  }
  match record.outcome {
    None => -33
    Some(Err(_)) => -32
    Some(Ok(_)) =>
      if record.host is Some(_) && record.start is Some(_) {
        0
      } else {
        -33
      }
  }
}

///|
#export_name("actql_compute_close")
pub fn close_native_compute(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.computes.get(handle) is Some(record) else {
    return -2
  }
  record.closing = true
  if record.pending {
    return -33
  }
  if value.run_invocations.values().any(source => source.compute == handle) {
    return -9
  }
  if value.tasks.values().any(task => task.compute == handle) {
    return -9
  }
  if record.host is Some(host) {
    let run = @local_run.local_compute_run(host)
    @strategy.stop_captured_dag(run)
    for
      task in 0..<@strategy.graph_task_count(@strategy.captured_dag_graph(run)) {
      @strategy.close_captured_task_output(run, task)
    }
    @strategy.refresh_captured_retention(run)
    if @strategy.captured_task_retirement_pending(run) {
      return -9
    }
  }
  let result = status(@buffers.return_buffer_borrow(value.pool, record.borrow))
  if result == 0 {
    value.computes.remove(handle) |> ignore
  }
  result
}
