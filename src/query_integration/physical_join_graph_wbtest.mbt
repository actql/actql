///|
test "checked two port DAG joins completed branches then counts in a separate Compute" {
  for self_join in [false, true] {
    let (run, issuer) = captured_graph_fixture(join=true, self_join~)
    let graph = @strategy.captured_dag_graph(run)
    assert_eq(@strategy.graph_task_count(graph), 5)
    assert_eq(@strategy.graph_data_count(graph), 5)
    assert_eq(@strategy.graph_control_count(graph), 4)
    let left = @strategy.graph_data_at(graph, 2).unwrap()
    let right = @strategy.graph_data_at(graph, 3).unwrap()
    assert_eq((left.producer, left.consumer, left.input), (1, 3, 0))
    assert_eq(
      (right.producer, right.consumer, right.input),
      (if self_join { 1 } else { 2 }, 3, 1),
    )
    assert_true(
      @strategy.captured_task_input(run, 3, 100, 10000, input_index=1)
      is Err(NotReady),
    )
    captured_graph_local(run, 1).unwrap()
    captured_graph_local(run, 2).unwrap()
    @planning.close_mock_query_issuer(issuer)
    assert_true(
      @strategy.captured_task_input(run, 3, 100, 10000, input_index=2)
      is Err(NotReady),
    )
    let first = @strategy.captured_task_input(run, 3, 100, 10000, input_index=0).unwrap()
    let second = @strategy.captured_task_input(
      run,
      3,
      100,
      10000,
      input_index=1,
    ).unwrap()
    assert_eq(@execution.producer_read_input_index(first), 0)
    assert_eq(@execution.producer_read_input_index(second), 1)
    captured_graph_local(run, 3).unwrap()
    let joined = @strategy.captured_task_output(run, 3, Step(0)).unwrap()
    assert_eq(@execution.completed_row_count(joined), 1)
    assert_true(@execution.completed_cell(joined, 0, 0) is Some(Number(3)))
    let ledger = @strategy.captured_dag_ledger(run)
    let before_close = @resources.ledger_usage(ledger).held_bytes
    @strategy.close_captured_task_output(run, 1)
    assert_eq(@resources.ledger_usage(ledger).held_bytes, before_close)
    @strategy.close_captured_task_output(run, 2)
    if !self_join {
      // The second parent must remain accounted for too, not just the first
      // edge found in the graph. Equal content is never the sharing key.
      assert_eq(@resources.ledger_usage(ledger).held_bytes, before_close)
    }
    captured_graph_local(run, 4).unwrap()
    let counted = @strategy.captured_task_output(run, 4, Step(0)).unwrap()
    assert_eq(@execution.completed_row_count(counted), 1)
    assert_true(@execution.completed_cell(counted, 0, 0) is Some(Number(1)))
    @strategy.close_captured_task_output(run, 3)
    assert_true(@strategy.captured_task_output(run, 4, Step(0)) is Some(_))
    assert_eq(@strategy.next_captured_task(run), None)
    @strategy.close_captured_task_output(run, 4)
    assert_eq(@resources.ledger_usage(ledger).held_bytes, 0L)
    assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
  }
}

///|
test "closing either prepared join input prevents start without revoking its other parent" {
  for closed in [1, 2] {
    let (run, _) = captured_graph_fixture(join=true)
    captured_graph_local(run, 1).unwrap()
    captured_graph_local(run, 2).unwrap()
    let reads = [0, 1].map(port => {
      @strategy.captured_task_input(run, 3, 100, 10000, input_index=port).unwrap()
    })
    @strategy.close_captured_task_output(run, closed)
    let port = closed - 1
    assert_false(@execution.producer_read_available(reads[port]))
    assert_true(
      @strategy.captured_task_input(run, 3, 100, 10000, input_index=port)
      is Err(MissingOutput),
    )
    assert_true(@strategy.captured_task_output(run, 3, Step(0)) is None)
    assert_true(@strategy.next_captured_task(run) is None)
    let other = if closed == 1 { 2 } else { 1 }
    assert_true(@strategy.captured_task_output(run, other, Step(1)) is Some(_))
    @strategy.close_captured_task_output(run, other)
    assert_eq(
      @resources.ledger_usage(@strategy.captured_dag_ledger(run)).held_bytes,
      0L,
    )
  }
}
