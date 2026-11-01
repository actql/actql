///|
test "Values pipeline measurement shares serializer and enforces exact three-dimensional limits" {
  let prepared = values_compilation_parts_prepared()
  let limits = run_materials_limits().sequence
  let (bytes, nodes, depth) = measure_prepared_client_values_pipeline(
    prepared, 0, limits, 100000, 10000, 100,
  ).unwrap()
  // Two Number rows, one field: 12 fixed values + three contract values +
  // two row-object/number pairs. The deepest container is one row object.
  assert_eq(nodes, 19)
  assert_eq(depth, 6)
  let wire = emit_prepared_client_values_pipeline(
    prepared, 0, limits, bytes, nodes, depth,
  ).unwrap()
  let expected =
    #|{"output":"values_0","sources":{},"steps":[{"id":"values_0","in":[],"op":"REL.values","params":{"rows":[{"id":1},{"id":2}],"schema":{"id":{"nullable":false,"type":"number"}}}}],"version":"aoa-pipeline/0.1"}
  assert_eq(wire, expected)
  assert_eq(wire.length(), bytes) // This independent fixture is entirely ASCII.
  assert_eq(
    measure_prepared_client_values_pipeline(
      prepared, 0, limits, bytes, nodes, depth,
    ).unwrap(),
    (bytes, nodes, depth),
  )
  assert_true(
    measure_prepared_client_values_pipeline(
      prepared,
      0,
      limits,
      bytes - 1,
      nodes,
      depth,
    )
    is Err(Encoding),
  )
  assert_true(
    measure_prepared_client_values_pipeline(
      prepared,
      0,
      limits,
      bytes,
      nodes - 1,
      depth,
    )
    is Err(Encoding),
  )
  assert_true(
    measure_prepared_client_values_pipeline(
      prepared,
      0,
      limits,
      bytes,
      nodes,
      depth - 1,
    )
    is Err(Encoding),
  )
  assert_true(
    emit_prepared_client_values_pipeline(
      prepared,
      0,
      limits,
      bytes - 1,
      nodes,
      depth,
    )
    is Err(Encoding),
  )
  assert_true(
    emit_prepared_client_values_pipeline(
      prepared,
      0,
      limits,
      bytes,
      nodes - 1,
      depth,
    )
    is Err(Encoding),
  )
  assert_true(
    emit_prepared_client_values_pipeline(
      prepared,
      0,
      limits,
      bytes,
      nodes,
      depth - 1,
    )
    is Err(Encoding),
  )
}

///|
test "Values Fragment construction measurement shares exact original body and finite bounds" {
  let prepared = values_compilation_parts_prepared()
  let limits = run_materials_limits().sequence
  let (bytes, nodes, depth) = measure_prepared_client_values_fragment(
    prepared, 0, limits, 100000, 10000, 100,
  ).unwrap()
  // Seven wrapper values enclose the independently pinned 19-node pipeline.
  // Its deepest row object is one level below the Fragment root.
  assert_eq(nodes, 26)
  assert_eq(depth, 7)
  let fragment = issue_prepared_client_values_fragment(
    prepared, 0, limits, bytes, nodes, depth,
  ).unwrap()
  assert_eq(@utf8.encode(fragment.wire).length(), bytes)
  for
    (b, n, d) in [
      (bytes - 1, nodes, depth),
      (bytes, nodes - 1, depth),
      (bytes, nodes, depth - 1),
    ] {
    assert_true(
      measure_prepared_client_values_fragment(prepared, 0, limits, b, n, d)
      is Err(_),
    )
    assert_true(
      issue_prepared_client_values_fragment(prepared, 0, limits, b, n, d)
      is Err(_),
    )
  }
}

