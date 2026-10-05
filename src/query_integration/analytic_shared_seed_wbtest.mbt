///|
fn analytic_shared_seed_document(join : Bool) -> String {
  // Independent machine Program. Both branches consume the same Values task;
  // the binary operation owns two distinct ports before analytic step 6.
  let binary = if join {
    (
      #|{"from":"left","join":{"kind":"inner","with":"right","on":[{"left":"id","right":"id"}],"select":{"id":"left.id","amount":"left.amount","branch":"right.branch"},"max_output_rows":2},"as":"combined"}
    )
  } else {
    (
      #|{"from":"left","append":{"with":"right"},"as":"combined"}
    )
  }
  let before =
    #|{"version":"actql/0.1","id":"analytic-shared-seed","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"amount":{"type":"number","nullable":false}},"rows":[{"id":3,"amount":30},{"id":1,"amount":10}]},"as":"seed"},{"from":"seed","derive":{"branch":{"literal":1}},"as":"left_derived"},{"from":"left_derived","select":["id","amount","branch"],"as":"left"},{"from":"seed","derive":{"branch":{"literal":2}},"as":"right_derived"},{"from":"right_derived","select":["id","amount","branch"],"as":"right"},
  let after =
    #|,{"from":"combined","analytic":{"partition_by":[],"order_by":[{"id":"asc"},{"branch":"asc"}],"frame":{"start":"unbounded_preceding","end":"current_row"},"functions":{"first":{"fn":"first_value","expr":"amount"},"n":{"fn":"count","field":"amount"},"previous":{"fn":"lag","expr":"amount"}}},"as":"windowed"},{"from":"windowed","select":["id","amount","branch","previous","first","n"],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id","amount","branch","previous","first","n"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
  before + binary + after
}

///|
fn analytic_shared_seed_environment(
  numeric? : Bool = false,
) -> @program_check.CheckEnvironment {
  @program_check.checking_environment(
    @environment.member_environment(
      @environment.source_request_member(
        @environment.source_request_at(
          query_program_catalog_fixture(analytic=true),
          0,
        ).unwrap(),
      ),
    ),
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    numeric_profile=if numeric {
      Some(@numeric.builtin_profile())
    } else {
      None
    },
  )
}

///|
fn analytic_shared_seed_limits() -> @publication_host.ClientProgramPreparationLimits {
  let (_, _, limits) = local_effect_export_fixture()
  { ..limits.program, max_tasks: 8, }
}

///|
fn analytic_shared_seed_prepared(
  join : Bool,
) -> @publication_host.PreparedClientProgram {
  @publication_host.prepare_effect_free_client_program(
    analytic_shared_seed_document(join),
    Json,
    analytic_shared_seed_environment(),
    None,
    analytic_shared_seed_limits(),
  ).unwrap()
}

