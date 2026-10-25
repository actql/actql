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
