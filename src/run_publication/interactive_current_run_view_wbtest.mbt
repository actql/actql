///|
fn inspect_fixture_cid(digit : String) -> String {
  "sha256:" + digit.repeat(64)
}

///|
fn inspect_fixture() -> (
  PublicationContract,
  RunEvidenceValue,
  RunEvidenceValue,
  String,
  String,
) {
  let prepared = seal_run_evidence_value(
    "prepared_invocation",
    "{\"version\":\"actql-prepared-invocation/0.1\",\"invocation_template_cid\":\"" +
    inspect_fixture_cid("1") +
    "\",\"compiled_plan_cid\":\"" +
    inspect_fixture_cid("2") +
    "\",\"execution_context_cid\":\"" +
    inspect_fixture_cid("3") +
    "\",\"host_policy_cid\":\"" +
    inspect_fixture_cid("4") +
    "\",\"policy_decision\":\"allow\",\"expires_at\":\"2026-10-12T00:00:00.000Z\"}",
    65536,
    1000,
    32,
  ).unwrap()
  let authorization = seal_run_evidence_value(
    "run_authorization",
    "{\"version\":\"actql-run-authorization/0.1\",\"prepared_invocation_cid\":\"" +
    prepared.identity +
    "\",\"execution_context_cid\":\"" +
    inspect_fixture_cid("3") +
    "\",\"host_policy_cid\":\"" +
    inspect_fixture_cid("4") +
    "\",\"decision\":\"allowed\"}",
    65536,
    1000,
    32,
  ).unwrap()
  let run = seal_publication_contract(
    "run_definition",
    "{\"version\":\"actql-run-definition/0.1\",\"scope_id\":\"scope\",\"run_id\":\"original\"," +
    "\"compiled_plan_cid\":\"" +
    inspect_fixture_cid("2") +
    "\",\"invocation_template_cid\":\"" +
    inspect_fixture_cid("1") +
    "\",\"authorization_context_cid\":\"" +
    inspect_fixture_cid("3") +
    "\",\"input_artifact_set_cid\":\"" +
    inspect_fixture_cid("5") +
    "\",\"created_at\":\"2026-10-11T00:00:00.000Z\",\"valid_until\":\"2026-10-12T00:00:00.000Z\"}",
    65536,
    1000,
    32,
  ).unwrap()
  let ref_wire = "{\"namespaceId\":\"scope\",\"authorityScopeCid\":\"" +
    inspect_fixture_cid("a") +
    "\",\"runDefinitionCid\":\"" +
    run.identity +
    "\"}"
  let state = "{\"version\":\"actql-run-state/0.1\",\"run_id\":\"original\",\"revision\":0,\"status\":\"running\"," +
    "\"updated_at\":\"2026-10-11T00:00:00.000Z\",\"next_action\":{\"kind\":\"none\"},\"result_available\":false," +
    "\"result_availability\":{},\"control\":{\"revision\":17,\"cancellation_requested\":false,\"physical_stop\":\"unknown\"}}"
  (run, prepared, authorization, ref_wire, state)
}

///|
fn inspect_fixture_snapshot(
  run : PublicationContract,
  ref_wire : String,
  state : String,
) -> String raise {
  // Snapshot identity follows the independently specified existing Owner
  // envelope, not a new control revision or a generated Run View.
  let value = parse_contract_wire(
    "{\"version\":\"actql-owner-snapshot/0.1\",\"ref\":" +
    ref_wire +
    ",\"owner\":{\"kind\":\"run\",\"scopeCid\":\"" +
    inspect_fixture_cid("a") +
    "\",\"streamCid\":\"" +
    run.identity +
    "\"},\"snapshot\":{\"value\":" +
    state +
    "}}",
    65536,
    1000,
    32,
    data_keys=true,
  ).unwrap()
  @json.cid_value(value, 65536, 1000, 32)
}

///|
test "current Run Inspect preserves exact original facts and unknown pending observations" {
  let (run, prepared, authorization, ref_wire, state) = inspect_fixture()
  let snapshot = inspect_fixture_snapshot(run, ref_wire, state)
  let result = project_current_interactive_run_view(
    run,
    prepared,
    authorization,
    ref_wire,
    state,
    snapshot,
    65536,
    1000,
    32,
    static_plan_installed=true,
  )
  assert_eq(result.map(_ => true), Ok(true))
  let wire = result.unwrap()
  let view = parse_interactive_run_control_shape(
    "run_view", wire, 65536, 1000, 32,
  ).unwrap()
  let current = @json.object_field(view, "run_state").unwrap()
  let capabilities = @json.object_field(view, "capabilities").unwrap()
  for field in ["static_plan", "inspect"] {
    assert_true(
      @json.object_field(capabilities, field) is Some(@json.Bool(true)),
    )
  }
  let default_wire = project_current_interactive_run_view(
    run, prepared, authorization, ref_wire, state, snapshot, 65536, 1000, 32,
  ).unwrap()
  assert_true(default_wire.contains("\"static_plan\":false"))
  assert_eq(interactive_integer(current, "control_revision"), Some(17L))
  let legacy = @json.object_field(current, "legacy_state").unwrap()
  assert_eq(interactive_integer(legacy, "revision"), Some(0L))
  for field in ["pause_pending", "expiry_pending", "cleanup_pending"] {
    assert_true(@json.object_field(current, field) is None)
  }
  assert_eq(
    project_interactive_legacy_state(
      @json.stringify_value(current, 65536, 1000, 32),
      65536,
      1000,
      32,
    ).unwrap(),
    @json.stringify_value(
      parse_contract_wire(state, 65536, 1000, 32).unwrap(),
      65536,
      1000,
      32,
    ),
  )
  assert_true(wire.contains("\"logical_map_cid\":null"))
  assert_true(
    wire.contains(
      "\"policy_revision_cid\":\"" + inspect_fixture_cid("4") + "\"",
    ),
  )
}

