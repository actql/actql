///|
test "formal Property Graph Plan retains typed graph ports and keyed parallel-edge constructor without legacy conversion" {
  let (_, environment, limits) = local_effect_export_fixture(
    property_graph=true,
  )
  let document =
    #|{"version":"actql/0.1","id":"keyed-graph-plan","stages":[{"id":"source","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1}]},"as":"nodes"},{"values":{"schema":{"key":{"type":"number","nullable":false},"src":{"type":"number","nullable":false},"dst":{"type":"number","nullable":false}},"rows":[{"key":10,"src":1,"dst":1},{"key":11,"src":1,"dst":1}]},"as":"edges"},{"property_graph":{"version":"actql-property-graph-constructor/0.1","nodes":[{"name":"N","from":"nodes","key":["id"],"labels":[{"name":"Node","properties":{"mode":"all_columns"}}]}],"edges":[{"name":"E","from":"edges","key":["key"],"source":{"definition":"N","key":["src"]},"target":{"definition":"N","key":["dst"]},"labels":[{"name":"R","properties":{"mode":"all_columns"}}]}]},"as":"g"},{"match_edges":{"definition":"E","label":"R","where":"key > 0","fields":["key"]},"as":"matched"}],"results":{"out":{"from":"matched","fields":["key"]}}}],"results":{"answer":{"from":{"stage":"source","result":"out"}}}}
  let prepared = @publication_host.prepare_effect_free_client_program(
    document,
    Json,
    environment,
    None,
    { ..limits.program, max_tasks: 10, max_graph_work: 100000, },
  ).unwrap()
  // The existing checked DAG owns all four tasks and the graph handoff.
  assert_eq(
    @strategy.graph_task_count(
      @publication_host.prepared_client_graph(prepared),
    ),
    4,
  )
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
  if issued is Err(Fragment(UnrepresentableContract)) {
    fail("the new typed Graph task port has no representable contract")
  }
  assert_true(issued is Ok(_))
  let wire = @publication_host.client_task_plan_graph_wire(issued.unwrap())
  assert_true(wire.contains("\"op\":\"BRIDGE.rows.to_property_graph\""))
  assert_true(wire.contains("actql-property-graph-contract/0.1"))
  assert_true(wire.contains("\"carrier\":\"graph\",\"contract_cid\":"))
  assert_false(wire.contains("\"op\":\"BRIDGE.rows.to_graph\""))
  assert_false(wire.contains("actql-graph-contract/0.1"))
  assert_true(wire.contains("\"definition\":\"E\""))
  assert_true(
    wire.contains(
      "\"key_contracts\":[{\"nullable\":false,\"type\":\"number\"}]",
    ),
  )
  assert_true(
    @publication_host.admit_prepared_client_task_plan_graph(
      prepared, wire, sequence, 1000000, 100000, 100,
    )
    is Ok(_),
  )
  assert_true(
    @publication_host.admit_prepared_client_task_plan_graph(
      prepared,
      wire.replace(
        old="BRIDGE.rows.to_property_graph",
        new="BRIDGE.rows.to_graph",
      ),
      sequence,
      1000000,
      100000,
      100,
    )
    is Err(MismatchedGraph),
  )
  let manifests = @publication_host.admit_client_compilation_manifests(
    @environment.compiler_grammar_manifest_wire(),
    @environment.compiler_barrier_contract_manifest_wire(),
    10000,
    1000,
    20,
  ).unwrap()
  let compilation = @publication_host.issue_prepared_client_task_compilation(
    prepared, manifests, sequence, 1000, 1000, 1000000, 100000, 100,
  )
  assert_true(compilation is Ok(_))
  let compiled = @publication.publication_contract_json(
    @publication_host.client_task_compilation_compiled_plan(
      compilation.unwrap(),
    ),
  )
  // The current contract is a pinned machine preimage, not a product-generated expectation.
  assert_true(
    compiled.contains(
      "\"aoa_contract_cid\":\"sha256:c8768130d38f4999ab2cb4640a273036fe1c822ca580038978d50692f2f0c958\"",
    ),
  )
  assert_eq(
    @publication_host.client_task_compilation_result_names(compilation.unwrap()),
    ["answer"],
  )
}

