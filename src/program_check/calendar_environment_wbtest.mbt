///|
fn calendar_environment_fixture(enabled? : Bool = true) -> CheckEnvironment {
  let wire = @environment.read(
    @utf8.encode(
      (
        #|{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[],"contract_registry":[],"evidence_bundle_cid":"sha256:eaa253817c6be7a3e1141487b87b702bfa23052afe190461db6c83369bd13ffe","host_policy_profile":{"calendar":{"conversion_law":"actql-calendar-boundaries/0.1","table_bytes_cid":"sha256:9f3724c9d9d160476ee7abf5d8eaa0701bbd5c17f900154496bb8615bf20f4ca","tzdb_version":"test-fixture","version":"actql-calendar-selection/0.1"},"capacity":{"max_aggregate_array_items":1000,"max_analytic_frame_memberships":1000,"max_analytic_input_wire_bytes":1000,"max_analytic_output_wire_bytes":1000,"max_analytic_partition_wire_bytes":1000,"max_artifact_bytes":1000,"max_artifact_rows":1000,"max_effect_items":1000,"max_graph_construction_edges":1000,"max_graph_construction_input_rows":1000,"max_graph_construction_nodes":1000,"max_graph_input_edges":1000,"max_graph_input_nodes":1000,"max_graph_output_rows":1000,"max_graph_paths":1000,"max_infer_items":1000,"max_model_input_tokens_per_item":1000,"max_model_request_bytes_per_item":1000,"max_model_total_duration_ms":1000,"max_nested_value_bytes":1000,"max_nested_value_depth":1000,"max_relation_output_rows":1000,"max_temporal_matches_per_key":1000,"max_temporal_output_rows":1000,"version":"actql-capacity-host-policy/0.1"}},"mapping_contracts":[],"model_task_contracts":[],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}
      ),
    ),
    "sha256:eaa253817c6be7a3e1141487b87b702bfa23052afe190461db6c83369bd13ffe",
    { max_bytes: 65536, max_nodes: 4096, max_depth: 64, max_members: 256, },
  ).unwrap()
  let tasks = @environment.check_model_tasks(wire, {
    bodies: {
      max_bytes: 65536,
      max_nodes: 4096,
      max_depth: 64,
      max_members: 256,
    },
    contracts: { max_nodes: 4096, max_depth: 64, max_text_bytes: 65536, },
    max_work: 65536,
  }).unwrap()
  checking_environment(
    wire,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: true, calendar: enabled, text_rank: false, },
    numeric_profile=Some(@numeric.builtin_profile()),
    model_tasks=Some(tasks),
  )
}

///|
fn calendar_environment_bytes() -> Bytes {
  @utf8.encode(
    (
      #|{"conversion_law":"actql-calendar-boundaries/0.1","coverage_end_ms":253402300800000,"coverage_start_ms":-62135596800000,"tzdb_version":"test-fixture","version":"actql-tzdb-table/0.1","zones":{"UTC":{"initial_offset_seconds":0,"transitions":[]}}}
    ),
  )
}

///|
fn calendar_environment_limits() -> @calendar_profile.Limits {
  {
    max_bytes: 1000,
    max_nodes: 100,
    max_depth: 8,
    max_zones: 1,
    max_transitions: 0,
  }
}

///|
test "Calendar artifact supplementation preserves the original checker owners" {
  let original = calendar_environment_fixture()
  let supplemented = checking_environment_with_calendar_artifact(
    original,
    calendar_environment_bytes(),
    calendar_environment_limits(),
    max_selection_work=10000,
  ).unwrap()
  assert_true(physical_equal(supplemented.wire, original.wire))
  assert_true(
    physical_equal(
      supplemented.model_tasks.unwrap(),
      original.model_tasks.unwrap(),
    ),
  )
  assert_true(
    physical_equal(supplemented.numeric.unwrap(), original.numeric.unwrap()),
  )
  assert_true(
    physical_equal(
      supplemented.request_value_policies,
      original.request_value_policies,
    ),
  )
  assert_eq(supplemented.expressions, original.expressions)
  assert_eq(supplemented.operations, original.operations)
  assert_eq(supplemented.graph, original.graph)
  assert_true(original.calendar is None)
  let profile = supplemented.calendar.unwrap()
  let selection = @environment.selected_calendar_selection(profile)
  assert_true(
    physical_equal(
      @environment.calendar_selection_environment(selection),
      original.wire,
    ),
  )
  assert_eq(
    @environment.calendar_selection_cid(selection),
    "sha256:9f3724c9d9d160476ee7abf5d8eaa0701bbd5c17f900154496bb8615bf20f4ca",
  )
}