///|
test "Run Inspect refuses swapped original evidence ref state and snapshot" {
  let (run, prepared, authorization, ref_wire, state) = inspect_fixture()
  let snapshot = inspect_fixture_snapshot(run, ref_wire, state)
  for
    (changed_ref, changed_state, changed_snapshot) in [
      (ref_wire.replace(old="scope", new="foreign"), state, snapshot),
      (ref_wire, state.replace(old="original", new="foreign"), snapshot),
      (ref_wire, state, inspect_fixture_cid("f")),
    ] {
    assert_true(
      project_current_interactive_run_view(
        run, prepared, authorization, changed_ref, changed_state, changed_snapshot,
        65536, 1000, 32,
      )
      is Err(LegacyProjectionMismatch(_)),
    )
  }
  assert_true(
    project_current_interactive_run_view(
      run, authorization, prepared, ref_wire, state, snapshot, 65536, 1000, 32,
    )
    is Err(LegacyProjectionMismatch("original_evidence")),
  )
}

///|
test "Run Inspect does not synthesize missing control revision or resume origin" {
  let (run, prepared, authorization, ref_wire, state) = inspect_fixture()
  let without_control = "{\"version\":\"actql-run-state/0.1\",\"run_id\":\"original\",\"revision\":0,\"status\":\"running\"," +
    "\"updated_at\":\"2026-10-11T00:00:00.000Z\",\"next_action\":{\"kind\":\"none\"},\"result_available\":false,\"result_availability\":{}}"
  for changed in [without_control, state.replace(old="running", new="resuming")] {
    assert_true(
      project_current_interactive_run_view(
        run,
        prepared,
        authorization,
        ref_wire,
        changed,
        inspect_fixture_cid("f"),
        65536,
        1000,
        32,
      )
      is Err(RunStateVersionUnsupported),
    )
  }
  assert_true(
    project_current_interactive_run_view(
      run,
      prepared,
      authorization,
      ref_wire,
      state,
      inspect_fixture_cid("f"),
      256,
      1000,
      32,
    )
    is Err(ControlReadContract(_)),
  )
}

///|
test "Run Inspect rejects missing state revision despite a valid original control" {
  let (run, prepared, authorization, ref_wire, state) = inspect_fixture()
  let missing = state.replace(old="\"revision\":0,", new="")
  let snapshot = inspect_fixture_snapshot(run, ref_wire, missing)
  assert_true(
    project_current_interactive_run_view(
      run, prepared, authorization, ref_wire, missing, snapshot, 65536, 1000, 32,
    )
    is Err(ControlReadContract(_)),
  )
}

