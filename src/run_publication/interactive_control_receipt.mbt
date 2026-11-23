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
    (
      contract_string_from_value(interval, "until") == Some("step") ||
      contract_string_from_value(interval, "until") == Some("terminal")
    ) &&
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
      run, ref_value, status, revision, park, max_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard valid_timestamp(accepted_at) &&
    boundary.paused_at <= accepted_at &&
    accepted_at < boundary.expires_at else {
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
      quote(boundary.boundary_cid) +
      ",\"paused_at\":" +
      quote(boundary.paused_at) +
      ",\"expires_at\":" +
      quote(boundary.expires_at) +
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
