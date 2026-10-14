///|
fn client_calendar_fixture(
  enabled? : Bool = true,
) -> @program_check.CheckEnvironment {
  client_program_check_environment(
    (
      #|{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[],"contract_registry":[],"evidence_bundle_cid":"sha256:eaa253817c6be7a3e1141487b87b702bfa23052afe190461db6c83369bd13ffe","host_policy_profile":{"calendar":{"conversion_law":"actql-calendar-boundaries/0.1","table_bytes_cid":"sha256:9f3724c9d9d160476ee7abf5d8eaa0701bbd5c17f900154496bb8615bf20f4ca","tzdb_version":"test-fixture","version":"actql-calendar-selection/0.1"},"capacity":{"max_aggregate_array_items":1000,"max_analytic_frame_memberships":1000,"max_analytic_input_wire_bytes":1000,"max_analytic_output_wire_bytes":1000,"max_analytic_partition_wire_bytes":1000,"max_artifact_bytes":1000,"max_artifact_rows":1000,"max_effect_items":1000,"max_graph_construction_edges":1000,"max_graph_construction_input_rows":1000,"max_graph_construction_nodes":1000,"max_graph_input_edges":1000,"max_graph_input_nodes":1000,"max_graph_output_rows":1000,"max_graph_paths":1000,"max_infer_items":1000,"max_model_input_tokens_per_item":1000,"max_model_request_bytes_per_item":1000,"max_model_total_duration_ms":1000,"max_nested_value_bytes":1000,"max_nested_value_depth":1000,"max_relation_output_rows":1000,"max_temporal_matches_per_key":1000,"max_temporal_output_rows":1000,"version":"actql-capacity-host-policy/0.1"}},"mapping_contracts":[],"model_task_contracts":[],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}
    ),
    "sha256:eaa253817c6be7a3e1141487b87b702bfa23052afe190461db6c83369bd13ffe",
    false,
    false,
    true,
    false,
    true,
    enabled,
    false,
  ).unwrap()
}

///|
fn client_calendar_artifact() -> Bytes {
  @utf8.encode(
    (
      #|{"conversion_law":"actql-calendar-boundaries/0.1","coverage_end_ms":253402300800000,"coverage_start_ms":-62135596800000,"tzdb_version":"test-fixture","version":"actql-tzdb-table/0.1","zones":{"UTC":{"initial_offset_seconds":0,"transitions":[]}}}
    ),
  )
}

///|
test "Calendar artifact bridge retains the original Host checker and missing runtime refusal" {
  let original = client_calendar_fixture()
  let selected = client_program_check_environment_with_calendar_artifact(
    original,
    client_calendar_artifact(),
    1000,
    100,
    8,
    1,
    0,
    10000,
  ).unwrap()
  let profile = @program_check.checking_environment_calendar_profile(selected).unwrap()
  let selected_wire = @check_environment.calendar_selection_environment(
    @check_environment.selected_calendar_selection(profile),
  )
  assert_true(
    physical_equal(
      selected_wire,
      @program_check.checking_environment_wire(original),
    ),
  )
  assert_true(
    physical_equal(
      @program_check.checking_environment_model_tasks(selected).unwrap(),
      @program_check.checking_environment_model_tasks(original).unwrap(),
    ),
  )
  assert_eq(
    @program_check.checking_environment_cid(selected),
    "sha256:eaa253817c6be7a3e1141487b87b702bfa23052afe190461db6c83369bd13ffe",
  )
  let context = client_program_check_context_identity(selected)
  assert_true(
    context.contains(
      "\"calendar_profile_cid\":\"sha256:9f3724c9d9d160476ee7abf5d8eaa0701bbd5c17f900154496bb8615bf20f4ca\"",
    ),
  )
  let document =
    #|{"version":"actql/0.1","id":"fixture.calendar_source","stages":[{"id":"main","inputs":{},"steps":[{"calendar_series":{"start":"2000-01-01T00:00:00.000Z","end":"2000-01-03T00:00:00.000Z","unit":"day","timezone":"UTC"},"as":"days"},{"calendar_bucket":{"time":"start","into":"month","unit":"month","timezone":"UTC"},"as":"bucketed"},{"from":"bucketed","sort":[{"field":"start","dir":"asc","nulls":"first"}]},{"select":["start","end","month"],"as":"out"}],"results":{"rows":{"from":"out","fields":["start","end","month"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
  assert_true(
    client_program_prepare_effect_free_with_parameters(
      document,
      "json",
      selected,
      None,
    )
    is Rejected(
      Preparation(
        @publication_host.Lowering({ kind: @lower.OperationNotImplemented, .. })
      )
    ),
  )
  assert_true(
    @program_check.checking_environment_calendar_profile(original) is None,
  )
}

///|
test "Calendar artifact bridge cannot enable a capability or repair changed bytes" {
  let disabled = client_calendar_fixture(enabled=false)
  let bytes = client_calendar_artifact()
  assert_true(
    client_program_check_environment_with_calendar_artifact(
      disabled, bytes, 1000, 100, 8, 1, 0, 10000,
    )
    is None,
  )
  let original = client_calendar_fixture()
  assert_true(
    client_program_check_environment_with_calendar_artifact(
      original, bytes, 1000, 100, 8, 1, 0, 0,
    )
    is None,
  )
  assert_true(
    client_program_check_environment_with_calendar_artifact(
      original,
      bytes,
      bytes.length() - 1,
      100,
      8,
      1,
      0,
      10000,
    )
    is None,
  )
  assert_true(
    client_program_check_environment_with_calendar_artifact(
      original,
      @utf8.encode(" " + @utf8.decode(bytes)),
      1000,
      100,
      8,
      1,
      0,
      10000,
    )
    is None,
  )
  assert_true(
    @program_check.checking_environment_calendar_profile(original) is None,
  )
}

///|
test "Calendar selected series prepares through the ordinary source-free client entry" {
  let selected = client_program_check_environment_with_calendar_artifact(
    client_calendar_fixture(),
    client_calendar_artifact(),
    1000,
    100,
    8,
    1,
    0,
    10000,
  ).unwrap()
  let document =
    #|{"version":"actql/0.1","id":"fixture.calendar_series","stages":[{"id":"main","inputs":{},"steps":[{"calendar_series":{"start":"2000-01-01T00:00:00.000Z","end":"2000-01-03T00:00:00.000Z","unit":"day","timezone":"UTC"},"as":"days"},{"from":"days","sort":[{"field":"start","dir":"asc","nulls":"first"}]},{"select":["start","end"],"as":"out"}],"results":{"rows":{"from":"out","fields":["start","end"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
  match
    client_program_prepare_effect_free_with_parameters(
      document,
      "json",
      selected,
      None,
    ) {
    Prepared(_) => ()
    Rejected(issue) =>
      fail("original source-free Calendar series rejected: \(issue)")
  }
}
