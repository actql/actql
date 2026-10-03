///|
test "captured Relation branches retain one acquisition and exact input ports" {
  // Independent machine Program: the narrowed branch cannot replace the full
  // captured input used by the other branch. No Frontend helper is involved.
  let document =
    #|{"version":"actql/0.1","id":"captured-branch","stages":[{"id":"capture","inputs":{"records":{"connector":"crm/main","resource":"r"}},"steps":[{"from":"records","filter":{"literal":true}},{"select":["id"],"as":"captured"}],"results":{"source":{"from":"captured","fields":["id"]}}},{"id":"main","inputs":{"records":{"result":{"stage":"capture","result":"source"}}},"steps":[{"from":"records","filter":{"gt":[{"field":"id"},{"literal":1}]}},{"select":["id"],"as":"selected"},{"from":"records","select":["id"],"as":"complete"},{"from":"complete","sort":[{"id":"asc"}],"as":"ordered"}],"results":{"rows":{"from":"ordered","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
  let checked = acquired_relation_branch_checked(document)
  let owners = physical_graph_owners(checked)
  let graph = @strategy.prepare_checked_dag(checked, owners, 10, 100000).unwrap()
  assert_eq(@strategy.graph_captured_prefix(graph), 1)
  assert_eq(@strategy.graph_task_count(graph), 5)
  for task in 1..<5 {
    assert_eq(@strategy.graph_task_selected_step(graph, task), Some(task - 1))
    assert_eq(@strategy.graph_task_input_count(graph, task), Some(1))
    assert_true(
      physical_equal(
        @strategy.graph_task_owner(graph, task).unwrap(),
        owners[1],
      ),
    )
  }
  let expected = [(0, 1), (1, 2), (0, 3), (3, 4)]
  assert_eq(@strategy.graph_data_count(graph), expected.length())
  for index, (producer, consumer) in expected {
    let edge = @strategy.graph_data_at(graph, index).unwrap()
    assert_eq(
      (edge.producer, edge.consumer, edge.input),
      (producer, consumer, 0),
    )
  }
  assert_true(@strategy.graph_ordered_inputs_complete(graph))
  assert_true(
    @strategy.prepare_checked_dag(checked, owners, 4, 100000) is Err(TaskLimit),
  )
}

///|
test "retained binary JOIN chain preserves its fused capacity owner" {
  let (run, issuer) = captured_graph_fixture(join=true, join_steps=[1, 2])
  let graph = @strategy.captured_dag_graph(run)
  assert_eq(@strategy.graph_task_count(graph), 5)
  assert_eq(@strategy.graph_task_selected_step(graph, 3), None)
  assert_eq(@strategy.graph_task_input_count(graph, 3), Some(2))
  assert_eq(@strategy.captured_task_join_output_count(run, 3), Some(2))
  assert_eq(
    @strategy.captured_task_join_output_at(run, 3, 0),
    Some((1, 10000L)),
  )
  assert_eq(
    @strategy.captured_task_join_output_at(run, 3, 1),
    Some((2, 10000L)),
  )
  @strategy.stop_captured_dag(run)
  for task in 0..<5 {
    @strategy.close_captured_task_output(run, task)
  }
  @mock.close_mock_query_issuer(issuer)
}

