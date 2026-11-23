///|
priv struct LocalDebugPark {
  logical_map_cid : String
  boundary_cid : String
  kind : String
  position : String
  step_wire : String
  paused_at : String
  expires_at : String
}

///|
// This rule is attested by the Journal's live park probe. The admitted
// entry deadline is capped by the original Run and lookup lease. Later
// public stops inherit that deadline. The epoch floor governs expiration.
let local_debug_ttl_policy : String =
  #|{"version":"actql-local-debug-park-ttl-policy/0.1","entry_deadline":"selected_within_original_run_and_lookup_lease","step_deadline":"inherit_entry_deadline","clock":"journal_epoch_floor","expired":"at_or_after_deadline"}

///|
fn admit_local_debug_park(
  run : PublicationContract,
  ref_value : @json.CanonicalValue,
  status : String,
  revision : Int64,
  park : @json.CanonicalValue,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[LocalDebugPark, RunControlReadIssue] {
  let invalid = ControlReadContract(InvalidField("debug_park"))
  guard @json.object_field(park, "run_ref") is Some(original_ref) &&
    @json.object_field_count(original_ref) == Some(3) &&
    contract_string_from_value(park, "logical_map_cid") is Some(map) &&
    valid_contract_cid(map) &&
    interactive_integer(park, "revision") == Some(revision) &&
    revision > 0L &&
    contract_string_from_value(park, "ttl_policy") ==
    Some("original_debug_entry_deadline") &&
    contract_string_from_value(park, "paused_at") is Some(paused_at) &&
    contract_string_from_value(park, "expires_at") is Some(expires_at) &&
    valid_timestamp(paused_at) &&
    valid_timestamp(expires_at) &&
    paused_at < expires_at &&
    contract_string(run, "valid_until") is Some(valid_until) &&
    expires_at <= valid_until else {
    return Err(invalid)
  }
  for field in ["namespaceId", "authorityScopeCid", "runDefinitionCid"] {
    if contract_string_from_value(original_ref, field) !=
      contract_string_from_value(ref_value, field) {
      return Err(invalid)
    }
  }
  fn quote(value : String) -> String raise {
    let writer = @encode.writer(max_bytes, 1, 1)
    @encode.string_value(writer, value)
    @encode.finish(writer)
  }
  let (kind, position, step_wire, task_fields) = match
    contract_string_from_value(park, "kind") {
    // The legacy Run view calls a reserved dispatch "running", including an
    // entry park whose original Journal has yet to reserve physical start.
    Some("entry") if (status == "preparing" || status == "running") &&
      @json.object_field_count(park) == Some(7) =>
      ("entry", "before", "null", "")
    Some("logical_step") if status == "running" &&
      @json.object_field_count(park) == Some(12) => {
      guard interactive_integer(park, "start_revision") is Some(start_revision) &&
        start_revision > 0L &&
        start_revision < revision &&
        interactive_integer(park, "control_revision") is Some(control_revision) &&
        control_revision >= 2L &&
        control_revision <= 2147483646L &&
        control_revision % 2L == 0L &&
        interactive_integer(park, "committed_generation") is Some(generation) &&
        generation >= 1L &&
        generation <= 2147483647L &&
        contract_string_from_value(park, "completed_step_id") is Some(completed) &&
        valid_contract_cid(completed) else {
        return Err(invalid)
      }
      let next = match @json.object_field(park, "next_step_id") {
        Some(@json.Null) => None
        Some(@json.String(value)) if valid_contract_cid(value) => Some(value)
        _ => return Err(invalid)
      }
      let (shown, fields) = try {
        let next_wire = match next {
          Some(value) => quote(value)
          None => "null"
        }
        (
          quote(next.unwrap_or(completed)),
          ",\"start_revision\":" +
          start_revision.to_string() +
          ",\"control_revision\":" +
          control_revision.to_string() +
          ",\"committed_generation\":" +
          generation.to_string() +
          ",\"completed_step_id\":" +
          quote(completed) +
          ",\"next_step_id\":" +
          next_wire,
        )
      } catch {
        _ => return Err(ControlReadContract(Encoding))
      }
      (
        "logical_step",
        if next is Some(_) {
          "before"
        } else {
          "after"
        },
        shown,
        fields,
      )
    }
    _ => return Err(invalid)
  }
  let boundary = try
    "{\"version\":\"actql-local-debug-park-boundary/0.1\",\"run_ref\":" +
    @json.stringify_value(ref_value, max_bytes, max_nodes, max_depth) +
    ",\"compiled_plan_cid\":" +
    quote(contract_string(run, "compiled_plan_cid").unwrap()) +
    ",\"logical_map_cid\":" +
    quote(map) +
    ",\"revision\":" +
    revision.to_string() +
    ",\"kind\":" +
    quote(kind) +
    task_fields +
    "}"
  catch {
    _ => return Err(ControlReadContract(Encoding))
  }
  let boundary_value = match
    parse_contract_wire(
      boundary,
      max_bytes,
      max_nodes,
      max_depth,
      data_keys=true,
    ) {
    Ok(value) => value
    Err(issue) => return Err(ControlReadContract(issue))
  }
  let boundary_cid = @json.cid_value(
    boundary_value, max_bytes, max_nodes, max_depth,
  ) catch {
    _ => return Err(ControlReadContract(Encoding))
  }
  Ok({
    logical_map_cid: map,
    boundary_cid,
    kind,
    position,
    step_wire,
    paused_at,
    expires_at,
  })
}

///|
fn encode_current_debug_park(
  run : PublicationContract,
  revision : Int64,
  park : LocalDebugPark,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, RunControlReadIssue] {
  fn quote(value : String) -> String raise {
    let writer = @encode.writer(max_bytes, 1, 1)
    @encode.string_value(writer, value)
    @encode.finish(writer)
  }
  let policy_value = match
    parse_contract_wire(
      local_debug_ttl_policy,
      max_bytes,
      max_nodes,
      max_depth,
      data_keys=true,
    ) {
    Ok(value) => value
    Err(issue) => return Err(ControlReadContract(issue))
  }
  try {
    let policy_cid = @json.cid_value(
      policy_value, max_bytes, max_nodes, max_depth,
    )
    let observed = quote(park.paused_at)
    Ok(
      "{\"version\":\"actql-controlled-run-state/0.1\",\"status\":\"paused\",\"run_id\":" +
      quote(contract_string(run, "run_id").unwrap()) +
      ",\"updated_at\":" +
      observed +
      ",\"control_revision\":" +
      revision.to_string() +
      ",\"stop_reason\":" +
      quote(if park.kind == "entry" { "entry" } else { "step" }) +
      ",\"matched_breakpoints\":[],\"paused_at\":" +
      observed +
      ",\"expires_at\":" +
      quote(park.expires_at) +
      ",\"ttl_policy_cid\":" +
      quote(policy_cid) +
      ",\"boundary\":{\"kind\":" +
      quote(park.kind) +
      ",\"position\":" +
      quote(park.position) +
      ",\"step_id\":" +
      park.step_wire +
      ",\"consumed_boundary_cid\":" +
      quote(park.boundary_cid) +
      "}}",
    )
  } catch {
    _ => Err(ControlReadContract(Encoding))
  }
}

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
  debug_park_wire? : String = "",
) -> Result[String, RunControlReadIssue] {
  match
    validate_original_interactive_run_evidence(run, prepared, authorization) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  // The validated original value is also displayed later in this projection.
  let policy = contract_string_from_value(
    authorization.value,
    "host_policy_cid",
  )
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
  let park = if debug_park_wire == "" {
    None
  } else {
    // The paused result omits legacy_state, so check the original with its
    // own registered validator before it can witness a park.
    if !validate_generated_protocol_shape(
        "run_state", state, true, max_bytes, max_nodes, max_depth,
      ) {
      return Err(ControlReadContract(InvalidField("run_state")))
    }
    if @json.object_field(control, "cancellation_requested")
      is Some(@json.Bool(true)) ||
      contract_string_from_value(control, "physical_stop") == Some("confirmed") {
      return Err(ControlReadContract(InvalidField("debug_park")))
    }
    let value = match
      parse_contract_wire(
        debug_park_wire,
        max_bytes,
        max_nodes,
        max_depth,
        data_keys=true,
      ) {
      Ok(value) => value
      Err(issue) => return Err(ControlReadContract(issue))
    }
    match
      admit_local_debug_park(
        run,
        ref_value,
        contract_string_from_value(state, "status").unwrap(),
        revision,
        value,
        max_bytes,
        max_nodes,
        max_depth,
      ) {
      Ok(value) => Some(value)
      Err(issue) => return Err(issue)
    }
  }
  let controlled = if park is Some(debug) {
    match
      encode_current_debug_park(
        run, revision, debug, max_bytes, max_nodes, max_depth,
      ) {
      Ok(wire) => wire
      Err(issue) => return Err(issue)
    }
  } else {
    try
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
  let body = try {
    let (map, journal_component) = match park {
      None => ("null", "")
      Some(debug) =>
        (
          quote(debug.logical_map_cid),
          ",{\"owner\":\"journal\",\"revision\":" +
          quote(revision.to_string()) +
          ",\"state\":\"observed\",\"provenance_cid\":" +
          quote(debug.boundary_cid) +
          "}",
        )
    }
    "{\"version\":\"actql-run-view/0.1\",\"run_ref\":" +
    encode(ref_value) +
    ",\"run_state\":" +
    controlled +
    ",\"compiled_plan_cid\":" +
    quote(contract_string(run, "compiled_plan_cid").unwrap()) +
    ",\"logical_map_cid\":" +
    map +
    ",\"consistency\":\"non_atomic\",\"observation_scope\":\"owner_local\"," +
    "\"components\":[{\"owner\":\"run\",\"revision\":null,\"state\":\"observed\",\"provenance_cid\":" +
    quote(snapshot_cid) +
    "}" +
    journal_component +
    "],\"quantities\":[],\"sample\":{\"state\":\"unavailable\",\"reason\":\"not_supported\"}," +
    "\"available_operations\":[\"inspect\"],\"capabilities\":{\"static_plan\":" +
    static_plan_installed.to_string() +
    ",\"inspect\":true," +
    "\"durable_control\":false,\"sample_capture\":[],\"full_intermediate_retention\":[]," +
    "\"cost_guard\":false,\"execution_batch\":false,\"policy_revision_cid\":" +
    quote(policy.unwrap()) +
    "}}"
  } catch {
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
