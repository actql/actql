///|
fn analytic_envelope_policy(omit : String) -> @policy.Policy raise {
  let fields = [
    "max_aggregate_array_items", "max_analytic_frame_memberships", "max_analytic_input_wire_bytes",
    "max_analytic_output_wire_bytes", "max_analytic_partition_wire_bytes", "max_artifact_bytes",
    "max_artifact_rows", "max_effect_items", "max_graph_input_edges", "max_graph_input_nodes",
    "max_graph_output_rows", "max_graph_paths", "max_infer_items", "max_model_input_tokens_per_item",
    "max_model_request_bytes_per_item", "max_model_total_duration_ms", "max_nested_value_bytes",
    "max_nested_value_depth", "max_relation_output_rows", "max_temporal_matches_per_key",
    "max_temporal_output_rows",
  ]
  let writer = @encode.writer(4096, 100, 4)
  @encode.begin_object(writer)
  for i in 0..<fields.length() {
    let name = fields[i]
    if name == omit {
      continue
    }
    @encode.key(writer, name)
    @encode.number_value(
      writer,
      if i >= 1 && i <= 4 {
        (i + 1).to_double()
      } else {
        1.0
      },
    )
  }
  @encode.key(writer, "version")
  @encode.string_value(writer, "actql-capacity-host-policy/0.1")
  @encode.end_object(writer)
  let bytes = @utf8.encode(@encode.finish(writer))
  @policy.admit(bytes, "sha256:" + @sha.hex(bytes), {
    max_bytes: 4096,
    max_nodes: 100,
    max_depth: 4,
  }).unwrap()
}

///|
test "analytic envelope binds distinct policy scopes through imported producer visits" {
  for
    omit in [
      "", "max_analytic_frame_memberships", "max_analytic_input_wire_bytes", "max_analytic_output_wire_bytes",
      "max_analytic_partition_wire_bytes",
    ] {
    let selected = analytic_envelope_policy(omit)
    let mut profile = bound_profile()
    for
      name in [
        "max_analytic_partition_wire_bytes", "max_analytic_output_wire_bytes", "max_analytic_input_wire_bytes",
        "max_analytic_frame_memberships",
      ] {
      if @policy.ceiling(selected, name) is Some(value) {
        profile = profile.replace(
          old="\"max_aggregate_array_items\":1",
          new="\"max_aggregate_array_items\":1,\"" +
            name +
            "\":" +
            @policy.ceiling_value(value).to_string(),
        )
      }
    }
    let profiles = resolution_profiles(
      operation_order_fixture(
        scalar_steps(
          "{\"analytic\":{\"partition_by\":[\"id\",\"id\"],\"order_by\":[{\"id\":\"asc\"}],\"functions\":{\"position\":{\"fn\":\"row_number\"}}}}",
        ),
        capacity_policy=selected,
        host_profile=profile,
      ),
    )
    let index = index_program_operation_resolutions(profiles, 10000000, 1000).unwrap()
    let requirements = operation_resolution_requirements(index)
    let mut envelopes = 0
    let mut demands = 0
    for i in 0..<operation_resolution_count(index) {
      let site = operation_requirements_at(requirements, i).unwrap()
      guard site.requirement is @pipeline.RelationRequirement(pending) else {
        continue
      }
      if pending.kind is @relation.AnalyticFrameDemand {
        assert_true(operation_resolution_at(index, i) is Some(Unresolved))
        demands += 1
      }
      guard pending.kind is @relation.AnalyticEnvelope else { continue }
      envelopes += 1
      if omit != "" {
        assert_true(operation_resolution_at(index, i) is Some(Unresolved))
        continue
      }
      guard operation_resolution_at(index, i)
        is Some(Execution(AnalyticEnvelope(check))) else {
        fail("missing analytic envelope")
      }
      assert_true(physical_equal(check.site, site))
      assert_true(physical_equal(check.policy, selected))
      assert_true(
        physical_equal(
          check.step,
          @pipeline.step_at(site.pipeline, site.step).unwrap(),
        ),
      )
      assert_eq(check.step.input, Some(check.input))
      assert_true(
        physical_equal(
          @relation.analytic(check.operation).unwrap(),
          check.analytic,
        ),
      )
      assert_eq(@relation.analytic_partition_count(check.analytic), 2)
      assert_eq(@relation.analytic_call_count(check.analytic), 1)
      for
        (ceiling, name, value) in [
          (check.frame_memberships, "max_analytic_frame_memberships", 2L),
          (check.input_wire_bytes, "max_analytic_input_wire_bytes", 3L),
          (check.output_wire_bytes, "max_analytic_output_wire_bytes", 4L),
          (check.partition_wire_bytes, "max_analytic_partition_wire_bytes", 5L),
          (check.output_rows, "max_relation_output_rows", 1L),
        ] {
        assert_eq(@policy.ceiling_field(ceiling), name)
        assert_eq(@policy.ceiling_value(ceiling), value)
        assert_true(physical_equal(@policy.ceiling_policy(ceiling), selected))
      }
      assert_eq(
        operation_execution_phase(AnalyticEnvelope(check)),
        BeforeOperationOutput,
      )
      assert_eq(
        operation_execution_failure(AnalyticEnvelope(check)),
        RejectOperationOutput,
      )
    }
    assert_true(envelopes > 1)
    assert_eq(envelopes, demands)
    assert_true(
      close_program_operations(index, 10000000, 1000)
      is Err(IncompleteResolution(_)),
    )
    let work = operation_resolution_work(index)
    let count = operation_resolution_count(index)
    assert_true(
      index_program_operation_resolutions(profiles, work, count) is Ok(_),
    )
    assert_true(
      index_program_operation_resolutions(profiles, work - 1, count)
      is Err(BudgetExceeded),
    )
    assert_true(
      index_program_operation_resolutions(profiles, work, count - 1)
      is Err(BudgetExceeded),
    )
  }
}