///|
test "current property Graph and external TRAIL starts split before Relation filter" {
  let (_, environment, limits) = local_effect_export_fixture(
    property_graph=true,
  )
  let document =
    #|{"version":"actql/0.1","id":"selected-current-trail","stages":[{"id":"seed_source","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1}]},"as":"nodes"},{"values":{"schema":{"key":{"type":"number","nullable":false},"src":{"type":"number","nullable":false},"dst":{"type":"number","nullable":false}},"rows":[{"key":10,"src":1,"dst":1}]},"as":"edges"},{"property_graph":{"version":"actql-property-graph-constructor/0.1","nodes":[{"name":"N","from":"nodes","key":["id"],"labels":[{"name":"Node","properties":{"mode":"all_columns"}}]}],"edges":[{"name":"E","from":"edges","key":["key"],"source":{"definition":"N","key":["src"]},"target":{"definition":"N","key":["dst"]},"labels":[{"name":"R","properties":{"mode":"all_columns"}}]}]},"as":"g"},{"from":"g","match_nodes":{"definition":"N","bindings":{"identity":"element"},"where":"true","fields":["element"]},"as":"seeds"}],"results":{"r":{"from":"seeds","fields":["element"]}}},{"id":"query","inputs":{"seeds":{"result":{"stage":"seed_source","result":"r"}}},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1}]},"as":"nodes"},{"values":{"schema":{"key":{"type":"number","nullable":false},"src":{"type":"number","nullable":false},"dst":{"type":"number","nullable":false}},"rows":[{"key":10,"src":1,"dst":1}]},"as":"edges"},{"property_graph":{"version":"actql-property-graph-constructor/0.1","nodes":[{"name":"N","from":"nodes","key":["id"],"labels":[{"name":"Node","properties":{"mode":"all_columns"}}]}],"edges":[{"name":"E","from":"edges","key":["key"],"source":{"definition":"N","key":["src"]},"target":{"definition":"N","key":["dst"]},"labels":[{"name":"R","properties":{"mode":"all_columns"}}]}]},"as":"g"},{"from":"g","traverse":{"start":{"from":"seeds","id":"element"},"direction":"out","min_hops":1,"max_hops":1,"path_mode":"trail","emit":"paths"},"as":"paths"},{"from":"paths","filter":"hop_count > 0","as":"out"}],"results":{"r":{"from":"out","fields":["hop_count"]}}}],"results":{"answer":{"from":{"stage":"query","result":"r"}}}}
  let prepared = @publication_host.prepare_effect_free_client_program(
    document,
    Json,
    environment,
    None,
    { ..limits.program, max_tasks: 20, max_graph_work: 100000, },
  ).unwrap()
  let graph = @publication_host.prepared_client_graph(prepared)
  assert_eq(@strategy.graph_task_count(graph), 9)
  assert_eq(@strategy.graph_task_unit_index(graph, 7), Some(1))
  assert_eq(@strategy.graph_task_selected_step(graph, 6), Some(2))
  assert_eq(@strategy.graph_task_selected_step(graph, 7), Some(3))
  assert_eq(@strategy.graph_task_input_count(graph, 7), Some(2))
  assert_eq(@strategy.graph_task_selected_step(graph, 8), Some(4))
}

