///|
test "owned task projection excludes imported join visits and keeps original claims" {
  let program = query_checked_program_fixture(dag=true, dag_join=true)
  let owners = physical_graph_owners(program)
  let graph = @strategy.prepare_checked_dag(program, owners, 5, 10000).unwrap()
  let closure = @context.stage_requirement_operations(
    @program_check.requirements(program),
  )
  let mut joins = 0
  let mut imported = 0
  for index in 0..<@context.operation_closure_count(closure) {
    if @context.operation_closure_at(closure, index)
      is Some(ExecutionCheck(JoinOutputLimit(check))) {
      if check.site.stage == 4 {
        imported += 1
      }
    }
  }
  assert_eq(imported, 1)
  for task in 0..<5 {
    for index in 0..<@strategy.graph_task_operation_count(graph, task).unwrap() {
      let entry = @strategy.graph_task_operation_at(graph, task, index).unwrap()
      assert_eq(entry.site.stage, task)
      assert_true(
        physical_equal(
          entry.site.pipeline,
          @program_check.unit_pipeline(program, task).unwrap(),
        ),
      )
      assert_eq(
        @context.program_identity_producer_is_local(
          @program_check.source_identity(program),
          task,
          entry.site.producer_visit,
        ),
        Some(true),
      )
      if entry.disposition is ExecutionCheck(JoinOutputLimit(check)) {
        joins += 1
        assert_eq((task, check.site.step), (3, 0))
        assert_true(physical_equal(entry.site, check.site))
        let mut exact = false
        for i in 0..<@context.operation_closure_count(closure) {
          if @context.operation_closure_at(closure, i)
            is Some(ExecutionCheck(JoinOutputLimit(original))) &&
            physical_equal(original.site, check.site) {
            exact = physical_equal(original.limit, check.limit)
          }
        }
        assert_true(exact)
      }
    }
    assert_true(@strategy.graph_task_operation_at(graph, task, -1) is None)
    assert_true(@strategy.graph_task_operation_at(graph, task, 10000) is None)
  }
  assert_eq(joins, 1)
  assert_eq(@strategy.graph_task_operation_count(graph, -1), None)
  assert_eq(@strategy.graph_task_operation_count(graph, 5), None)
}

///|
test "generic captured DAG executes Local sort take and its downstream consumer" {
  let (run, issuer) = captured_graph_fixture(
    sort_take=true,
    retention={
      received_wire_bytes: 10000,
      retained_wire_bytes: 10000,
      measurement: {
        max_columns: 10,
        max_order_work: 1000,
        max_bytes: 10000,
        max_nodes: 1000,
        max_depth: 10,
      },
    },
    rows=Some(["{\"id\":2}", "{\"id\":4}", "{\"id\":3}", "{\"id\":4}"]),
  )
  assert_eq(@strategy.next_captured_task(run), Some(1))
  captured_graph_local(run, 1).unwrap()
  let output = @strategy.captured_task_output(run, 1, Step(1)).unwrap()
  assert_eq(@execution.completed_row_count(output), 2)
  assert_true(@execution.completed_cell(output, 0, 0) is Some(Number(4)))
  assert_true(@execution.completed_cell(output, 1, 0) is Some(Number(4)))
  captured_graph_local(run, 2).unwrap()
  @mock.close_mock_query_issuer(issuer)
  captured_graph_local(run, 3).unwrap()
  let downstream = @strategy.captured_task_output(run, 3, Step(1)).unwrap()
  assert_eq(@execution.completed_row_count(downstream), 2)
  assert_true(@execution.completed_cell(downstream, 0, 0) is Some(Number(4)))
  assert_true(@execution.completed_cell(downstream, 1, 0) is Some(Number(4)))
  @strategy.stop_captured_dag(run)
  for task in 0..<4 {
    @strategy.close_captured_task_output(run, task)
  }
}

