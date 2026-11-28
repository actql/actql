///|
priv struct LocalDebugPark {
  logical_map_cid : String?
  boundary_cid : String
  kind : String
  position : String
  step_wire : String
  paused_at : String
  expires_at : String
  continuation_available : Bool
  effect_write : @json.CanonicalValue?
  matched_breakpoint : String?
  breakpoint_targets : @json.CanonicalValue?
  entry_breakpoint_selection : @json.CanonicalValue?
}

///|
// This rule is attested by the Journal's live park probe. The admitted
// entry deadline is capped by the original Run and lookup lease. Later
// public stops inherit that deadline. The epoch floor governs expiration.
let local_debug_ttl_policy : String =
  #|{"version":"actql-local-debug-park-ttl-policy/0.1","entry_deadline":"selected_within_original_run_and_lookup_lease","step_deadline":"inherit_entry_deadline","clock":"journal_epoch_floor","expired":"at_or_after_deadline"}

///|
// Every member inherits the acknowledged physical start's original expiry.
// Neither release nor an input continuation replenishes it.
let local_effect_write_ttl_policy : String =
  #|{"version":"actql-local-effect-write-park-ttl-policy/0.1","member_deadline":"inherit_original_physical_start_deadline","clock":"journal_epoch_floor","expired":"at_or_after_deadline"}