///|
fn check_analytic_shared_seed_graph(join : Bool) -> Unit raise {
  let prepared = analytic_shared_seed_prepared(join)
  let graph = @publication_host.prepared_client_graph(prepared)
  assert_eq(@strategy.graph_task_count(graph), 8)
  assert_eq(@strategy.graph_data_count(graph), 8)
  assert_eq(@strategy.graph_captured_prefix(graph), 0)
  let owner = @strategy.graph_task_owner(graph, 0).unwrap()
  for task, inputs in [0, 1, 1, 1, 1, 2, 1, 1] {
    assert_eq(
      @strategy.graph_task_target(graph, task),
      Some(@pipeline.Step(task)),
    )
    assert_eq(@strategy.graph_task_selected_step(graph, task), Some(task))
    assert_eq(@strategy.graph_task_prefix_end(graph, task), None)
    assert_eq(@strategy.graph_task_unit_index(graph, task), Some(0))
    assert_eq(@strategy.graph_task_input_count(graph, task), Some(inputs))
    assert_true(
      physical_equal(owner, @strategy.graph_task_owner(graph, task).unwrap()),
    )
  }
  let expected_edges = [
    (0, 1, 0),
    (1, 2, 0),
    (0, 3, 0),
    (3, 4, 0),
    (2, 5, 0),
    (4, 5, 1),
    (5, 6, 0),
    (6, 7, 0),
  ]
  for index, expected in expected_edges {
    let edge = @strategy.graph_data_at(graph, index).unwrap()
    assert_eq((edge.producer, edge.consumer, edge.input), expected)
    assert_eq(edge.target, @pipeline.Step(expected.0))
    assert_eq(
      @strategy.data_edge_operation_input(edge),
      Some((expected.1, expected.2)),
    )
  }
  assert_true(
    @lower.payload(@lower.node_at(@lower.bound_preparation(owner), 6).unwrap())
    is @lower.Analytic(_),
  )
  assert_eq(@strategy.graph_result_count(graph), 1)
  assert_eq(@strategy.graph_result_name(graph, 0), Some("answer"))
  assert_eq(@strategy.graph_result_task(graph, 0), Some(7))
  let occurrence = @strategy.graph_result_occurrence(graph, 0).unwrap()
  assert_true(
    physical_equal(
      owner,
      @execution.managed_result_occurrence_owner(occurrence),
    ),
  )
  assert_eq(
    @relation_results.port_target(
      @execution.managed_result_occurrence_port(occurrence),
    ),
    @pipeline.Step(7),
  )
  assert_eq(
    @strategy.graph_program_definition_cid(graph),
    @publication_host.prepared_client_identity(prepared).program_definition_cid,
  )
  assert_true(
    @publication_host.prepare_effect_free_client_program(
      analytic_shared_seed_document(join),
      Json,
      analytic_shared_seed_environment(),
      None,
      { ..analytic_shared_seed_limits(), max_tasks: 7, },
    )
    is Err(Graph(TaskLimit)),
  )
  let manifests = @publication_host.admit_client_compilation_manifests(
    @environment.compiler_grammar_manifest_wire(),
    @environment.compiler_barrier_contract_manifest_wire(),
    10000,
    1000,
    20,
  ).unwrap()
  let compilation = @publication_host.issue_prepared_client_task_compilation(
    prepared,
    manifests,
    @publication_host.client_standard_values_sequence_limits(),
    1000,
    1000,
    1000000,
    100000,
    100,
  ).unwrap()
  assert_eq(
    @publication_host.client_task_compilation_result_names(compilation),
    ["answer"],
  )
  let policy = "sha256:" + "1".repeat(64)
  let compiled = @publication_host.issue_client_task_compiled_run(
    prepared, compilation, policy, policy, "2027-01-01T00:00:00.000Z",
  ).unwrap()
  assert_true(@publication_host.client_compiled_run_matches(compiled, prepared))
}

///|
test "analytic shared Values append owns exact selected tasks and publication" {
  check_analytic_shared_seed_graph(false)
}

///|
test "analytic shared Values JOIN owns exact selected tasks and publication" {
  check_analytic_shared_seed_graph(true)
}

