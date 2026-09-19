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
) -> @remote_completion.RemoteManagedOutputProof {
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
  let subject = @remote.prepare_remote_managed_output_subject(
    @remote.dispatch_request_identity(request),
    "material-a",
    remote_completion_cid("c"),
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
    @remote.prepare_retain_remote_output(
      record,
      "material-a",
      remote_completion_cid("c"),
    ).unwrap(),
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
  { evidence, subject, measurement, }
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
test "remote proof creates one exact common managed completion" {
  let owner = remote_completion_owner()
  let request = remote_completion_request()
  let profile = @execution.selected_managed_execution_profile()
  let profile_cid = @execution.managed_execution_profile_cid(profile)
  let attempt = @execution.issue_managed_execution_attempt()
  let live = Ref(true)
  let checked_physical = Ref(false)
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
        holding == remote_completion_cid("c") &&
        manifest == remote_completion_cid("8") &&
        retained_bytes == 8L {
        checked_physical.val = true
        Some((handle, fn() { live.val }))
      } else {
        None
      }
    },
    attempt~,
  ).unwrap()
  let completed = @remote_completion.finish_remote_managed_completion(port, {
    output: remote_completion_proof(request, profile_cid),
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
  assert_true(
    @remote_completion.finish_remote_managed_completion(port, {
      output: remote_completion_proof(request, profile_cid),
      material: "foreign-handle",
    })
    is Err(UnverifiedMaterial),
  )
  assert_false(@remote_completion.cancel_remote_managed_completion_port(port))
}
