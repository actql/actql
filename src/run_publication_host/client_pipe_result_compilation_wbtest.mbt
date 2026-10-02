///|
test "named prefix and limited primary Results compile through the normal task owner" {
  let document =
    #|{"version":"actql/0.1","id":"prefix-results","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"amount":{"type":"number","nullable":true}},"rows":[{"id":3,"amount":30},{"id":1,"amount":null},{"id":2,"amount":20},{"id":3,"amount":30}]},"as":"source"},{"from":"source","sort":[{"field":"id","dir":"asc","nulls":"first"}]},{"select":["id","amount"],"as":"original"},{"take":{"count":1,"offset":0},"as":"limited"}],"results":{"original":{"from":"original","fields":["id","amount"]},"limited":{"from":"limited","fields":["id","amount"]}}}],"results":{"original":{"from":{"stage":"main","result":"original"}},"answer":{"from":{"stage":"main","result":"limited"}}}}
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
  let compilation = match compilation {
    Ok(value) => value
    Err(Plan(TaskGraph(Root(Root(RequiresResultTransformation))))) =>
      fail("prefix requires Result transformation")
    Err(Plan(TaskGraph(Root(Root(TaskFragment(_)))))) =>
      fail("prefix Result task fragment rejected")
    Err(Plan(TaskGraph(Root(Root(ResultPlan(_)))))) =>
      fail("prefix Result Plan rejected")
    Err(Plan(TaskGraph(Root(Root(_))))) =>
      fail("prefix direct Result root rejected")
    Err(Plan(TaskGraph(Root(Transformation(_))))) =>
      fail("prefix transformation rejected")
    Err(Plan(TaskGraph(Fragment(_)))) => fail("task fragment rejected")
    Err(Plan(TaskGraph(_))) => fail("another task graph issue")
    Err(Plan(_)) => fail("another executable Plan issue")
    Err(_) => fail("another task compilation issue")
  }
  let names = client_task_compilation_result_names(compilation)
  assert_eq(names.length(), 2)
  assert_true(names.contains("answer") && names.contains("original"))
  let graph = prepared_client_graph(prepared)
  assert_eq(@strategy.graph_task_count(graph), 4)
  for result in 0..<prepared_client_result_count(prepared) {
    let task = @strategy.graph_result_task(graph, result).unwrap()
    let occurrence = @strategy.graph_result_occurrence(graph, result).unwrap()
    assert_eq(
      @strategy.graph_task_target(graph, task),
      Some(
        @results.port_target(
          @execution.managed_result_occurrence_port(occurrence),
        ),
      ),
    )
  }
  assert_true(
    prepare_effect_free_client_program(document, Json, environment, None, {
      ..limits.preparation,
      max_tasks: 3,
    })
    is Err(Graph(TaskLimit)),
  )
  // A final-only linear Relation remains one task. Intermediate Results,
  // not the operation spelling or a new source mode, require this split.
  let final_only = document.replace(
    old="\"original\":{\"from\":{\"stage\":\"main\",\"result\":\"original\"}},",
    new="",
  )
  let final_prepared = prepare_effect_free_client_program(
    final_only,
    Json,
    environment,
    None,
    limits.preparation,
  ).unwrap()
  assert_eq(
    @strategy.graph_task_count(prepared_client_graph(final_prepared)),
    1,
  )
}