///|
test "Common Inspect admits the original park and distinguishes TTL policy from expiry" {
  let (run, prepared, authorization, ref_wire, state) = inspect_fixture()
  let snapshot = inspect_fixture_snapshot(run, ref_wire, state)
  let park = "{\"kind\":\"logical_step\",\"run_ref\":" +
    ref_wire +
    ",\"revision\":17,\"logical_map_cid\":\"" +
    inspect_fixture_cid("8") +
    "\",\"paused_at\":\"2026-10-11T00:05:00.000Z\",\"expires_at\":\"2026-10-11T00:10:00.000Z\"," +
    "\"ttl_policy\":\"original_debug_entry_deadline\",\"start_revision\":3,\"control_revision\":2," +
    "\"committed_generation\":6,\"completed_step_id\":\"" +
    inspect_fixture_cid("b") +
    "\",\"next_step_id\":\"" +
    inspect_fixture_cid("c") +
    "\"}"
  let project = fn(facts) {
    project_current_interactive_run_view(
      run,
      prepared,
      authorization,
      ref_wire,
      state,
      snapshot,
      65536,
      1000,
      32,
      debug_park_wire=facts,
    )
  }
  let expected_policy = "sha256:4a06ba524815748a22538336a03e266e62c56d3ee74fd331e18c09946c709112"
  for expiry in ["00:10:00", "00:11:00"] {
    let wire = project(park.replace(old="00:10:00", new=expiry)).unwrap()
    let value = parse_contract_wire(wire, 65536, 1000, 32, data_keys=true).unwrap()
    assert_eq(
      contract_string_from_value(value, "logical_map_cid"),
      Some(inspect_fixture_cid("8")),
    )
    assert_eq(
      contract_string_from_value(value, "compiled_plan_cid"),
      Some(inspect_fixture_cid("2")),
    )
    assert_eq(
      contract_string_from_value(value, "consistency"),
      Some("non_atomic"),
    )
    let paused = @json.object_field(value, "run_state").unwrap()
    assert_eq(contract_string_from_value(paused, "status"), Some("paused"))
    assert_eq(
      contract_string_from_value(paused, "expires_at"),
      Some("2026-10-11T" + expiry + ".000Z"),
    )
    assert_eq(
      contract_string_from_value(paused, "ttl_policy_cid"),
      Some(expected_policy),
    )
    assert_true(@json.object_field(paused, "legacy_state") is None)
    let boundary = @json.object_field(paused, "boundary").unwrap()
    assert_eq(contract_string_from_value(boundary, "position"), Some("before"))
    assert_eq(
      contract_string_from_value(boundary, "step_id"),
      Some(inspect_fixture_cid("c")),
    )
    let boundary_body = parse_contract_wire(
      "{\"version\":\"actql-local-debug-park-boundary/0.1\",\"run_ref\":" +
      ref_wire +
      ",\"compiled_plan_cid\":\"" +
      inspect_fixture_cid("2") +
      "\",\"logical_map_cid\":\"" +
      inspect_fixture_cid("8") +
      "\",\"kind\":\"logical_step\",\"revision\":17,\"start_revision\":3,\"control_revision\":2," +
      "\"committed_generation\":6,\"completed_step_id\":\"" +
      inspect_fixture_cid("b") +
      "\",\"next_step_id\":\"" +
      inspect_fixture_cid("c") +
      "\"}",
      65536,
      1000,
      32,
      data_keys=true,
    ).unwrap()
    assert_eq(
      contract_string_from_value(boundary, "consumed_boundary_cid"),
      Some(@json.cid_value(boundary_body, 65536, 1000, 32)),
    )
  }
  for
    corrupt in [
      park.replace(
        old="original_debug_entry_deadline",
        new="observed_absolute_expiry",
      ),
      park.replace(old="\"revision\":17", new="\"revision\":16"),
      park.replace(old="\"scope\"", new="\"foreign\""),
      park.replace(old="2026-10-11T00:10:00", new="2026-10-13T00:10:00"),
      park.replace(
        old="\"committed_generation\":6",
        new="\"committed_generation\":6,\"other\":0",
      ),
    ] {
    assert_true(
      project(corrupt) is Err(ControlReadContract(InvalidField("debug_park"))),
    )
  }
  let stopped_state = state
    .replace(old="\"running\"", new="\"needs_reconciliation\"")
    .replace(
      old="\"physical_stop\":\"unknown\"",
      new="\"physical_stop\":\"confirmed\"",
    )
    .replace(
      old="\"next_action\":{\"kind\":\"none\"}",
      new="\"next_action\":{\"kind\":\"reconcile_run\",\"reason\":\"execution_unknown\"}",
    )
  let stopped_park = park
    .replace(
      old="\"kind\":\"logical_step\"",
      new="\"kind\":\"stopped_logical_step\"",
    )
    .replace(
      old="\"revision\":17",
      new="\"revision\":17,\"parked_revision\":16,\"resume_available\":true",
    )
  fn project_stopped(
    observed : String,
    facts : String,
  ) -> Result[String, RunControlReadIssue] raise {
    project_current_interactive_run_view(
      run,
      prepared,
      authorization,
      ref_wire,
      observed,
      inspect_fixture_snapshot(run, ref_wire, observed),
      65536,
      1000,
      32,
      debug_park_wire=facts,
    )
  }
  let stopped_wire = project_stopped(stopped_state, stopped_park).unwrap()
  let restored = parse_contract_wire(
    stopped_wire,
    65536,
    1000,
    32,
    data_keys=true,
  ).unwrap()
  let ready = @json.object_field(restored, "run_state").unwrap()
  assert_eq(contract_string_from_value(ready, "status"), Some("paused"))
  assert_eq(interactive_integer(ready, "control_revision"), Some(17L))
  let continued = @json.object_field(ready, "boundary").unwrap()
  assert_eq(
    contract_string_from_value(continued, "step_id"),
    Some(inspect_fixture_cid("c")),
  )
  let marked_park = stopped_park.replace(
    old="\"resume_available\":true",
    new="\"resume_available\":true,\"matched_breakpoint_step_id\":\"" +
      inspect_fixture_cid("c") +
      "\"",
  )
  let marked = parse_contract_wire(
    project_stopped(stopped_state, marked_park).unwrap(),
    65536,
    1000,
    32,
    data_keys=true,
  ).unwrap()
  let marked_state = @json.object_field(marked, "run_state").unwrap()
  assert_eq(
    contract_string_from_value(marked_state, "stop_reason"),
    Some("breakpoint"),
  )
  let marks = @json.object_field(marked_state, "matched_breakpoints").unwrap()
  assert_eq(
    @json.stringify_value(marks, 1024, 4, 4),
    "[\"" + inspect_fixture_cid("c") + "\"]",
  )
  assert_true(
    project_stopped(
      stopped_state,
      marked_park.replace(
        old="\"matched_breakpoint_step_id\":\"" + inspect_fixture_cid("c"),
        new="\"matched_breakpoint_step_id\":\"" + inspect_fixture_cid("d"),
      ),
    )
    is Err(ControlReadContract(InvalidField("debug_park"))),
  )
  let running_wire = project(park).unwrap()
  let running = parse_contract_wire(
    running_wire,
    65536,
    1000,
    32,
    data_keys=true,
  ).unwrap()
  let live = @json.object_field(
    @json.object_field(running, "run_state").unwrap(),
    "boundary",
  ).unwrap()
  assert_eq(
    contract_string_from_value(continued, "consumed_boundary_cid"),
    contract_string_from_value(live, "consumed_boundary_cid"),
  )
  let input_state = state
    .replace(old="\"running\"", new="\"resuming\"")
    .replace(
      old="\"physical_stop\":\"unknown\"",
      new="\"physical_stop\":\"confirmed\"",
    )
  let input_park = park.replace(
    old="\"kind\":\"logical_step\"",
    new="\"kind\":\"input_logical_step\"",
  )
  let input_view = parse_contract_wire(
    project_stopped(input_state, input_park).unwrap(),
    65536,
    1000,
    32,
    data_keys=true,
  ).unwrap()
  let input_paused = @json.object_field(input_view, "run_state").unwrap()
  assert_eq(contract_string_from_value(input_paused, "status"), Some("paused"))
  assert_eq(interactive_integer(input_paused, "control_revision"), Some(17L))
  let input_boundary = @json.object_field(input_paused, "boundary").unwrap()
  assert_eq(
    contract_string_from_value(input_boundary, "consumed_boundary_cid"),
    contract_string_from_value(live, "consumed_boundary_cid"),
  )
  for
    (observed, facts) in [
      (state, stopped_park),
      (stopped_state, park),
      (state, input_park),
      (input_state, park),
      (
        input_state.replace(
          old="\"physical_stop\":\"confirmed\"",
          new="\"physical_stop\":\"unknown\"",
        ),
        input_park,
      ),
      (
        stopped_state,
        stopped_park.replace(
          old="\"parked_revision\":16",
          new="\"parked_revision\":15",
        ),
      ),
      (
        stopped_state.replace(
          old="\"cancellation_requested\":false",
          new="\"cancellation_requested\":true",
        ),
        stopped_park,
      ),
    ] {
    assert_true(
      project_stopped(observed, facts)
      is Err(ControlReadContract(InvalidField("debug_park"))),
    )
  }
  let entry_state = state.replace(old="\"running\"", new="\"preparing\"")
  let entry_snapshot = inspect_fixture_snapshot(run, ref_wire, entry_state)
  let entry = "{\"kind\":\"entry\",\"run_ref\":" +
    ref_wire +
    ",\"revision\":17,\"logical_map_cid\":\"" +
    inspect_fixture_cid("8") +
    "\",\"paused_at\":\"2026-10-11T00:05:00.000Z\",\"expires_at\":\"2026-10-11T00:10:00.000Z\"," +
    "\"ttl_policy\":\"original_debug_entry_deadline\"}"
  let wire = project_current_interactive_run_view(
    run,
    prepared,
    authorization,
    ref_wire,
    entry_state,
    entry_snapshot,
    65536,
    1000,
    32,
    debug_park_wire=entry,
  ).unwrap()
  let projected = parse_contract_wire(wire, 65536, 1000, 32, data_keys=true).unwrap()
  let paused = @json.object_field(projected, "run_state").unwrap()
  assert_eq(contract_string_from_value(paused, "stop_reason"), Some("entry"))
  assert_eq(
    contract_string_from_value(paused, "ttl_policy_cid"),
    Some(expected_policy),
  )
  let boundary = @json.object_field(paused, "boundary").unwrap()
  assert_true(@json.object_field(boundary, "step_id") is Some(@json.Null))
  fn project_entry(facts : String) -> Result[String, RunControlReadIssue] {
    project_current_interactive_run_view(
      run,
      prepared,
      authorization,
      ref_wire,
      entry_state,
      entry_snapshot,
      65536,
      1000,
      32,
      debug_park_wire=facts,
    )
  }
  let step = inspect_fixture_cid("c")
  let mapped = entry.replace(
    old="\"ttl_policy\":",
    new="\"next_step_id\":\"" +
      step +
      "\",\"resume_available\":true,\"ttl_policy\":",
  )
  let mapped_view = parse_contract_wire(
    project_entry(mapped).unwrap(),
    65536,
    1000,
    32,
    data_keys=true,
  ).unwrap()
  let mapped_boundary = @json.object_field(
    @json.object_field(mapped_view, "run_state").unwrap(),
    "boundary",
  ).unwrap()
  assert_eq(contract_string_from_value(mapped_boundary, "step_id"), Some(step))
  assert_eq(
    contract_string_from_value(mapped_boundary, "consumed_boundary_cid"),
    contract_string_from_value(boundary, "consumed_boundary_cid"),
  )
  let selection = "{\"logical_map_cid\":\"" +
    inspect_fixture_cid("8") +
    "\",\"before_step_ids\":[\"" +
    step +
    "\",\"" +
    inspect_fixture_cid("d") +
    "\"]}"
  let marked = mapped.replace(
    old="\"ttl_policy\":",
    new="\"entry_breakpoint_selection\":" + selection + ",\"ttl_policy\":",
  )
  let marked_view = parse_contract_wire(
    project_entry(marked).unwrap(),
    65536,
    1000,
    32,
    data_keys=true,
  ).unwrap()
  let expected_selection = parse_contract_wire(
    selection,
    65536,
    1000,
    32,
    data_keys=true,
  ).unwrap()
  assert_eq(
    @json.stringify_value(
      @json.object_field(marked_view, "entry_breakpoint_selection").unwrap(),
      65536,
      1000,
      32,
    ),
    @json.stringify_value(expected_selection, 65536, 1000, 32),
  )
  assert_eq(
    @json.stringify_value(
      @json.object_field(marked_view, "run_state").unwrap(),
      65536,
      1000,
      32,
    ),
    @json.stringify_value(
      @json.object_field(mapped_view, "run_state").unwrap(),
      65536,
      1000,
      32,
    ),
  )
  assert_true(
    project_entry(
      marked.replace(
        old="\"resume_available\":true",
        new="\"resume_available\":false",
      ),
    )
    is Err(_),
  )
  assert_true(
    project_entry(
      marked.replace(
        old=selection,
        new=selection.replace(
          old=inspect_fixture_cid("8"),
          new=inspect_fixture_cid("f"),
        ),
      ),
    )
    is Err(_),
  )
  assert_true(
    project_entry(
      marked.replace(
        old=selection,
        new=selection.replace(old=inspect_fixture_cid("d"), new=step),
      ),
    )
    is Err(_),
  )
  let mapless = entry.replace(
    old="\"" + inspect_fixture_cid("8") + "\"",
    new="null",
  )
  assert_true(project_entry(mapless) is Ok(_))
  assert_true(
    project_entry(
      mapless.replace(
        old="\"ttl_policy\":",
        new="\"resume_available\":true,\"ttl_policy\":",
      ),
    )
    is Err(ControlReadContract(InvalidField("debug_park"))),
  )
  let malformed = state.replace(
    old="\"revision\":0",
    new="\"unexpected\":0,\"revision\":0",
  )
  assert_true(
    project_current_interactive_run_view(
      run,
      prepared,
      authorization,
      ref_wire,
      malformed,
      inspect_fixture_snapshot(run, ref_wire, malformed),
      65536,
      1000,
      32,
      debug_park_wire=park,
    )
    is Err(ControlReadContract(InvalidField("run_state"))),
  )
  let cancelled = state.replace(
    old="\"cancellation_requested\":false",
    new="\"cancellation_requested\":true",
  )
  assert_true(
    project_current_interactive_run_view(
      run,
      prepared,
      authorization,
      ref_wire,
      cancelled,
      inspect_fixture_snapshot(run, ref_wire, cancelled),
      65536,
      1000,
      32,
      debug_park_wire=park,
    )
    is Err(ControlReadContract(InvalidField("debug_park"))),
  )
}