///|
fn acquired_relation_branch_checked(
  document : String,
  join_steps? : Array[Int] = [],
) -> @program_check.CheckedProgram raise {
  let input_limits : @syntax.Limits = {
    source: { max_input_bytes: 1000000, max_nodes: 100000, max_depth: 100, },
    tree: {
      max_nodes: 100000,
      max_depth: 100,
      max_string_bytes: 1000000,
      max_total_string_bytes: 1000000,
    },
    max_stages: 10,
  }
  let environment = @environment.contract_registry_environment(
    @environment.catalog_registry(
      @environment.reference_contents(
        @environment.data_policy_references(
          @environment.value_contract_policies(
            @environment.source_view_shape_values(
              @environment.read_mode_shapes(
                @environment.carrier_schema_modes(
                  @environment.source_request_carriers(
                    query_program_catalog_fixture(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  )
  let program = @syntax.parse(document, input_limits, format=Json).unwrap()
  match
    @program_check.check_parsed_with_evidence(
      program,
      @program_check.checking_environment(
        environment,
        { text_time: false, veca: false, },
        {
          rela: true,
          sga: false,
          tea: false,
          calendar: false,
          text_rank: false,
        },
      ),
      None,
      if join_steps.is_empty() {
        []
      } else {
        [join_graph_capacity_material(environment, "main", steps=join_steps)]
      },
      { input: input_limits, compilation: query_checked_limits(10), },
    ) {
    Checked(value) => value
    NeedsInputs(_) => fail("the admitted source has its checked schema")
    Rejected(diagnostic) => raise @program_check.diagnostic_cause(diagnostic)
  }
}

///|
test "shared captured producer feeds both append ports and cleans up eight rows" {
  // Independent equivalent of the DATA-local CTE/UNION ALL shape. In
  // particular the right branch reads chosen, not the preceding left branch.
  let document = acquired_shared_producer_document()
  let checked = acquired_relation_branch_checked(document)
  let rows = ["{\"id\":3}", "{\"id\":1}", "{\"id\":2}", "{\"id\":3}"]
  let (run, issuer) = captured_graph_fixture(
    checked_program=Some(checked),
    rows=Some(rows),
    ledger_limits=Some({
      planning_work: 10000,
      attempts: 20,
      holdings: 20,
      transfer_bytes: 300000L,
      retained_bytes: 134217728L,
      execution_bytes: 536870912L,
    }),
    // Four records: each scan/output array is 37 UTF-8 bytes and nine
    // structural nodes. Both retained arrays require exactly 74/18.
    retention={
      received_wire_bytes: 37,
      retained_wire_bytes: 74,
      measurement: {
        max_columns: 1,
        max_order_work: 1000,
        max_bytes: 74,
        max_nodes: 18,
        max_depth: 10,
      },
    },
  )
  let graph = @strategy.captured_dag_graph(run)
  assert_eq(@strategy.graph_captured_prefix(graph), 1)
  assert_eq(@strategy.graph_task_count(graph), 6)
  let expected_edges = [
    (0, 1, 0),
    (1, 2, 0),
    (1, 3, 0),
    (2, 4, 0),
    (3, 4, 1),
    (4, 5, 0),
  ]
  assert_eq(@strategy.graph_data_count(graph), expected_edges.length())
  for index, expected in expected_edges {
    let edge = @strategy.graph_data_at(graph, index).unwrap()
    assert_eq((edge.producer, edge.consumer, edge.input), expected)
  }
  let registry = search_registry()
  let limits = dispatch_test_limits()
  let installed = @local_driver.prepare_local_dispatch_module(
    @host_driver.open_dispatch_driver(run),
    registry,
    @connector.capability_registration_at(registry, 0).unwrap(),
    dispatch_test_generated(run),
    limits.local_execution,
    limits.guards,
    limits.candidate_work,
  ).unwrap()
  @local_driver.configure_local_retained_inputs(
    installed,
    {
      max_rows: 100,
      values: limits.local_execution.rows.input_values,
      wire: retained_attempt_wire_limits(),
      row: { max_bytes: 100, max_nodes: 20, max_depth: 4, max_text_bytes: 100, },
      max_batch_bytes: 64,
    },
    None,
  ).unwrap()
  let operations : Array[@local_driver.LocalManagedDispatchOperations[Int]] = []
  let outputs : Array[@execution.ManagedCompletedOutput[Int]] = []
  let lives : Array[Ref[Bool]] = []
  for task in 1..<6 {
    let live = Ref(true)
    let (inputs, input_rows) = match task {
      1 => ([], [])
      2 | 3 => ([outputs[0]], [local_managed_test_rows(operations[0])])
      4 =>
        (
          [outputs[1], outputs[2]],
          [
            local_managed_test_rows(operations[1]),
            local_managed_test_rows(operations[2]),
          ],
        )
      _ => ([outputs[3]], [local_managed_test_rows(operations[3])])
    }
    let ordered_outputs = if task == 1 {
      Some([@local_driver.local_managed_captured_relation_input()])
    } else {
      None
    }
    let (ops, output) = run_local_managed_test_task(
      installed,
      run,
      task,
      inputs,
      input_rows,
      task,
      live,
      ordered_outputs~,
      require_provider=true,
      execution_quantum=1,
    )
    operations.push(ops)
    outputs.push(output)
    lives.push(live)
    assert_true(@execution.managed_completed_output_available(outputs[0]))
  }
  assert_eq(local_managed_test_rows(operations[1]), rows)
  assert_eq(local_managed_test_rows(operations[2]), rows)
  assert_eq(local_managed_test_rows(operations[4]), [
    "{\"id\":1}", "{\"id\":1}", "{\"id\":2}", "{\"id\":2}", "{\"id\":3}", "{\"id\":3}",
    "{\"id\":3}", "{\"id\":3}",
  ])
  for offset in 0..<5 {
    let index = 4 - offset
    lives[index].val = false
    @strategy.close_captured_task_output(run, index + 1)
    (operations[index].close)()
    (operations[index].cleanup_refresh)() |> ignore
  }
  @strategy.stop_captured_dag(run)
  @strategy.close_captured_task_output(run, 0)
  @strategy.refresh_captured_retention(run)
  let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.held_bytes, 0L)
  @mock.close_mock_query_issuer(issuer)
}

///|
fn acquired_shared_producer_document() -> String {
  (
    #|{"version":"actql/0.1","id":"captured-cte-append","stages":[{"id":"capture","inputs":{"records":{"connector":"crm/main","resource":"r"}},"steps":[{"from":"records","filter":{"literal":true}},{"select":["id"],"as":"captured"}],"results":{"source":{"from":"captured","fields":["id"]}}},{"id":"main","inputs":{"records":{"result":{"stage":"capture","result":"source"}}},"steps":[{"from":"records","select":["id"],"as":"chosen"},{"from":"chosen","select":["id"],"as":"left_rows"},{"from":"chosen","select":["id"],"as":"right_rows"},{"from":"left_rows","append":{"with":"right_rows"},"as":"appended"},{"from":"appended","sort":[{"id":"asc"}],"as":"ordered"}],"results":{"rows":{"from":"ordered","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
  )
}

///|
test "split JOIN retains checked step ceiling and both shared producer ports" {
  let document = acquired_shared_producer_document().replace(
    old="\"append\":{\"with\":\"right_rows\"}",
    new="\"join\":{\"with\":\"right_rows\",\"kind\":\"inner\",\"on\":[{\"left\":\"id\",\"right\":\"id\"}],\"select\":{\"id\":\"left.id\"}}",
  )
  let checked = acquired_relation_branch_checked(document, join_steps=[3])
  let (run, issuer) = captured_graph_fixture(checked_program=Some(checked), retention={
    received_wire_bytes: 28,
    retained_wire_bytes: 56,
    measurement: {
      max_columns: 1,
      max_order_work: 1000,
      max_bytes: 56,
      max_nodes: 14,
      max_depth: 10,
    },
  })
  let graph = @strategy.captured_dag_graph(run)
  assert_eq(@strategy.graph_task_count(graph), 6)
  assert_eq(@strategy.graph_task_selected_step(graph, 4), Some(3))
  assert_eq(@strategy.graph_task_input_count(graph, 4), Some(2))
  assert_eq(@strategy.captured_task_join_output_count(run, 4), Some(1))
  assert_eq(
    @strategy.captured_task_join_output_at(run, 4, 0),
    Some((3, 10000L)),
  )
  for (index, producer, port) in [(3, 2, 0), (4, 3, 1)] {
    let edge = @strategy.graph_data_at(graph, index).unwrap()
    assert_eq((edge.producer, edge.consumer, edge.input), (producer, 4, port))
  }
  for task in 1..<4 {
    captured_graph_local(run, task).unwrap()
  }
  let inputs = [0, 1].map(port => {
    @strategy.captured_task_input(run, 4, 100, 10000, input_index=port).unwrap()
  })
  let owner = @strategy.graph_task_owner(graph, 4).unwrap()
  let request = @connector.prepare_selected_fixed_compute_request(
    owner,
    3,
    inputs,
    dispatch_test_limits().capacity,
  ).unwrap()
  let registry = search_registry()
  let generated = @execution.select_generated_sequence_step(
    task_test_generated(owner),
    3,
  ).unwrap()
  let prepared = @local_connector.local_fixed_compute_candidate(
    @connector.capability_registration_at(registry, 0).unwrap(),
    request,
    generated,
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
    fail("selected JOIN candidate")
  }
  let calls = Ref(0)
  let before = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  for ceilings in [[], [(0, 1L)], [(3, 10001L)]] {
    let compute = @connector.bind_synchronous_compute(
      choice,
      prepared,
      { retained_bytes: 0L, execution_bytes: 0L, },
      ceilings,
      _ => {
        calls.val += 1
        Err(MissingOutput)
      },
    ).unwrap()
    assert_true(
      @strategy.execute_captured_synchronous_task(run, 4, compute)
      is Err(ForeignCandidate),
    )
    assert_eq(calls.val, 0)
    assert_eq(
      @resources.ledger_usage(@strategy.captured_dag_ledger(run)),
      before,
    )
  }
  @strategy.stop_captured_dag(run)
  for task in 0..<6 {
    @strategy.close_captured_task_output(run, task)
  }
  @mock.close_mock_query_issuer(issuer)
}

///|
test "binary JOIN of one internal CTE producer selects both occurrence ports" {
  let document = acquired_shared_producer_document().replace(
    old="{\"from\":\"chosen\",\"select\":[\"id\"],\"as\":\"left_rows\"},{\"from\":\"chosen\",\"select\":[\"id\"],\"as\":\"right_rows\"},{\"from\":\"left_rows\",\"append\":{\"with\":\"right_rows\"},\"as\":\"appended\"}",
    new="{\"from\":\"chosen\",\"join\":{\"with\":\"chosen\",\"kind\":\"inner\",\"on\":[{\"left\":\"id\",\"right\":\"id\"}],\"select\":{\"id\":\"left.id\"}},\"as\":\"appended\"}",
  )
  let checked = acquired_relation_branch_checked(document, join_steps=[1])
  let graph = @strategy.prepare_checked_dag(
    checked,
    physical_graph_owners(checked),
    10,
    100000,
  ).unwrap()
  assert_eq(@strategy.graph_task_count(graph), 4)
  assert_eq(@strategy.graph_task_selected_step(graph, 2), Some(1))
  assert_eq(@strategy.graph_task_input_count(graph, 2), Some(2))
  for index in [1, 2] {
    let edge = @strategy.graph_data_at(graph, index).unwrap()
    assert_eq((edge.producer, edge.consumer, edge.input), (1, 2, index - 1))
  }
  let obligation = @strategy.graph_task_operation_at(graph, 2, 0).unwrap()
  assert_eq((obligation.site.stage, obligation.site.step), (1, 1))
}
