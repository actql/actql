///|
fn task_result_input_fixture(
  explicit_selection : Bool,
) -> PreparedClientProgram {
  let document = if explicit_selection {
    (
      #|{"version":"actql/0.1","id":"events-explicit-result-input","stages":[{"id":"source","inputs":{},"steps":[{"values":{"schema":{"number":{"type":"int64","nullable":false},"clock_ms":{"type":"number","nullable":false}},"rows":[{"number":"1","clock_ms":1},{"number":"4","clock_ms":4}]},"as":"seed"},{"from":"seed","to_events":{"id":"number","time":"clock_ms"},"as":"events"},{"from":"events","window_events":{"kind":"fixed","size":2},"as":"windowed"},{"from":"windowed","events":true,"as":"rows"},{"from":"rows","select":["number","window_start_ms","window_end_ms"],"as":"selected"}],"results":{"r":{"from":"selected","fields":["number","window_start_ms","window_end_ms"]}}},{"id":"consumer","inputs":{"x":{"result":{"stage":"source","result":"r"}}},"steps":[{"select":["number","window_start_ms"],"as":"out"}],"results":{"r":{"from":"out","fields":["number","window_start_ms"]}}}],"results":{"windowed":{"from":{"stage":"source","result":"r"}},"consumed":{"from":{"stage":"consumer","result":"r"}}}}
    )
  } else {
    (
      #|{"version":"actql/0.1","id":"events-private-result-input","stages":[{"id":"source","inputs":{},"steps":[{"values":{"schema":{"number":{"type":"int64","nullable":false},"clock_ms":{"type":"number","nullable":false}},"rows":[{"number":"1","clock_ms":1},{"number":"4","clock_ms":4}]},"as":"seed"},{"from":"seed","to_events":{"id":"number","time":"clock_ms"},"as":"events"},{"from":"events","window_events":{"kind":"fixed","size":2},"as":"windowed"},{"from":"windowed","events":true,"as":"rows"}],"results":{"r":{"from":"rows","fields":["number","window_start_ms","window_end_ms"]}}},{"id":"consumer","inputs":{"x":{"result":{"stage":"source","result":"r"}}},"steps":[{"select":["number","window_start_ms"],"as":"out"}],"results":{"r":{"from":"out","fields":["number","window_start_ms"]}}}],"results":{"consumed":{"from":{"stage":"consumer","result":"r"}}}}
    )
  }
  let environment = admit_client_check_environment(
    run_materials_environment_wire,
    run_materials_environment_cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: true, calendar: false, text_rank: false, },
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
test "checked Result dependency projects an internal-only Result without a new root" {
  let prepared = task_result_input_fixture(false)
  let graph = issue_prepared_client_task_plan_graph(
    prepared,
    run_materials_limits().sequence,
    1000000,
    100000,
    100,
  ).unwrap()
  let value = parse_plan_identity_value(graph.wire, 1000000, 100000, 100).unwrap()
  guard @canonical.object_field(value, "nodes") is Some(@canonical.Array(nodes)) else {
    fail("missing actual Plan nodes")
  }
  let projected = @canonical.array_values(nodes).filter(node => {
    match @canonical.object_field(node, "node_id") {
      Some(@canonical.String(id)) => id.has_prefix("result_input_")
      _ => false
    }
  })
  assert_eq(projected.length(), 1)
  let node = projected[0]
  guard @canonical.object_field(node, "pipeline") is Some(pipeline) &&
    @canonical.object_field(pipeline, "steps") is Some(@canonical.Array(steps)) &&
    @canonical.array_values(steps).get(0) is Some(step) &&
    @canonical.object_field(step, "params") is Some(params) &&
    @canonical.object_field(params, "columns")
    is Some(@canonical.Array(columns)) else {
    fail("missing physical checked Result projection")
  }
  assert_true(
    @canonical.object_field(step, "op") is Some(@canonical.String("REL.select")),
  )
  let names : Array[String] = []
  for column in @canonical.array_values(columns) {
    guard column is @canonical.String(name) else {
      fail("non-string checked projection column")
    }
    names.push(name)
  }
  assert_eq(names, ["number", "window_start_ms", "window_end_ms"])
  let compilation = issue_prepared_client_task_compilation(
    prepared,
    run_materials_manifests(),
    run_materials_limits().sequence,
    1000,
    1000,
    1000000,
    100000,
    100,
  ).unwrap()
  assert_eq(client_task_compilation_result_names(compilation), ["consumed"])
}

///|
test "checked Result dependency retains an authored selection after the Event bridge" {
  let prepared = task_result_input_fixture(true)
  let compilation = issue_prepared_client_task_compilation(
    prepared,
    run_materials_manifests(),
    run_materials_limits().sequence,
    1000,
    1000,
    1000000,
    100000,
    100,
  ).unwrap()
  let names = client_task_compilation_result_names(compilation)
  assert_eq(names.length(), 2)
  assert_true(names.contains("windowed"))
  assert_true(names.contains("consumed"))
}

///|
test "checked Result dependency refuses foreign Carrier and contract identities" {
  let prepared = task_result_input_fixture(false)
  let graph = prepared_client_graph(prepared)
  let mut checked = false
  for index in 0..<@strategy.graph_data_count(graph) {
    let edge = @strategy.graph_data_at(graph, index).unwrap()
    if client_task_result_input_port(graph, edge) is Ok(Some(_)) {
      let source = issue_prepared_client_task_fragment(
        prepared,
        @strategy.data_edge_producer(edge),
        run_materials_limits().sequence,
        1000000,
        100000,
        100,
      ).unwrap()
      let foreign_cid = "sha256:" + "f".repeat(64)
      assert_not_eq(source.output_contract_cid, foreign_cid)
      for
        foreign in [
          { ..source, output_contract_cid: foreign_cid, },
          { ..source, output_carrier: "events", },
        ] {
        assert_true(
          issue_client_task_result_input_projection(
            graph, edge, index, foreign, 1000000, 100000, 100,
          )
          is Err(ContractMismatch),
        )
      }
      let plan = issue_prepared_client_task_plan_graph(
        prepared,
        run_materials_limits().sequence,
        1000000,
        100000,
        100,
      ).unwrap()
      assert_true(
        admit_prepared_client_task_plan_graph(
          prepared,
          plan.wire.replace(old=source.output_contract_cid, new=foreign_cid),
          run_materials_limits().sequence,
          1000000,
          100000,
          100,
        )
        is Err(MismatchedGraph),
      )
      checked = true
    }
  }
  assert_true(checked)
}

///|
test "checked Result dependency construction covers projection scratch and graph bodies" {
  let prepared = task_result_input_fixture(false)
  let measured = measure_prepared_client_pure_compilation_construction(
    prepared,
    run_materials_manifests(),
    run_materials_limits().sequence,
    1000,
    1000,
    1000000,
    100000,
    100,
  ).unwrap()
  assert_eq(measured.projections.filter(p => p.root == (0, 0, 0)).length(), 1)
  assert_eq(measured.projections.filter(p => p.root != (0, 0, 0)).length(), 1)
  let compiled = issue_prepared_client_task_compilation(
    prepared,
    run_materials_manifests(),
    run_materials_limits().sequence,
    1000,
    1000,
    1000000,
    100000,
    100,
  ).unwrap()
  let plan = parse_plan_identity_value(
    compiled.plan.plan.wire,
    1000000,
    100000,
    100,
  ).unwrap()
  assert_compilation_geometry_covers(measured.executable_plan, plan)
  for
    (name, bound) in [
      ("nodes", measured.nodes),
      ("data_edges", measured.edges),
      ("root_refs", measured.roots),
    ] {
    assert_compilation_geometry_covers(
      bound,
      @canonical.object_field(plan, name).unwrap(),
    )
  }
}
