///|
// Protocol-only component: real admitted Coordinator/Site transitions, not
// physical execution, normal Workers/SDK acceptance or a cleanup ACK.
fn single_site_test_cid(digit : String) -> String {
  "sha256:" + digit.repeat(64)
}

///|
fn single_site_definition() -> @publication.PublicationContract {
  @publication.seal_publication_contract(
    "run_definition",
    "{\"version\":\"actql-run-definition/0.1\",\"scope_id\":\"original-scope\",\"run_id\":\"original-single-site-run\",\"compiled_plan_cid\":\"" +
    single_site_test_cid("1") +
    "\",\"invocation_template_cid\":\"" +
    single_site_test_cid("2") +
    "\",\"authorization_context_cid\":\"" +
    single_site_test_cid("3") +
    "\",\"input_artifact_set_cid\":\"" +
    single_site_test_cid("4") +
    "\",\"created_at\":\"2026-11-01T00:00:00.000Z\",\"valid_until\":\"2099-01-01T00:00:00.000Z\"}",
    65536,
    4096,
    32,
  ).unwrap()
}

///|
fn single_site_state_text(wire : String, name : String) -> String {
  let source = @source.parse_json(wire, {
    max_input_bytes: 65536,
    max_nodes: 256,
    max_depth: 16,
  }).unwrap()
  let cursor = @decode.admit(source, {
    max_nodes: 256,
    max_depth: 16,
    max_string_bytes: 4096,
    max_total_string_bytes: 65536,
  }).unwrap()
  let object = @decode.open_object(cursor).unwrap()
  @decode.text(@decode.required(object, name).unwrap()).unwrap()
}

///|
fn single_site_observation_fixture(
  authority : String,
  run : String,
  task : String,
  rejected : Bool,
  released : Bool,
) -> @remote.DurableCoordinatorDispatchRecord {
  let bundle = single_site_test_cid("a")
  let request = @remote.prepare_dispatch_request(
    authority,
    run,
    task,
    1,
    "evidence-dispatch",
    "site-a",
    1,
    bundle,
    "local",
    "local/1",
    "strategy/1",
    single_site_test_cid("1"),
    single_site_test_cid("2"),
    single_site_test_cid("3"),
    single_site_test_cid("4"),
    single_site_test_cid("5"),
  ).unwrap()
  let site = @site.create_site("site-a", 1, bundle, 4, 4, 1048576L, 1048576L).unwrap()
  let (_, record) = @remote.commit_dispatch_acceptance(
    @remote.prepare_dispatch_acceptance(
      @remote.create_site_dispatch_journal(site, "actql-remote-site/0.1").unwrap(),
      request,
    ).unwrap(),
    true,
  ).unwrap()
  let capability = @remote.register_remote_execution_capability(
    site,
    bundle,
    "local",
    "local/1",
    "strategy/1",
    single_site_test_cid("5"),
  ).unwrap()
  @remote.commit_dispatch_transition(
    @remote.prepare_begin_provisioning(record, capability).unwrap(),
    true,
  ).unwrap()
  @remote.commit_dispatch_transition(
    @remote.prepare_begin_remote_execution(record).unwrap(),
    true,
  ).unwrap()
  @remote.commit_dispatch_transition(
    @remote.prepare_confirm_native_settled(record).unwrap(),
    true,
  ).unwrap()
  if rejected {
    let failure = @remote.prepare_remote_runtime_failure(record, false, true).unwrap()
    @remote.commit_dispatch_transition(
      @remote.remote_runtime_step_transition(failure).unwrap(),
      true,
    ).unwrap()
  }
  if released {
    @remote.commit_dispatch_transition(
      @remote.prepare_begin_remote_release(record).unwrap(),
      true,
    ).unwrap()
    @remote.commit_dispatch_transition(
      @remote.prepare_confirm_remote_release(record).unwrap(),
      true,
    ).unwrap()
  }
  let initial = @remote.prepare_coordinator_dispatch_intent(
    @remote.create_coordinator_dispatch_journal(authority).unwrap(),
    request,
  ).unwrap()
  let saved = @remote.admit_durable_coordinator_dispatch_record(
    @utf8.encode(
      @remote.coordinator_dispatch_admission_durable_json(initial).unwrap(),
    ),
  ).unwrap()
  let (_, coordinator) = @remote.commit_coordinator_dispatch_intent(
    initial, true,
  ).unwrap()
  let codes = @remote.dispatch_record_state_codes(record)
  let transition = @remote.prepare_coordinator_site_observation(
    coordinator,
    @remote.dispatch_record_revision(record),
    codes[0],
    codes[1],
    codes[2],
    codes[3] == 1,
    codes[4] == 1,
    None,
  ).unwrap()
  let observed = @remote.admit_durable_coordinator_dispatch_record(
    @utf8.encode(
      @remote.coordinator_dispatch_transition_durable_json(saved, transition).unwrap(),
    ),
  ).unwrap()
  @remote.commit_coordinator_dispatch_transition(transition, true).unwrap()
  observed
}

///|
test "single Site rejection reaches failed Run without rewriting execution or cleanup" {
  let definition = single_site_definition()
  let authority = single_site_test_cid("c")
  let task = "original-task"
  let run = @publication.publication_contract_identity(definition)
  for (released, cancelled) in [(false, false), (true, false), (true, true)] {
    let saved = single_site_observation_fixture(
      authority, run, task, true, released,
    )
    let fields = client_host_project_site_run(
      definition,
      task,
      ["answer"],
      authority,
      @remote.durable_coordinator_dispatch_record_json(saved),
      "2026-11-01T00:01:00.000Z",
      cancelled,
      true,
    ).unwrap()
    assert_eq(single_site_state_text(fields[0], "status"), "failed")
    assert_eq(fields[1], "settled")
    assert_eq(fields[2], if released { "complete" } else { "pending" })
    assert_eq(fields[4], if released { "none" } else { "cleanup" })
  }
}

///|
test "single Site rejection is distinct from settled pending evidence after release" {
  let definition = single_site_definition()
  let authority = single_site_test_cid("c")
  let task = "original-task"
  let saved = single_site_observation_fixture(
    authority,
    @publication.publication_contract_identity(definition),
    task,
    false,
    true,
  )
  let fields = client_host_project_site_run(
    definition,
    task,
    ["answer"],
    authority,
    @remote.durable_coordinator_dispatch_record_json(saved),
    "2026-11-01T00:01:00.000Z",
    false,
    true,
  ).unwrap()
  assert_true(single_site_state_text(fields[0], "status") != "failed")
  assert_eq(fields[1], "settled")
  assert_eq(fields[2], "complete")
  assert_eq(fields[4], "reconcile")
}

///|
test "single Site projection retains original authority Run and task refusal" {
  let definition = single_site_definition()
  let authority = single_site_test_cid("c")
  let task = "original-task"
  let saved = single_site_observation_fixture(
    authority,
    @publication.publication_contract_identity(definition),
    task,
    true,
    true,
  )
  for
    (supplied_authority, supplied_task) in [
      (single_site_test_cid("d"), task),
      (authority, "foreign-task"),
    ] {
    assert_true(
      client_host_project_site_run(
        definition,
        supplied_task,
        ["answer"],
        supplied_authority,
        @remote.durable_coordinator_dispatch_record_json(saved),
        "2026-11-01T00:01:00.000Z",
        false,
        true,
      )
      is Err(_),
    )
  }
}
