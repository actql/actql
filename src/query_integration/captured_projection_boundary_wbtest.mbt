///|
test "captured projection consumes the acquisition port before publishing its later Result" {
  // Independent machine Program: acquisition completes Step 1, while the
  // imported Stage Result belongs to Step 3. Neither port can stand for the other.
  let document =
    #|{"version":"actql/0.1","id":"captured-projection","stages":[{"id":"capture","inputs":{"records":{"connector":"crm/main","resource":"r"}},"steps":[{"from":"records","filter":{"literal":true}},{"select":["id"],"as":"captured"},{"from":"captured","derive":{"value":"id + 10"},"as":"derived"},{"from":"derived","select":["id","value"],"as":"projected"}],"results":{"source":{"from":"projected","fields":["id","value"]}}},{"id":"main","inputs":{"records":{"result":{"stage":"capture","result":"source"}}},"steps":[{"from":"records","sort":[{"id":"asc"}],"as":"out"}],"results":{"rows":{"from":"out","fields":["id","value"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
  let checked = acquired_relation_branch_checked(document)
  let sequence = query_checked_sequence(checked, prefix_end=Some(1))
  let owners = physical_graph_owners(checked)
  owners[0] = @query.query_sequence_owner(sequence)
  let graph = @strategy.prepare_checked_dag(checked, owners, 10, 100000).unwrap()
  let receipt = @query.admit_query_receipt(
    sequence,
    ["{\"id\":3}", "{\"id\":1}", "{\"id\":2}"].map(input_cursor),
    3,
    run_limits().input_values,
  ).unwrap()
  let live = Ref(true)
  let limits = dispatch_test_limits()
  let active = @client_local_host.start_client_query_residual(
    sequence,
    receipt,
    fn() { live.val },
    max_name_bytes=10000,
    limits.local_execution,
    limits.guards,
    100,
    10000,
  ).unwrap()
  let mut completed = None
  for _ in 0..<1000 {
    if completed is Some(_) {
      break
    }
    match @local_connector.advance_managed_provider(active, 1).unwrap() {
      @local_connector.Continue(work~, ..) => assert_true(work <= 1L)
      @local_connector.Complete(output, work~, ..) => {
        assert_true(work <= 1L)
        completed = Some(output)
      }
      _ => fail("the owned acquisition prefix did not complete")
    }
  }
  let output = completed.unwrap()
  // Trusted capture verifier fixture: the original bounded provider supplies
  // the completed prefix. This grants no Source, Model or Effect authority.
  let port = @query.prepare_trusted_capture_port(
    sequence,
    @program_check.source_identity(checked),
    fn(_ : Unit) { if live.val { Some((output, 28)) } else { None } },
  ).unwrap()
  let source = @query.capture_verified_source(port, ()).unwrap()
  // Keep the original target guard: raw acquisition cannot satisfy the later
  // projected Result merely because its bound owner and issuer are identical.
  assert_true(
    @query.bind_captured_source(source, owners[1], 0)
    is Err(Binding(@execution.ProducerTargetMismatch)),
  )
  let ledger = @resources.create_ledger({
    planning_work: 10000,
    attempts: 10,
    holdings: 10,
    transfer_bytes: 300000L,
    retained_bytes: 32000000L,
    execution_bytes: 134217728L,
  }).unwrap()
  let run = @strategy.open_captured_dag(graph, source, ledger).unwrap()
  assert_eq(@strategy.graph_task_count(graph), 4)
  assert_eq(@strategy.graph_task_prefix_end(graph, 0), Some(1))
  assert_eq(@strategy.graph_task_target(graph, 0), Some(@pipeline.Step(1)))
  assert_eq(@strategy.graph_task_selected_step(graph, 1), Some(2))
  assert_eq(@strategy.graph_task_selected_step(graph, 2), Some(3))
  assert_eq(
    @strategy.graph_stage_target_task(graph, 0, @pipeline.Step(3)),
    Some(2),
  )
  let edge = @strategy.graph_data_at(graph, 0).unwrap()
  assert_eq(
    (edge.producer, edge.consumer, edge.target),
    (0, 1, @pipeline.Step(1)),
  )
  assert_eq(@strategy.data_edge_operation_input(edge), Some((2, 0)))
  assert_true(@strategy.graph_ordered_inputs_complete(graph))
  let input = @strategy.captured_task_input(run, 1, 100, 10000).unwrap()
  assert_eq(@execution.producer_read_row_count(input), 3)
  assert_true(@execution.producer_read_available(input))
  assert_true(@execution.producer_read_has_cell_access(input))
  assert_true(
    @execution.producer_read_matches_operation_input(input, owners[0], 2, 0),
  )
  let generated = @execution.select_generated_sequence_step(
    task_test_generated(owners[0]),
    2,
  ).unwrap()
  let rows = @execution.start_bounded_binding_rows(
    @bounded.control(),
    generated,
    input,
    100,
    limits.local_execution.rows.input_values,
    limits.local_execution.rows.output_values,
    limits.local_execution.max_work,
    limits.local_execution.max_frames,
    limits.local_execution.rows.operation_entries,
    10000,
  ).unwrap()
  let mut projected = None
  for _ in 0..<1000 {
    if projected is Some(_) {
      break
    }
    match @execution.advance_bounded_binding_rows(rows, 1).unwrap() {
      @execution.BoundedBindingRowsComplete(output, ..) =>
        projected = Some(output)
      @execution.BoundedBindingRowsContinue(..) => ()
      _ => fail("the selected captured projection did not complete")
    }
  }
  let projected = projected.unwrap()
  assert_eq(@execution.completed_row_count(projected), 3)
  assert_true(@execution.completed_cell(projected, 0, 1) is Some(Number(13.0)))
  assert_true(@execution.completed_cell(projected, 1, 1) is Some(Number(11.0)))
  assert_true(@execution.completed_cell(projected, 2, 1) is Some(Number(12.0)))
  @execution.cancel_bounded_binding_rows(rows) |> ignore
  assert_true(@execution.cleanup_bounded_binding_rows(rows))
  live.val = false
  assert_false(@execution.producer_read_available(input))
  @strategy.stop_captured_dag(run)
  for task in 0..<@strategy.graph_task_count(graph) {
    @strategy.close_captured_task_output(run, task)
  }
  assert_true(@local_connector.cleanup_managed_provider(active).unwrap())
}
