///|
test "formal Graph diff Plan retains both Graph occurrences and a Delta Relation" {
  let (_, environment, limits) = local_effect_export_fixture(graph=true)
  // Even self-diff has two exact input occurrences. Its ordinary JSON output
  // is not an admission receipt for the subsequent Delta application.
  let document =
    #|{"version":"actql/0.1","id":"graph-diff-plan","stages":[{"id":"source","inputs":{},"steps":[
    #|{"values":{"schema":{"person_key":{"type":"number","nullable":false}},"rows":[{"person_key":1}]},"as":"nodes"},
    #|{"graph":{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"nodes","key":["person_key"],"labels":[{"name":"Node","properties":{"mode":"no_properties"}}]}],"edges":[]},"as":"g"},
    #|{"from":"g","graph_diff":{"with":"g"},"as":"changes"},
    #|{"from":"g","apply_graph_delta":{"with":"changes","field":"delta"},"as":"applied"},
    #|{"from":"applied","node_rows":true,"as":"rows"}],"results":{"out":{"from":"rows","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"source","result":"out"}}}}
  let prepared = @publication_host.prepare_effect_free_client_program(
    document,
    Json,
    environment,
    None,
    { ..limits.program, max_tasks: 10, max_graph_work: 100000, },
  ).unwrap()
  let graph = @publication_host.prepared_client_graph(prepared)
  assert_eq(@strategy.graph_task_count(graph), 5)
  assert_eq(@strategy.graph_task_input_count(graph, 2), Some(2))
  assert_eq(@strategy.graph_task_selected_step(graph, 2), Some(2))
  let sequence : @lower.SequenceLimits = {
    max_steps: 100,
    max_rows: 100,
    max_cells: 10000,
    max_bindings: 100,
    max_name_bytes: 100000,
    expressions: {
      max_nodes: 10000,
      max_work: 100000,
      max_depth: 100,
      max_literal_nodes: 10000,
      max_literal_text_bytes: 10000,
    },
  }
  let plan = @publication_host.issue_prepared_client_task_plan_graph(
    prepared, sequence, 1000000, 100000, 100,
  ).unwrap()
  let wire = @publication_host.client_task_plan_graph_wire(plan)
  assert_true(wire.contains("\"op\":\"SGA.diff\""))
  assert_true(wire.contains("\"op\":\"SGA.apply_delta\""))
  assert_true(
    @publication_host.admit_prepared_client_task_plan_graph(
      prepared, wire, sequence, 1000000, 100000, 100,
    )
    is Ok(_),
  )
}
