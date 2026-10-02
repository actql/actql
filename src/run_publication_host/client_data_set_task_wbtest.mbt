///|
test "independent ordered DATA machine Program owns every bounded Relation step" {
  // Authored independently of the query compiler: two Values roots, append,
  // one evaluated sort slot, ordering, projection and LIMIT. Expected public
  // rows are [{id: 1}]; packed execution separately checks that expectation.
  let document =
    #|{"version":"actql/0.1","id":"independent-data-set","stages":[{"id":"main","inputs":{},"steps":[{"as":"left","values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":2}]}},{"as":"right","values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1}]}},{"from":"left","append":{"with":"right"},"as":"combined"},{"from":"combined","derive":{"sort_slot":{"add":[{"field":"id"},{"literal":1}]}},"as":"derived"},{"from":"derived","sort":[{"field":"sort_slot","dir":"asc","nulls":"first"}],"as":"ordered"},{"from":"ordered","select":["id"],"as":"projected"},{"from":"projected","take":{"count":1,"offset":0},"as":"limited"}],"results":{"rows":{"from":"limited","fields":["id"]}}}],"results":{"nodes":{"from":{"stage":"main","result":"rows"}}}}
  let environment = admit_client_check_environment(
    run_materials_environment_wire,
    run_materials_environment_cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let limits = run_materials_limits()
  let prepared = prepare_effect_free_client_program(
    document,
    Json,
    environment,
    None,
    limits.preparation,
  ).unwrap()
  let graph = prepared_client_graph(prepared)
  assert_eq(@strategy.graph_task_count(graph), 7)
  for task in 0..<7 {
    assert_eq(
      @strategy.graph_task_target(graph, task),
      Some(@pipeline.Step(task)),
    )
  }
  let result_task = @strategy.graph_result_task(graph, 0).unwrap()
  assert_eq(
    @strategy.graph_task_target(graph, result_task),
    Some(@pipeline.Step(6)),
  )
  let compilation = issue_prepared_client_task_compilation(
    prepared,
    run_materials_manifests(),
    limits.sequence,
    1000,
    1000,
    1000000,
    100000,
    100,
  ).unwrap()
  assert_eq(client_task_compilation_result_names(compilation), ["nodes"])
  assert_true(
    prepare_effect_free_client_program(document, Json, environment, None, {
      ..limits.preparation,
      max_tasks: 6,
    })
    is Err(Graph(TaskLimit)),
  )
}
