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
      "\"aoa_contract_cid\":\"sha256:072c1c6e630f683e41a1c814b3a000d0544506ae25c5d89210fa8982ff73c5ff\"",
    ),
  )
  assert_eq(
    @publication_host.client_task_compilation_result_names(compilation.unwrap()),
    ["answer"],
  )
}