///|
test "external Relation-selected subgraph keeps both checked input ports" {
  let (_, environment, limits) = local_effect_export_fixture(
    property_graph=true,
  )
  let document =
    #|{"version":"actql/0.1","id":"selected-current-subgraph","stages":[{"id":"seed_source","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1}]},"as":"nodes"},{"values":{"schema":{"key":{"type":"number","nullable":false},"src":{"type":"number","nullable":false},"dst":{"type":"number","nullable":false}},"rows":[{"key":10,"src":1,"dst":1}]},"as":"edges"},{"property_graph":{"version":"actql-property-graph-constructor/0.1","nodes":[{"name":"N","from":"nodes","key":["id"],"labels":[{"name":"Node","properties":{"mode":"all_columns"}}]}],"edges":[{"name":"E","from":"edges","key":["key"],"source":{"definition":"N","key":["src"]},"target":{"definition":"N","key":["dst"]},"labels":[{"name":"R","properties":{"mode":"all_columns"}}]}]},"as":"g"},{"from":"g","match_nodes":{"definition":"N","bindings":{"identity":"element"},"where":"true","fields":["element"]},"as":"seeds"}],"results":{"r":{"from":"seeds","fields":["element"]}}},{"id":"query","inputs":{"seeds":{"result":{"stage":"seed_source","result":"r"}}},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1}]},"as":"nodes"},{"values":{"schema":{"key":{"type":"number","nullable":false},"src":{"type":"number","nullable":false},"dst":{"type":"number","nullable":false}},"rows":[{"key":10,"src":1,"dst":1}]},"as":"edges"},{"property_graph":{"version":"actql-property-graph-constructor/0.1","nodes":[{"name":"N","from":"nodes","key":["id"],"labels":[{"name":"Node","properties":{"mode":"all_columns"}}]}],"edges":[{"name":"E","from":"edges","key":["key"],"source":{"definition":"N","key":["src"]},"target":{"definition":"N","key":["dst"]},"labels":[{"name":"R","properties":{"mode":"all_columns"}}]}]},"as":"g"},{"from":"g","subgraph":{"nodes":{"from":"seeds","id":"element"}},"as":"slice"},{"from":"slice","match_nodes":{"definition":"N","where":"true","fields":["id"]},"as":"projected"},{"from":"projected","filter":"true","as":"out"}],"results":{"r":{"from":"out","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"query","result":"r"}}}}
  let prepared = @publication_host.prepare_effect_free_client_program(
    document,
    Json,
    environment,
    None,
    { ..limits.program, max_tasks: 20, max_graph_work: 100000, },
  ).unwrap()
  let graph = @publication_host.prepared_client_graph(prepared)
  assert_eq(@strategy.graph_task_count(graph), 10)
  assert_eq(@strategy.graph_task_selected_step(graph, 7), Some(3))
  assert_eq(@strategy.graph_task_input_count(graph, 7), Some(2))
  let domain_at = fn(task : Int) {
    let owner = @strategy.graph_task_owner(graph, task).unwrap()
    guard @lower.preparation_carrier_at(
        @lower.bound_preparation(owner),
        @pipeline.Step(2),
      )
      is Some(@carrier_contract.GraphValue(contract)) else {
      abort("expected keyed Graph carrier")
    }
    @carrier_contract.property_graph_domain(
      @carrier_contract.graph_property_definition(contract),
    )
  }
  assert_eq(domain_at(2), domain_at(6))
}

