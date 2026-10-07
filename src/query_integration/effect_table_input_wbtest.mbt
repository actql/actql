///|
fn verify_captured_private_table_input(empty : Bool) -> Unit raise {
  let (document, environment, limits) = local_effect_export_fixture(
    table=true,
    empty~,
  )
  let prepared = match
    @publication_host.prepare_client_effect_computation(
      document,
      Json,
      environment,
      None,
      [],
      limits,
    ) {
    Ok(value) => value
    Err(Candidate(_)) => fail("private Table candidate preparation failed")
    Err(Static(@stage_results.MappingRules(issue))) =>
      fail(
        "private Table Mapping rules failed: " +
        @debug.to_string(@stage_results.effect_mapping_rule_issue_kind(issue)),
      )
    Err(Static(_)) => fail("private Table static closure failed")
    Err(Graph(issue)) =>
      fail("private Table physical graph failed: " + @debug.to_string(issue))
    Err(_) => fail("private Table Host preparation failed")
  }
  let computation = @publication_host.prepared_client_effect_computation_graph(
    prepared,
  )
  assert_true(@strategy.checked_effect_source_at(computation, 0) is None)
  assert_true(
    @strategy.checked_effect_table_input_at(computation, 0) is Some(_),
  )
  assert_true(@strategy.checked_effect_source_at(computation, 1) is Some(_))
  assert_true(@strategy.checked_effect_table_input_at(computation, 1) is None)
  let (_, _, _, effect_run) = local_effect_open_run(prepared)
  let run = @strategy.captured_effect_run_dag(effect_run)
  let (operations, completed, available) = local_effect_execute_managed_values(
    prepared, run,
  )
  // Two ordinary Manifest/Effect Result views have been pinned when the
  // Table pin reaches the same per-task ceiling. Failure rolls both back.
  assert_true(
    @strategy.pin_captured_effect_sources(effect_run, 2)
    is Err(@strategy.Physical(@resources.HoldingLimit)),
  )
  let inputs = @strategy.pin_captured_effect_sources(effect_run, 3).unwrap()
  assert_eq(@strategy.captured_effect_inputs_count(inputs), 2)
  assert_true(@strategy.captured_effect_input_at(inputs, 0) is None)
  assert_true(@strategy.captured_effect_table_input_at(inputs, 1) is None)
  let table = @strategy.captured_effect_table_input_at(inputs, 0).unwrap()
  assert_eq(@strategy.captured_effect_table_input_member(table), 0)
  assert_eq(@strategy.captured_effect_table_input_stage(table), 0)
  assert_eq(@strategy.captured_effect_table_input_task(table), 0)
  let ordinary = @strategy.captured_effect_input_at(inputs, 1).unwrap()
  assert_eq(@strategy.captured_effect_local_result_count(inputs), 2)
  assert_true(@strategy.close_captured_effect_source_port(inputs, 0))
  assert_true(@strategy.captured_effect_input_at(inputs, 1) is Some(_))
  assert_true(@strategy.captured_effect_table_input_at(inputs, 0) is Some(_))
  let borrow = @strategy.captured_effect_table_input_borrow(table)
  assert_true(
    @strategy.captured_table_input_borrow_matches_managed(borrow, completed),
  )
  assert_true(@strategy.captured_table_input_borrow_cell_output(borrow) is None)
  let bridge = @execution.prepare_managed_publication_bridge(
    completed,
    (operations.material)().unwrap(),
    10,
    { max_nodes: 1000, max_text_bytes: 10000, max_depth: 20, max_work: 10000, },
    100,
    10000,
  ).unwrap()
  for row in local_managed_test_rows(operations) {
    @execution.append_managed_publication_bridge_wire(bridge, row, {
      max_bytes: 100,
      max_nodes: 20,
      max_depth: 4,
      max_text_bytes: 100,
    }).unwrap()
  }
  let output = @execution.finish_managed_publication_bridge(bridge).unwrap()
  let occurrence = @strategy.captured_effect_table_input_occurrence(table)
  let preparation = @execution.start_completed_table_input_relation_export(
    output,
    occurrence,
    {
      max_fields: 10,
      max_mapping_work: 100,
      max_order_work: 100,
      max_workspace_entries: 20,
    },
    10,
    { max_nodes: 1000, max_text_bytes: 10000, max_depth: 20, max_work: 10000, },
    row_wire_limits(),
    row_wire_limits(),
    { max_fields: 10, max_bytes: 10000, max_nodes: 1000, max_depth: 20, },
    64,
  ).unwrap()
  assert_true(
    @execution.managed_publication_bridge_matches_table_input_export(
      bridge, completed, preparation, occurrence,
    ),
  )
  let mut ready = false
  for _ in 0..<100 {
    if @execution.advance_completed_table_input_relation_export(preparation, 1).unwrap().0 {
      ready = true
      break
    }
  }
  assert_true(ready)
  let stream = @execution.finish_completed_table_input_relation_export_preparation(
    preparation,
  ).unwrap()
  let text = StringBuilder()
  while @execution.next_completed_output_export(stream).unwrap() is Some(chunk) {
    text.write_string(chunk)
  }
  let (receipt, tail) = @execution.finish_completed_relation_export(stream).unwrap()
  text.write_string(tail)
  assert_eq(text.to_string(), if empty { "[]" } else { "[{\"value\":1}]" })
  assert_eq(@execution.completed_relation_export_field_names(receipt), ["value"])
  assert_eq(
    @execution.relation_schema_wire(
      @execution.completed_relation_export_schema_identity(receipt),
    ),
    "{\"value\":{\"nullable\":false,\"type\":\"number\"}}",
  )
  assert_true(@strategy.release_captured_effect_inputs(inputs))
  assert_false(@strategy.release_captured_effect_inputs(inputs))
  assert_true(@strategy.captured_effect_table_input_at(inputs, 0) is None)
  assert_false(@strategy.captured_table_input_borrow_available(borrow))
  assert_false(
    @strategy.captured_any_result_borrow_available(
      @strategy.captured_effect_input_borrow(ordinary),
    ),
  )
  @execution.cancel_completed_relation_export_receipt(receipt)
  @execution.close_managed_publication_bridge(bridge)
  available.val = false
  (operations.cleanup_refresh)() |> ignore
  @strategy.refresh_captured_retention(run)
  let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_eq(usage.held_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.reserved_execution_bytes, 0L)
}

///|
test "checked Effect capture distinguishes private Table input from its same-name Result" {
  verify_captured_private_table_input(false)
}

///|
test "checked Effect capture retains an empty typed private Table input" {
  verify_captured_private_table_input(true)
}
