///|
/// Issue the immutable receipt for the winning local Debug resume CAS. The
/// Journal owns the selected park, acceptance time, and atomic retention of
/// this receipt with the accepted command. This function does not authorize
/// the command or acknowledge a physical continuation.
pub fn issue_local_debug_resume_receipt(
  run : PublicationContract,
  command : RunEvidenceValue,
  park_wire : String,
  accepted_revision : Int,
  accepted_at : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[RunEvidenceValue, RunControlReadIssue] {
  let wrong_command = ControlReadContract(InvalidField("control_command"))
  guard run.name == "run_definition" &&
    command.name == "control_command" &&
    contract_string_from_value(command.value, "operation") == Some("resume") &&
    @json.object_field(command.value, "run_ref") is Some(ref_value) &&
    contract_string_from_value(ref_value, "runDefinitionCid") ==
    Some(run.identity) &&
    contract_string_from_value(ref_value, "namespaceId") ==
    contract_string(run, "scope_id") &&
    contract_string_from_value(command.value, "operation_id")
    is Some(operation_id) &&
    @json.object_field(command.value, "interval") is Some(interval) &&
    @json.object_field(interval, "guards") is Some(@json.Null) &&
    contract_string_from_value(interval, "until") is Some(until) &&
    (until == "step" || until == "terminal" || until == "breakpoint") &&
    interactive_integer(command.value, "expected_control_revision")
    is Some(revision) &&
    revision >= 1L &&
    accepted_revision.to_int64() == revision + 1L else {
    return Err(wrong_command)
  }
  let park = match
    parse_contract_wire(
      park_wire,
      max_bytes,
      max_nodes,
      max_depth,
      data_keys=true,
    ) {
    Ok(value) => value
    Err(issue) => return Err(ControlReadContract(issue))
  }
  let status = match contract_string_from_value(park, "kind") {
    Some("entry") => "preparing"
    Some("logical_step") => "running"
    _ => return Err(ControlReadContract(InvalidField("debug_park")))
  }
  let boundary = match
    admit_local_debug_park(
      run, ref_value, status, revision, false, park, max_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if until == "breakpoint" {
    guard (
        boundary.kind == "entry" ||
        (
          boundary.kind == "logical_step" &&
          contract_string_from_value(park, "next_step_id") is Some(_)
        )
      ) &&
      @json.object_field(interval, "breakpoint_selection") is Some(selection) &&
      boundary.logical_map_cid is Some(map) &&
      contract_string_from_value(selection, "logical_map_cid") == Some(map) else {
      return Err(wrong_command)
    }
  }
  issue_accepted_local_debug_control_receipt(
    run,
    command,
    {
      ref_value,
      operation_id,
      revision,
      boundary_cid: boundary.boundary_cid,
      paused_at: boundary.paused_at,
      expires_at: boundary.expires_at,
    },
    accepted_revision,
    accepted_at,
    max_bytes,
    max_nodes,
    max_depth,
  )
}

///|
/// Seal logical acceptance of a confirmation at the exact original Effect
/// park. The Journal still owns the physical-start and live park selection,
/// the revision CAS, and retention before handoff. This is no policy ruling,
/// no permission to send an Effect and no observation of a send.
pub fn issue_local_effect_write_confirmation_receipt(
  run : PublicationContract,
  command : RunEvidenceValue,
  park_wire : String,
  accepted_revision : Int,
  accepted_at : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[RunEvidenceValue, RunControlReadIssue] {
  let wrong_command = ControlReadContract(InvalidField("control_command"))
  guard run.name == "run_definition" &&
    command.name == "control_command" &&
    contract_string_from_value(command.value, "operation") ==
    Some("confirm_write") &&
    @json.object_field(command.value, "run_ref") is Some(ref_value) &&
    contract_string_from_value(ref_value, "runDefinitionCid") ==
    Some(run.identity) &&
    contract_string_from_value(ref_value, "namespaceId") ==
    contract_string(run, "scope_id") &&
    contract_string_from_value(command.value, "operation_id")
    is Some(operation_id) &&
    interactive_integer(command.value, "expected_control_revision")
    is Some(revision) &&
    revision >= 2L &&
    accepted_revision.to_int64() == revision + 1L &&
    @json.object_field(command.value, "effect_write") is Some(selection) else {
    return Err(wrong_command)
  }
  let park = match
    parse_contract_wire(
      park_wire,
      max_bytes,
      max_nodes,
      max_depth,
      data_keys=true,
    ) {
    Ok(value) => value
    Err(issue) => return Err(ControlReadContract(issue))
  }
  let boundary = match
    admit_local_effect_write_park(
      run, ref_value, revision, park, max_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  for field in ["unit_id", "effect_preview_cid", "member_preview_cid"] {
    if contract_string_from_value(boundary.selection, field) !=
      contract_string_from_value(selection, field) {
      return Err(ControlReadContract(InvalidField("effect_write_park")))
    }
  }
  issue_accepted_local_debug_control_receipt(
    run,
    command,
    {
      ref_value,
      operation_id,
      revision,
      boundary_cid: boundary.boundary_cid,
      paused_at: boundary.paused_at,
      expires_at: boundary.expires_at,
    },
    accepted_revision,
    accepted_at,
    max_bytes,
    max_nodes,
    max_depth,
  )
}

///|
priv struct LocalEffectWritePark {
  selection : @json.CanonicalValue
  boundary_cid : String
  paused_at : String
  expires_at : String
}

///|
// Both Inspect and receipt issuance attest the exact same held boundary.
fn admit_local_effect_write_park(
  run : PublicationContract,
  ref_value : @json.CanonicalValue,
  revision : Int64,
  park : @json.CanonicalValue,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[LocalEffectWritePark, RunControlReadIssue] {
  let wrong_park = ControlReadContract(InvalidField("effect_write_park"))
  guard @json.object_field_count(park) == Some(7) &&
    contract_string_from_value(park, "version") ==
    Some("actql-local-debug-effect-write-park/0.1") &&
    @json.object_field(park, "run_ref") is Some(park_ref) &&
    @json.object_field_count(park_ref) == Some(3) &&
    @json.object_field(park, "effect_write") is Some(park_selection) &&
    @json.object_field_count(park_selection) == Some(3) &&
    contract_string_from_value(park_selection, "unit_id") is Some(_) &&
    contract_string_from_value(park_selection, "effect_preview_cid")
    is Some(preview) &&
    valid_contract_cid(preview) &&
    contract_string_from_value(park_selection, "member_preview_cid")
    is Some(member_cid) &&
    valid_contract_cid(member_cid) &&
    interactive_integer(park, "start_revision") is Some(start_revision) &&
    start_revision > 0L &&
    start_revision < revision &&
    interactive_integer(park, "revision") == Some(revision) &&
    contract_string_from_value(park, "paused_at") is Some(paused_at) &&
    contract_string_from_value(park, "expires_at") is Some(expires_at) &&
    valid_timestamp(paused_at) &&
    valid_timestamp(expires_at) &&
    paused_at < expires_at &&
    contract_string(run, "valid_until") is Some(valid_until) &&
    expires_at <= valid_until else {
    return Err(wrong_park)
  }
  for field in ["namespaceId", "authorityScopeCid", "runDefinitionCid"] {
    if contract_string_from_value(park_ref, field) !=
      contract_string_from_value(ref_value, field) {
      return Err(wrong_park)
    }
  }
  let boundary_cid = @json.cid_value(park, max_bytes, max_nodes, max_depth) catch {
    _ => return Err(ControlReadContract(Encoding))
  }
  Ok({ selection: park_selection, boundary_cid, paused_at, expires_at, })
}

///|
priv struct LocalDebugControlAcceptance {
  ref_value : @json.CanonicalValue
  operation_id : String
  revision : Int64
  boundary_cid : String
  paused_at : String
  expires_at : String
}

///|
fn issue_accepted_local_debug_control_receipt(
  run : PublicationContract,
  command : RunEvidenceValue,
  original : LocalDebugControlAcceptance,
  accepted_revision : Int,
  accepted_at : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[RunEvidenceValue, RunControlReadIssue] {
  let {
    ref_value,
    operation_id,
    revision,
    boundary_cid,
    paused_at,
    expires_at,
  } = original
  guard valid_timestamp(accepted_at) &&
    paused_at <= accepted_at &&
    accepted_at < expires_at else {
    return Err(ControlReadContract(InvalidField("accepted_at")))
  }
  fn quote(value : String) -> String raise {
    let writer = @encode.writer(max_bytes, 1, 1)
    @encode.string_value(writer, value)
    @encode.finish(writer)
  }
  fn identify(preimage : String) -> String raise {
    let value = match
      parse_contract_wire(
        preimage,
        max_bytes,
        max_nodes,
        max_depth,
        data_keys=true,
      ) {
      Ok(value) => value
      Err(_) => raise @encode.OutputLimit
    }
    @json.cid_value(value, max_bytes, max_nodes, max_depth)
  }
  let body = try {
    let reference = "{\"run_ref\":" +
      @json.stringify_value(ref_value, max_bytes, max_nodes, max_depth) +
      ",\"operation_id\":" +
      quote(operation_id) +
      ",\"command_cid\":" +
      quote(command.identity) +
      ",\"accepted_from_revision\":" +
      revision.to_string() +
      "}"
    // The continuation generation names the original parked occurrence and
    // its selected lifetime. It is independent of any attempted command.
    let generation = identify(
      "{\"version\":\"actql-local-debug-continuation-generation/0.1\",\"consumed_boundary_cid\":" +
      quote(boundary_cid) +
      ",\"paused_at\":" +
      quote(paused_at) +
      ",\"expires_at\":" +
      quote(expires_at) +
      "}",
    )
    // The fence names the winning logical CAS over that original generation.
    let fence = identify(
      "{\"version\":\"actql-local-debug-resume-fence/0.1\",\"operation_ref\":" +
      reference +
      ",\"continuation_generation_cid\":" +
      quote(generation) +
      ",\"accepted_revision\":" +
      accepted_revision.to_string() +
      "}",
    )
    "{\"version\":\"actql-control-operation-receipt/0.1\",\"outcome\":\"accepted\",\"operation_ref\":" +
    reference +
    ",\"observed_state\":{\"version\":\"actql-controlled-run-state/0.1\",\"status\":\"resuming\",\"run_id\":" +
    quote(contract_string(run, "run_id").unwrap()) +
    ",\"updated_at\":" +
    quote(accepted_at) +
    ",\"control_revision\":" +
    accepted_revision.to_string() +
    ",\"resume_origin\":{\"kind\":\"manual\",\"command_cid\":" +
    quote(command.identity) +
    ",\"continuation_generation_cid\":" +
    quote(generation) +
    ",\"fence_cid\":" +
    quote(fence) +
    "}}}"
  } catch {
    _ => return Err(ControlReadContract(Encoding))
  }
  match
    seal_run_evidence_value(
      "control_operation_receipt", body, max_bytes, max_nodes, max_depth,
    ) {
    Ok(receipt) => Ok(receipt)
    Err(_) => Err(ControlReadContract(Encoding))
  }
}
