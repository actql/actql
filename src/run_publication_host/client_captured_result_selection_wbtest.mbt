///|
let captured_selection_program : String =
  #|{"version":"actql/0.1","id":"captured-result-view","stages":[{"id":"producer","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1}]} ,"as":"rows"}],"results":{"rows":{"from":"rows","fields":["id"]}}},{"id":"consumer","inputs":{"input":{"result":{"stage":"producer","result":"rows"}}},"steps":[{"select":["id"],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"consumer","result":"rows"}}}}

///|
fn captured_selection_limits() -> PublicationOutputExportLimits {
  let wire : @execution.RowWireLimits = {
    max_columns: 10,
    max_order_work: 10000,
    max_bytes: 100000,
    max_nodes: 10000,
    max_depth: 100,
  }
  {
    max_result_fields: 10,
    max_result_mapping_work: 10000,
    max_result_order_work: 10000,
    max_result_workspace_entries: 100,
    max_rows: 100,
    values: {
      max_nodes: 10000,
      max_text_bytes: 10000,
      max_depth: 100,
      max_work: 100000,
    },
    payload_wire: wire,
    logical_wire: wire,
    schema: {
      max_fields: 10,
      max_bytes: 10000,
      max_nodes: 1000,
      max_depth: 10,
    },
    max_batch_bytes: 10000,
  }
}

///|
test "captured Result selection follows the original occurrence across physical views" {
  let prepared = input_result_prepared(captured_selection_program)
  let graph = prepared_client_graph(prepared)
  let projection = @strategy.prepare_retained_task_projection(
    graph,
    @strategy.graph_task_count(graph) - 1,
  ).unwrap()
  let view = @strategy_view.retained_task_projection_graph(projection)
  assert_false(physical_equal(graph, view))
  assert_true(
    physical_equal(
      @strategy.graph_result_occurrence(graph, 0).unwrap(),
      @strategy.graph_result_occurrence(view, 0).unwrap(),
    ),
  )
  let selected = prepare_client_result_transformation(
    { ..prepared, graph: view, },
    0,
    100000,
    10000,
    100,
  ).unwrap()
  let run = open_prepared_source_free_client_run(prepared, {
    planning_work: 100000,
    attempts: 10,
    holdings: 10,
    transfer_bytes: 500000L,
    retained_bytes: 200000000L,
    execution_bytes: 536870912L,
  }).unwrap()
  // Selection correspondence does not grant completion: the untouched Result
  // retention boundary must still refuse this unexecuted producer.
  assert_true(
    start_captured_client_result_transformation(
      selected,
      run,
      0,
      captured_selection_limits(),
    )
    is Err(Retain(_)),
  )
  @strategy.stop_captured_dag(run)
  @strategy.refresh_captured_retention(run)
  let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_eq(usage.live_reservations, 0)
}

///|
test "captured Result selection refuses foreign checked owners and occurrences" {
  let prepared = input_result_prepared(captured_selection_program)
  let foreign = input_result_prepared(captured_selection_program)
  assert_eq(
    prepared_client_identity(prepared).program_definition_cid,
    prepared_client_identity(foreign).program_definition_cid,
  )
  let selection = prepare_client_result_transformation(
    prepared, 0, 100000, 10000, 100,
  ).unwrap()
  let foreign_occurrence = @strategy.graph_result_occurrence(
    prepared_client_graph(foreign),
    0,
  ).unwrap()
  let run = open_prepared_source_free_client_run(prepared, {
    planning_work: 100000,
    attempts: 10,
    holdings: 10,
    transfer_bytes: 500000L,
    retained_bytes: 200000000L,
    execution_bytes: 536870912L,
  }).unwrap()
  // Equal CIDs cannot replace either original. Keep the other original intact
  // in each counterexample so the two correspondence checks stay independent.
  assert_true(
    start_captured_client_result_transformation(
      { ..selection, owner: foreign, },
      run,
      0,
      captured_selection_limits(),
    )
    is Err(ForeignSelection),
  )
  assert_true(
    start_captured_client_result_transformation(
      { ..selection, occurrence: foreign_occurrence, },
      run,
      0,
      captured_selection_limits(),
    )
    is Err(ForeignSelection),
  )
  assert_true(
    start_captured_client_result_transformation(
      selection,
      run,
      1,
      captured_selection_limits(),
    )
    is Err(ForeignSelection),
  )
  @strategy.stop_captured_dag(run)
  @strategy.refresh_captured_retention(run)
  let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_eq(usage.live_reservations, 0)
}