///|
test "later and multiple join obligations keep their step and producer ownership" {
  for steps in [[1], [1, 2]] {
    let (run, issuer) = captured_graph_fixture(join=true, join_steps=steps)
    let graph = @strategy.captured_dag_graph(run)
    assert_eq(
      @strategy.captured_task_join_output_count(run, 3),
      Some(steps.length()),
    )
    assert_eq(@strategy.captured_task_join_output_count(run, 4), Some(0))
    assert_eq(@strategy.captured_task_join_output_limit(run, 3, 0), None)
    for index, step in steps {
      assert_eq(
        @strategy.captured_task_join_output_at(run, 3, index),
        Some((step, 10000L)),
      )
      assert_eq(
        @strategy.captured_task_join_output_limit(run, 3, step),
        Some(10000L),
      )
    }
    let registry = search_registry()
    let driver = @host_driver.open_dispatch_driver(run)
    let installed = @local_driver.prepare_local_dispatch_module(
      driver,
      registry,
      @connector.capability_registration_at(registry, 0).unwrap(),
      dispatch_test_generated(run),
      compute_test_limits(),
      { max_work: 10000, max_bytes: 10000, max_nodes: 10000, max_depth: 100, },
      10000,
    ).unwrap()
    if steps.length() == 2 {
      assert_eq(
        @local_driver.local_dispatch_rejection(installed, 3),
        Some("multiple_join_ceilings_unsupported"),
      )
      assert_true(
        @local_driver.estimate_local_dispatch_offer(installed, 3, [], 1000)
        is Err(Configuration(ComputeUnsupported)),
      )
    } else {
      assert_eq(@local_driver.local_dispatch_rejection(installed, 3), None)
      for task in [1, 2, 3, 4] {
        captured_graph_local(run, task).unwrap()
      }
      let output = @strategy.captured_task_output(run, 4, Step(0)).unwrap()
      assert_true(@execution.completed_cell(output, 0, 0) is Some(Number(1)))
    }
    assert_eq(@strategy.graph_task_operation_count(graph, 1000), None)
    @strategy.stop_captured_dag(run)
    for task in 0..<5 {
      @strategy.close_captured_task_output(run, task)
    }
    @mock.close_mock_query_issuer(issuer)
  }
}

///|
test "captured tasks retain selected aggregate output ceilings" {
  let (run, issuer) = captured_graph_fixture(
    local_values_group_chain=true,
    local_values_group_variant="collections",
  )
  assert_eq(@strategy.captured_task_aggregate_output_count(run, 2), Some(2))
  assert_eq(
    @strategy.captured_task_aggregate_output_limit(
      run,
      2,
      1,
      "items",
      @connector.array_items_output_unit(),
    ),
    Some(3L),
  )
  assert_eq(
    @strategy.captured_task_aggregate_output_limit(
      run,
      2,
      1,
      "text",
      @connector.string_bytes_output_unit(),
    ),
    Some(17L),
  )
  assert_eq(
    @strategy.captured_task_aggregate_output_limit(
      run,
      2,
      1,
      "items",
      @connector.string_bytes_output_unit(),
    ),
    None,
  )
  assert_eq(@strategy.captured_task_aggregate_output_count(run, 1), Some(0))
  @strategy.stop_captured_dag(run)
  for task in 0..<5 {
    @strategy.close_captured_task_output(run, task)
  }
  @mock.close_mock_query_issuer(issuer)
}

