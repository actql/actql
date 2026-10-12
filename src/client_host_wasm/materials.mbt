///|
/// Invocation custody and an existing Ledger reservation, never durable Run
/// state. A failed producer keeps this same handle until physical cleanup.
priv struct StoredMaterial {
  run : Int
  kind : Int
  slot : @buffers.BufferSlot
  mut invoked : Bool
  mut produced : Bool
  mut output_closed : Bool
  mut submission : StoredSubmittedMaterial?
}

///|
priv struct StoredSubmittedMaterial {
  current_configuration : Int
  borrow : Result[@buffers.BufferBorrow, @buffers.BufferIssue]
  mut rows : @local_run.LocalSubmittedRunRows?
}

///|
/// Reserve the complete wire allowance before encoding. The original Run
/// remains live until this output retires, including an interrupted export.
#export_name("actql_material_reserve")
pub fn reserve_material(
  nonce : Int64,
  run : Int,
  kind : Int,
  physical_ticket : Int,
  physical_copy_bytes : Int64,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.runs.get(run) is Some({ outcome: Some(Ok(_)), .. }) else {
    return -2
  }
  if kind < 1 || kind > 5 {
    return -3
  }
  reserve_material_record(
    value, run, kind, physical_ticket, physical_copy_bytes,
  )
}

///|
fn reserve_material_record(
  value : Instance,
  run : Int,
  kind : Int,
  physical_ticket : Int,
  physical_copy_bytes : Int64,
) -> Int {
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
  if value.closing || value.runtime_closing {
    return -5
  }
  let slot = match
    @buffers.reserve_output_buffer(value.pool, 1048576, physical_copy_bytes, () => {
      physical_input_cleanup(physical_ticket) == 0
    }) {
    Ok(slot) => slot
    Err(issue) => return issue_code(issue)
  }
  let handle = value.next_handle
  value.materials[handle] = {
    run,
    kind,
    slot,
    invoked: false,
    produced: false,
    output_closed: false,
    submission: None,
  }
  value.copies[handle] = (slot, physical_ticket)
  value.next_handle += 1
  handle
}

///|
/// Original row candidates only. Authentication and complete journal custody
/// must still be observed in the same physical admission transaction.
#export_name("actql_material_reserve_submitted_rows")
pub fn reserve_submitted_rows_material(
  nonce : Int64,
  run : Int,
  current_configuration : Int,
  input : Int,
  physical_ticket : Int,
  physical_copy_bytes : Int64,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.runs.get(run) is Some(record) &&
    record.outcome is Some(Ok(_)) &&
    value.preparations.get(record.preparation) is Some(preparation) &&
    preparation.submitted is Some(_) &&
    value.run_configurations.contains(current_configuration) &&
    value.copies.get(input) is Some((slot, physical)) else {
    return -2
  }
  let handle = reserve_material_record(
    value, run, 6, physical_ticket, physical_copy_bytes,
  )
  if handle <= 0 {
    return handle
  }
  let borrow = @buffers.borrow_buffer(value.pool, slot, () => {
    physical_reader_stop(physical, handle) == 0
  })
  value.materials[handle].submission = Some({
    current_configuration,
    borrow,
    rows: None,
  })
  handle
}

///|
fn submitted_rows_material_wire(
  value : Instance,
  material : StoredMaterial,
  plan : @local_run.LocalRunPlan,
  preparation : StoredPreparation,
) -> Result[String, Int] {
  guard material.submission is Some(submission) &&
    preparation.submitted is Some(original) &&
    value.run_configurations.get(submission.current_configuration)
    is Some(current) else {
    return Err(-2)
  }
  let borrow = match submission.borrow {
    Ok(value) => value
    Err(issue) => return Err(issue_code(issue))
  }
  guard input_cursor(value, borrow.slot) is Some(cursor) &&
    @decode.closed_object(cursor, ["reference", "preparing", "now"])
    is Ok(object) &&
    required_text(object, "reference") is Some(reference) &&
    required_text(object, "preparing") is Some(preparing) &&
    required_number(object, "now") is Some(now) else {
    return Err(-31)
  }
  let reference = match
    @host.admit_client_submission_reference_record(reference) {
    Ok(value) => value
    Err(_) => return Err(-31)
  }
  let permit = match
    @authorization.bind_dispatch_authorization(
      current.account,
      current.tuple,
      @authorization.Activation,
      @host.prepared_client_identity(@local_run.local_run_prepared(plan)).program_definition_cid,
      current.context_cid,
    ) {
    Ok(value) => value
    Err(_) => return Err(-32)
  }
  let rows = match
    @local_run.prepare_local_submitted_run_rows(
      plan,
      original,
      reference,
      @utf8.encode(preparing),
      permit,
      current.account,
      current.tuple,
      current.context_cid,
      now,
    ) {
    Ok(value) => value
    Err(@local_run.AuthorizationMismatch) => return Err(-32)
    Err(_) => return Err(-31)
  }
  submission.rows = Some(rows)
  let fields = match @local_run.local_submitted_run_rows(rows, plan, original) {
    Ok(value) => value
    Err(_) => return Err(-31)
  }
  try {
    let writer = @encode.writer(1048576, 8, 1)
    @encode.begin_object(writer)
    for
      (key, text) in [
        ("run_key", fields.0),
        ("submission_key", fields.1),
        ("preparing", @utf8.decode(fields.2)),
        ("run", @utf8.decode(fields.3)),
        ("submitted", @utf8.decode(fields.4)),
      ] {
      @encode.key(writer, key)
      @encode.string_value(writer, text)
    }
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => Err(-34)
  }
}

