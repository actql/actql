// Actual lowering is a reproduction input only. Expected rows come from the
// independent original interval law, not from the product observation.

///|
test "original temporal operands complete through selected interval with exact six-pair budget" {
  for
    (steps, step, left_step, right_step) in [
      (
        "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"at\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":1,\"at\":10},{\"id\":2,\"at\":30},{\"id\":3,\"at\":50}]},\"as\":\"l\"},{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"begin\":{\"type\":\"number\",\"nullable\":false},\"finish\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":7,\"begin\":5,\"finish\":15},{\"id\":8,\"begin\":20,\"finish\":25}]},\"as\":\"r\"},{\"from\":\"l\",\"interval_join\":{\"with\":\"r\",\"kind\":\"left\",\"mode\":\"point_in_interval\",\"on\":[],\"left\":{\"time\":\"at\"},\"right\":{\"start\":\"begin\",\"end\":\"finish\"},\"select\":{\"id\":\"left.id\",\"value\":\"right.id\"},\"max_output_rows\":3},\"as\":\"matched\"},{\"from\":\"matched\",\"sort\":[{\"field\":\"id\",\"dir\":\"asc\",\"nulls\":\"first\"}]},{\"select\":[\"id\",\"value\"],\"as\":\"out\"}]",
        2, 0, 1,
      ),
      (
        "[{\"values\":{\"schema\":{\"aql_source_free_unit\":{\"type\":\"boolean\",\"nullable\":false}},\"rows\":[{\"aql_source_free_unit\":true}]},\"as\":\"aql_script_seed_2\"},{\"from\":\"aql_script_seed_2\",\"derive\":{\"aql_query_expr_0\":{\"literal\":1},\"aql_query_expr_1\":{\"literal\":10}}},{\"select\":[{\"id\":\"aql_query_expr_0\"},{\"at\":\"aql_query_expr_1\"}],\"as\":\"aql_data_set_term_1\"},{\"values\":{\"schema\":{\"aql_source_free_unit\":{\"type\":\"boolean\",\"nullable\":false}},\"rows\":[{\"aql_source_free_unit\":true}]},\"as\":\"aql_script_seed_4\"},{\"from\":\"aql_script_seed_4\",\"derive\":{\"aql_query_expr_0\":{\"literal\":2},\"aql_query_expr_1\":{\"literal\":30}}},{\"select\":[{\"id\":\"aql_query_expr_0\"},{\"at\":\"aql_query_expr_1\"}],\"as\":\"aql_data_set_term_3\"},{\"from\":\"aql_data_set_term_1\",\"append\":{\"with\":\"aql_data_set_term_3\"},\"as\":\"aql_data_set_combined_5\"},{\"values\":{\"schema\":{\"aql_source_free_unit\":{\"type\":\"boolean\",\"nullable\":false}},\"rows\":[{\"aql_source_free_unit\":true}]},\"as\":\"aql_script_seed_7\"},{\"from\":\"aql_script_seed_7\",\"derive\":{\"aql_query_expr_0\":{\"literal\":3},\"aql_query_expr_1\":{\"literal\":50}}},{\"select\":[{\"id\":\"aql_query_expr_0\"},{\"at\":\"aql_query_expr_1\"}],\"as\":\"aql_data_set_term_6\"},{\"from\":\"aql_data_set_combined_5\",\"append\":{\"with\":\"aql_data_set_term_6\"},\"as\":\"aql_script_cte_0\"},{\"values\":{\"schema\":{\"aql_source_free_unit\":{\"type\":\"boolean\",\"nullable\":false}},\"rows\":[{\"aql_source_free_unit\":true}]},\"as\":\"aql_script_seed_11\"},{\"from\":\"aql_script_seed_11\",\"derive\":{\"aql_query_expr_0\":{\"literal\":7},\"aql_query_expr_1\":{\"literal\":5},\"aql_query_expr_2\":{\"literal\":15}}},{\"select\":[{\"id\":\"aql_query_expr_0\"},{\"begin\":\"aql_query_expr_1\"},{\"finish\":\"aql_query_expr_2\"}],\"as\":\"aql_data_set_term_10\"},{\"values\":{\"schema\":{\"aql_source_free_unit\":{\"type\":\"boolean\",\"nullable\":false}},\"rows\":[{\"aql_source_free_unit\":true}]},\"as\":\"aql_script_seed_13\"},{\"from\":\"aql_script_seed_13\",\"derive\":{\"aql_query_expr_0\":{\"literal\":8},\"aql_query_expr_1\":{\"literal\":20},\"aql_query_expr_2\":{\"literal\":25}}},{\"select\":[{\"id\":\"aql_query_expr_0\"},{\"begin\":\"aql_query_expr_1\"},{\"finish\":\"aql_query_expr_2\"}],\"as\":\"aql_data_set_term_12\"},{\"from\":\"aql_data_set_term_10\",\"append\":{\"with\":\"aql_data_set_term_12\"},\"as\":\"aql_script_cte_9\"},{\"from\":\"aql_script_cte_0\",\"interval_join\":{\"with\":\"aql_script_cte_9\",\"kind\":\"left\",\"mode\":\"point_in_interval\",\"on\":[],\"left\":{\"time\":\"at\"},\"right\":{\"start\":\"begin\",\"end\":\"finish\"},\"select\":{\"id\":\"left.id\",\"value\":\"right.id\"},\"max_output_rows\":3},\"as\":\"aql_carrier_16\"},{\"from\":\"aql_carrier_16\",\"select\":[\"id\",\"value\"]},{\"sort\":[{\"field\":\"id\",\"dir\":\"asc\",\"nulls\":\"first\"}],\"as\":\"aql_script_result\"}]",
        18, 10, 17,
      ),
    ] {
    let owner = bound_pipeline(steps)
    let retained = Array::makei(
      @pipeline.step_count(@lower.pipeline(@lower.bound_preparation(owner))),
      fn(index) {
        @lower.node_id(
          @lower.node_at(@lower.bound_preparation(owner), index).unwrap(),
        )
      },
    )
    let generated = prepare_generated_sequence(
      registered_relation_contracts(),
      prepared_sequence(owner),
      [],
      retained,
      100000,
      10000,
    ).unwrap()
    let generated = constrain_generated_interval_search(generated, step, 6L).unwrap()
    let generated = constrain_generated_join_output(generated, step, 3L).unwrap()
    let completed = execute_generated_sequence(
      generated,
      [],
      compute_test_limits(),
    ).unwrap()
    let left_output = completed_output(completed, @pipeline.Step(left_step)).unwrap()
    let right_output = completed_output(completed, @pipeline.Step(right_step)).unwrap()
    assert_eq(completed_row_count(left_output), 3)
    assert_eq(completed_row_count(right_output), 2)
    let left = prepare_producer_read(
      owner,
      bind_completed_operation_input(owner, step, 0, owner, left_output).unwrap(),
      100,
      10000,
    ).unwrap()
    let right = prepare_producer_read(
      owner,
      bind_completed_operation_input(owner, step, 1, owner, right_output).unwrap(),
      100,
      10000,
    ).unwrap()
    let selected = select_generated_sequence_step(generated, step).unwrap()
    let limits = compute_test_limits()
    let active = start_bounded_interval_join(
      @bounded.control(),
      selected,
      left,
      right,
      3,
      limits.rows.output_values,
      limits.max_work,
      limits.max_frames,
      limits.rows.operation_entries,
      10000,
    ).unwrap()
    let mut output = None
    for _ in 0..<100000 {
      if output is None {
        match advance_bounded_interval_join(active, 1).unwrap() {
          BoundedIntervalJoinContinue(..) => ()
          BoundedIntervalJoinComplete(value, ..) => output = Some(value)
          BoundedIntervalJoinFailed(issue, ..) => {
            let category = match issue {
              InvalidExecution => "invalid_execution"
              Rows(RowLimit) => "rows.row_limit"
              Rows(InvalidRowLimits) => "rows.invalid_limits"
              Rows(_) => "rows"
              Capture(_) => "capture"
              Completion(_) => "completion"
              Execution(_) => "execution"
            }
            fail("typed interval failure: " + category)
          }
          BoundedIntervalJoinStopped(_, ..) => fail("unexpected interval stop")
        }
      }
    }
    let rows = output.unwrap()
    assert_eq(completed_row_count(rows), 3)
    for (index, id) in [1.0, 2.0, 3.0].mapi(fn(index, id) { (index, id) }) {
      assert_true(
        completed_cell(rows, index, 0) is Some(Number(actual)) && actual == id,
      )
    }
    assert_true(completed_cell(rows, 0, 1) is Some(Number(7.0)))
    assert_true(completed_cell(rows, 1, 1) is Some(Null))
    assert_true(completed_cell(rows, 2, 1) is Some(Null))
    assert_true(cleanup_bounded_interval_join(active).unwrap())
    assert_false(bounded_interval_join_cleanup_pending(active))
  }
}