///|
fn admit_current_effect_write_park(
  run : PublicationContract,
  ref_value : @json.CanonicalValue,
  status : String,
  revision : Int64,
  park : @json.CanonicalValue,
  original : @json.CanonicalValue,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[LocalDebugPark, RunControlReadIssue] {
  guard @json.object_field_count(park) == Some(2) &&
    @json.object_field(park, "confirm_available")
    is Some(@json.Bool(confirm_available)) &&
    (
      status == "running" ||
      status == "waiting_checkpoint" ||
      status == "resuming"
    ) else {
    return Err(ControlReadContract(InvalidField("effect_write_park")))
  }
  match
    admit_local_effect_write_park(
      run, ref_value, revision, original, max_bytes, max_nodes, max_depth,
    ) {
    Err(issue) => Err(issue)
    Ok(boundary) =>
      Ok({
        logical_map_cid: None,
        boundary_cid: boundary.boundary_cid,
        kind: "effect_write",
        position: "before",
        step_wire: "null",
        paused_at: boundary.paused_at,
        expires_at: boundary.expires_at,
        continuation_available: confirm_available,
        effect_write: Some(boundary.selection),
        matched_breakpoint: None,
        breakpoint_targets: None,
        entry_breakpoint_selection: None,
      })
  }
}

///|
fn admit_local_debug_park(
  run : PublicationContract,
  ref_value : @json.CanonicalValue,
  status : String,
  revision : Int64,
  physical_closed : Bool,
  park : @json.CanonicalValue,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[LocalDebugPark, RunControlReadIssue] {
  let invalid = ControlReadContract(InvalidField("debug_park"))
  let park_kind = contract_string_from_value(park, "kind")
  // Current delivery permission is separate from the enduring park identity.
  let (resume_available, availability_fields) = match
    @json.object_field(park, "resume_available") {
    None => (false, 0)
    Some(@json.Bool(value)) => (value, 1)
    _ => return Err(invalid)
  }
  let matched_breakpoint = match
    @json.object_field(park, "matched_breakpoint_step_id") {
    None => None
    Some(@json.String(step)) if (
        park_kind == Some("logical_step") ||
        park_kind == Some("stopped_logical_step")
      ) &&
      valid_contract_cid(step) &&
      contract_string_from_value(park, "next_step_id") == Some(step) =>
      Some(step)
    _ => return Err(invalid)
  }
  let breakpoint_targets = match
    @json.object_field(park, "breakpoint_targets") {
    None => None
    Some(@json.Array(targets) as value) if park_kind == Some("logical_step") &&
      resume_available &&
      contract_string_from_value(park, "next_step_id") is Some(next) => {
      let entries = @json.array_values(targets)
      guard !entries.is_empty() else { return Err(invalid) }
      let seen : Map[String, Bool] = Map([])
      for entry in entries {
        guard entry is @json.String(step) &&
          valid_contract_cid(step) &&
          step != next &&
          !seen.contains(step) else {
          return Err(invalid)
        }
        seen[step] = true
      }
      Some(value)
    }
    _ => return Err(invalid)
  }
  let map = match @json.object_field(park, "logical_map_cid") {
    Some(@json.String(cid)) if valid_contract_cid(cid) => Some(cid)
    // Entry consumes the checked Run boundary before any logical Step. A
    // Host without a retained map cannot issue a logical Step boundary.
    Some(@json.Null) if park_kind == Some("entry") && !resume_available => None
    _ => return Err(invalid)
  }
  let entry_breakpoint_selection = match
    @json.object_field(park, "entry_breakpoint_selection") {
    None => None
    Some(value) if park_kind == Some("entry") &&
      resume_available &&
      contract_string_from_value(park, "next_step_id") is Some(_) &&
      map is Some(original_map) &&
      @json.object_field_count(value) == Some(2) &&
      contract_string_from_value(value, "logical_map_cid") == Some(original_map) &&
      @json.object_field(value, "before_step_ids") is Some(@json.Array(marks)) &&
      @json.array_count(marks) > 0 &&
      @json.array_count(marks) <= 32 => Some(value)
    _ => return Err(invalid)
  }
  guard @json.object_field(park, "run_ref") is Some(original_ref) &&
    @json.object_field_count(original_ref) == Some(3) &&
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
  fn map_wire() -> String raise {
    match map {
      Some(cid) => quote(cid)
      None => "null"
    }
  }
  let (kind, position, step_wire, task_fields) = match park_kind {
    // The legacy Run view calls a reserved dispatch "running", including an
    // entry park whose original Journal has yet to reserve physical start.
    Some("entry") if !physical_closed &&
      (status == "preparing" || status == "running") => {
      let (step_wire, step_fields) = match
        @json.object_field(park, "next_step_id") {
        None => ("null", 0)
        Some(@json.String(step)) if map is Some(_) && valid_contract_cid(step) =>
          (
            quote(step) catch {
              _ => return Err(ControlReadContract(Encoding))
            },
            1,
          )
        _ => return Err(invalid)
      }
      guard @json.object_field_count(park) ==
        Some(
          7 +
          availability_fields +
          step_fields +
          (if entry_breakpoint_selection is Some(_) { 1 } else { 0 }),
        ) else {
        return Err(invalid)
      }
      // Display the first known Step without changing the consumed entry
      // boundary or the existing Journal receipt's identity.
      ("entry", "before", step_wire, "")
    }
    Some(task_kind) if (
        task_kind == "logical_step" && status == "running" && !physical_closed
      ) ||
      (
      // The active input continuation uses the original start and keeps
      // the prior physical stop in the legacy observation.
        task_kind == "input_logical_step" &&
        status == "resuming" &&
        physical_closed
      ) ||
      (
        task_kind == "stopped_logical_step" &&
        status == "needs_reconciliation" &&
        physical_closed
      ) => {
      let stopped = task_kind == "stopped_logical_step"
      let task_fields = if stopped { 13 } else { 12 }
      let breakpoint_fields = (if matched_breakpoint is Some(_) {
          1
        } else {
          0
        }) +
        (if breakpoint_targets is Some(_) { 1 } else { 0 })
      let parked_revision = if stopped {
        guard interactive_integer(park, "parked_revision")
          is Some(parked_revision) &&
          parked_revision == revision - 1L else {
          return Err(invalid)
        }
        parked_revision
      } else {
        revision
      }
      guard @json.object_field_count(park) ==
        Some(task_fields + availability_fields + breakpoint_fields) &&
        interactive_integer(park, "start_revision") is Some(start_revision) &&
        start_revision > 0L &&
        start_revision < parked_revision &&
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
    map_wire() +
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
    continuation_available: resume_available,
    effect_write: None,
    matched_breakpoint,
    breakpoint_targets,
    entry_breakpoint_selection,
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
      if park.effect_write is Some(_) {
        local_effect_write_ttl_policy
      } else {
        local_debug_ttl_policy
      },
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
    let (reason, selection) = match park.effect_write {
      Some(value) =>
        (
          "effect_write",
          ",\"effect_write\":" +
          @json.stringify_value(value, max_bytes, max_nodes, max_depth),
        )
      None =>
        (
          if park.matched_breakpoint is Some(_) {
            "breakpoint"
          } else if park.kind == "entry" {
            "entry"
          } else {
            "step"
          },
          "",
        )
    }
    let matched = match park.matched_breakpoint {
      Some(step) => "[" + quote(step) + "]"
      None => "[]"
    }
    Ok(
      "{\"version\":\"actql-controlled-run-state/0.1\",\"status\":\"paused\",\"run_id\":" +
      quote(contract_string(run, "run_id").unwrap()) +
      ",\"updated_at\":" +
      observed +
      ",\"control_revision\":" +
      revision.to_string() +
      ",\"stop_reason\":" +
      quote(reason) +
      ",\"matched_breakpoints\":" +
      matched +
      ",\"paused_at\":" +
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
      selection +
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
      is Some(@json.Bool(true)) {
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
    let status = contract_string_from_value(state, "status").unwrap()
    let boundary = match @json.object_field(value, "effect_write_park") {
      Some(original) =>
        admit_current_effect_write_park(
          run, ref_value, status, revision, value, original, max_bytes, max_nodes,
          max_depth,
        )
      None =>
        admit_local_debug_park(
          run,
          ref_value,
          status,
          revision,
          contract_string_from_value(control, "physical_stop") ==
          Some("confirmed"),
          value,
          max_bytes,
          max_nodes,
          max_depth,
        )
    }
    match boundary {
      Ok(value) => Some(value)
      Err(issue) => return Err(issue)
    }
  }
  // An admitted park can supersede the older input-continuation observation.
  // An unobserved resume has no dispatch/fence evidence here.
  if contract_string_from_value(state, "status") == Some("resuming") &&
    park is None {
    return Err(RunStateVersionUnsupported)
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
          match debug.logical_map_cid {
            Some(cid) => quote(cid)
            None => "null"
          },
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
    "\"available_operations\":" +
    (match park {
      Some(debug) if debug.continuation_available =>
        if debug.effect_write is Some(_) {
          "[\"inspect\",\"confirm_write\"]"
        } else {
          "[\"inspect\",\"resume\"]"
        }
      _ => "[\"inspect\"]"
    }) +
    (match park {
      Some({ breakpoint_targets: Some(targets), .. }) =>
        ",\"breakpoint_targets\":" + encode(targets)
      Some({ entry_breakpoint_selection: Some(selection), .. }) =>
        ",\"entry_breakpoint_selection\":" + encode(selection)
      _ => ""
    }) +
    ",\"capabilities\":{\"static_plan\":" +
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
