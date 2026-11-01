///|
fn result_graph_value_geometry(
  value : @canonical.CanonicalValue,
) -> (Int, Int, Int) {
  try {
    let writer = @encode.measuring_writer(100000, 10000, 100)
    @canonical.emit_value(value, writer)
    @encode.finish_measurement_usage(writer)
  } catch {
    _ => abort("fixture geometry")
  }
}

///|
fn result_graph_ordered_fixture() -> PreparedClientProgram {
  let environment = admit_client_check_environment(
    run_materials_environment_wire,
    run_materials_environment_cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let document =
    #|{"version":"actql/0.1","id":"result-projection-geometry","stages":[{"id":"main","inputs":{},"steps":[{"as":"v","values":{"schema":{"id":{"type":"number","nullable":false},"label":{"type":"string","nullable":true}},"rows":[{"id":3,"label":"日本語😀"},{"id":1,"label":null},{"id":2,"label":"second"}]}},{"from":"v","sort":[{"field":"id","dir":"desc","nulls":"first"}],"as":"sorted"}],"results":{"rows":{"from":"sorted","fields":["id"],"order_by":[{"field":"id","dir":"desc","nulls":"first"}]}}}],"results":{"é/~":{"from":{"stage":"main","result":"rows"}}}}
  prepare_effect_free_client_program(
    document,
    Json,
    environment,
    None,
    run_materials_limits().preparation,
  ).unwrap()
}

///|
test "Result graph geometry retains direct roots and separately measures potential projection" {
  let value = complete_result_inventory_prepared()
  let fragment = issue_prepared_client_values_fragment(
    value,
    0,
    run_materials_limits().sequence,
    100000,
    10000,
    100,
  ).unwrap()
  let mut direct = 0
  let mut projected = 0
  for result in 0..<2 {
    let measured = measure_prepared_client_result_graph_construction(
      value,
      result,
      fragment.node_id,
      fragment.node_id,
      100000,
      10000,
      100,
    ).unwrap()
    let actual = issue_client_result_plan_parts(
      value,
      result,
      fragment.node_id,
      fragment.node_id,
      fragment.output_contract_cid,
      100000,
      10000,
      100,
    ).unwrap()
    match actual.transformation {
      None => {
        direct += 1
        assert_eq(
          measured.direct_root,
          result_graph_value_geometry(actual.root),
        )
        assert_true(actual.selection is None)
      }
      Some((node, edge)) => {
        projected += 1
        assert_eq(measured.node, result_graph_value_geometry(node))
        assert_eq(measured.edge, result_graph_value_geometry(edge))
        assert_eq(measured.root, result_graph_value_geometry(actual.root))
        assert_eq(
          measured.pipeline,
          result_graph_value_geometry(
            @canonical.object_field(node, "pipeline").unwrap(),
          ),
        )
        assert_true(actual.selection is Some(_))
      }
    }
  }
  assert_eq(direct, 1)
  assert_eq(projected, 1)
}

///|
test "Result graph geometry includes original Unicode names and authored order terms" {
  let value = result_graph_ordered_fixture()
  let fragment = issue_prepared_client_task_fragment(
    value,
    0,
    run_materials_limits().sequence,
    100000,
    10000,
    100,
  ).unwrap()
  let measured = measure_prepared_client_result_graph_construction(
    value,
    0,
    fragment.node_id,
    fragment.output_port,
    100000,
    10000,
    100,
  ).unwrap()
  let actual = issue_client_result_plan_parts(
    value,
    0,
    fragment.node_id,
    fragment.output_port,
    fragment.output_contract_cid,
    100000,
    10000,
    100,
  ).unwrap()
  let (node, edge) = actual.transformation.unwrap()
  assert_eq(measured.node, result_graph_value_geometry(node))
  assert_eq(measured.edge, result_graph_value_geometry(edge))
  assert_eq(measured.root, result_graph_value_geometry(actual.root))
  let pipeline = @canonical.object_field(node, "pipeline").unwrap()
  assert_eq(measured.pipeline, result_graph_value_geometry(pipeline))
  assert_true(
    @canonical.object_field(pipeline, "output")
    is Some(@canonical.String("ordered")),
  )
  let writer = @encode.writer(100000, 10000, 100)
  @encode.begin_object(writer)
  for (name, value) in [("node", node), ("edge", edge), ("root", actual.root)] {
    @encode.key(writer, name)
    @canonical.emit_value(value, writer)
  }
  @encode.end_object(writer)
  let wire = @encode.finish(writer)
  assert_eq(measured.parts, publication_original_wire_geometry(wire))
  let (bytes, nodes, depth) = measured.parts
  assert_eq(
    measure_prepared_client_result_graph_construction(
      value,
      0,
      fragment.node_id,
      fragment.output_port,
      bytes,
      nodes,
      depth,
    ).unwrap(),
    measured,
  )
  for
    (b, n, d) in [
      (bytes - 1, nodes, depth),
      (bytes, nodes - 1, depth),
      (bytes, nodes, depth - 1),
    ] {
    assert_true(
      measure_prepared_client_result_graph_construction(
        value,
        0,
        fragment.node_id,
        fragment.output_port,
        b,
        n,
        d,
      )
      is Err(Encoding),
    )
  }
}

///|
test "Result graph geometry is data and leaves producer and saved-root admission independent" {
  let value = values_compilation_parts_prepared()
  let fragment = issue_prepared_client_values_fragment(
    value,
    0,
    run_materials_limits().sequence,
    100000,
    10000,
    100,
  ).unwrap()
  let before = issue_prepared_client_direct_values_result_root(
    value,
    0,
    run_materials_limits().sequence,
    100000,
    10000,
    100,
  ).unwrap()
  let _ = measure_prepared_client_result_graph_construction(
    value, 0, "foreign-producer", "foreign-port", 100000, 10000, 100,
  ).unwrap()
  let after = issue_prepared_client_direct_values_result_root(
    value,
    0,
    run_materials_limits().sequence,
    100000,
    10000,
    100,
  ).unwrap()
  assert_eq(before.wire, after.wire)
  assert_eq(before.plan.cid, after.plan.cid)
  assert_false(physical_equal(before.plan, after.plan))
  let restored = admit_prepared_client_direct_values_result_root(
    value,
    0,
    before.wire,
    run_materials_limits().sequence,
    100000,
    10000,
    100,
  ).unwrap()
  assert_eq(restored.wire, before.wire)
  assert_true(
    admit_prepared_client_direct_values_result_root(
      value,
      0,
      before.wire.replace(old=fragment.node_id, new="other"),
      run_materials_limits().sequence,
      100000,
      10000,
      100,
    )
    is Err(MismatchedRoot),
  )
}

///|
test "Result graph geometry preserves missing original and finite-invalid limits" {
  let value = values_compilation_parts_prepared()
  for result in [-1, 1] {
    assert_true(
      measure_prepared_client_result_graph_construction(
        value, result, "values_0", "values_0", 100000, 10000, 100,
      )
      is Err(Root(ResultPlan(MissingResult))),
    )
  }
  for (b, n, d) in [(0, 10000, 100), (100000, 0, 100), (100000, 10000, 0)] {
    assert_true(
      measure_prepared_client_result_graph_construction(
        value, 0, "values_0", "values_0", b, n, d,
      )
      is Err(Root(InvalidLimits)),
    )
  }
}
