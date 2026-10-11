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
  let state = "{\"version\":\"actql-run-state/0.1\",\"run_id\":\"original\",\"status\":\"running\"," +
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
    run, prepared, authorization, ref_wire, state, snapshot, 65536, 1000, 32,
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
    assert_true(@json.object_field(capabilities, field) is Some(@json.Bool(true)))
  }
  let default_wire = project_current_interactive_run_view(
    run, prepared, authorization, ref_wire, state, snapshot, 65536, 1000, 32,
  ).unwrap()
  assert_true(default_wire.contains("\"static_plan\":false"))
  assert_eq(interactive_integer(current, "control_revision"), Some(17L))
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
  let without_control = "{\"version\":\"actql-run-state/0.1\",\"run_id\":\"original\",\"status\":\"running\"," +
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