///|
test "Calendar artifact supplementation cannot enable an unavailable capability" {
  let original = calendar_environment_fixture(enabled=false)
  assert_true(
    checking_environment_with_calendar_artifact(
      original,
      calendar_environment_bytes(),
      calendar_environment_limits(),
      max_selection_work=10000,
    )
    is Err(CapabilityDisabled),
  )
  assert_false(original.operations.calendar)
  assert_true(original.calendar is None)
}

///|
test "Calendar artifact supplementation retains selection and artifact bounds" {
  let original = calendar_environment_fixture()
  let limits = calendar_environment_limits()
  let bytes = calendar_environment_bytes()
  assert_true(
    checking_environment_with_calendar_artifact(
      original,
      bytes,
      limits,
      max_selection_work=0,
    )
    is Err(Selection(BudgetExceeded)),
  )
  assert_true(
    checking_environment_with_calendar_artifact(
      original,
      bytes,
      { ..limits, max_bytes: bytes.length() - 1, },
      max_selection_work=10000,
    )
    is Err(Artifact(BudgetExceeded)),
  )
  assert_true(
    checking_environment_with_calendar_artifact(
      original,
      bytes,
      { ..limits, max_transitions: -1, },
      max_selection_work=10000,
    )
    is Err(Artifact(InvalidLimits)),
  )
  assert_true(
    checking_environment_with_calendar_artifact(
      original,
      @utf8.encode(" " + @utf8.decode(bytes)),
      limits,
      max_selection_work=10000,
    )
    is Err(Artifact(IdentityMismatch)),
  )
  assert_true(original.calendar is None)
}

///|
test "Calendar supplementation binds identical artifact bytes to each original environment" {
  let left = calendar_environment_fixture()
  let right = calendar_environment_fixture()
  assert_eq(checking_environment_cid(left), checking_environment_cid(right))
  assert_false(physical_equal(left.wire, right.wire))
  let bytes = calendar_environment_bytes()
  let limits = calendar_environment_limits()
  let left_selected = checking_environment_with_calendar_artifact(
    left,
    bytes,
    limits,
    max_selection_work=10000,
  ).unwrap()
  let right_selected = checking_environment_with_calendar_artifact(
    right,
    bytes,
    limits,
    max_selection_work=10000,
  ).unwrap()
  let left_wire = @environment.calendar_selection_environment(
    @environment.selected_calendar_selection(left_selected.calendar.unwrap()),
  )
  let right_wire = @environment.calendar_selection_environment(
    @environment.selected_calendar_selection(right_selected.calendar.unwrap()),
  )
  assert_true(physical_equal(left_wire, left.wire))
  assert_true(physical_equal(right_wire, right.wire))
  assert_false(physical_equal(left_wire, right_wire))
}

