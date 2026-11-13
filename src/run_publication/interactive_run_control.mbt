///|
/// Closed canonical shape admission only. This creates neither control intent
/// nor authority, and does not assert a Sample's referenced type/custody proof.
/// The existing Run/Checkpoint/material Owners remain responsible for facts.
pub fn parse_interactive_run_control_shape(
  name : String,
  wire : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[@json.CanonicalValue, PublicationContractIssue] {
  if !generated_interactive_protocol_schema(name) {
    return Err(UnknownContract)
  }
  let value = match
    parse_contract_wire(
      wire,
      max_wire_bytes,
      max_nodes,
      max_depth,
      data_keys=true,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  admit_interactive_run_control_value(
    name, wire, value, max_wire_bytes, max_nodes, max_depth,
  )
}

///|
/// Validate the same closed canonical value supplied by an already-backed
/// source parser. Wire equality, complete shape and self identity remain
/// mandatory; this entry issues no control authority or resource backing.
pub fn admit_interactive_run_control_value(
  name : String,
  wire : String,
  value : @json.CanonicalValue,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[@json.CanonicalValue, PublicationContractIssue] {
  if !generated_interactive_protocol_schema(name) {
    return Err(UnknownContract)
  }
  if max_wire_bytes < 1 || max_nodes < 1 || max_depth < 1 {
    return Err(InvalidLimits)
  }
  let canonical = @json.stringify_value(
    value, max_wire_bytes, max_nodes, max_depth,
  ) catch {
    _ => return Err(Encoding)
  }
  if canonical != wire {
    return Err(InvalidWire)
  }
  if !validate_generated_protocol_shape(
      name, value, true, max_wire_bytes, max_nodes, max_depth,
    ) {
    return Err(InvalidField(name))
  }
  if generated_interactive_identity_field(name) is Some(field) {
    match
      run_evidence_value(
        name, field, value, max_wire_bytes, max_nodes, max_depth,
      ) {
      Ok(_) => ()
      Err(_) => return Err(InvalidField("self_cid"))
    }
  }
  Ok(value)
}

///|
pub(all) enum RunControlReadIssue {
  ControlReadContract(PublicationContractIssue)
  RunStateVersionUnsupported
  LegacyProjectionMismatch(String)
} derive(Eq, Debug)

///|
/// Exact old-state projection is intentionally not a lifecycle decision.
/// A paused/manual-origin state never acquires fabricated approval evidence.
pub fn project_interactive_legacy_state(
  wire : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, RunControlReadIssue] {
  let state = match
    parse_interactive_run_control_shape(
      "controlled_run_state", wire, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(ControlReadContract(issue))
  }
  if contract_string_from_value(state, "status") == Some("paused") {
    return Err(RunStateVersionUnsupported)
  }
  if @json.object_field(state, "resume_origin") is Some(origin) &&
    contract_string_from_value(origin, "kind") == Some("manual") {
    return Err(RunStateVersionUnsupported)
  }
  guard @json.object_field(state, "legacy_state") is Some(legacy) else {
    return Err(RunStateVersionUnsupported)
  }
  for field in ["run_id", "status", "updated_at"] {
    if contract_string_from_value(legacy, field) !=
      contract_string_from_value(state, field) {
      return Err(LegacyProjectionMismatch(field))
    }
  }
  guard @json.object_field(legacy, "control") is Some(control) else {
    return Err(RunStateVersionUnsupported)
  }
  if interactive_integer(control, "revision") !=
    interactive_integer(state, "control_revision") {
    return Err(LegacyProjectionMismatch("control_revision"))
  }
  Ok(@json.stringify_value(legacy, max_wire_bytes, max_nodes, max_depth)) catch {
    _ => Err(ControlReadContract(Encoding))
  }
}

///|
fn interactive_integer(value : @json.CanonicalValue, name : String) -> Int64? {
  match @json.object_field(value, name) {
    Some(@json.Number(number)) => @scalar.read_safe_integer(number)
    _ => None
  }
}
