///|
fn ordered_client_program() -> PreparedClientProgram {
  let environment = admit_client_check_environment(
    run_materials_environment_wire,
    run_materials_environment_cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let document =
    #|{"version":"actql/0.1","id":"ordered-public-plan","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1}]},"as":"input"},{"from":"input","derive":[{"old":{"field":"id"}},{"id":{"add":[{"field":"old"},{"literal":1}]}},{"total":{"add":[{"field":"old"},{"field":"id"}]}}],"as":"derived"},{"from":"derived","select":["id","total"],"as":"projected"}],"results":{"rows":{"from":"projected","fields":["id","total"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
  prepare_effect_free_client_program(
    document,
    Json,
    environment,
    None,
    run_materials_limits().preparation,
  ).unwrap()
}

///|
test "public ordered Plan uses registered params and exact prior slot references" {
  let prepared = ordered_client_program()
  let graph = prepared_client_graph(prepared)
  assert_eq(@strategy.graph_task_count(graph), 1)
  let limits = run_materials_limits()
  // This is the former public serialization boundary: raw lowering still
  // refuses ordered nodes without their registered params owner.
  let owner = @strategy.graph_task_owner(graph, 0).unwrap()
  let raw_sequence = @lower.prepare_sequence(owner, limits.sequence).unwrap()
  let raw_writer = @encode.writer(1000000, 100000, 100)
  assert_true(
    try {
      @lower.emit_sequence_steps(raw_sequence, raw_writer)
      false
    } catch {
      @encode.InvalidStructure => true
      _ => false
    },
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
  assert_eq(client_task_compilation_result_names(compilation), ["answer"])
  assert_true(
    issue_prepared_client_values_compilation(
      prepared,
      run_materials_manifests(),
      limits.sequence,
      32,
      64,
      1000000,
      100000,
      100,
    )
    is Ok(_),
  )
  let pipeline = emit_prepared_client_task_pipeline(
    prepared,
    0,
    limits.sequence,
    1000000,
    100000,
    100,
  ).unwrap()
  // The Values prefix remains fused; the exact checked input edge is retained.
  // These references are independent consequences of the authored prefix.
  assert_true(pipeline.contains("\"in\":[\"values_0\"]"))
  assert_true(pipeline.contains("\"input_field\":\"id\""))
  assert_true(
    pipeline.contains(
      "\"at\":\"/bindings/1/expr/body/0\",\"target\":{\"prior_slot\":0}",
    ),
  )
  assert_true(
    pipeline.contains(
      "\"at\":\"/bindings/2/expr/body/0\",\"target\":{\"prior_slot\":0}",
    ),
  )
  assert_true(
    pipeline.contains(
      "\"at\":\"/bindings/2/expr/body/1\",\"target\":{\"prior_slot\":1}",
    ),
  )
  assert_true(
    pipeline.contains(
      "\"row_kernel_contract_cid\":\"sha256:2e29b27ce6d75b190ab34926bdc4fe4127b654da86f41f027470b3144082919a\"",
    ),
  )
}

///|
test "ordered Plan remaps a retained producer edge without rewriting prior slots" {
  let environment = admit_client_check_environment(
    run_materials_environment_wire,
    run_materials_environment_cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let document =
    #|{"version":"actql/0.1","id":"ordered-retained-plan","stages":[{"id":"source","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1}]},"as":"seed"}],"results":{"rows":{"from":"seed","fields":["id"]}}},{"id":"producer","inputs":{"rows":{"result":{"stage":"source","result":"rows"}}},"steps":[{"derive":[{"old":{"field":"id"}},{"id":{"add":[{"field":"old"},{"literal":1}]}}],"as":"derived"},{"select":["id"],"as":"projected"}],"results":{"rows":{"from":"projected","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"producer","result":"rows"}}}}
  let prepared = prepare_effect_free_client_program(
    document,
    Json,
    environment,
    None,
    run_materials_limits().preparation,
  ).unwrap()
  assert_eq(@strategy.graph_task_count(prepared_client_graph(prepared)), 3)
  let pipeline = emit_prepared_client_task_pipeline(
    prepared,
    1,
    run_materials_limits().sequence,
    1000000,
    100000,
    100,
  ).unwrap()
  assert_true(pipeline.contains("\"in\":[\"input_0\"]"))
  assert_true(
    pipeline.contains(
      "\"at\":\"/bindings/0/expr\",\"target\":{\"input_field\":\"id\"}",
    ),
  )
  assert_true(
    pipeline.contains(
      "\"at\":\"/bindings/1/expr/body/0\",\"target\":{\"prior_slot\":0}",
    ),
  )
}

///|
test "selected ordered compiler bodies fail closed under finite admission limits" {
  let limits : @execution.RegistryLimits = {
    max_body_bytes: 1000000,
    max_body_nodes: 100000,
    max_body_depth: 100,
  }
  assert_true(client_compiler_ordered_contract(limits) is Some(_))
  for
    cap in [
      { ..limits, max_body_bytes: 0, },
      { ..limits, max_body_nodes: 0, },
      { ..limits, max_body_depth: 0, },
    ] {
    assert_true(client_compiler_ordered_contract(cap) is None)
  }
  let prepared = ordered_client_program()
  assert_true(
    emit_prepared_client_task_pipeline(
      prepared,
      0,
      run_materials_limits().sequence,
      1,
      100000,
      100,
    )
    is Err(ClientTaskPipelineIssue::Encoding),
  )
}