///|
fn run_analytic_shared_seed(
  join : Bool,
  expected : Array[String],
  cancel? : Bool = false,
) -> Unit raise {
  let prepared = analytic_shared_seed_prepared(join)
  let setup = @client_local_host.open_source_free_local_retained_host(
    prepared,
    @identity.stringify_value(registered_body(), 100000, 10000, 100),
    @identity.stringify_value(registered_values(), 100000, 10000, 100),
    1L,
    0L,
    0L,
    0L,
    fragment_body=Some(
      @identity.stringify_value(registered_fragment(), 100000, 10000, 100),
    ),
  ).unwrap()
  let run = @host_driver.dispatch_driver_run(
    @builtin.configured_host_driver(setup),
  )
  let installed = @builtin.configured_local_module(
    @builtin.configured_host_modules(setup),
  ).unwrap()
  let ledger = @strategy.captured_dag_ledger(run)
  assert_eq(@strategy.graph_task_count(@strategy.captured_dag_graph(run)), 8)
  assert_eq(@resources.ledger_limits(ledger).execution_bytes, 536870912L)
  assert_true(@strategy.captured_dag_strategy(run) is Some(_))
  // The selected analytic task owns the unchanged declared policy envelope.
  for task in 0..<8 {
    assert_eq(
      @strategy.captured_task_analytic_envelope_count(run, task),
      Some(if task == 6 { 1 } else { 0 }),
    )
  }
  let envelope = @strategy.captured_task_analytic_envelope_at(run, 6, 0).unwrap()
  assert_eq(@connector.analytic_envelope_step(envelope), 6)
  assert_eq(@connector.analytic_envelope_input_wire_bytes(envelope), 10000L)
  assert_eq(@connector.analytic_envelope_output_wire_bytes(envelope), 10000L)
  assert_eq(@connector.analytic_envelope_partition_wire_bytes(envelope), 10000L)
  assert_eq(@connector.analytic_envelope_frame_memberships(envelope), 10000L)
  let sources = [[], [0], [1], [0], [3], [2, 4], [5], [6]]
  let operations : Array[@local_driver.LocalManagedDispatchOperations[Int]] = []
  let outputs : Array[@execution.ManagedCompletedOutput[Int]] = []
  let rows : Array[Array[String]] = []
  let lives : Array[Ref[Bool]] = []
  for task, inputs in sources {
    assert_eq(@local_driver.local_dispatch_rejection(installed, task), None)
    if cancel && task == 6 {
      let operation = start_local_managed_test_task_operations(
        installed,
        run,
        task,
        [outputs[5]],
        [rows[5]],
        require_provider=true,
      )
      for _ in 0..<3 {
        let next = (operation.advance)(1).unwrap()
        assert_false(next.complete)
        assert_eq(next.work, 1L)
      }
      assert_true((operation.request_cancel)())
      assert_true((operation.advance)(1) is Err(Execution(Stopped)))
      assert_true((operation.execution_stopped)())
      assert_true((operation.output_row)(0) is Err(_))
      assert_true(
        (operation.complete)(task, operation.storage_bytes, fn() { true })
        is Err(_),
      )
      (operation.settle)().unwrap()
      assert_true((operation.cleanup_refresh)())
      assert_false(@strategy.captured_task_completed(run, 6))
      assert_false(@strategy.captured_task_completed(run, 7))
      assert_true(@execution.managed_completed_output_available(outputs[0]))
      assert_true(@execution.managed_completed_output_available(outputs[5]))
      break
    }
    let live = Ref(true)
    let advances = Ref(0)
    let (operation, output) = run_local_managed_test_task(
      installed,
      run,
      task,
      inputs.map(index => outputs[index]),
      inputs.map(index => rows[index]),
      task,
      live,
      execution_quantum=1,
      execution_advances=Some(advances),
      require_provider=true,
    )
    assert_true(@strategy.captured_task_completed(run, task))
    if task == 6 {
      assert_true(advances.val > 4)
    }
    operations.push(operation)
    outputs.push(output)
    rows.push(local_managed_test_rows(operation))
    lives.push(live)
    if task == 3 {
      assert_true(@execution.managed_completed_output_available(outputs[0]))
      assert_eq(rows[0], [
        "{\"amount\":30,\"id\":3}", "{\"amount\":10,\"id\":1}",
      ])
    }
  }
  if !cancel {
    assert_eq(rows[7], expected)
    assert_eq(@strategy.next_captured_task(run), None)
    assert_eq(@resources.ledger_usage(ledger).attempts, 8)
  }
  for offset in 0..<outputs.length() {
    let task = outputs.length() - 1 - offset
    lives[task].val = false
    @strategy.close_captured_task_output(run, task)
    (operations[task].close)()
    assert_true((operations[task].cleanup_refresh)())
    assert_false(@execution.managed_completed_output_available(outputs[task]))
  }
  @strategy.stop_captured_dag(run)
  for task in 0..<8 {
    @strategy.close_captured_task_output(run, task)
  }
  @strategy.refresh_captured_retention(run)
  let usage = @resources.ledger_usage(ledger)
  assert_eq(usage.held_bytes, 0L)
  assert_eq(usage.reserved_transfer_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.reserved_execution_bytes, 0L)
}