///|
test "retained external Relation selector splits only its Carrier consumer" {
  let (_, environment, limits) = local_effect_export_fixture(
    property_graph=true,
  )
  let document =
    #|{"version":"actql/0.1","id":"external-constructor-subgraph","stages":[
    #|{"id":"rows","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1}]},"as":"nodes"},{"values":{"schema":{"key":{"type":"number","nullable":false},"src":{"type":"number","nullable":false},"dst":{"type":"number","nullable":false}},"rows":[{"key":10,"src":1,"dst":1}]},"as":"edges"}],"results":{"nodes":{"from":"nodes","fields":["id"]},"edges":{"from":"edges","fields":["key","src","dst"]}}},
    #|{"id":"selections","inputs":{"nodes":{"result":{"stage":"rows","result":"nodes"}},"edges":{"result":{"stage":"rows","result":"edges"}}},"steps":[{"property_graph":{"version":"actql-property-graph-constructor/0.1","nodes":[{"name":"N","from":"nodes","key":["id"],"labels":[{"name":"Node","properties":{"mode":"all_columns"}}]}],"edges":[{"name":"E","from":"edges","key":["key"],"source":{"definition":"N","key":["src"]},"target":{"definition":"N","key":["dst"]},"labels":[{"name":"R","properties":{"mode":"all_columns"}}]}]},"as":"g"},{"from":"g","match_nodes":{"definition":"N","bindings":{"identity":"element"},"where":"true","fields":["element"]},"as":"selected"}],"results":{"r":{"from":"selected","fields":["element"]}}},
    #|{"id":"query","inputs":{"nodes":{"result":{"stage":"rows","result":"nodes"}},"edges":{"result":{"stage":"rows","result":"edges"}},"seeds":{"result":{"stage":"selections","result":"r"}}},"steps":[{"property_graph":{"version":"actql-property-graph-constructor/0.1","nodes":[{"name":"N","from":"nodes","key":["id"],"labels":[{"name":"Node","properties":{"mode":"all_columns"}}]}],"edges":[{"name":"E","from":"edges","key":["key"],"source":{"definition":"N","key":["src"]},"target":{"definition":"N","key":["dst"]},"labels":[{"name":"R","properties":{"mode":"all_columns"}}]}]},"as":"g"},{"from":"g","subgraph":{"nodes":{"from":"seeds","id":"element"}},"as":"slice"},{"from":"slice","match_nodes":{"definition":"N","where":"true","fields":["id"]},"as":"out"}],"results":{"r":{"from":"out","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"query","result":"r"}}}}
  let preparation = @publication_host.prepare_effect_free_client_program(
    document,
    Json,
    environment,
    None,
    {
      ..limits.program,
      checking: {
        input: { ..limits.program.checking.input, max_stages: 3, },
        compilation: {
          ..limits.program.checking.compilation,
          structure: {
            ..limits.program.checking.compilation.structure,
            stages: 3,
          },
        },
      },
      max_tasks: 20,
      max_graph_work: 100000,
    },
  )
  if preparation is Err(Check(diagnostic)) {
    raise @program_check.diagnostic_cause(diagnostic)
  }
  let prepared = preparation.unwrap()
  let graph = @publication_host.prepared_client_graph(prepared)
  assert_eq(@strategy.graph_task_count(graph), 5)
  // Retained constructor inputs alone keep the established fused MATCH task.
  assert_eq(@strategy.graph_task_selected_step(graph, 1), None)
  assert_eq(@strategy.graph_task_selected_step(graph, 2), Some(0))
  assert_eq(@strategy.graph_task_selected_step(graph, 3), Some(1))
  assert_eq(@strategy.graph_task_input_count(graph, 3), Some(2))
  assert_eq(@strategy.graph_task_selected_step(graph, 4), Some(2))
  let program = @strategy.graph_program(graph)
  let owners = [
    @strategy.graph_task_owner(graph, 0).unwrap(),
    @strategy.graph_task_owner(graph, 1).unwrap(),
    @strategy.graph_task_owner(graph, 2).unwrap(),
  ]
  let requirement_inventory = @context.stage_requirement_operations(
    @program_check.requirements(program),
  )
  assert_eq(@context.operation_closure_count(requirement_inventory), 55)
  // Two Values requirements; five each for both constructors and MATCHes;
  // eleven for the typed Subgraph operation. Three stage remap visits.
  for task, expected in [2, 10, 5, 11, 5] {
    assert_eq(@strategy.graph_task_operation_count(graph, task), Some(expected))
    assert_eq(
      @strategy.graph_task_numeric_observation_count(graph, task),
      Some(0),
    )
  }
  // Original DAG admission: former 43 + 55 contextual obligation visits
  // + one root Result binding = 99. Repeated imported producer occurrences
  // are distinct visits: rows 2; selections 10 + 2 * 2 = 14;
  // query 21 + 2 * 2 + 14 = 39; total 2 + 14 + 39 = 55.
  // classification 30 (including the five retained-selector edge visits);
  // task mapping 8; edge mapping 33; controls 2; operations 36; Result 1.
  // The full retained-selector scan costs five even when its match is last.
  // Preserve previous low limits, including the former 153-unit success.
  // The inventory is spent before classification: 122 stops before the
  // selector's first edge and 126 before its fifth. 208 is one short of
  // the complete graph; 209 succeeds without changing any output/owner.
  for work in [0, 43, 66, 70, 99, 122, 126, 152, 153, 208] {
    assert_true(
      @strategy.prepare_checked_dag(
        program,
        owners,
        20,
        work,
        source_free_root=true,
      )
      is Err(WorkLimit),
    )
  }
  let bounded = @strategy.prepare_checked_dag(
    program,
    owners,
    20,
    209,
    source_free_root=true,
  ).unwrap()
  assert_true(physical_equal(@strategy.graph_program(bounded), program))
  assert_eq(@strategy.graph_task_count(bounded), 5)
  for task, expected in [None, None, Some(0), Some(1), Some(2)] {
    assert_eq(@strategy.graph_task_selected_step(bounded, task), expected)
    assert_true(
      physical_equal(
        @strategy.graph_task_owner(bounded, task).unwrap(),
        owners[if task < 2 { task } else { 2 }],
      ),
    )
  }
  assert_eq(@strategy.graph_task_input_count(bounded, 3), Some(2))
  assert_eq(@strategy.graph_data_count(bounded), 7)
  assert_eq(@strategy.graph_control_count(bounded), 2)
  assert_eq(@strategy.graph_result_count(bounded), 1)
  assert_eq(@strategy.graph_result_task(bounded, 0), Some(4))
}
