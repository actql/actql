///|
test "formal Delta application Plan retains exact mixed input roles and runtime admission" {
  let (_, environment, limits) = local_effect_export_fixture(
    property_graph=true,
  )
  // An expression's JSON literal is ordinary data. Plan construction retains
  // exact-row, action, base, before and target checks rather than treating this
  // deliberately unadmitted payload as an admission receipt.
  let document =
    #|{"version":"actql/0.1","id":"delta-application-plan","stages":[{"id":"source","inputs":{},"steps":[
    #|{"values":{"schema":{"person_key":{"type":"number","nullable":false}},"rows":[{"person_key":1}]},"as":"nodes"},
    #|{"property_graph":{"version":"actql-property-graph-constructor/0.1","nodes":[{"name":"N","from":"nodes","key":["person_key"],"labels":[{"name":"Node","properties":{"mode":"no_properties"}}]}],"edges":[]},"as":"g"},
    #|{"from":"nodes","derive":{"delta":{"literal":{}}},"as":"changes"},
    #|{"from":"g","apply_graph_delta":{"with":"changes","field":"delta"},"as":"applied"},
    #|{"from":"applied","node_rows":true,"as":"rows"}],"results":{"out":{"from":"rows","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"source","result":"out"}}}}
  let outcome = @publication_host.prepare_effect_free_client_program(
    document,
    Json,
    environment,
    None,
    { ..limits.program, max_tasks: 10, max_graph_work: 100000, },
  )
  let prepared = outcome.unwrap()
  let graph = @publication_host.prepared_client_graph(prepared)
  assert_eq(@strategy.graph_task_count(graph), 5)
  assert_eq(@strategy.graph_task_input_count(graph, 3), Some(2))
  assert_eq(@strategy.graph_task_selected_step(graph, 3), Some(3))
  assert_eq(@strategy.graph_task_operation_count(graph, 3), Some(5))
  // Profile selection is static, while every data/resource obligation remains
  // on the same checked occurrence for execution. Neither is an admission ACK.
  let mut profiles = 0
  let mut runtime_checks = 0
  for index in 0..<5 {
    let entry = @strategy.graph_task_operation_at(graph, 3, index).unwrap()
    assert_eq(entry.site.step, 3)
    assert_eq(entry.site.index, index)
    match entry.disposition {
      StaticResolution(ProfileResolution(_)) => {
        profiles += 1
        assert_eq(index, 0)
      }
      ExecutionCheck(GraphDeltaExecution(check)) => {
        runtime_checks += 1
        assert_true(physical_equal(check.site, entry.site))
        assert_eq(check.left, @pipeline.Step(1))
        assert_eq(check.right, @pipeline.Step(2))
        assert_eq(
          check.rule,
          [
            @context.RequireDeltaResources,
            @context.RequireExactlyOneDeltaRow,
            @context.AdmitCompleteDeltaActions,
            @context.CheckExactBaseBeforeTarget,
          ][index - 1],
        )
      }
      _ => fail("Delta requirement lost its exact profile/runtime disposition")
    }
  }
  assert_eq((profiles, runtime_checks), (1, 4))
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
  let issued = @publication_host.issue_prepared_client_task_plan_graph(
    prepared, sequence, 1000000, 100000, 100,
  )
  guard issued is Ok(plan) else { fail("Delta Plan issuance failed") }
  let wire = @publication_host.client_task_plan_graph_wire(plan)
  assert_true(wire.contains("\"op\":\"SGA.apply_delta\""))
  assert_true(wire.contains("actql-property-graph-contract/0.1"))
  assert_false(wire.contains("actql-graph-contract/0.1"))
  assert_true(
    @publication_host.admit_prepared_client_task_plan_graph(
      prepared, wire, sequence, 1000000, 100000, 100,
    )
    is Ok(_),
  )
}
