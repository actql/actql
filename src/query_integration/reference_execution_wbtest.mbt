///|
suberror NumericTestFailure {
  Failure(@reference_compute.PlanIssue)
}

///|
test "independent numeric bundle executes through common reservation and retained completion" {
  for mode in [0, 1, 2] {
    let cancel = mode != 0
    let (run, _) = captured_graph_fixture()
    let input = @strategy.captured_task_input(run, 1, 100, 10000).unwrap()
    let owner = @execution.producer_read_receiver(input)
    let request = @connector.prepare_fixed_compute_request([input], {
      contract_cid: "sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f",
      max_rows: 100,
      max_value_bytes: 10000,
      common_fragment: None,
    }).unwrap()
    let installed = @connector.install_bundles(
      [@reference_compute.numeric_bundle("reference")],
      1,
      100,
    ).unwrap()
    let registry = @connector.installed_bundle_registry(installed)
    let registration = @connector.capability_registration_at(registry, 0).unwrap()
    let implementation = @connector.capability_implementation(
      @connector.installed_compute_implementations(installed),
      registration,
    ).unwrap()
    let candidate = @reference_compute.propose_numeric_compute(
      implementation,
      request,
      100,
      10000,
      native_compile_limits().expressions,
      1,
      [{ work_slots: [0], milliseconds: Some(1L), }],
      { transfer_bytes: Some(0L), retained_bytes: None, money_units: None, },
    ).unwrap()
    guard @connector.choose_fixed_compute_candidate(
        registry,
        request,
        [@connector.prepared_compute_candidate(candidate)],
        None,
        100,
      ).unwrap()
      is Proposed(choice) else {
      abort("expected numeric choice")
    }
    let generated = query_generated(owner, retained=[
      @lower.node_id(
        @lower.node_at(@lower.bound_preparation(owner), 1).unwrap(),
      ),
    ])
    let physical : @execution.FixedInputGuardMeasureLimits = {
      max_work: 100,
      max_bytes: 100,
      max_nodes: 100,
      max_depth: 10,
    }
    let prepared : @connector.PreparedExecution[
      @reference_compute.NumericAttempt,
      @strategy.RunIssue,
      @strategy.TaskPublication,
    ] = @reference_compute.prepare_numeric_execution(
      choice,
      candidate,
      generated,
      {
        max_work: 100,
        max_entries: 100,
        max_name_bytes: 10000,
        values: {
          max_nodes: 100,
          max_text_bytes: 100,
          max_depth: 10,
          max_work: 100,
        },
        physical,
        roots: physical,
      },
      issue => {
        @strategy.RunIssue::Implementation(NumericTestFailure::Failure(issue))
      },
    ).unwrap()
    let ledger = @strategy.captured_dag_ledger(run)
    let saturation = @resources.reserve_attempt(
      ledger, 300000L, 32000000L, 134217728L,
    ).unwrap()
    assert_true(
      @strategy.start_captured_execution(run, 1, prepared) is Err(Physical(_)),
    )
    assert_true(@connector.prepared_execution_available(prepared))
    @resources.settle_reservation(ledger, saturation).unwrap()
    let (attempt, task) = @strategy.start_captured_execution(run, 1, prepared).unwrap()
    assert_true(@strategy.captured_task_output(run, 1, Step(1)) is None)
    if mode == 2 {
      // Settlement cannot free scratch and then permit fresh kernel work.
      @strategy.settle_task_execution(run, task, true).unwrap()
      assert_true(
        @reference_compute.execute_numeric_attempt(attempt) is Err(Unsupported),
      )
      @strategy.close_task_execution(run, task)
      assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
      assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
      continue
    }
    if cancel {
      @strategy.close_task_execution(run, task)
      assert_true(
        @reference_compute.execute_numeric_attempt(attempt) is Err(Unsupported),
      )
      assert_true(@resources.ledger_usage(ledger).reserved_execution_bytes > 0L)
    } else {
      @reference_compute.execute_numeric_attempt(attempt).unwrap()
      assert_true(@strategy.captured_task_output(run, 1, Step(1)) is None)
      assert_true(
        @strategy.complete_task_execution(run, task) is Err(Physical(_)),
      )
    }
    @strategy.settle_task_execution(run, task, true).unwrap()
    if !cancel {
      @strategy.complete_task_execution(run, task).unwrap()
      let output = @strategy.captured_task_output(run, 1, Step(1)).unwrap()
      assert_eq(@execution.completed_row_count(output), 1)
      assert_true(@execution.completed_cell(output, 0, 0) is Some(Number(3.0)))
      assert_true(@resources.ledger_usage(ledger).held_bytes > 0L)
      captured_graph_local(run, 2).unwrap()
      captured_graph_local(run, 3).unwrap()
      let downstream = @strategy.captured_task_output(run, 3, Step(1)).unwrap()
      assert_eq(@execution.completed_row_count(downstream), 1)
      assert_true(
        @execution.completed_cell(downstream, 0, 0) is Some(Number(3.0)),
      )
      @strategy.close_task_execution(run, task)
      assert_eq(@execution.completed_row_count(downstream), 1)
    }
    assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
    assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
    assert_eq(@resources.ledger_usage(ledger).transferred_bytes, 0L)
  }
}
