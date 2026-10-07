///|
/// Declare a separate private port on the real fixture's checked producer.
/// Its name intentionally equals the ordinary Result name; the namespaces and
/// typed occurrences must not become interchangeable.
fn table_retention_occurrence(
  result : @execution.ManagedResultOccurrence,
) -> @execution.ManagedTableInputOccurrence raise {
  let owner = @execution.managed_result_occurrence_owner(result)
  let definition = @relation_results.port_result(
    @execution.managed_result_occurrence_port(result),
  )
  let source = @decode.open_object(
    @relation_results.definition_source(definition),
  ).unwrap()
  let from = @decode.text(@decode.lookup(source, "from").unwrap()).unwrap()
  let writer = @encode.writer(10000, 1000, 10)
  @encode.begin_object(writer)
  @encode.key(writer, @execution.managed_result_occurrence_name(result))
  @encode.begin_object(writer)
  @encode.key(writer, "from")
  @encode.string_value(writer, from)
  @encode.key(writer, "fields")
  @encode.begin_array(writer)
  for field in @relation_results.fields(definition) {
    @encode.string_value(writer, field)
  }
  @encode.end_array(writer)
  @encode.end_object(writer)
  @encode.end_object(writer)
  let declarations = @relation_results.check_table_inputs(
    @lower.pipeline(@lower.bound_preparation(owner)),
    input_cursor(@encode.finish(writer)),
    {
      max_results: 10,
      max_work: 100000,
      max_nodes: 10000,
      max_text_bytes: 100000,
      max_depth: 100,
    },
  ).unwrap()
  @execution.bind_managed_table_input_occurrence(
    owner,
    declarations,
    @execution.managed_result_occurrence_name(result),
  ).unwrap()
}

///|
test "private Table pin shares Result limits and retains original producer order after close" {
  let (run, issuer) = captured_graph_fixture(
    rows=Some(["{\"id\":2}", "{\"id\":1}", "{\"id\":3}"]),
  )
  let graph = @strategy.captured_dag_graph(run)
  for task in 1..<@strategy.graph_task_count(graph) {
    captured_graph_local(run, task).unwrap()
  }
  let task = @strategy.graph_result_task(graph, 0).unwrap()
  let result = @strategy.graph_result_occurrence(graph, 0).unwrap()
  let occurrence = table_retention_occurrence(result)
  let table = @strategy.borrow_captured_table_input_output(
    run, task, occurrence, 2,
  ).unwrap()
  let published = @strategy.borrow_captured_result_output(run, task, result, 2).unwrap()
  assert_true(
    @strategy.borrow_captured_table_input_output(run, task, occurrence, 2)
    is Err(@strategy.Physical(@resources.HoldingLimit)),
  )
  let output = @strategy.captured_table_input_borrow_cell_output(table).unwrap()
  @strategy.close_captured_task_output(run, task)
  assert_true(
    @strategy.borrow_captured_table_input_output(run, task, occurrence, 2)
    is Err(@strategy.NotReady),
  )
  assert_true(@strategy.release_captured_result_borrow(published))
  assert_true(@strategy.captured_table_input_borrow_available(table))
  assert_true(
    @resources.ledger_usage(@strategy.captured_dag_ledger(run)).held_bytes > 0L,
  )
  let limits = native_publication_export_limits()
  let preparation = @strategy.start_captured_table_input_borrow_export(
    table,
    {
      max_fields: 10,
      max_mapping_work: 100,
      max_order_work: 1000,
      max_workspace_entries: 20,
    },
    limits.max_rows,
    limits.values,
    limits.payload_wire,
    limits.logical_wire,
    limits.schema,
    limits.max_batch_bytes,
  ).unwrap()
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
  // The explicitly authored acquisition order is 2, 1, 3. Filtering id > 1
  // preserves 2, 3; a private input cannot invent a different query order.
  assert_eq(text.to_string(), "[{\"id\":2},{\"id\":3}]")
  assert_eq(@execution.completed_relation_export_field_names(receipt), ["id"])
  assert_true(@strategy.release_captured_table_input_borrow(table))
  assert_false(@strategy.release_captured_table_input_borrow(table))
  assert_false(@execution.completed_output_available(output))
  assert_false(@strategy.captured_table_input_borrow_available(table))
  @execution.cancel_completed_relation_export_receipt(receipt)
  for index in 0..<@strategy.graph_task_count(graph) {
    @strategy.close_captured_task_output(run, index)
  }
  @mock.close_mock_query_issuer(issuer)
  assert_eq(
    @resources.ledger_usage(@strategy.captured_dag_ledger(run)).held_bytes,
    0L,
  )
}

