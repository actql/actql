///|
/// Independent Program from issue #1350. Do not insert a projection step to
/// work around the shared input-only Stage emission boundary.
let input_result_document : String =
  #|{"version":"actql/0.1","id":"fixture.identity_stage_result","stages":[{"id":"producer","inputs":{},"steps":[{"values":{"schema":{"A":{"type":"number","nullable":false}},"rows":[{"A":0}]},"as":"out"}],"results":{"rows":{"from":"out","fields":["A"]}}},{"id":"main","inputs":{"source":{"result":{"stage":"producer","result":"rows"}}},"steps":[],"results":{"rows":{"from":"source","fields":["A"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}

///|
fn input_result_prepared(document : String) -> PreparedClientProgram {
  let environment = admit_client_check_environment(
    run_materials_environment_wire,
    run_materials_environment_cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  prepare_effect_free_client_program(
    document,
    Json,
    environment,
    None,
    run_materials_limits().preparation,
  ).unwrap()
}

///|
test "input-only Stage Result compiles the unchanged independent Program" {
  let prepared = input_result_prepared(input_result_document)
  let limits = run_materials_limits()
  let compilation = issue_prepared_client_task_compilation(
    prepared,
    run_materials_manifests(),
    limits.sequence,
    1000,
    1000,
    1000000,
    100000,
    100,
  )
  match compilation {
    Ok(value) =>
      assert_eq(client_task_compilation_result_names(value), ["answer"])
    Err(Plan(TaskGraph(Fragment(Pipeline(MissingOutput))))) =>
      fail("issue #1350: checked input-only task has no emitted output")
    Err(_) => fail("input-only Stage Result compilation rejected")
  }
  let graph = prepared_client_graph(prepared)
  assert_eq(@strategy.graph_task_target(graph, 1), Some(@pipeline.Input(0)))
  let contracts = @execution.admit_relation_registry(
    parse_plan_identity_value(
      compiler_registered_body_wire(),
      1000000,
      100000,
      100,
    ).unwrap(),
    parse_plan_identity_value(
      compiler_registered_values_wire(),
      1000000,
      100000,
      100,
    ).unwrap(),
    { max_body_bytes: 1000000, max_body_nodes: 100000, max_body_depth: 100, },
  ).unwrap()
  let sequence = prepare_client_task_sequence(
    prepared,
    1,
    contracts,
    [],
    limits.sequence,
    10000,
    10000,
  ).unwrap()
  assert_eq(@execution.generated_sequence_step_count(sequence), 0)
  assert_eq(
    emit_prepared_client_task_pipeline(
      prepared,
      1,
      limits.sequence,
      1000000,
      100000,
      100,
    ).unwrap(),
    "{\"output\":\"source\",\"sources\":{\"source\":{\"sort\":\"relation\"}},\"steps\":[],\"version\":\"aoa-pipeline/0.1\"}",
  )
}

///|
test "input-only Stage Result opens the checked source-free Run" {
  let prepared = input_result_prepared(input_result_document)
  let opened = open_prepared_source_free_client_run(prepared, {
    planning_work: 10000,
    attempts: 2,
    holdings: 2,
    transfer_bytes: 1000000L,
    retained_bytes: 1000000L,
    execution_bytes: 1000000L,
  })
  match opened {
    Ok(run) => {
      assert_eq(@strategy.next_captured_task(run), Some(0))
      assert_eq(
        @strategy.captured_task_target(run, 1),
        Some(@pipeline.Input(0)),
      )
      @strategy.stop_captured_dag(run)
      @strategy.refresh_captured_retention(run)
    }
    Err(Run(UnsupportedGraph)) =>
      fail("issue #1350: physical Run opening rejects an input-only task")
    Err(_) => fail("input-only Stage Result Run opening rejected")
  }
}

///|
test "input-only Stage Result inherits producer occurrence order" {
  let prepared = input_result_prepared(
    input_result_document.replace(
      old="[{\"A\":0}]",
      new="[{\"A\":2},{\"A\":0},{\"A\":2}]",
    ),
  )
  let occurrence = @strategy.graph_result_occurrence(
    prepared_client_graph(prepared),
    0,
  ).unwrap()
  let port = @execution.managed_result_occurrence_port(occurrence)
  assert_eq(@results.port_target(port), @pipeline.Input(0))
  assert_eq(
    @results.publication_strategy(@results.port_order(port)),
    @results.Inherited,
  )
  assert_eq(@results.port_order_term_count(port), 0)
}