///|
test "breakpoint receipt binds a matching original entry or task park" {
  let (run, _, _, ref_wire, _) = inspect_fixture()
  let map = inspect_fixture_cid("8")
  let command = seal_run_evidence_value(
    "control_command",
    "{\"version\":\"actql-control-command/0.1\",\"operation\":\"resume\",\"operation_id\":\"breakpoint-original\",\"run_ref\":" +
    ref_wire +
    ",\"expected_control_revision\":17,\"interval\":{\"until\":\"breakpoint\",\"guards\":null,\"breakpoint_selection\":{\"logical_map_cid\":\"" +
    map +
    "\",\"before_step_ids\":[\"" +
    inspect_fixture_cid("c") +
    "\"]}}}",
    4096,
    64,
    8,
  ).unwrap()
  let original = "{\"run_ref\":" +
    ref_wire +
    ",\"revision\":17,\"logical_map_cid\":\"" +
    map +
    "\",\"paused_at\":\"2026-10-11T00:05:00.000Z\",\"expires_at\":\"2026-10-11T00:10:00.000Z\",\"ttl_policy\":\"original_debug_entry_deadline\","
  let task = original +
    "\"kind\":\"logical_step\",\"start_revision\":3,\"control_revision\":2,\"committed_generation\":6,\"completed_step_id\":\"" +
    inspect_fixture_cid("b") +
    "\",\"next_step_id\":\"" +
    inspect_fixture_cid("d") +
    "\"}"
  let accepted_at = "2026-10-11T00:06:00.000Z"
  let receipt = issue_local_debug_resume_receipt(
    run, command, task, 18, accepted_at, 65536, 1000, 32,
  ).unwrap()
  let operation = @json.object_field(receipt.value, "operation_ref").unwrap()
  assert_eq(
    contract_string_from_value(operation, "command_cid"),
    Some(command.identity),
  )
  let mismatched_map = task.replace(old=map, new=inspect_fixture_cid("9"))
  let entry = original + "\"kind\":\"entry\"}"
  let entry_receipt = issue_local_debug_resume_receipt(
    run, command, entry, 18, accepted_at, 65536, 1000, 32,
  ).unwrap()
  let entry_operation = @json.object_field(entry_receipt.value, "operation_ref").unwrap()
  assert_eq(
    contract_string_from_value(entry_operation, "command_cid"),
    Some(command.identity),
  )
  assert_true(entry_receipt.identity != receipt.identity)
  let mismatched_entry = entry.replace(old=map, new=inspect_fixture_cid("9"))
  let no_next = task.replace(
    old="\"" + inspect_fixture_cid("d") + "\"",
    new="null",
  )
  for park in [mismatched_map, mismatched_entry, no_next] {
    assert_true(
      issue_local_debug_resume_receipt(
        run, command, park, 18, accepted_at, 65536, 1000, 32,
      )
      is Err(ControlReadContract(InvalidField("control_command"))),
    )
  }
}