///|
/// Project existing Owner records. Encoding is not admission, durable storage,
/// physical start or permission to retry. An interrupted handle is not reused.
#export_name("actql_material_produce")
pub fn produce_material(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.materials.get(handle) is Some(material) &&
    value.runs.get(material.run) is Some(record) &&
    record.outcome is Some(Ok(plan)) &&
    value.preparations.get(record.preparation) is Some(preparation) &&
    preparation.outcome is Some(Ok(input)) &&
    value.environments.get(preparation.environment) is Some(environment) else {
    return -2
  }
  if value.closing || value.runtime_closing || material.output_closed {
    return -5
  }
  if material.produced {
    return 0
  }
  if material.invoked {
    return -33
  }
  guard @buffers.buffer_output_limit(value.pool, material.slot) is Some(_) else {
    return -5
  }
  material.invoked = true
  let wire = match material.kind {
    1 => {
      let body = environment.wire
      match
        @local_run.export_local_run_materials(
          plan,
          environment.environment,
          body,
          None,
        ) {
        Ok(wire) => wire
        Err(_) => return -34
      }
    }
    2 =>
      match
        @host.client_request_identity_record_wire(
          @local_run.local_run_request(plan),
        ) {
        Ok(wire) => wire
        Err(_) => return -34
      }
    3 => @local_run.local_run_definition_cid(plan)
    4 =>
      match @preparation.local_prepared_original(input) {
        Program(wire) | Aql(wire) => wire
      }
    5 => {
      // Only the original checked audit can issue a completion-free journal.
      // The retained projection is not durable admission or execution permission.
      let normalization = match record.normalization {
        Some(original) => original
        None =>
          match @local_run.issue_local_run_normalization(plan) {
            Ok(original) => {
              record.normalization = Some(original)
              original
            }
            Err(_) => return -34
          }
      }
      match @local_run.local_run_normalization_evidence(plan, normalization) {
        Ok(evidence) => @publication.run_evidence_value_json(evidence)
        Err(_) => return -34
      }
    }
    6 =>
      match submitted_rows_material_wire(value, material, plan, preparation) {
        Ok(value) => value
        Err(issue) => return issue
      }
    _ => return -3
  }
  let result = status(
    @buffers.supply_buffer_output(value.pool, material.slot, @utf8.encode(wire)),
  )
  if result == 0 {
    material.produced = true
  }
  result
}

///|
#export_name("actql_material_length")
pub fn material_length(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.materials.get(handle) is Some(material) else {
    return -2
  }
  match @buffers.buffer_length(value.pool, material.slot) {
    Some(length) => length
    None => -33
  }
}

///|
#export_name("actql_material_close")
pub fn close_material(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.materials.get(handle) is Some(material) else {
    return -2
  }
  if value.journal_observations.values().any(child => child.material == handle) {
    return -9
  }
  if !material.output_closed {
    let result = status(@buffers.close_buffer(value.pool, material.slot))
    if result != 0 {
      return result
    }
    material.output_closed = true
  }
  let result = match material.submission {
    Some({ borrow: Ok(borrow), .. }) =>
      status(@buffers.return_buffer_borrow(value.pool, borrow))
    _ => 0
  }
  if result == 0 {
    value.materials.remove(handle) |> ignore
    value.copies.remove(handle) |> ignore
  }
  result
}
