///|
pub(all) enum RunWaitIssue {
  InvalidState
  InvalidSince
} derive(Eq, Debug)

///|
pub(all) enum RunWaitUntil {
  Stable
  Final
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
  run_wait_ready_until(wire, since, Stable, max_bytes, max_nodes, max_depth)
}

///|
/// The final variant follows the original Run outcome through waiting phases.
/// It acknowledges no physical close, Result availability or current authority.
/// The original default readiness and its wire/ABI remain unchanged above.
pub fn run_wait_ready_until(
  wire : String,
  since : Int64?,
  until : RunWaitUntil,
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
  let reached = match until {
    Stable => generated_run_wait_stable(status)
    Final =>
      match read_run_outcome_status(status) {
        Some(Succeeded | Failed | Cancelled) => true
        Some(
          Preparing
          | Running
          | WaitingCheckpoint
          | Resuming
          | NeedsReconciliation
        ) => false
        None => return Err(InvalidState)
      }
  }
  Ok(reached && newer)
}