///|
test "local Debug receipt seals the original entry and Step CAS in Common" {
  let (run, _, _, ref_wire, _) = inspect_fixture()
  let operation_id = "manual-original"
  let accepted_at = "2026-10-11T00:06:00.000Z"
  let window =
    #|,"paused_at":"2026-10-11T00:05:00.000Z","expires_at":"2026-10-11T00:10:00.000Z"
  let task = ",\"start_revision\":3,\"control_revision\":2,\"committed_generation\":6,\"completed_step_id\":\"" +
    inspect_fixture_cid("b") +
    "\",\"next_step_id\":null"
  fn hash(preimage : String) -> String raise {
    let data = parse_contract_wire(preimage, 65536, 1000, 32, data_keys=true).unwrap()
    @json.cid_value(data, 65536, 1000, 32)
  }
  for (kind, fields) in [("entry", ""), ("logical_step", task)] {
    let command = seal_run_evidence_value(
      "control_command",
      "{\"version\":\"actql-control-command/0.1\",\"operation\":\"resume\",\"operation_id\":\"" +
      operation_id +
      "\",\"run_ref\":" +
      ref_wire +
      ",\"expected_control_revision\":17,\"interval\":{\"until\":\"step\",\"guards\":null}}",
      4096,
      64,
      8,
    ).unwrap()
    let park = "{\"kind\":\"" +
      kind +
      "\",\"run_ref\":" +
      ref_wire +
      ",\"revision\":17,\"logical_map_cid\":\"" +
      inspect_fixture_cid("8") +
      "\"" +
      window +
      ",\"ttl_policy\":\"original_debug_entry_deadline\"" +
      fields +
      "}"
    let receipt = issue_local_debug_resume_receipt(
      run, command, park, 18, accepted_at, 65536, 1000, 32,
    ).unwrap()
    let boundary = hash(
      "{\"version\":\"actql-local-debug-park-boundary/0.1\",\"kind\":\"" +
      kind +
      "\",\"run_ref\":" +
      ref_wire +
      ",\"revision\":17,\"compiled_plan_cid\":\"" +
      inspect_fixture_cid("2") +
      "\",\"logical_map_cid\":\"" +
      inspect_fixture_cid("8") +
      "\"" +
      fields +
      "}",
    )
    let generation = hash(
      "{\"version\":\"actql-local-debug-continuation-generation/0.1\",\"consumed_boundary_cid\":\"" +
      boundary +
      "\"" +
      window +
      "}",
    )
    let operation_ref = "{\"run_ref\":" +
      ref_wire +
      ",\"accepted_from_revision\":17,\"operation_id\":\"manual-original\",\"command_cid\":\"" +
      command.identity +
      "\"}"
    let fence = hash(
      "{\"version\":\"actql-local-debug-resume-fence/0.1\",\"operation_ref\":" +
      operation_ref +
      ",\"continuation_generation_cid\":\"" +
      generation +
      "\",\"accepted_revision\":18}",
    )
    let original = "{\"version\":\"actql-control-operation-receipt/0.1\",\"outcome\":\"accepted\",\"operation_ref\":" +
      operation_ref +
      ",\"observed_state\":{\"version\":\"actql-controlled-run-state/0.1\",\"run_id\":\"original\",\"status\":\"resuming\",\"control_revision\":18,\"updated_at\":\"" +
      accepted_at +
      "\",\"resume_origin\":{\"kind\":\"manual\",\"command_cid\":\"" +
      command.identity +
      "\",\"continuation_generation_cid\":\"" +
      generation +
      "\",\"fence_cid\":\"" +
      fence +
      "\"}}}"
    assert_eq(receipt.identity, hash(original))
    let admitted = parse_interactive_run_control_shape(
      "control_operation_receipt",
      receipt.wire,
      65536,
      1000,
      32,
    ).unwrap()
    let observed = @json.object_field(admitted, "observed_state").unwrap()
    assert_eq(contract_string_from_value(observed, "status"), Some("resuming"))
    assert_true(@json.object_field(observed, "legacy_state") is None)
    assert_true(@json.object_field(observed, "cleanup_pending") is None)
    let (bytes, nodes, depth) = receipt.wire_usage.unwrap()
    assert_true(
      issue_local_debug_resume_receipt(
        run, command, park, 18, accepted_at, bytes, nodes, depth,
      ).unwrap().wire ==
      receipt.wire,
    )
    for
      (changed, revision, at, limit) in [
        (
          park.replace(old="\"scope\"", new="\"foreign\""),
          18,
          accepted_at,
          65536,
        ),
        (
          park.replace(
            old=inspect_fixture_cid("a"),
            new=inspect_fixture_cid("e"),
          ),
          18,
          accepted_at,
          65536,
        ),
        (
          park.replace(old="\"revision\":17", new="\"revision\":16"),
          18,
          accepted_at,
          65536,
        ),
        (park, 19, accepted_at, 65536),
        (park, 18, "2026-10-11T00:10:00.000Z", 65536),
        (park, 18, "2026-10-11T00:04:59.999Z", 65536),
        (park, 18, accepted_at, bytes - 1),
      ] {
      assert_true(
        issue_local_debug_resume_receipt(
          run, command, changed, revision, at, limit, 1000, 32,
        )
        is Err(_),
      )
    }
  }
}

