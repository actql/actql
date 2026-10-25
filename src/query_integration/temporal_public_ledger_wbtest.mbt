// Original normalized inputs; expected rows remain independently authored.

///|
test "original temporal JSON and SQL retain the installed Host reservation" {
  for
    text in [
      (
        #|{"version":"actql/0.1","id":"temporal-ledger-control","stages":[{"id":"main","inputs":{},"steps":[{"as":"l","values":{"rows":[{"at":10,"id":1},{"at":30,"id":2},{"at":50,"id":3}],"schema":{"at":{"nullable":false,"type":"number"},"id":{"nullable":false,"type":"number"}}}},{"as":"r","values":{"rows":[{"begin":5,"finish":15,"id":7},{"begin":20,"finish":25,"id":8}],"schema":{"begin":{"nullable":false,"type":"number"},"finish":{"nullable":false,"type":"number"},"id":{"nullable":false,"type":"number"}}}},{"as":"matched","from":"l","interval_join":{"kind":"left","left":{"time":"at"},"max_output_rows":3,"mode":"point_in_interval","on":[],"right":{"end":"finish","start":"begin"},"select":{"id":"left.id","value":"right.id"},"with":"r"}},{"from":"matched","sort":[{"dir":"asc","field":"id","nulls":"first"}]},{"as":"out","select":["id","value"]}],"results":{"rows":{"from":"out","fields":["id","value"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
      ),
      (
        #|{"version":"actql/0.1","id":"temporal-ledger-control","stages":[{"id":"main","inputs":{},"steps":[{"as":"aql_script_seed_2","values":{"rows":[{"aql_source_free_unit":true}],"schema":{"aql_source_free_unit":{"nullable":false,"type":"boolean"}}}},{"derive":{"aql_query_expr_0":{"literal":1},"aql_query_expr_1":{"literal":10}},"from":"aql_script_seed_2"},{"as":"aql_data_set_term_1","select":[{"id":"aql_query_expr_0"},{"at":"aql_query_expr_1"}]},{"as":"aql_script_seed_4","values":{"rows":[{"aql_source_free_unit":true}],"schema":{"aql_source_free_unit":{"nullable":false,"type":"boolean"}}}},{"derive":{"aql_query_expr_0":{"literal":2},"aql_query_expr_1":{"literal":30}},"from":"aql_script_seed_4"},{"as":"aql_data_set_term_3","select":[{"id":"aql_query_expr_0"},{"at":"aql_query_expr_1"}]},{"append":{"with":"aql_data_set_term_3"},"as":"aql_data_set_combined_5","from":"aql_data_set_term_1"},{"as":"aql_script_seed_7","values":{"rows":[{"aql_source_free_unit":true}],"schema":{"aql_source_free_unit":{"nullable":false,"type":"boolean"}}}},{"derive":{"aql_query_expr_0":{"literal":3},"aql_query_expr_1":{"literal":50}},"from":"aql_script_seed_7"},{"as":"aql_data_set_term_6","select":[{"id":"aql_query_expr_0"},{"at":"aql_query_expr_1"}]},{"append":{"with":"aql_data_set_term_6"},"as":"aql_script_cte_0","from":"aql_data_set_combined_5"},{"as":"aql_script_seed_11","values":{"rows":[{"aql_source_free_unit":true}],"schema":{"aql_source_free_unit":{"nullable":false,"type":"boolean"}}}},{"derive":{"aql_query_expr_0":{"literal":7},"aql_query_expr_1":{"literal":5},"aql_query_expr_2":{"literal":15}},"from":"aql_script_seed_11"},{"as":"aql_data_set_term_10","select":[{"id":"aql_query_expr_0"},{"begin":"aql_query_expr_1"},{"finish":"aql_query_expr_2"}]},{"as":"aql_script_seed_13","values":{"rows":[{"aql_source_free_unit":true}],"schema":{"aql_source_free_unit":{"nullable":false,"type":"boolean"}}}},{"derive":{"aql_query_expr_0":{"literal":8},"aql_query_expr_1":{"literal":20},"aql_query_expr_2":{"literal":25}},"from":"aql_script_seed_13"},{"as":"aql_data_set_term_12","select":[{"id":"aql_query_expr_0"},{"begin":"aql_query_expr_1"},{"finish":"aql_query_expr_2"}]},{"append":{"with":"aql_data_set_term_12"},"as":"aql_script_cte_9","from":"aql_data_set_term_10"},{"as":"aql_carrier_16","from":"aql_script_cte_0","interval_join":{"kind":"left","left":{"time":"at"},"max_output_rows":3,"mode":"point_in_interval","on":[],"right":{"end":"finish","start":"begin"},"select":{"id":"left.id","value":"right.id"},"with":"aql_script_cte_9"}},{"from":"aql_carrier_16","select":["id","value"]},{"as":"aql_script_result","sort":[{"dir":"asc","field":"id","nulls":"first"}]}],"results":{"rows":{"from":"aql_script_result","fields":["id","value"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
      ),
    ] {
    let (_, original_environment, _) = local_effect_export_fixture()
    let environment = @program_check.checking_environment(
      @program_check.checking_environment_wire(original_environment),
      { text_time: false, veca: false, },
      { rela: true, sga: false, tea: true, calendar: false, text_rank: false, },
    )
    let prepared = @publication_host.prepare_effect_free_client_program(
      text,
      Json,
      environment,
      None,
      @publication_host.client_standard_program_preparation_limits(),
    ).unwrap()
    let generated = @client_local_host.prepare_client_local_sequences(
      prepared,
      registered_installed_sequence_contracts(),
      @identity.stringify_value(registered_values(), 100000, 10000, 100),
      Some(@identity.stringify_value(registered_fragment(), 100000, 10000, 100)),
      Some(@identity.stringify_value(registered_ordered(), 100000, 10000, 100)),
    )
    assert_true(
      generated is Some(_),
      msg="original local sequences must prepare",
    )
    println("TEMPORAL_HOST tasks=" + generated.unwrap().length().to_string())
    let setup = @client_local_host.open_source_free_local_host(
      prepared,
      registered_installed_sequence_contracts(),
      @identity.stringify_value(registered_values(), 100000, 10000, 100),
      1L,
      0L,
      0L,
      0L,
      fragment_body=Some(
        @identity.stringify_value(registered_fragment(), 100000, 10000, 100),
      ),
      ordered_body=Some(
        @identity.stringify_value(registered_ordered(), 100000, 10000, 100),
      ),
      provider_factory=capacity => {
        [
          @local_tea_provider.interval_join_provider(
            {
              max_input_records: 100,
              max_records: 100,
              max_fields_per_record: 100,
              max_value_bytes: 10000,
              max_total_value_bytes: 100000,
              max_retained_value_bytes: 100000,
              max_value_nodes: 10000,
              max_value_depth: 100,
              max_contract_work: 10000,
              max_work: 100000,
              max_workspace_slots: 10000,
            },
            capacity,
          ),
        ]
      },
    )
    assert_true(setup is Some(_), msg="original installed Host must prepare")
    let setup = setup.unwrap()
    let run = @host_driver.dispatch_driver_run(
      @builtin.configured_host_driver(setup),
    )
    let installed = @builtin.configured_local_module(
      @builtin.configured_host_modules(setup),
    ).unwrap()
    let graph = @strategy.captured_dag_graph(run)
    let ledger = @strategy.captured_dag_ledger(run)
    let count = @strategy.graph_task_count(graph)
    assert_eq(@resources.ledger_limits(ledger).execution_bytes, 536870912L)
    let operations : Array[@local_driver.LocalManagedDispatchOperations[Int]] = []
    let outputs : Array[@execution.ManagedCompletedOutput[Int]] = []
    let rows : Array[Array[String]] = []
    let lives : Array[Ref[Bool]] = []
    for task in 0..<count {
      let input_count = @strategy.graph_task_input_count(graph, task).unwrap()
      let sources = Array::make(input_count, -1)
      for index in 0..<@strategy.graph_data_count(graph) {
        let edge = @strategy.graph_data_at(graph, index).unwrap()
        if @strategy.data_edge_consumer(edge) == task {
          sources[@strategy.data_edge_input(edge)] = @strategy.data_edge_producer(
            edge,
          )
        }
      }
      assert_true(sources.all(index => index >= 0 && index < task))
      let live = Ref(true)
      let (operation, output) = run_local_managed_test_task(
        installed,
        run,
        task,
        sources.map(index => outputs[index]),
        sources.map(index => rows[index]),
        task,
        live,
        execution_quantum=1,
        require_provider=true,
      )
      operations.push(operation)
      outputs.push(output)
      rows.push(local_managed_test_rows(operation))
      lives.push(live)
    }
    assert_eq(rows[count - 1], [
      "{\"id\":1,\"value\":7}", "{\"id\":2,\"value\":null}", "{\"id\":3,\"value\":null}",
    ])
    for offset in 0..<count {
      let task = count - 1 - offset
      lives[task].val = false
      @strategy.close_captured_task_output(run, task)
      (operations[task].close)()
      assert_true((operations[task].cleanup_refresh)())
    }
    @strategy.stop_captured_dag(run)
    @strategy.refresh_captured_retention(run)
    let usage = @resources.ledger_usage(ledger)
    assert_eq(usage.held_bytes, 0L)
    assert_eq(usage.reserved_transfer_bytes, 0L)
    assert_eq(usage.reserved_retention_bytes, 0L)
    assert_eq(usage.reserved_execution_bytes, 0L)
  }
}
