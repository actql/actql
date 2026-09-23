///|
fn remote_completion_cid(unit : String) -> String {
  "sha256:" + unit.repeat(64)
}

///|
fn remote_completion_owner() -> @lower.BoundPrepared {
  let checked = @pipeline.check(
    input_cursor(
      "[{\"values\":{\"schema\":{\"n\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[]},\"as\":\"v\"},{\"select\":[\"n\"]}]",
    ),
    [],
    None,
    None,
    {
      max_steps: 10,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 20,
    },
  ).unwrap()
  @lower.bind_parameters(
    @lower.prepare(checked, {
      max_nodes: 100,
      max_references: 100,
      max_work: 1000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}

///|
fn remote_completion_request() -> @remote.DispatchRequest {
  @remote.prepare_dispatch_request(
    "coordinator-a",
    remote_completion_cid("0"),
    "task-a",
    1,
    "dispatch-a",
    "site-a",
    1,
    remote_completion_cid("a"),
    "local",
    "local/1",
    "strategy/1",
    remote_completion_cid("1"),
    remote_completion_cid("2"),
    remote_completion_cid("3"),
    remote_completion_cid("b"),
    remote_completion_cid("4"),
  ).unwrap()
}

///|
fn remote_completion_proof(
  request : @remote.DispatchRequest,
  profile_cid : String,
) -> (
  @remote.CoordinatorDispatchIntentRecord,
  @remote_completion.RemoteManagedOutputProof,
) {
  let measurement = @remote.prepare_remote_managed_output_measurement(
    2,
    0,
    0,
    0,
    [2],
    [2],
    [2],
    [1],
    [0],
    [10],
  ).unwrap()
  let holding = @remote.remote_output_holding_evidence_cid(
    request, "material-a", 8L,
  ).unwrap()
  let subject = @remote.prepare_remote_managed_output_subject(
    @remote.dispatch_request_identity(request),
    "material-a",
    holding,
    profile_cid,
    remote_completion_cid("5"),
    remote_completion_cid("6"),
    remote_completion_cid("7"),
    remote_completion_cid("8"),
    @remote.remote_managed_output_measurement_cid(measurement),
    2,
    8L,
  ).unwrap()
  let site = @site.create_site(
    "site-a",
    1,
    remote_completion_cid("a"),
    4,
    4,
    1048576L,
    1048576L,
  ).unwrap()
  let journal = @remote.create_site_dispatch_journal(
    site, "actql-remote-site/0.1",
  ).unwrap()
  let (_, record) = @remote.commit_dispatch_acceptance(
    @remote.prepare_dispatch_acceptance(journal, request).unwrap(),
    true,
  ).unwrap()
  let capability = @remote.register_remote_execution_capability(
    site,
    remote_completion_cid("a"),
    "local",
    "local/1",
    "strategy/1",
    remote_completion_cid("4"),
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
  @remote.commit_dispatch_transition(
    @remote.prepare_retain_remote_output(record, "material-a", holding).unwrap(),
    true,
  ).unwrap()
  let issuer = @remote.register_remote_evidence_issuer(
    site,
    remote_completion_cid("a"),
    "local",
    "local/1",
    "strategy/1",
    @remote.remote_managed_output_evidence_kind(),
    remote_completion_cid("b"),
  ).unwrap()
  let evidence = @remote.issue_remote_managed_output_evidence(
    issuer, record, subject,
  ).unwrap()
  let coordinator = @remote.create_coordinator_dispatch_journal("coordinator-a").unwrap()
  let (_, coordinator_record) = @remote.commit_coordinator_dispatch_intent(
    @remote.prepare_coordinator_dispatch_intent(coordinator, request).unwrap(),
    true,
  ).unwrap()
  @remote.commit_coordinator_dispatch_transition(
    @remote.prepare_coordinator_managed_output_observation(
      coordinator_record,
      @remote.dispatch_record_revision(record),
      3,
      2,
      1,
      true,
      false,
      evidence,
      subject,
      measurement,
    ).unwrap(),
    true,
  ).unwrap()
  (coordinator_record, { evidence, subject, measurement, })
}

///|
fn remote_completion_values(
  owner : @lower.BoundPrepared,
) -> @execution.ManagedOutputValues {
  @execution.prepare_managed_output_values(
    owner,
    @pipeline.Step(1),
    2,
    { max_nodes: 100, max_text_bytes: 1000, max_depth: 10, max_work: 1000, },
    100,
    { max_work: 100, max_bytes: 1000, max_nodes: 100, max_depth: 10, },
  ).unwrap()
}

///|
fn start_remote_completion_test_execution(
  run : @strategy.CapturedDAG,
  input : @execution.ProducerRead,
  registration_name? : String = "local",
) -> @strategy.TaskExecution {
  let request = @connector.prepare_fixed_compute_request([input], {
    contract_cid: "sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f",
    max_rows: 10,
    max_value_bytes: 100,
    common_fragment: None,
  }).unwrap()
  let registry = @connector.prepare_capability_registry(
    [
      {
        name: registration_name,
        acquisition: false,
        fixed_compute: true,
        effect: false,
      },
    ],
    1,
    100,
  ).unwrap()
  let prepared = @connector.bind_compute_candidate(
    @connector.capability_registration_at(registry, 0).unwrap(),
    request,
    (),
    1,
    [{ work_slots: [0], milliseconds: Some(1L), }],
    { transfer_bytes: Some(0L), retained_bytes: Some(8L), money_units: None, },
    10,
  ).unwrap()
  guard @connector.choose_fixed_compute_candidate(
      registry,
      request,
      [@connector.prepared_compute_candidate(prepared)],
      None,
      10,
    ).unwrap()
    is Proposed(choice) else {
    abort("remote test candidate")
  }
  let settled = Ref(false)
  let bound = @connector.bind_prepared_materializing_execution(
    choice,
    prepared,
    {
      transfer_bytes: 0L,
      retained_bytes: 8L,
      scratch_bytes: 0L,
      execution_bytes: 0L,
    },
    [],
    fn(_) {
      let operations : @connector.ExecutionLifecycleOperations[
        @strategy.RunIssue,
      ] = {
        cancel: fn() { () },
        dispose: fn() { () },
        settled: fn() { settled.val = true },
        retention_released: fn() { true },
        released: fn() { () },
        ready: fn() {
          if settled.val {
            Ok(())
          } else {
            Err(@strategy.RunIssue::NotReady)
          }
        },
      }
      Ok(((), operations))
    },
  ).unwrap()
  @strategy.start_captured_materializing_execution(run, 1, bound).unwrap().1
}

///|
test "remote proof creates one exact common managed completion" {
  let owner = remote_completion_owner()
  let request = remote_completion_request()
  let profile = @execution.selected_managed_execution_profile()
  let profile_cid = @execution.managed_execution_profile_cid(profile)
  let attempt = @execution.issue_managed_execution_attempt()
  let live = Ref(true)
  let checked_physical = Ref(false)
  let expected_holding = @remote.remote_output_holding_evidence_cid(
    request, "material-a", 8L,
  ).unwrap()
  let port = @remote_completion.prepare_remote_managed_completion_port(
    remote_completion_values(owner),
    request,
    {
      managed_profile_cid: profile_cid,
      result_schema_cid: remote_completion_cid("5"),
      logical_view_cid: remote_completion_cid("6"),
      representation_codec_cid: remote_completion_cid("7"),
    },
    profile,
    task_test_completion(owner),
    @pipeline.Step(1),
    1000,
    10000,
    (handle : String, generation, holding, manifest, retained_bytes) => {
      if handle == "opaque-handle-a" &&
        generation == "material-a" &&
        holding == expected_holding &&
        manifest == remote_completion_cid("8") &&
        retained_bytes == 8L {
        checked_physical.val = true
        Some((handle, fn() { live.val }))
      } else {
        None
      }
    },
  ).unwrap()
  assert_true(
    @remote_completion.bind_remote_managed_completion_attempt(port, attempt),
  )
  assert_false(
    @remote_completion.bind_remote_managed_completion_attempt(port, attempt),
  )
  let (coordinator, output) = remote_completion_proof(request, profile_cid)
  let completed = @remote_completion.finish_remote_managed_completion(port, {
    coordinator,
    output,
    material: "opaque-handle-a",
  }).unwrap()
  assert_true(checked_physical.val)
  assert_true(
    @execution.managed_completed_output_matches_port(
      completed,
      owner,
      @pipeline.Step(1),
    ),
  )
  assert_true(
    @execution.managed_completed_output_matches_attempt(completed, attempt),
  )
  assert_eq(@execution.managed_completed_output_row_count(completed), 2)
  assert_eq(
    @execution.managed_completed_output_storage_bytes(completed),
    Some(8L),
  )
  live.val = false
  assert_false(@execution.managed_completed_output_available(completed))
}

///|
test "foreign remote material cannot create a common completion" {
  let owner = remote_completion_owner()
  let request = remote_completion_request()
  let profile = @execution.selected_managed_execution_profile()
  let profile_cid = @execution.managed_execution_profile_cid(profile)
  let port = @remote_completion.prepare_remote_managed_completion_port(
    remote_completion_values(owner),
    request,
    {
      managed_profile_cid: profile_cid,
      result_schema_cid: remote_completion_cid("5"),
      logical_view_cid: remote_completion_cid("6"),
      representation_codec_cid: remote_completion_cid("7"),
    },
    profile,
    task_test_completion(owner),
    @pipeline.Step(1),
    1000,
    10000,
    fn(_ : String, _, _, _, _) -> (String, () -> Bool)? { None },
  ).unwrap()
  let (coordinator, output) = remote_completion_proof(request, profile_cid)
  assert_true(
    @remote_completion.finish_remote_managed_completion(port, {
      coordinator,
      output,
      material: "foreign-handle",
    })
    is Err(UnverifiedMaterial),
  )
  assert_false(@remote_completion.cancel_remote_managed_completion_port(port))
}

///|
test "Site evidence without Coordinator commit cannot complete a task" {
  let owner = remote_completion_owner()
  let request = remote_completion_request()
  let profile = @execution.selected_managed_execution_profile()
  let profile_cid = @execution.managed_execution_profile_cid(profile)
  let material_checked = Ref(false)
  let port = @remote_completion.prepare_remote_managed_completion_port(
    remote_completion_values(owner),
    request,
    {
      managed_profile_cid: profile_cid,
      result_schema_cid: remote_completion_cid("5"),
      logical_view_cid: remote_completion_cid("6"),
      representation_codec_cid: remote_completion_cid("7"),
    },
    profile,
    task_test_completion(owner),
    @pipeline.Step(1),
    1000,
    10000,
    fn(_ : String, _, _, _, _) -> (String, () -> Bool)? {
      material_checked.val = true
      Some(("unexpected", fn() { true }))
    },
  ).unwrap()
  let (_, output) = remote_completion_proof(request, profile_cid)
  let coordinator = @remote.create_coordinator_dispatch_journal("coordinator-a").unwrap()
  let (_, uncommitted) = @remote.commit_coordinator_dispatch_intent(
    @remote.prepare_coordinator_dispatch_intent(coordinator, request).unwrap(),
    true,
  ).unwrap()
  assert_true(
    @remote_completion.finish_remote_managed_completion(port, {
      coordinator: uncommitted,
      output,
      material: "opaque-handle-a",
    })
    is Err(UncommittedCoordinatorEvidence),
  )
  assert_false(material_checked.val)
}

///|
test "remote completion commits only its selected task and registration" {
  let (run, _) = captured_graph_fixture()
  let input = @strategy.captured_task_input(run, 1, 100, 10000).unwrap()
  let execution = start_remote_completion_test_execution(run, input)
  let owner = @strategy.graph_task_owner(@strategy.captured_dag_graph(run), 1).unwrap()
  let request = remote_completion_request()
  let profile = @execution.selected_managed_execution_profile()
  let profile_cid = @execution.managed_execution_profile_cid(profile)
  let expected_holding = @remote.remote_output_holding_evidence_cid(
    request, "material-a", 8L,
  ).unwrap()
  let port = @remote_completion.prepare_remote_managed_completion_port(
    remote_completion_values(owner),
    request,
    {
      managed_profile_cid: profile_cid,
      result_schema_cid: remote_completion_cid("5"),
      logical_view_cid: remote_completion_cid("6"),
      representation_codec_cid: remote_completion_cid("7"),
    },
    profile,
    task_test_completion(owner),
    @pipeline.Step(1),
    1000,
    10000,
    fn(handle : String, generation, holding, manifest, retained_bytes) {
      if handle == "opaque-handle-a" &&
        generation == "material-a" &&
        holding == expected_holding &&
        manifest == remote_completion_cid("8") &&
        retained_bytes == 8L {
        Some((handle, fn() { true }))
      } else {
        None
      }
    },
    inputs=[input],
  ).unwrap()
  assert_true(
    @remote_completion.bind_remote_managed_completion_task(port, run, execution),
  )
  @strategy.settle_task_execution(run, execution, true).unwrap()
  let (coordinator, output) = remote_completion_proof(request, profile_cid)
  let completed = @remote_completion.finish_remote_managed_task_completion(
    port,
    run,
    execution,
    { coordinator, output, material: "opaque-handle-a", },
  ).unwrap()
  assert_true(@strategy.captured_task_completed(run, 1))
  assert_true(
    @strategy.captured_managed_task_output_matches(
      run,
      1,
      @pipeline.Step(1),
      completed,
    ),
  )

  let (foreign_run, _) = captured_graph_fixture()
  let foreign_input = @strategy.captured_task_input(foreign_run, 1, 100, 10000).unwrap()
  let foreign_execution = start_remote_completion_test_execution(
    foreign_run,
    foreign_input,
    registration_name="other",
  )
  let foreign_owner = @strategy.graph_task_owner(
    @strategy.captured_dag_graph(foreign_run),
    1,
  ).unwrap()
  let foreign_port = @remote_completion.prepare_remote_managed_completion_port(
    remote_completion_values(foreign_owner),
    request,
    {
      managed_profile_cid: profile_cid,
      result_schema_cid: remote_completion_cid("5"),
      logical_view_cid: remote_completion_cid("6"),
      representation_codec_cid: remote_completion_cid("7"),
    },
    profile,
    task_test_completion(foreign_owner),
    @pipeline.Step(1),
    1000,
    10000,
    fn(_ : String, _, _, _, _) -> (String, () -> Bool)? {
      Some(("foreign", fn() { true }))
    },
    inputs=[foreign_input],
  ).unwrap()
  assert_false(
    @remote_completion.bind_remote_managed_completion_task(
      foreign_port, foreign_run, foreign_execution,
    ),
  )
  assert_false(@strategy.captured_task_completed(foreign_run, 1))
}