///|
test "Calendar artifact supplementation closes the original missing-artifact checker request" {
  let original = calendar_environment_fixture()
  let document =
    #|{"version":"actql/0.1","id":"fixture.calendar_source","stages":[{"id":"main","inputs":{},"steps":[{"calendar_series":{"start":"2000-01-01T00:00:00.000Z","end":"2000-01-03T00:00:00.000Z","unit":"day","timezone":"UTC"},"as":"days"},{"calendar_bucket":{"time":"start","into":"month","unit":"month","timezone":"UTC"},"as":"bucketed"},{"from":"bucketed","sort":[{"field":"start","dir":"asc","nulls":"first"}]},{"select":["start","end","month"],"as":"out"}],"results":{"rows":{"from":"out","fields":["start","end","month"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
  let limits : CheckLimits = {
    input: {
      source: { max_input_bytes: 10000, max_nodes: 10000, max_depth: 100, },
      tree: {
        max_nodes: 10000,
        max_depth: 100,
        max_string_bytes: 10000,
        max_total_string_bytes: 100000,
      },
      max_stages: 20,
    },
    compilation: {
      work: 10000000,
      artifacts: { bytes: 1000000, nodes: 100000, depth: 100, },
      structure: {
        stages: 20,
        steps: 20,
        results: 20,
        parameters: 10,
        bindings: 100,
        slots: 1000,
        references: 1000,
        requirements: 1000,
        tokens: 10000,
      },
      traversal: {
        nodes: 100000,
        depth: 100,
        text_bytes: 10000000,
        string_bytes: 100000,
        name_bytes: 1000000,
        pointer_units: 1000000,
        comparison_pairs: 1000000,
      },
      values: { nodes: 1000000, depth: 100, text_bytes: 100000, },
      policy: { bytes: 10000, nodes: 1000000, depth: 100, },
      patterns: { bytes: 1000000, nodes: 1000000, depth: 100, },
    },
  }
  guard check_document(document, original, None, limits, format=Json)
    is NeedsInputs(requests) else {
    fail("missing selected artifact")
  }
  assert_eq(input_request_count(requests), 1)
  assert_true(
    input_request_at(requests, 0).unwrap().kind is CalendarProfileArtifact(_),
  )
  let supplemented = checking_environment_with_calendar_artifact(
    original,
    calendar_environment_bytes(),
    calendar_environment_limits(),
    max_selection_work=10000,
  ).unwrap()
  guard check_document(document, supplemented, None, limits, format=Json)
    is Checked(program) else {
    fail("same-owner artifact reaches the ordinary checker")
  }
  assert_true(physical_equal(checked_environment(program), original.wire))
  assert_true(
    physical_equal(
      checked_model_tasks(program).unwrap(),
      original.model_tasks.unwrap(),
    ),
  )
  let closure = @context.stage_requirement_operations(requirements(program))
  let selected = @context.operation_calendar_profile(
    @context.operation_profile_links_calendar(
      @context.operation_resolution_profiles(
        @context.operation_closure_index(closure),
      ),
    ),
  ).unwrap()
  assert_true(physical_equal(selected, supplemented.calendar.unwrap()))
  let mut execution_checks = 0
  for i in 0..<@context.operation_closure_count(closure) {
    guard @context.operation_closure_at(closure, i)
      is Some(ExecutionCheck(CalendarExecution(_))) else {
      continue
    }
    execution_checks += 1
  }
  // Two Calendar operations retain three mandatory future checks each.
  // Ordinary checking does not convert these into executed boundary receipts.
  assert_eq(execution_checks, 6)
}

///|
test "Calendar supplementation does not invent a missing optional selection" {
  let wire = @environment.read(
    @utf8.encode(
      (
        #|{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[],"contract_registry":[],"evidence_bundle_cid":"sha256:f7a722e2504c266873a228d46add79847b08daa2ff3a457baa140d08accbd3c6","host_policy_profile":{"capacity":{"max_aggregate_array_items":1000,"max_analytic_frame_memberships":1000,"max_analytic_input_wire_bytes":1000,"max_analytic_output_wire_bytes":1000,"max_analytic_partition_wire_bytes":1000,"max_artifact_bytes":1000,"max_artifact_rows":1000,"max_effect_items":1000,"max_graph_construction_edges":1000,"max_graph_construction_input_rows":1000,"max_graph_construction_nodes":1000,"max_graph_input_edges":1000,"max_graph_input_nodes":1000,"max_graph_output_rows":1000,"max_graph_paths":1000,"max_infer_items":1000,"max_model_input_tokens_per_item":1000,"max_model_request_bytes_per_item":1000,"max_model_total_duration_ms":1000,"max_nested_value_bytes":1000,"max_nested_value_depth":1000,"max_relation_output_rows":1000,"max_temporal_matches_per_key":1000,"max_temporal_output_rows":1000,"version":"actql-capacity-host-policy/0.1"}},"mapping_contracts":[],"model_task_contracts":[],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}
      ),
    ),
    "sha256:f7a722e2504c266873a228d46add79847b08daa2ff3a457baa140d08accbd3c6",
    { max_bytes: 65536, max_nodes: 4096, max_depth: 64, max_members: 256, },
  ).unwrap()
  let original = checking_environment(
    wire,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: true, calendar: true, text_rank: false, },
  )
  assert_true(
    checking_environment_with_calendar_artifact(
      original,
      calendar_environment_bytes(),
      calendar_environment_limits(),
      max_selection_work=10000,
    )
    is Err(Selection(MissingSelection)),
  )
  assert_true(original.calendar is None)
  assert_true(physical_equal(original.wire, wire))
}