///|
test "common start checks every selected aggregate output ceiling" {
  let (run, issuer) = captured_graph_fixture(collections=true)
  let input = @strategy.captured_task_input(run, 1, 100, 10000).unwrap()
  let request = @connector.prepare_fixed_compute_request(
    [input],
    dispatch_test_limits().capacity,
  ).unwrap()
  let registry = @connector.prepare_capability_registry(
    [{ name: "aggregate-limit-test", acquisition: false, fixed_compute: true, }],
    1,
    100,
  ).unwrap()
  let prepared = @connector.bind_compute_candidate(
    @connector.capability_registration_at(registry, 0).unwrap(),
    request,
    17,
    1,
    [{ work_slots: [0], milliseconds: Some(1L), }],
    { transfer_bytes: Some(0L), retained_bytes: None, money_units: None, },
    100,
  ).unwrap()
  guard @connector.choose_fixed_compute_candidate(
      registry,
      request,
      [@connector.prepared_compute_candidate(prepared)],
      None,
      100,
    ).unwrap()
    is Proposed(choice) else {
    abort("choice")
  }
  let items = fn(name : String, maximum : Int64) {
    @connector.aggregate_output_ceiling(
      2,
      name,
      @connector.array_items_output_unit(),
      maximum,
    ).unwrap()
  }
  let text = fn(maximum : Int64) {
    @connector.aggregate_output_ceiling(
      2,
      "text",
      @connector.string_bytes_output_unit(),
      maximum,
    ).unwrap()
  }
  let calls = Ref(0)
  let before = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  for
    ceilings in [
      [],
      [items("items", 5L)],
      [items("other", 5L), text(17L)],
      [items("items", 6L), text(17L)],
      [items("items", 5L), text(18L)],
    ] {
    let compute = @connector.bind_synchronous_compute(
      choice,
      prepared,
      { retained_bytes: 0L, execution_bytes: 0L, },
      [],
      _ => {
        calls.val += 1
        Err(MissingOutput)
      },
      aggregate_output_ceilings=ceilings,
    ).unwrap()
    assert_true(
      @strategy.execute_captured_synchronous_task(run, 1, compute)
      is Err(ForeignCandidate),
    )
    assert_eq(
      @resources.ledger_usage(@strategy.captured_dag_ledger(run)),
      before,
    )
  }
  assert_eq(calls.val, 0)
  let valid = @connector.bind_synchronous_compute(
    choice,
    prepared,
    { retained_bytes: 0L, execution_bytes: 0L, },
    [],
    _ => {
      calls.val += 1
      Err(MissingOutput)
    },
    aggregate_output_ceilings=[items("items", 4L), text(16L)],
  ).unwrap()
  assert_true(
    @strategy.execute_captured_synchronous_task(run, 1, valid) is Err(_),
  )
  assert_eq(calls.val, 1)
  assert_false(@strategy.captured_task_completed(run, 1))
  @strategy.stop_captured_dag(run)
  for task in 0..<4 {
    @strategy.close_captured_task_output(run, task)
  }
  @mock.close_mock_query_issuer(issuer)
}

///|
test "common start checks every selected join ceiling before spending an attempt" {
  let (run, issuer) = captured_graph_fixture(join=true, join_steps=[1, 2])
  captured_graph_local(run, 1).unwrap()
  captured_graph_local(run, 2).unwrap()
  let inputs = [0, 1].map(port => {
    @strategy.captured_task_input(run, 3, 100, 10000, input_index=port).unwrap()
  })
  let request = @connector.prepare_fixed_compute_request(
    inputs,
    dispatch_test_limits().capacity,
  ).unwrap()
  let registry = search_registry()
  let entry = @connector.capability_registration_at(registry, 0).unwrap()
  let owner = @strategy.graph_task_owner(@strategy.captured_dag_graph(run), 3).unwrap()
  let prepared = @local_connector.local_fixed_compute_candidate(
    entry,
    request,
    task_test_generated(owner),
    [],
    { transfer_bytes: None, retained_bytes: None, money_units: None, },
    100,
  ).unwrap()
  guard @connector.choose_fixed_compute_candidate(
      registry,
      request,
      [@connector.prepared_compute_candidate(prepared)],
      Some([0]),
      100,
    )
    is Ok(Proposed(choice)) else {
    abort("choice")
  }
  let calls = [0]
  let before = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  for
    ceilings in [[], [(0, 1L)], [(1, 10001L), (2, 2L)], [(1, 1L), (2, 10001L)]] {
    let compute = @connector.bind_synchronous_compute(
      choice,
      prepared,
      { retained_bytes: 0L, execution_bytes: 0L, },
      ceilings,
      _ => {
        calls[0] += 1
        Err(MissingOutput)
      },
    ).unwrap()
    assert_true(
      @strategy.execute_captured_synchronous_task(run, 3, compute)
      is Err(ForeignCandidate),
    )
    assert_eq(
      @resources.ledger_usage(@strategy.captured_dag_ledger(run)),
      before,
    )
  }
  assert_eq(calls[0], 0)
  // Distinct stricter ceilings are valid declarations for the two occurrences;
  // the callback still cannot manufacture an owned completed result.
  let valid = @connector.bind_synchronous_compute(
    choice,
    prepared,
    { retained_bytes: 0L, execution_bytes: 0L, },
    [(1, 1L), (2, 2L)],
    _ => {
      calls[0] += 1
      Err(MissingOutput)
    },
  ).unwrap()
  assert_true(
    @strategy.execute_captured_synchronous_task(run, 3, valid) is Err(_),
  )
  assert_eq(calls[0], 1)
  assert_false(@strategy.captured_task_completed(run, 3))
  @strategy.stop_captured_dag(run)
  for task in 0..<5 {
    @strategy.close_captured_task_output(run, task)
  }
  @mock.close_mock_query_issuer(issuer)
}