///|
test "Values Fragment construction measurement retains original Unicode and width" {
  let environment = admit_client_check_environment(
    run_materials_environment_wire,
    run_materials_environment_cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let document =
    #|{"version":"actql/0.1","id":"unicode-fragment","stages":[{"id":"main","inputs":{},"steps":[{"as":"v","values":{"schema":{"id":{"type":"number","nullable":false},"text":{"type":"string","nullable":false}},"rows":[{"id":1,"text":"日本語😀"},{"id":2,"text":"e\u0301\n"}]}}],"results":{"rows":{"from":"v","fields":["id","text"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
  let prepared = prepare_effect_free_client_program(
    document,
    Json,
    environment,
    None,
    run_materials_limits().preparation,
  ).unwrap()
  let limits = run_materials_limits().sequence
  let measurement = measure_prepared_client_values_fragment(
    prepared, 0, limits, 100000, 10000, 100,
  ).unwrap()
  let fragment = issue_prepared_client_values_fragment(
    prepared, 0, limits, 100000, 10000, 100,
  ).unwrap()
  assert_eq(measurement.0, @utf8.encode(fragment.wire).length())
  let tree = parse_plan_identity_value(fragment.wire, 100000, 10000, 100).unwrap()
  let out = @encode.measuring_writer(100000, 10000, 100)
  @canonical.emit_value(tree, out)
  assert_eq(measurement, @encode.finish_measurement_usage(out))
}

///|
test "Result Plan measurement shares original projection order and exact body limits" {
  let value = result_material_prepared()
  let measurement = measure_prepared_client_result_plan(
    value, 0, 100000, 10000, 100,
  ).unwrap()
  let plan = issue_prepared_client_result_plan(value, 0, 100000, 10000, 100).unwrap()
  assert_eq(measurement.0, @utf8.encode(plan.wire).length())
  let tree = parse_plan_identity_value(plan.wire, 100000, 10000, 100).unwrap()
  let out = @encode.measuring_writer(100000, 10000, 100)
  @canonical.emit_value(tree, out)
  assert_eq(measurement, @encode.finish_measurement_usage(out))
  let (bytes, nodes, depth) = measurement
  assert_eq(
    measure_prepared_client_result_plan(value, 0, bytes, nodes, depth).unwrap(),
    measurement,
  )
  for
    (b, n, d) in [
      (bytes - 1, nodes, depth),
      (bytes, nodes - 1, depth),
      (bytes, nodes, depth - 1),
    ] {
    assert_true(
      measure_prepared_client_result_plan(value, 0, b, n, d) is Err(Encoding),
    )
  }
}

///|
test "Result Plan measurement keeps multiple root identities and authored field order" {
  let environment = admit_client_check_environment(
    run_materials_environment_wire,
    run_materials_environment_cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let document =
    #|{"version":"actql/0.1","id":"multiple-results","stages":[{"id":"source","inputs":{},"steps":[{"as":"v","values":{"schema":{"id":{"type":"number","nullable":false},"label":{"type":"string","nullable":false}},"rows":[{"id":1,"label":"日本語😀"},{"id":2,"label":"second"}]}}],"results":{"rows":{"from":"v","fields":["label","id"]}}}],"results":{"answer":{"from":{"stage":"source","result":"rows"}},"other":{"from":{"stage":"source","result":"rows"}}}}
  let value = prepare_effect_free_client_program(
    document,
    Json,
    environment,
    None,
    run_materials_limits().preparation,
  ).unwrap()
  assert_eq(prepared_client_result_count(value), 2)
  let first = issue_prepared_client_result_plan(value, 0, 100000, 10000, 100).unwrap()
  let second = issue_prepared_client_result_plan(value, 1, 100000, 10000, 100).unwrap()
  assert_true(first.cid != second.cid)
  for result in 0..<2 {
    let plan = if result == 0 { first } else { second }
    let measurement = measure_prepared_client_result_plan(
      value, result, 100000, 10000, 100,
    ).unwrap()
    assert_eq(measurement.0, @utf8.encode(plan.wire).length())
    let tree = parse_plan_identity_value(plan.wire, 100000, 10000, 100).unwrap()
    let out = @encode.measuring_writer(100000, 10000, 100)
    @canonical.emit_value(tree, out)
    assert_eq(measurement, @encode.finish_measurement_usage(out))
    guard @canonical.object_field(tree, "projection")
      is Some(@canonical.Array(fields)) &&
      @canonical.array_at(fields, 0) is Some(field) else {
      assert_true(false)
      continue
    }
    assert_true(
      @canonical.object_field(field, "input")
      is Some(@canonical.String("label")),
    )
  }
}

///|
test "execution material geometry uses the original semantic Program and Result names" {
  let value = result_material_prepared()
  let manifests = run_materials_manifests()
  let measurement = measure_prepared_client_execution_material(
    value, manifests, 100000, 10000, 100,
  ).unwrap()
  let compilation = issue_prepared_client_values_compilation(
    value,
    manifests,
    run_materials_limits().sequence,
    32,
    64,
    100000,
    10000,
    100,
  ).unwrap()
  let wire = client_values_executable_plan_wire(compilation.plan)
  let plan = parse_plan_identity_value(wire, 100000, 10000, 100).unwrap()
  guard @canonical.object_field(plan, "execution_material") is Some(material) else {
    assert_true(false)
    return
  }
  let actual = @encode.measuring_writer(100000, 10000, 100)
  @canonical.emit_value(material, actual)
  assert_eq(measurement, @encode.finish_measurement_usage(actual))
  let (bytes, nodes, depth) = measurement
  for
    (b, n, d) in [
      (bytes - 1, nodes, depth),
      (bytes, nodes - 1, depth),
      (bytes, nodes, depth - 1),
    ] {
    assert_true(
      measure_prepared_client_execution_material(value, manifests, b, n, d)
      is Err(Encoding),
    )
  }
}

///|
test "execution material geometry retains multiple requested Result identities" {
  let environment = admit_client_check_environment(
    run_materials_environment_wire,
    run_materials_environment_cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let document =
    #|{"version":"actql/0.1","id":"material-roots","stages":[{"id":"source","inputs":{},"steps":[{"as":"v","values":{"schema":{"id":{"type":"number","nullable":false},"label":{"type":"string","nullable":false}},"rows":[{"id":1,"label":"日本語😀"},{"id":2,"label":"second"}]}}],"results":{"rows":{"from":"v","fields":["label","id"]}}}],"results":{"answer":{"from":{"stage":"source","result":"rows"}},"other":{"from":{"stage":"source","result":"rows"}}}}
  let value = prepare_effect_free_client_program(
    document,
    Json,
    environment,
    None,
    run_materials_limits().preparation,
  ).unwrap()
  let manifests = run_materials_manifests()
  let measurement = measure_prepared_client_execution_material(
    value, manifests, 100000, 10000, 100,
  ).unwrap()
  let compilation = issue_prepared_client_task_compilation(
    value,
    manifests,
    run_materials_limits().sequence,
    32,
    64,
    100000,
    10000,
    100,
  ).unwrap()
  let wire = client_task_executable_plan_wire(compilation.plan)
  let plan = parse_plan_identity_value(wire, 100000, 10000, 100).unwrap()
  guard @canonical.object_field(plan, "execution_material") is Some(material) else {
    assert_true(false)
    return
  }
  let actual = @encode.measuring_writer(100000, 10000, 100)
  @canonical.emit_value(material, actual)
  assert_eq(measurement, @encode.finish_measurement_usage(actual))
}

///|
test "standalone Task material consumes the retained graph before original body measurement" {
  let value = result_material_prepared()
  let manifests = run_materials_manifests()
  let material = issue_prepared_client_task_execution_material(
    value,
    manifests,
    run_materials_limits().sequence,
    100000,
    10000,
    100,
  ).unwrap()
  let measured = measure_prepared_client_execution_material(
    value, manifests, 100000, 10000, 100,
  ).unwrap()
  assert_eq(
    measured,
    (material.wire_bytes, material.wire_nodes, material.wire_depth),
  )
  assert_true(@canonical.object_field(material.body, "program") is Some(_))
  guard @canonical.object_field(material.body, "result_plan_logical_cids")
    is Some(results) else {
    assert_true(false)
    return
  }
  assert_true(
    @canonical.object_field(results, "answer") is Some(@canonical.String(_)),
  )
}
