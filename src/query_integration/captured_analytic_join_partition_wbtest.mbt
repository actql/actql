///|
test "captured Relation with independent Values roots selects its bounded analytic occurrence" {
  let text =
    #|{"version":"actql/0.1","id":"captured-analytic-join","params":{"minimum":{"type":"number","nullable":false}},"stages":[{"id":"a","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id > $minimum","as":"filtered"},{"select":["id"],"as":"captured"}],"results":{"r":{"from":"captured","fields":["id"]}}},{"id":"main","inputs":{"records":{"result":{"stage":"a","result":"r"}}},"steps":[{"values":{"schema":{"k":{"type":"number","nullable":false}},"rows":[{"k":2}]},"as":"two"},{"values":{"schema":{"k":{"type":"number","nullable":false}},"rows":[{"k":3}]},"as":"three"},{"from":"two","append":{"with":"three"},"as":"keys"},{"from":"records","join":{"with":"keys","kind":"inner","on":[{"left":"id","right":"k"}],"max_output_rows":10,"select":{"id":"left.id"}},"as":"joined"},{"from":"joined","analytic":{"partition_by":[],"order_by":[{"field":"id","dir":"asc","nulls":"first"}],"functions":{"n":{"fn":"row_number"}}},"as":"numbered"},{"from":"numbered","filter":{"lte":[{"field":"n"},{"literal":2}]},"as":"qualified"},{"from":"qualified","select":["id","n"],"as":"out"}],"results":{"rows":{"from":"out","fields":["id","n"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
  let checked = query_checked_program_fixture(
    program_text=Some(text),
    local_values_analytic_chain=true,
  )
  let (run, issuer) = captured_graph_fixture(
    checked_program=Some(checked),
    rows=Some(["{\"id\":2}", "{\"id\":3}"]),
    preparation_work=10000,
  )
  let graph = @strategy.captured_dag_graph(run)
  let mut selected_analytics = 0
  for task in 0..<@strategy.graph_task_count(graph) {
    if @strategy.graph_task_selected_step(graph, task) is Some(step) {
      let owner = @strategy.graph_task_owner(graph, task).unwrap()
      let node = @lower.node_at(@lower.bound_preparation(owner), step).unwrap()
      if @lower.payload(node) is @lower.Analytic(_) {
        selected_analytics += 1
        assert_eq(
          @strategy.captured_task_analytic_envelope_count(run, task),
          Some(1),
        )
      }
    }
  }
  assert_eq(selected_analytics, 1)
  @strategy.stop_captured_dag(run)
  for task in 0..<@strategy.graph_task_count(graph) {
    @strategy.close_captured_task_output(run, task)
  }
  @strategy.refresh_captured_retention(run)
  let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.held_bytes, 0L)
  @mock.close_mock_query_issuer(issuer)
}