///|
test "sort take excludes statically unsupported DuckDB before comparison at any price" {
  for price in [0L, 10000L] {
    let (run, issuer) = captured_graph_fixture(sort_take=true)
    let registry = search_registry()
    let host = adaptive_host(run, registry)
    let excluded = @dbhost.dispatch_excluded_realizations(host, 100).unwrap()
    assert_true(
      excluded.any(item => item.0 == 1 && item.2 == "unsupported_shape"),
    )
    let profiles = adaptive_profiles()
    profiles[0].native_rates[0] = {
      ..profiles[0].native_rates[0],
      fixed_ms: Some(price),
    }
    profiles[2].native_rates[0] = {
      ..profiles[2].native_rates[0],
      fixed_ms: Some(10000L),
    }
    @dbhost.configure_dispatch_estimates(host, profiles, {
      max_offers: 6,
      max_strategies: 8,
      max_work: 1000,
      max_revisions: 3,
    }).unwrap()
    @dbhost.refresh_dispatch_estimates(host).unwrap()
    assert_eq(
      @resources.ledger_usage(@strategy.captured_dag_ledger(run)).attempts,
      0,
    )
    for task in [1, 2, 3] {
      let dispatch = @dbhost.prepare_next_dispatch(host).unwrap().unwrap()
      assert_true(
        physical_equal(
          @dbhost.dispatch_registration(dispatch).unwrap(),
          @connector.capability_registration_at(registry, 0).unwrap(),
        ),
      )
      @dbhost.execute_synchronous_dispatch(dispatch).unwrap()
      assert_true(@strategy.captured_task_completed(run, task))
    }
    let output = @strategy.captured_task_output(run, 3, Step(1)).unwrap()
    assert_eq(@execution.completed_row_count(output), 2)
    assert_true(@execution.completed_cell(output, 0, 0) is Some(Number(3)))
    assert_true(@execution.completed_cell(output, 1, 0) is Some(Number(2)))
    @strategy.stop_captured_dag(run)
    for task in 0..<4 {
      @strategy.close_captured_task_output(run, task)
    }
    @mock.close_mock_query_issuer(issuer)
  }
}

///|
test "sort take failure stops later control gates without publishing a partial result" {
  let (run, issuer) = captured_graph_fixture(sort_take=true)
  let ordinary = compute_test_limits()
  assert_true(
    captured_graph_local(run, 1, limits={
      ..ordinary,
      rows: { ..ordinary.rows, max_rows: 1, },
    })
    is Err(_),
  )
  assert_false(@strategy.captured_task_completed(run, 1))
  assert_false(@strategy.captured_task_completed(run, 2))
  assert_true(@strategy.captured_task_output(run, 1, Step(1)) is None)
  assert_eq(@strategy.next_captured_task(run), None)
  @strategy.stop_captured_dag(run)
  for task in 0..<4 {
    @strategy.close_captured_task_output(run, task)
  }
  @mock.close_mock_query_issuer(issuer)
}
