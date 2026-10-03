///|
test "captured Relation branches retain one acquisition and exact input ports" {
  // Independent machine Program: the narrowed branch cannot replace the full
  // captured input used by the other branch. No Frontend helper is involved.
  let document =
    #|{"version":"actql/0.1","id":"captured-branch","stages":[{"id":"capture","inputs":{"records":{"connector":"crm/main","resource":"r"}},"steps":[{"from":"records","filter":{"literal":true}},{"select":["id"],"as":"captured"}],"results":{"source":{"from":"captured","fields":["id"]}}},{"id":"main","inputs":{"records":{"result":{"stage":"capture","result":"source"}}},"steps":[{"from":"records","filter":{"gt":[{"field":"id"},{"literal":1}]}},{"select":["id"],"as":"selected"},{"from":"records","select":["id"],"as":"complete"},{"from":"complete","sort":[{"id":"asc"}],"as":"ordered"}],"results":{"rows":{"from":"ordered","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
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
  let checked = match
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
      [],
      { input: input_limits, compilation: query_checked_limits(10), },
    ) {
    Checked(value) => value
    NeedsInputs(_) => fail("the admitted source has its checked schema")
    Rejected(diagnostic) => raise @program_check.diagnostic_cause(diagnostic)
  }
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
  assert_eq(@strategy.captured_task_join_output_at(run, 3, 0), Some((1, 10000L)))
  assert_eq(@strategy.captured_task_join_output_at(run, 3, 1), Some((2, 10000L)))
  @strategy.stop_captured_dag(run)
  for task in 0..<5 {
    @strategy.close_captured_task_output(run, task)
  }
  @mock.close_mock_query_issuer(issuer)
}