///|
test "analytic shared Values append executes LAG FIRST_VALUE and frame count" {
  // Analytic position is (id, branch); publication retains append source order.
  run_analytic_shared_seed(false, [
    "{\"id\":3,\"amount\":30,\"branch\":1,\"previous\":10,\"first\":10,\"n\":3}",
    "{\"id\":1,\"amount\":10,\"branch\":1,\"previous\":null,\"first\":10,\"n\":1}",
    "{\"id\":3,\"amount\":30,\"branch\":2,\"previous\":30,\"first\":10,\"n\":4}",
    "{\"id\":1,\"amount\":10,\"branch\":2,\"previous\":10,\"first\":10,\"n\":2}",
  ])
}

///|
test "analytic shared Values JOIN executes LAG FIRST_VALUE and frame count" {
  run_analytic_shared_seed(true, [
    "{\"id\":3,\"amount\":30,\"branch\":2,\"previous\":10,\"first\":10,\"n\":2}",
    "{\"id\":1,\"amount\":10,\"branch\":2,\"previous\":null,\"first\":10,\"n\":1}",
  ])
}

///|
test "analytic shared Values cancellation releases the selected analytic attempt" {
  run_analytic_shared_seed(false, [], cancel=true)
}

///|
test "analytic shared Values retains the numeric profile admission owner" {
  let document = analytic_shared_seed_document(false).replace(
    old="\"fn\":\"count\"",
    new="\"fn\":\"sum\"",
  )
  guard @publication_host.prepare_effect_free_client_program(
      document,
      Json,
      analytic_shared_seed_environment(),
      None,
      analytic_shared_seed_limits(),
    )
    is Err(NeedsInputs(requests)) else {
    fail("binary64 analytic sum must retain its numeric profile request")
  }
  assert_eq(@program_check.input_request_count(requests), 1)
  assert_true(
    @program_check.input_request_at(requests, 0).unwrap().kind
    is @program_check.NumericReductionProfile(_),
  )
  let prepared = @publication_host.prepare_effect_free_client_program(
    document,
    Json,
    analytic_shared_seed_environment(numeric=true),
    None,
    analytic_shared_seed_limits(),
  ).unwrap()
  let graph = @publication_host.prepared_client_graph(prepared)
  assert_eq(@strategy.graph_task_count(graph), 8)
  let sequence = prepared_sequence(
    @strategy.graph_task_owner(graph, 6).unwrap(),
  )
  guard @lower.sequence_step(sequence, 6) is Some(@lower.RowStep(kernel)) else {
    fail("the selected analytic occurrence must remain a row kernel")
  }
  let analytic = @lower.kernel_analytic(kernel).unwrap()
  assert_false(@execution.analytic_execution_supported(analytic))
  assert_true(@execution.analytic_execution_supported_with_numeric(analytic))
}

///|
test "analytic shared Values does not admit structured ordering" {
  // Structured ordering is rejected by the existing checker before providers.
  let document = analytic_shared_seed_document(false)
    .replace(
      old="\"branch\":{\"literal\":1}",
      new="\"branch\":{\"literal\":[1]}",
    )
    .replace(
      old="\"branch\":{\"literal\":2}",
      new="\"branch\":{\"literal\":[2]}",
    )
  assert_true(
    @publication_host.prepare_effect_free_client_program(
      document,
      Json,
      analytic_shared_seed_environment(),
      None,
      analytic_shared_seed_limits(),
    )
    is Err(Check(_)),
  )
}
