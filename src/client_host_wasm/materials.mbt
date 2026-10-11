///|
/// Invocation custody and an existing Ledger reservation, never durable Run
/// state. A failed producer keeps this same handle until physical cleanup.
priv struct StoredMaterial {
  run : Int
  kind : Int
  slot : @buffers.BufferSlot
  mut invoked : Bool
  mut produced : Bool
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
  if kind < 1 ||
    kind > 5 ||
    physical_ticket <= 0 ||
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
  }
  value.copies[handle] = (slot, physical_ticket)
  value.next_handle += 1
  handle
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
  if material.produced {
    return 0
  }
  if value.closing || value.runtime_closing {
    return -5
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
  let result = status(@buffers.close_buffer(value.pool, material.slot))
  if result == 0 {
    value.materials.remove(handle) |> ignore
    value.copies.remove(handle) |> ignore
  }
  result
}
