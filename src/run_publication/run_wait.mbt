///|
pub(all) enum RunWaitIssue {
  InvalidState
  InvalidSince
} derive(Eq, Debug)

///|
/// Observe only the existing Run projection. Readiness grants no authority,
/// starts no work and acknowledges no cancellation or physical cleanup.
pub fn run_wait_ready(
  wire : String,
  since : Int64?,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Bool, RunWaitIssue] {
  if since is Some(revision) && !valid_observation_revision(revision) {
    return Err(InvalidSince)
  }
  let value = match
    parse_contract_wire(wire, max_bytes, max_nodes, max_depth, data_keys=true) {
    Ok(value) => value
    Err(_) => return Err(InvalidState)
  }
  if !validate_generated_protocol_shape(
      "run_state", value, true, max_bytes, max_nodes, max_depth,
    ) {
    return Err(InvalidState)
  }
  let revision = match @json.object_field(value, "revision") {
    Some(@json.Number(number)) =>
      match @scalar.read_safe_integer(number) {
        Some(revision) => revision
        None => return Err(InvalidState)
      }
    _ => return Err(InvalidState)
  }
  if since is Some(prior) && prior > revision {
    return Err(InvalidSince)
  }
  let status = match contract_string_from_value(value, "status") {
    Some(status) => status
    None => return Err(InvalidState)
  }
  let newer = match since {
    None => true
    Some(prior) => revision > prior
  }
  Ok(generated_run_wait_stable(status) && newer)
}
