///|
// Protocol component only: these committed in-memory Site transitions are not
// observations of a physical executor, storage ACK or provider cleanup.
fn remote_evidence_observation_fixture(
  authority : String,
  run : String,
  task : String,
  rejected : Bool,
  released : Bool,
) -> @remote.DurableCoordinatorDispatchRecord {
  let bundle = retained_input_cid("a")
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
    retained_input_cid("1"),
    retained_input_cid("2"),
    retained_input_cid("3"),
    retained_input_cid("4"),
    retained_input_cid("5"),
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
    retained_input_cid("5"),
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
test "settled rejected evidence reaches original Run failure without physical cleanup" {
  let (prepared, compilation, admission, definition) = retained_input_run(
    "refused-evidence-original",
  )
  let run = client_task_run_binding_definition_cid(
    bind_client_task_run(prepared, compilation, admission, definition).unwrap(),
  )
  let authority = retained_input_cid("c")
  let keys = compilation.standard_progress_keys.unwrap()
  // The later slot is deliberate: an earlier unstarted dependency remains
  // otherwise ready, but this failed Run must not dispatch it afterwards.
  let saved = remote_evidence_observation_fixture(
    authority,
    run,
    keys[1],
    true,
    false,
  )
  let progress = inspect_client_remote_task_progress(
    prepared,
    compilation,
    admission,
    definition,
    authority,
    [saved],
  ).unwrap()
  let observation = progress.observations[1].unwrap()
  assert_eq(observation.execution, Some(@remote.NativeSettled))
  assert_eq(observation.cleanup, Some(@remote.CleanupActive))
  assert_true(observation.execution_terminal)
  assert_false(observation.cleanup_complete)
  let projection = project_client_remote_task_run(
    progress,
    "2026-10-05T00:01:00.000Z",
    false,
    [keys[1]],
  ).unwrap()
  let fields = client_remote_task_run_projection_fields(projection)
  let state = @json.parse(fields[0]) catch { _ => abort("Expected Run state") }
  guard state is Object(state) else { abort("Expected Run state object") }
  assert_eq(state.get("status"), Some(Json::string("failed")))
  assert_eq(state.get("result_available"), Some(Json::boolean(false)))
  assert_eq(fields[1], "failed")
  assert_eq(fields[2], "-1")
  assert_eq(fields[3], "0")
  assert_eq(fields[4], "0")
  assert_eq(progress.dependency_ready_task, None)
  assert_eq(progress.next_task, None)
  assert_eq(client_remote_task_run_projection_work(projection), [
    "none", "release",
  ])
}

///|
test "settled pending evidence remains unresolved independently of cleanup" {
  let (prepared, compilation, admission, definition) = retained_input_run(
    "pending-evidence-original",
  )
  let run = @publication.publication_contract_identity(definition)
  let authority = retained_input_cid("c")
  let keys = compilation.standard_progress_keys.unwrap()
  for released in [false, true] {
    let saved = remote_evidence_observation_fixture(
      authority,
      run,
      keys[0],
      false,
      released,
    )
    let progress = inspect_client_remote_task_progress(
      prepared,
      compilation,
      admission,
      definition,
      authority,
      [saved],
    ).unwrap()
    let observation = progress.observations[0].unwrap()
    assert_eq(observation.execution, Some(@remote.NativeSettled))
    assert_false(observation.evidence_rejected)
    assert_eq(observation.cleanup_complete, released)
    let projection = project_client_remote_task_run(
      progress,
      "2026-10-05T00:01:00.000Z",
      false,
      [keys[0]],
    ).unwrap()
    let fields = client_remote_task_run_projection_fields(projection)
    assert_eq(fields[1], "running")
    assert_eq(fields[3], "0")
    assert_eq(
      client_remote_task_run_projection_work(projection)[0],
      "reconcile",
    )
  }
}

///|
test "settled rejected evidence retains failure after independent release and cancellation" {
  let (prepared, compilation, admission, definition) = retained_input_run(
    "released-refused-evidence-original",
  )
  let authority = retained_input_cid("c")
  let keys = compilation.standard_progress_keys.unwrap()
  let saved = remote_evidence_observation_fixture(
    authority,
    @publication.publication_contract_identity(definition),
    keys[0],
    true,
    true,
  )
  let progress = inspect_client_remote_task_progress(
    prepared,
    compilation,
    admission,
    definition,
    authority,
    [saved],
  ).unwrap()
  let observation = progress.observations[0].unwrap()
  assert_eq(observation.execution, Some(@remote.NativeSettled))
  assert_eq(observation.cleanup, Some(@remote.CleanupReleased))
  assert_true(observation.evidence_rejected)
  assert_true(observation.cleanup_complete)
  let projection = project_client_remote_task_run(
    progress,
    "2026-10-05T00:01:00.000Z",
    true,
    [keys[0]],
  ).unwrap()
  let fields = client_remote_task_run_projection_fields(projection)
  assert_eq(fields[1], "failed")
  assert_eq(fields[2], "-1")
  assert_eq(fields[3], "0")
  assert_eq(client_remote_task_run_projection_work(projection), ["none", "none"])
}

///|
test "Effect precheckpoint projection carries rejected evidence without whole Run cleanup" {
  let original = effect_projection_fixture()
  let keys = original.progress.keys
  let saved = remote_evidence_observation_fixture(
    original.progress.authority,
    @publication.publication_contract_identity(original.progress.definition),
    keys[0],
    true,
    true,
  )
  let progress = inspect_client_remote_effect_task_progress(
    original.allowed,
    original.progress.definition,
    original.progress.authority,
    [saved],
  ).unwrap()
  let claims = effect_projection_claims(progress)
  claims[0] = {
    ..claims[0],
    dispatch_cid: Some(
      @remote.durable_coordinator_dispatch_record_request_identity(saved),
    ),
    dispatch_reserved: true,
    physical_start_claimed: true,
  }
  let projection = project_client_remote_effect_task_run(
    progress, "2026-10-09T00:01:00.000Z", true, claims,
  ).unwrap()
  let state = effect_projection_state(projection)
  assert_eq(state.get("status"), Some(Json::string("failed")))
  assert_eq(state.get("result_available"), Some(Json::boolean(false)))
  let fields = client_remote_effect_task_run_projection_fields(projection)
  assert_eq(fields[2], "-1")
  assert_eq(fields[3], "0")
  assert_eq(fields[4], "0")
}

///|
test "durable accepted evidence still advances its checked dependent task" {
  let (prepared, compilation, admission, definition) = retained_input_run(
    "accepted-evidence-original",
  )
  let edge = prepare_client_retained_input_edge(
    prepared, compilation, admission, definition, 1, 0,
  ).unwrap()
  let saved = retained_coordinator_complete(retained_coordinator_fixture(edge))
  let progress = inspect_client_remote_task_progress(
    prepared,
    compilation,
    admission,
    definition,
    "authority-a",
    [saved],
  ).unwrap()
  assert_false(progress.observations[0].unwrap().evidence_rejected)
  assert_true(progress.completed[0])
  assert_eq(progress.next_task, Some(1))
  let projection = project_client_remote_task_run(
    progress,
    "2026-10-05T00:01:00.000Z",
    false,
    [progress.keys[0]],
  ).unwrap()
  let fields = client_remote_task_run_projection_fields(projection)
  assert_eq(fields[1], "running")
  assert_eq(fields[2], "1")
  assert_eq(fields[3], "0")
}
