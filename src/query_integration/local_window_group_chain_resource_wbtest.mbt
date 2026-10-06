///|
/// Run the zero-input values, fixed row window and keyed window group chain
/// with the given execution work, operation-entry limits and resume quantum.
/// Returns "complete", "work" or "workspace", with the charged work.
fn run_window_group_chain_budget(
  max_work : Int,
  max_entries : Int,
  cancel_after? : Int? = None,
  quantum? : Int = 1,
) -> (String, Int64) raise {
  let (run, issuer) = captured_graph_fixture(
    local_values_window_group_chain=true,
    local_values_window_group_variant="fixed_keyed",
  )
  let registry = search_registry()
  let defaults = { ..dispatch_test_limits(), candidate_work: 1000, }
  let execution : @execution.SequenceExecutionLimits = {
    rows: { ..defaults.local_execution.rows, operation_entries: max_entries, },
    max_work,
    max_frames: defaults.local_execution.max_frames,
  }
  let installed = @local_driver.prepare_local_dispatch_module(
    @host_driver.open_dispatch_driver(run),
    registry,
    @connector.capability_registration_at(registry, 0).unwrap(),
    dispatch_test_generated(run),
    execution,
    defaults.guards,
    defaults.candidate_work,
  ).unwrap()
  @local_driver.configure_local_retained_inputs(
    installed,
    {
      max_rows: 100,
      values: execution.rows.input_values,
      wire: {
        ..retained_attempt_wire_limits(),
        max_bytes: 2000,
        max_nodes: 200,
        max_depth: 10,
        max_columns: 12,
      },
      row: {
        max_bytes: 2000,
        max_nodes: 200,
        max_depth: 10,
        max_text_bytes: 2000,
      },
      max_batch_bytes: 2000,
    },
    None,
  ).unwrap()
  let owner = @strategy.graph_task_owner(@strategy.captured_dag_graph(run), 1).unwrap()
  let setup : @local_driver.LocalManagedDispatchConfiguration[Int] = @local_driver.prepare_local_managed_dispatch_with_outputs(
      installed,
      [],
      @execution.process_managed_obligations(owner),
      0L,
    )
    .unwrap()
    .unwrap()
  assert_true(@local_driver.local_managed_dispatch_uses_provider(setup))
  let operations = @local_driver.start_local_managed_dispatch_node(setup).unwrap()
  let mut outcome = ""
  let mut charged = 0L
  let mut advances = 0
  while outcome == "" {
    assert_true(advances < 1000)
    if cancel_after is Some(limit) && advances == limit {
      assert_true((operations.request_cancel)())
      assert_true((operations.advance)(1) is Err(_))
      assert_true((operations.execution_stopped)())
      outcome = "cancelled"
      break
    }
    match (operations.advance)(quantum) {
      Ok(observation) => {
        assert_true(observation.work <= quantum.to_int64())
        charged += observation.work
        advances += 1
        if observation.complete {
          outcome = "complete"
        }
      }
      Err(
        @local_driver.Configuration(@connector.Execution(@execution.InputLimit))
      ) => outcome = "work"
      Err(
        @local_driver.Configuration(
          @connector.Execution(@execution.Rows(_, @execution.RowLimit))
        )
      ) => outcome = "workspace"
      Err(_) => outcome = "other"
    }
  }
  if outcome == "complete" {
    let rows = local_managed_test_rows(operations)
    assert_eq(rows, [
      "{\"k\":null,\"n\":2,\"window_end\":10,\"window_start\":0}", "{\"k\":1,\"n\":1,\"window_end\":20,\"window_start\":10}",
    ])
    let live = Ref(true)
    (operations.prepare_finalization)(1, operations.storage_bytes, fn() {
      live.val
    }).unwrap()
    while !(operations.advance_finalization)(1).unwrap().complete {

    }
    (operations.settle)().unwrap()
    let output = (operations.complete)(1, operations.storage_bytes, fn() {
      live.val
    }).unwrap()
    assert_true(@execution.managed_completed_output_available(output))
    live.val = false
    @strategy.close_captured_task_output(run, 1)
    (operations.close)()
    (operations.cleanup_refresh)() |> ignore
  } else {
    assert_true((operations.output_row)(0) is Err(_))
    assert_false(@strategy.captured_task_completed(run, 1))
    (operations.settle)().unwrap()
    (operations.close)()
    assert_true((operations.cleanup_refresh)())
  }
  @strategy.stop_captured_dag(run)
  for task in 0..<4 {
    @strategy.close_captured_task_output(run, task)
  }
  @strategy.refresh_captured_retention(run)
  let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.held_bytes, 0L)
  @mock.close_mock_query_issuer(issuer)
  (outcome, charged)
}

///|
test "ordinary window group chain admits exact work and one-short limits" {
  // These counts follow the phase transitions, not a successful run's meter.
  // Values (three rows, two columns): names + begin/cells/row-charge + finish.
  // Row-charge pays start + each name + each scalar value + commit, not one
  // synchronous commit. This changes Values from 15 to 30 steps.
  let values = 2 + 3 * (1 + 2 + (1 + 2 + 2 + 1)) + 1
  // Window: six schema fields, three row/two scalar input charges, then
  // begin/membership/four output cells/ten row-charge steps per output row.
  // The window's old one-step commit becomes ten, changing 37 to 64 steps.
  let window = 6 + 3 * (1 + 2) + 3 * (1 + 1 + 4 + (1 + 4 + 4 + 1)) + 1
  // General keyed group: input charge 15; name/profile setup 92; stable merge
  // 57; group ranges 21; two count groups plus terminal transitions 17;
  // two four-cell output rows plus commits 10; output finish 1 = 213.
  // Stable merge uses one 13-step equal three-key comparison and two
  // four-step NULL/number comparisons. Ranges use the same equal comparison
  // and one unequal comparison. Neither adds work for yielding itself.
  let group = 15 + 92 + 57 + 21 + 17 + 10 + 1
  let exact = values + window + group + 2 // Two completed child handoffs.
  assert_eq((values, window, group, exact), (30, 64, 213, 309))
  for quantum in [1, 7, 256] {
    assert_eq(
      run_window_group_chain_budget(exact, 10000, quantum~),
      ("complete", exact.to_int64()),
    )
    assert_eq(
      run_window_group_chain_budget(exact - 1, 10000, quantum~).0,
      "work",
    )
  }
}

///|
test "ordinary window group chain admits exact workspace and one-short limit" {
  assert_eq(run_window_group_chain_budget(100000, 37).0, "complete")
  assert_eq(run_window_group_chain_budget(100000, 36).0, "workspace")
}

///|
test "ordinary window group chain cancels after bounded work and cleans up" {
  // Stop inside the window group, after the values and window steps.
  assert_eq(
    run_window_group_chain_budget(100000, 10000, cancel_after=Some(200)).0,
    "cancelled",
  )
}
