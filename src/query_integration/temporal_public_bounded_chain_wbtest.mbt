// Actual normalized inputs are reproduction material only; the rows below
// remain independently fixed by the original point-in-interval example.

///|
test "original interval JSON and SQL use the installed bounded Relation chain" {
  for
    (case_index, text) in [
      (
        #|[{"as":"l","values":{"rows":[{"at":10,"id":1},{"at":30,"id":2},{"at":50,"id":3}],"schema":{"at":{"nullable":false,"type":"number"},"id":{"nullable":false,"type":"number"}}}},{"as":"r","values":{"rows":[{"begin":5,"finish":15,"id":7},{"begin":20,"finish":25,"id":8}],"schema":{"begin":{"nullable":false,"type":"number"},"finish":{"nullable":false,"type":"number"},"id":{"nullable":false,"type":"number"}}}},{"as":"matched","from":"l","interval_join":{"kind":"left","left":{"time":"at"},"max_output_rows":3,"mode":"point_in_interval","on":[],"right":{"end":"finish","start":"begin"},"select":{"id":"left.id","value":"right.id"},"with":"r"}},{"from":"matched","sort":[{"dir":"asc","field":"id","nulls":"first"}]},{"as":"out","select":["id","value"]}]
      ),
      (
        #|[{"as":"aql_script_seed_2","values":{"rows":[{"aql_source_free_unit":true}],"schema":{"aql_source_free_unit":{"nullable":false,"type":"boolean"}}}},{"derive":{"aql_query_expr_0":{"literal":1},"aql_query_expr_1":{"literal":10}},"from":"aql_script_seed_2"},{"as":"aql_data_set_term_1","select":[{"id":"aql_query_expr_0"},{"at":"aql_query_expr_1"}]},{"as":"aql_script_seed_4","values":{"rows":[{"aql_source_free_unit":true}],"schema":{"aql_source_free_unit":{"nullable":false,"type":"boolean"}}}},{"derive":{"aql_query_expr_0":{"literal":2},"aql_query_expr_1":{"literal":30}},"from":"aql_script_seed_4"},{"as":"aql_data_set_term_3","select":[{"id":"aql_query_expr_0"},{"at":"aql_query_expr_1"}]},{"append":{"with":"aql_data_set_term_3"},"as":"aql_data_set_combined_5","from":"aql_data_set_term_1"},{"as":"aql_script_seed_7","values":{"rows":[{"aql_source_free_unit":true}],"schema":{"aql_source_free_unit":{"nullable":false,"type":"boolean"}}}},{"derive":{"aql_query_expr_0":{"literal":3},"aql_query_expr_1":{"literal":50}},"from":"aql_script_seed_7"},{"as":"aql_data_set_term_6","select":[{"id":"aql_query_expr_0"},{"at":"aql_query_expr_1"}]},{"append":{"with":"aql_data_set_term_6"},"as":"aql_script_cte_0","from":"aql_data_set_combined_5"},{"as":"aql_script_seed_11","values":{"rows":[{"aql_source_free_unit":true}],"schema":{"aql_source_free_unit":{"nullable":false,"type":"boolean"}}}},{"derive":{"aql_query_expr_0":{"literal":7},"aql_query_expr_1":{"literal":5},"aql_query_expr_2":{"literal":15}},"from":"aql_script_seed_11"},{"as":"aql_data_set_term_10","select":[{"id":"aql_query_expr_0"},{"begin":"aql_query_expr_1"},{"finish":"aql_query_expr_2"}]},{"as":"aql_script_seed_13","values":{"rows":[{"aql_source_free_unit":true}],"schema":{"aql_source_free_unit":{"nullable":false,"type":"boolean"}}}},{"derive":{"aql_query_expr_0":{"literal":8},"aql_query_expr_1":{"literal":20},"aql_query_expr_2":{"literal":25}},"from":"aql_script_seed_13"},{"as":"aql_data_set_term_12","select":[{"id":"aql_query_expr_0"},{"begin":"aql_query_expr_1"},{"finish":"aql_query_expr_2"}]},{"append":{"with":"aql_data_set_term_12"},"as":"aql_script_cte_9","from":"aql_data_set_term_10"},{"as":"aql_carrier_16","from":"aql_script_cte_0","interval_join":{"kind":"left","left":{"time":"at"},"max_output_rows":3,"mode":"point_in_interval","on":[],"right":{"end":"finish","start":"begin"},"select":{"id":"left.id","value":"right.id"},"with":"aql_script_cte_9"}},{"from":"aql_carrier_16","select":["id","value"]},{"as":"aql_script_result","sort":[{"dir":"asc","field":"id","nulls":"first"}]}]
      ),
    ].mapi(fn(index, text) { (index, text) }) {
    let checked = @pipeline.check(input_cursor(text), [], None, None, {
      max_steps: 100,
      max_work: 100000,
      max_text_bytes: 100000,
      max_nodes: 10000,
      max_tokens: 10000,
      max_depth: 100,
    }).unwrap()
    let owner = @lower.bind_parameters(
      @lower.prepare(checked, {
        max_nodes: 1000,
        max_references: 1000,
        max_work: 100000,
        max_identifier_bytes: 10000,
      }).unwrap(),
      None,
      max_parameters=0,
      max_name_bytes=0,
    ).unwrap()
    let generated = task_test_generated(owner)
    let interval_step = @execution.generated_sequence_step_count(generated) - 3
    let generated = @execution.constrain_generated_interval_search(
      generated, interval_step, 6L,
    ).unwrap()
    let generated = @execution.constrain_generated_join_output(
      generated, interval_step, 3L,
    ).unwrap()
    let registry = search_registry()
    let limits = dispatch_test_limits()
    let capacity = @execution.generated_sequence_capacity(
      generated,
      limits.local_execution,
      limits.guards,
    ).unwrap()
    let family = @local_tea_provider.interval_join_provider(
      carrier_events_storage_limits(),
      capacity,
    )
    let implementation = @local_connector.prepare_local_compute_module(
      registry,
      @connector.capability_registration_at(registry, 0).unwrap(),
      [generated],
      limits.local_execution,
      limits.guards,
      limits.candidate_work,
      1,
      managed_providers=[family],
    ).unwrap()
    let provider = @local_connector.local_module_managed_provider(
      implementation, 0, generated,
    ).unwrap()
    let active = @local_connector.start_managed_provider_with_inputs_and_execution(
      provider,
      generated,
      [],
      limits.local_execution.rows.max_rows,
      limits.guards.max_bytes,
      limits.local_execution,
    ).unwrap()
    let mut output = None
    let mut failure = None
    for _ in 0..<100000 {
      if output is None && failure is None {
        match @local_connector.advance_managed_provider(active, 1).unwrap() {
          Continue(..) | Waiting(..) | Settling(_, ..) => ()
          Complete(result, ..) => output = Some(result)
          Failed(issue, ..) =>
            failure = Some(
              match issue {
                @connector.Execution(@execution.InputSet) =>
                  "execution.input_set"
                @connector.Execution(@execution.InputLimit) =>
                  "execution.input_limit"
                @connector.Execution(
                  @execution.Rows(step, @execution.InputMismatch)
                ) => "rows.input_mismatch:" + step.to_string()
                @connector.Execution(@execution.Rows(step, @execution.RowLimit)) =>
                  "rows.row_limit:" + step.to_string()
                @connector.Execution(_) => "execution.other"
                _ => "other_typed_issue"
              },
            )
          _ => failure = Some("unexpected_provider_phase")
        }
      }
    }
    if failure is Some(reason) {
      assert_true(@local_connector.cleanup_managed_provider(active).unwrap())
      fail("original case " + case_index.to_string() + ": " + reason)
    }
    let result = output.unwrap()
    assert_eq(@execution.completed_row_count(result), 3)
    assert_eq(@execution.completed_column_name(result, 0), Some("id"))
    assert_eq(@execution.completed_column_name(result, 1), Some("value"))
    for (row, id) in [1.0, 2.0, 3.0].mapi(fn(index, id) { (index, id) }) {
      assert_true(
        @execution.completed_cell(result, row, 0) is Some(Number(actual)) &&
        actual == id,
      )
    }
    assert_true(@execution.completed_cell(result, 0, 1) is Some(Number(7.0)))
    assert_true(@execution.completed_cell(result, 1, 1) is Some(Null))
    assert_true(@execution.completed_cell(result, 2, 1) is Some(Null))
    assert_true(@local_connector.cleanup_managed_provider(active).unwrap())
  }
}
