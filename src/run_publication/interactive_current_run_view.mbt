///|
/// Project facts already read by the current authorized Run Owner. This is
/// neither admission authority nor a lifecycle decision. Original evidence
/// supplies policy identity; current configuration must not replace it.
/// The trusted consumer declares installed static planning separately. This
/// portable reader cannot infer another Host's installation or grant access.
pub fn project_current_interactive_run_view(
  run : PublicationContract,
  prepared : RunEvidenceValue,
  authorization : RunEvidenceValue,
  run_ref_wire : String,
  state_wire : String,
  snapshot_cid : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  static_plan_installed? : Bool = false,
) -> Result[String, RunControlReadIssue] {
  if run.name != "run_definition" ||
    prepared.name != "prepared_invocation" ||
    authorization.name != "run_authorization" {
    return Err(LegacyProjectionMismatch("original_evidence"))
  }
  for field in ["compiled_plan_cid", "invocation_template_cid"] {
    if contract_string_from_value(prepared.value, field) !=
      contract_string(run, field) {
      return Err(LegacyProjectionMismatch(field))
    }
  }
  if contract_string_from_value(authorization.value, "prepared_invocation_cid") !=
    Some(prepared.identity) ||
    contract_string_from_value(prepared.value, "policy_decision") !=
    Some("allow") ||
    contract_string_from_value(authorization.value, "decision") !=
    Some("allowed") {
    return Err(LegacyProjectionMismatch("authorization"))
  }
  let context = contract_string(run, "authorization_context_cid")
  if context !=
    contract_string_from_value(prepared.value, "execution_context_cid") ||
    context !=
    contract_string_from_value(authorization.value, "execution_context_cid") {
    return Err(LegacyProjectionMismatch("execution_context_cid"))
  }
  let policy = contract_string_from_value(
    authorization.value,
    "host_policy_cid",
  )
  if policy != contract_string_from_value(prepared.value, "host_policy_cid") {
    return Err(LegacyProjectionMismatch("host_policy_cid"))
  }
  let state = match
    parse_contract_wire(
      state_wire,
      max_bytes,
      max_nodes,
      max_depth,
      data_keys=true,
    ) {
    Ok(value) => value
    Err(issue) => return Err(ControlReadContract(issue))
  }
  if contract_string_from_value(state, "version") != Some("actql-run-state/0.1") ||
    contract_string_from_value(state, "status") is None ||
    contract_string_from_value(state, "updated_at") is None {
    return Err(ControlReadContract(InvalidField("run_state")))
  }
  if contract_string_from_value(state, "run_id") !=
    contract_string(run, "run_id") {
    return Err(LegacyProjectionMismatch("run_id"))
  }
  // This small read profile does not observe continuation/fence evidence.
  // Refuse that projection rather than inventing a resume origin.
  if contract_string_from_value(state, "status") == Some("resuming") {
    return Err(RunStateVersionUnsupported)
  }
  guard @json.object_field(state, "control") is Some(control) &&
    interactive_integer(control, "revision") is Some(revision) else {
    return Err(RunStateVersionUnsupported)
  }
  let ref_value = match
    parse_contract_wire(
      run_ref_wire,
      max_bytes,
      max_nodes,
      max_depth,
      data_keys=true,
    ) {
    Ok(value) => value
    Err(issue) => return Err(ControlReadContract(issue))
  }
  if contract_string_from_value(ref_value, "runDefinitionCid") !=
    Some(run.identity) ||
    contract_string_from_value(ref_value, "namespaceId") !=
    contract_string(run, "scope_id") {
    return Err(LegacyProjectionMismatch("run_ref"))
  }
  fn encode(value : @json.CanonicalValue) -> String raise {
    @json.stringify_value(value, max_bytes, max_nodes, max_depth)
  }
  fn quote(value : String) -> String raise {
    let writer = @encode.writer(max_bytes, 1, 1)
    @encode.string_value(writer, value)
    @encode.finish(writer)
  }
  let controlled = try
    "{\"version\":\"actql-controlled-run-state/0.1\",\"run_id\":" +
    quote(contract_string(run, "run_id").unwrap()) +
    ",\"status\":" +
    quote(contract_string_from_value(state, "status").unwrap()) +
    ",\"updated_at\":" +
    quote(contract_string_from_value(state, "updated_at").unwrap()) +
    ",\"control_revision\":" +
    revision.to_string() +
    ",\"legacy_state\":" +
    encode(state) +
    "}"
  catch {
    _ => return Err(ControlReadContract(Encoding))
  }
  // The registered controlled envelope references the unchanged closed old
  // RunState schema. Validate that exact embedded consumer, not an invented
  // standalone publication identity for the old state.
  let controlled_value = match
    parse_contract_wire(
      controlled,
      max_bytes,
      max_nodes,
      max_depth,
      data_keys=true,
    ) {
    Ok(value) => value
    Err(issue) => return Err(ControlReadContract(issue))
  }
  if !validate_generated_protocol_shape(
      "controlled_run_state", controlled_value, true, max_bytes, max_nodes, max_depth,
    ) {
    return Err(ControlReadContract(InvalidField("controlled_run_state")))
  }
  let snapshot_body = try
    "{\"version\":\"actql-owner-snapshot/0.1\",\"ref\":" +
    encode(ref_value) +
    ",\"owner\":{\"kind\":\"run\",\"scopeCid\":" +
    quote(
      contract_string_from_value(ref_value, "authorityScopeCid").unwrap_or(""),
    ) +
    ",\"streamCid\":" +
    quote(run.identity) +
    "},\"snapshot\":{\"value\":" +
    encode(state) +
    "}}"
  catch {
    _ => return Err(ControlReadContract(Encoding))
  }
  let snapshot_value = match
    parse_contract_wire(
      snapshot_body,
      max_bytes,
      max_nodes,
      max_depth,
      data_keys=true,
    ) {
    Ok(value) => value
    Err(issue) => return Err(ControlReadContract(issue))
  }
  let expected_snapshot = @json.cid_value(
    snapshot_value, max_bytes, max_nodes, max_depth,
  ) catch {
    _ => return Err(ControlReadContract(Encoding))
  }
  if expected_snapshot != snapshot_cid {
    return Err(LegacyProjectionMismatch("snapshot_cid"))
  }
  let body = try
    "{\"version\":\"actql-run-view/0.1\",\"run_ref\":" +
    encode(ref_value) +
    ",\"run_state\":" +
    controlled +
    ",\"compiled_plan_cid\":" +
    quote(contract_string(run, "compiled_plan_cid").unwrap()) +
    ",\"logical_map_cid\":null,\"consistency\":\"non_atomic\",\"observation_scope\":\"owner_local\"," +
    "\"components\":[{\"owner\":\"run\",\"revision\":null,\"state\":\"observed\",\"provenance_cid\":" +
    quote(snapshot_cid) +
    "}],\"quantities\":[],\"sample\":{\"state\":\"unavailable\",\"reason\":\"not_supported\"}," +
    "\"available_operations\":[\"inspect\"],\"capabilities\":{\"static_plan\":" +
    static_plan_installed.to_string() +
    ",\"inspect\":true," +
    "\"durable_control\":false,\"sample_capture\":[],\"full_intermediate_retention\":[]," +
    "\"cost_guard\":false,\"execution_batch\":false,\"policy_revision_cid\":" +
    quote(policy.unwrap()) +
    "}}"
  catch {
    _ => return Err(ControlReadContract(Encoding))
  }
  let value = match
    parse_contract_wire(body, max_bytes, max_nodes, max_depth, data_keys=true) {
    Ok(value) => value
    Err(issue) => return Err(ControlReadContract(issue))
  }
  let wire = encode(value) catch {
    _ => return Err(ControlReadContract(Encoding))
  }
  match
    parse_interactive_run_control_shape(
      "run_view", wire, max_bytes, max_nodes, max_depth,
    ) {
    Ok(_) => Ok(wire)
    Err(issue) => Err(ControlReadContract(issue))
  }
}
