///|
/// Borrow the original source-free Compute/input. No Source evidence, task
/// activation, current publisher permission or durable outcome is synthesized.
pub fn reserve_source_free_invocation(
  nonce : Int64,
  compute : Int,
  input : Int,
  physical_ticket : Int,
  physical_copy_bytes : Int64,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.computes.get(compute)
    is Some(
      {
        origin: SourceFree(_, _),
        closing: false,
        outcome: Some(Ok(_)),
        host: Some(_),
        start: Some(_),
        ..
      }
    ) &&
    value.copies.get(input) is Some((input_slot, physical)) else {
    return -2
  }
  reserve_run_invocation_output(
    value, compute, input_slot, physical, physical_ticket, physical_copy_bytes, true,
  )
}

///|
pub fn prepare_source_free_invocation(
  nonce : Int64,
  handle : Int,
  current_configuration : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.run_invocations.get(handle) is Some(record) &&
    record.source_free &&
    value.computes.get(record.compute)
    is Some(
      {
        origin: SourceFree(_, _),
        closing: false,
        host: Some(host),
        start: Some(start),
        ..
      }
    ) &&
    value.run_configurations.get(current_configuration) is Some(current) else {
    return -2
  }
  if value.closing || value.runtime_closing || record.closing {
    return -5
  }
  if record.invoked || record.pending {
    return -33
  }
  match run_configuration_current(value, current) {
    Ok(_) => ()
    Err(code) => return code
  }
  record.invoked = true
  let borrow = match record.borrow {
    Ok(borrow) => borrow
    Err(issue) => return issue_code(issue)
  }
  guard input_cursor(value, borrow.slot) is Some(cursor) &&
    @decode.closed_object(cursor, []) is Ok(_) else {
    return -31
  }
  record.pending = true
  let invocation = @local_run.issue_local_source_free_invocation(
    host,
    start,
    current.account,
  )
  record.pending = false
  let invocation = match invocation {
    Ok(invocation) => invocation
    Err(_) => return -32
  }
  // Keep the nominal invocation if encoding or output cleanup fails.
  record.invocation = Some(invocation)
  let writer = @encode.writer(65536, 3, 1) catch { _ => return -34 }
  let wire = try {
    @encode.begin_object(writer)
    @encode.key(writer, "observation")
    @encode.string_value(
      writer,
      @publication.run_evidence_value_json(
        @local_run.local_run_invocation_observation(invocation),
      ),
    )
    @encode.key(writer, "invocation")
    @encode.string_value(
      writer,
      @publication.publication_contract_json(
        @local_run.local_run_invocation_contract(invocation),
      ),
    )
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
pub fn source_free_invocation_length(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.run_invocations.get(handle) is Some(record) &&
    record.source_free else {
    return -2
  }
  run_invocation_length(value, record)
}

///|
pub fn close_source_free_invocation(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.run_invocations.get(handle) is Some(record) &&
    record.source_free else {
    return -2
  }
  close_run_invocation(value, handle, record)
}