///|
test "private Table pin set rolls back foreign or repeated over-limit requests without releasing another consumer" {
  let (run, issuer) = captured_graph_fixture()
  let (foreign, foreign_issuer) = captured_graph_fixture()
  let graph = @strategy.captured_dag_graph(run)
  for task in 1..<@strategy.graph_task_count(graph) {
    captured_graph_local(run, task).unwrap()
  }
  let task = @strategy.graph_result_task(graph, 0).unwrap()
  let result = @strategy.graph_result_occurrence(graph, 0).unwrap()
  let occurrence = table_retention_occurrence(result)
  let foreign_occurrence = table_retention_occurrence(
    @strategy.graph_result_occurrence(@strategy.captured_dag_graph(foreign), 0).unwrap(),
  )
  let existing = @strategy.borrow_captured_result_output(run, task, result, 2).unwrap()
  assert_true(
    @strategy.pin_captured_table_input_output_set(
      run,
      [(task, occurrence), (task, foreign_occurrence)],
      2,
    )
    is Err(@strategy.ForeignCandidate),
  )
  assert_true(@strategy.captured_result_borrow_available(existing))
  assert_true(
    @strategy.pin_captured_table_input_output_set(
      run,
      [(task, occurrence), (task, occurrence)],
      2,
    )
    is Err(@strategy.Physical(@resources.HoldingLimit)),
  )
  assert_true(@strategy.captured_result_borrow_available(existing))
  let table = @strategy.borrow_captured_table_input_output(
    run, task, occurrence, 2,
  ).unwrap()
  assert_true(@strategy.release_captured_table_input_borrow(table))
  assert_true(@strategy.release_captured_result_borrow(existing))
  let set = @strategy.pin_captured_table_input_output_set(
    run,
    [(task, occurrence), (task, occurrence)],
    2,
  ).unwrap()
  let first = @strategy.captured_table_input_output_set_borrow_at(set, 0).unwrap()
  let second = @strategy.captured_table_input_output_set_borrow_at(set, 1).unwrap()
  @strategy.close_captured_task_output(run, task)
  assert_true(@strategy.captured_table_input_borrow_available(first))
  assert_true(@strategy.captured_table_input_borrow_available(second))
  assert_true(@strategy.release_captured_table_input_output_set(set))
  assert_false(@strategy.release_captured_table_input_output_set(set))
  assert_true(
    @strategy.captured_table_input_output_set_borrow_at(set, 0) is None,
  )
  assert_false(@strategy.captured_table_input_borrow_available(first))
  assert_false(@strategy.captured_table_input_borrow_available(second))
  for index in 0..<@strategy.graph_task_count(graph) {
    @strategy.close_captured_task_output(run, index)
  }
  @mock.close_mock_query_issuer(issuer)
  @mock.close_mock_query_issuer(foreign_issuer)
  @strategy.stop_captured_dag(foreign)
  @strategy.close_captured_task_output(foreign, 0)
  assert_eq(
    @resources.ledger_usage(@strategy.captured_dag_ledger(run)).held_bytes,
    0L,
  )
}

///|
test "private Table pin release cannot confirm pending physical cleanup" {
  let (run, issuer) = captured_graph_fixture()
  let graph = @strategy.captured_dag_graph(run)
  let ledger = @strategy.captured_dag_ledger(run)
  let reservation = @resources.reserve_attempt(ledger, 100L, 100L, 0L).unwrap()
  let holding = @resources.retain_allocation(ledger, reservation, 100L).unwrap()
  let released = Ref(false)
  @strategy.retain_captured_task_allocation(run, 0, holding, release_confirmed=fn() {
    released.val
  }).unwrap()
  @resources.settle_reservation(ledger, reservation).unwrap()
  for task in 1..<@strategy.graph_task_count(graph) {
    captured_graph_local(run, task).unwrap()
  }
  let task = @strategy.graph_result_task(graph, 0).unwrap()
  let table = @strategy.borrow_captured_table_input_output(
    run,
    task,
    table_retention_occurrence(
      @strategy.graph_result_occurrence(graph, 0).unwrap(),
    ),
    1,
  ).unwrap()
  for index in 0..<@strategy.graph_task_count(graph) {
    @strategy.close_captured_task_output(run, index)
  }
  @mock.close_mock_query_issuer(issuer)
  assert_true(@strategy.release_captured_table_input_borrow(table))
  @strategy.refresh_captured_retention(run)
  assert_eq(@resources.ledger_usage(ledger).held_bytes, 100L)
  released.val = true
  @strategy.refresh_captured_retention(run)
  @strategy.refresh_captured_retention(run)
  assert_eq(@resources.ledger_usage(ledger).held_bytes, 0L)
}
