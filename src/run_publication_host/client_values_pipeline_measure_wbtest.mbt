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
