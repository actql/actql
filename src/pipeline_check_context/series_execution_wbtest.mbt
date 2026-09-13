///|
test "series execution rejects missing or foreign range evidence before computing a count" {
  let a = "2000-01-01T00:00:00.000Z"
  let z = "2000-01-01T00:00:00.010Z"
  let pipeline = @pipeline.check_with_evidence(
    asof_test_cursor(
      "[{\"time_series\":{\"start\":\"" +
      a +
      "\",\"end\":\"" +
      z +
      "\",\"step\":3},\"as\":\"grid\"}]",
    ),
    [],
    None,
    None,
    {
      max_steps: 1,
      max_work: 100000,
      max_text_bytes: 100000,
      max_nodes: 10000,
      max_tokens: 10000,
      max_depth: 100,
    },
  ).unwrap()
  let step = @pipeline.step_at(pipeline, 0).unwrap()
  let obligations = @pipeline.operation_obligation_group_at(step.operation, 0).unwrap()
  let entries : Array[OperationRequirementSite] = []
  let mut range_index = -1
  for index in 0..<@pipeline.operation_obligations_count(obligations) {
    let requirement = @pipeline.operation_obligations_at(obligations, index).unwrap()
    if requirement is @pipeline.SeriesRequirement(ValidateRange) {
      range_index = index
    }
    entries.push({
      stage: 0,
      producer_visit: 1,
      step: 0,
      group: 0,
      index,
      pipeline,
      obligations,
      requirement,
    })
  }
  let range : OperationRangeResolution = {
    requirement_index: range_index,
    site: entries[range_index],
    start: a,
    end: z,
    start_parameter: None,
    end_parameter: None,
  }
  let fields = [
    "max_aggregate_array_items", "max_artifact_bytes", "max_artifact_rows", "max_effect_items",
    "max_graph_input_edges", "max_graph_input_nodes", "max_graph_output_rows", "max_graph_paths",
    "max_infer_items", "max_model_input_tokens_per_item", "max_model_request_bytes_per_item",
    "max_model_total_duration_ms", "max_nested_value_bytes", "max_nested_value_depth",
    "max_relation_output_rows", "max_temporal_matches_per_key", "max_temporal_output_rows",
  ]
  let policy = @policy.admit(
    @wire_utf8.encode(
      "{" +
      fields.map(name => "\"" + name + "\":1").join(",") +
      ",\"version\":\"actql-capacity-host-policy/0.1\"}",
    ),
    "sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63",
    { max_bytes: 4096, max_nodes: 100, max_depth: 4, },
  ).unwrap()
  let states : Array[OperationResolutionState] = Array::make(
    entries.length(),
    Unresolved,
  )
  states[range_index] = Resolved(Range(range))
  for index in 0..<entries.length() {
    if index == range_index {
      continue
    }
    let site = entries[index]
    let (result, work) = series_execution_check(
      site, index, entries, states, policy, 1000,
    )
    guard result is Ok(Some(SeriesExecution(check))) else {
      fail("series check")
    }
    assert_eq(check.row_count, 4L)
    assert_true(physical_equal(check.range, range))
    assert_true(
      series_execution_check(site, index, entries, states, policy, work).0
      is Ok(Some(_)),
    )
    assert_true(
      series_execution_check(site, index, entries, states, policy, work - 1).0
      is Err(BudgetExceeded),
    )
    for
      replacement in [
        OperationResolutionState::Unresolved,
        Resolved(Range({ ..range, requirement_index: range_index + 1, })),
        Resolved(Range({ ..range, site: { ..range.site, stage: 1, }, })),
        Resolved(
          Range({ ..range, site: { ..range.site, producer_visit: 2, }, }),
        ),
      ] {
      let changed = states.copy()
      changed[range_index] = replacement
      assert_true(
        series_execution_check(site, index, entries, changed, policy, 1000).0
        is Err(ForeignOccurrence(_)),
      )
    }
  }
}