///|
test "Effect Inspect and confirmation share the original write hold" {
  let (run, prepared, authorization, ref_wire, state) = inspect_fixture()
  let preview_cid = inspect_fixture_cid("c")
  let member_cid = inspect_fixture_cid("d")
  let selection = "{\"unit_id\":\"write\",\"effect_preview_cid\":\"" +
    preview_cid +
    "\",\"member_preview_cid\":\"" +
    member_cid +
    "\"}"
  fn command_for(operation_id : String) -> RunEvidenceValue {
    seal_run_evidence_value(
      "control_command",
      "{\"version\":\"actql-control-command/0.1\",\"operation\":\"confirm_write\",\"run_ref\":" +
      ref_wire +
      ",\"expected_control_revision\":17,\"operation_id\":\"" +
      operation_id +
      "\",\"effect_write\":" +
      selection +
      "}",
      4096,
      64,
      8,
    ).unwrap()
  }
  let command = command_for("original-write")
  let accepted = "2026-10-11T00:06:00.000Z"
  let window =
    #|,"paused_at":"2026-10-11T00:05:00.000Z","expires_at":"2026-10-11T00:10:00.000Z"
  let park = "{\"version\":\"actql-local-debug-effect-write-park/0.1\",\"run_ref\":" +
    ref_wire +
    ",\"start_revision\":5,\"revision\":17,\"effect_write\":" +
    selection +
    window +
    "}"
  fn issue(
    wire : String,
    revision : Int,
    at : String,
    bytes : Int,
  ) -> Result[RunEvidenceValue, RunControlReadIssue] {
    issue_local_effect_write_confirmation_receipt(
      run, command, wire, revision, at, bytes, 1000, 32,
    )
  }
  fn hash(wire : String) -> String raise {
    let value = parse_contract_wire(wire, 65536, 1000, 32, data_keys=true).unwrap()
    @json.cid_value(value, 65536, 1000, 32)
  }
  let receipt = issue(park, 18, accepted, 65536).unwrap()
  fn inspect(
    original : String,
    current_state : String,
    can_confirm : Bool,
  ) -> Result[String, RunControlReadIssue] raise {
    project_current_interactive_run_view(
      run,
      prepared,
      authorization,
      ref_wire,
      current_state,
      inspect_fixture_snapshot(run, ref_wire, current_state),
      65536,
      1000,
      32,
      debug_park_wire="{\"effect_write_park\":" +
        original +
        ",\"confirm_available\":" +
        can_confirm.to_string() +
        "}",
    )
  }
  for can_confirm in [false, true] {
    let view = parse_interactive_run_control_shape(
      "run_view",
      inspect(park, state, can_confirm).unwrap(),
      65536,
      1000,
      32,
    ).unwrap()
    let observed = @json.object_field(view, "run_state").unwrap()
    let boundary = @json.object_field(observed, "boundary").unwrap()
    assert_eq(contract_string_from_value(observed, "status"), Some("paused"))
    assert_eq(
      contract_string_from_value(observed, "stop_reason"),
      Some("effect_write"),
    )
    assert_eq(contract_string_from_value(boundary, "position"), Some("before"))
    assert_true(@json.object_field(boundary, "step_id") is Some(@json.Null))
    assert_eq(
      contract_string_from_value(boundary, "consumed_boundary_cid"),
      Some(hash(park)),
    )
    let shown = @json.object_field(boundary, "effect_write").unwrap()
    assert_eq(@json.cid_value(shown, 65536, 1000, 32), hash(selection))
    let operations = @json.object_field(view, "available_operations").unwrap()
    let expected = if can_confirm {
      "[\"inspect\",\"confirm_write\"]"
    } else {
      "[\"inspect\"]"
    }
    assert_eq(@json.cid_value(operations, 65536, 1000, 32), hash(expected))
  }
  assert_true(
    inspect(
      park.replace(old="\"revision\":17", new="\"revision\":16"),
      state,
      true,
    )
    is Err(_),
  )
  assert_true(
    inspect(
      park.replace(old=inspect_fixture_cid("a"), new=inspect_fixture_cid("e")),
      state,
      true,
    )
    is Err(_),
  )
  assert_true(
    inspect(
      park,
      state.replace(
        old="\"cancellation_requested\":false",
        new="\"cancellation_requested\":true",
      ),
      true,
    )
    is Err(_),
  )
  let preimage = "{\"version\":\"actql-local-debug-continuation-generation/0.1\",\"consumed_boundary_cid\":\"" +
    hash(park) +
    "\"" +
    window +
    "}"
  let generation = hash(preimage)
  let operation = "{\"run_ref\":" +
    ref_wire +
    ",\"operation_id\":\"original-write\",\"command_cid\":\"" +
    command.identity +
    "\",\"accepted_from_revision\":17}"
  let fence = hash(
    "{\"version\":\"actql-local-debug-resume-fence/0.1\",\"operation_ref\":" +
    operation +
    ",\"continuation_generation_cid\":\"" +
    generation +
    "\",\"accepted_revision\":18}",
  )
  assert_eq(
    receipt.identity,
    hash(
      "{\"version\":\"actql-control-operation-receipt/0.1\",\"outcome\":\"accepted\",\"operation_ref\":" +
      operation +
      ",\"observed_state\":{\"version\":\"actql-controlled-run-state/0.1\",\"run_id\":\"original\",\"status\":\"resuming\",\"control_revision\":18,\"updated_at\":\"" +
      accepted +
      "\",\"resume_origin\":{\"kind\":\"manual\",\"command_cid\":\"" +
      command.identity +
      "\",\"continuation_generation_cid\":\"" +
      generation +
      "\",\"fence_cid\":\"" +
      fence +
      "\"}}}",
    ),
  )
  let competing = issue_local_effect_write_confirmation_receipt(
    run,
    command_for("competing-write"),
    park,
    18,
    accepted,
    65536,
    1000,
    32,
  ).unwrap()
  let observed = @json.object_field(competing.value, "observed_state").unwrap()
  let origin = @json.object_field(observed, "resume_origin").unwrap()
  assert_eq(
    contract_string_from_value(origin, "continuation_generation_cid"),
    Some(generation),
  )
  assert_true(contract_string_from_value(origin, "fence_cid") != Some(fence))
  for
    wrong in [
      park.replace(old="\"scope\"", new="\"other\""),
      park.replace(old=inspect_fixture_cid("a"), new=inspect_fixture_cid("e")),
      park.replace(old="\"write\"", new="\"foreign-unit\""),
      park.replace(old=preview_cid, new=inspect_fixture_cid("f")),
      park.replace(old=member_cid, new=inspect_fixture_cid("f")),
      park.replace(old="\"start_revision\":5", new="\"start_revision\":17"),
      park.replace(old="\"revision\":17", new="\"revision\":16"),
      park.replace(
        old=",\"revision\":17",
        new=",\"revision\":17,\"approval\":true",
      ),
    ] {
    assert_true(issue(wrong, 18, accepted, 65536) is Err(_))
  }
  let (bytes, _, _) = receipt.wire_usage.unwrap()
  assert_eq(issue(park, 18, accepted, bytes).unwrap().wire, receipt.wire)
  assert_true(issue(park, 18, accepted, bytes - 1) is Err(_))
  assert_true(issue(park, 19, accepted, 65536) is Err(_))
  assert_true(issue(park, 18, "2026-10-11T00:04:59.999Z", 65536) is Err(_))
  assert_true(issue(park, 18, "2026-10-11T00:10:00.000Z", 65536) is Err(_))
}
