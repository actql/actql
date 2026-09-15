///|
fn policy_request_environment(
  profile : String,
  cid : String,
) -> @program_check.CheckEnvironment {
  // Canonical input CIDs independently calculated with Node SHA-256, excluding
  // evidence_bundle_cid. No product checker output supplies an expected result.
  let body = "{\"command_contracts\":[],\"connector_capabilities\":[],\"connector_catalogs\":[],\"contract_registry\":[],\"evidence_bundle_cid\":\"" +
    cid +
    "\",\"host_policy_profile\":" +
    profile +
    ",\"mapping_contracts\":[],\"model_task_contracts\":[],\"schema_snapshots\":[],\"source_views\":[],\"version\":\"actql-check-environment/0.1\"}"
  let wire = @environment.read(@utf8.encode(body), cid, {
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 100,
    max_members: 10,
  }).unwrap()
  @program_check.checking_environment(
    wire,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  )
}

///|
test "absent Host capacity requests a selection without inventing policy or source span" {
  let (text, program, complete, _, limits) = public_input_fixture()
  let absent = policy_request_environment(
    "{}", "sha256:bf3e299a7386f7442aa04abc23901a1b3f580b490e6c625fe4ea686dce61032c",
  )
  guard @program_check.check_parsed(program, absent, None, limits)
    is NeedsInputs(requests) else {
    fail("expected capacity request")
  }
  assert_eq(@program_check.input_request_count(requests), 1)
  let request = @program_check.input_request_at(requests, 0).unwrap()
  assert_eq(@program_check.input_request_origin(request), CheckEnvironment)
  assert_true(request.kind is HostCapacityPolicy)
  assert_true(physical_equal(request.program, program))
  assert_true(physical_equal(request.environment, absent))
  assert_eq(@program_check.input_request_path(request), [
    @source.Key("host_policy_profile"),
    @source.Key("capacity"),
  ])
  assert_true(@program_check.input_request_source(request) is None)
  assert_true(@program_check.input_request_at(requests, -1) is None)
  assert_true(@program_check.input_request_at(requests, 1) is None)
  assert_true(
    @program_check.check_document(text, absent, None, limits, format=Json)
    is NeedsInputs(_),
  )
  // A new environment is checked from the beginning. The old request is not
  // fulfilled by mutation and does not authorize any execution.
  assert_true(
    @program_check.check_parsed(program, complete, None, limits) is Checked(_),
  )
  assert_true(
    @program_check.check_parsed(program, absent, None, {
      ..limits,
      compilation: { ..limits.compilation, work: 20000000, },
    })
    is NeedsInputs(_),
  )
  assert_true(
    @program_check.check_parsed(program, absent, None, {
      ..limits,
      compilation: { ..limits.compilation, work: 0, },
    })
    is Rejected(_),
  )
  assert_true(
    @program_check.input_request_at(requests, 0).unwrap().kind
    is HostCapacityPolicy,
  )
}

///|
test "present invalid capacity is rejected rather than requested" {
  let (_, program, _, _, limits) = public_input_fixture()
  for
    (body, cid) in [
      (
        "{\"capacity\":null}", "sha256:1087c7c18744cb4b42aa4967d9841d4bb00e365577e03426421fc00c88d24c0b",
      ),
      (
        "{\"capacity\":{}}", "sha256:277670c9b723fb5b88b5a8fae4f854f1de1bcf1a2aa9c3c404cf7a6fc96c037d",
      ),
      (
        "{\"capacity\":[]}", "sha256:847767677ae502c3fef698858327a7a564bed985ce698e73accbe29dac0b1de8",
      ),
    ] {
    guard @program_check.check_parsed(
        program,
        policy_request_environment(body, cid),
        None,
        limits,
      )
      is Rejected(diagnostic) else {
      fail("invalid capacity became a request")
    }
    assert_true(
      @program_check.diagnostic_cause(diagnostic)
      is @program_check.LocalConstructionFailure::Source(
        SourceView(Context(Policy(_)))
      ),
    )
  }
}

///|
test "request frontier can reveal a later policy selection after Parameter admission" {
  let (text, _, complete, _, limits) = public_input_fixture()
  let text = text.replace(old=",\"default\":1", new="")
  let absent = policy_request_environment(
    "{}", "sha256:bf3e299a7386f7442aa04abc23901a1b3f580b490e6c625fe4ea686dce61032c",
  )
  guard @program_check.check_document(text, absent, None, limits, format=Json)
    is NeedsInputs(parameters) else {
    fail("expected Parameter frontier")
  }
  assert_true(
    @program_check.input_request_at(parameters, 0).unwrap().kind
    is ParameterValue(_),
  )
  let supplied = Some(request_values("{\"n\":2}"))
  guard @program_check.check_document(
      text,
      absent,
      supplied,
      limits,
      format=Json,
    )
    is NeedsInputs(policy) else {
    fail("expected later policy frontier")
  }
  assert_true(
    @program_check.input_request_at(policy, 0).unwrap().kind
    is HostCapacityPolicy,
  )
  assert_true(
    @program_check.check_document(text, complete, supplied, limits, format=Json)
    is Checked(_),
  )
  assert_true(
    @program_check.check_document(
      text,
      absent,
      Some(request_values("{\"n\":\"bad\"}")),
      limits,
      format=Json,
    )
    is Rejected(_),
  )
}
