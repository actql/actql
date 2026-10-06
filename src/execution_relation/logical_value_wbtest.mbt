///|
fn logical_literal(text : String) -> Value {
  let kernel = row_kernel(
    row_owner(",{\"derive\":{\"x\":{\"literal\":" + text + "}}}"),
    1,
  )
  guard @lower.kernel_body(kernel) is @lower.SnapshotMap(bindings) else {
    abort("map")
  }
  guard @lower.expression_body(bindings[0].1) is @lower.Literal(value) else {
    abort("literal")
  }
  capture(value.value)
}

///|
test "logical measures match independent typed wire vectors" {
  for
    (value, weight, bytes) in [
      (Null, 1L, 4),
      (logical_literal("{}"), 1L, 12),
      (logical_literal("{\"x\":1}"), 3L, 17),
      (logical_literal("[1,\"é\"]"), 5L, 18),
      (Text("a\n"), 3L, 5),
      (logical_literal("{\"a\":[true,null]}"), 5L, 27),
      (Text("😀"), 5L, 6),
    ] {
    let got = measure_logical_value(value, weight, bytes, 100, 100).unwrap()
    assert_eq(got.weight, weight)
    assert_eq(got.wire_bytes, bytes)
    assert_true(
      measure_logical_value(value, weight - 1L, bytes, 100, 100)
      is Err(LogicalWorkLimit),
    )
    assert_true(
      measure_logical_value(value, weight, bytes - 1, 100, 100)
      is Err(WireMeasureFailure),
    )
  }
}

///|
test "decimal logical weight counts typed wire scale not coefficient storage" {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"x\":{\"type\":\"decimal\",\"precision\":4,\"scale\":2,\"nullable\":false}},\"rows\":[{\"x\":{\"literal\":\"19.90\"}},{\"x\":{\"literal\":\"0.01\"}},{\"x\":{\"literal\":\"-0.01\"}}]},\"as\":\"seed\"}]",
  )
  let table = row_capture(owner)
  for i, expected in [(6L, 7), (5L, 6), (6L, 7)] {
    let got = measure_logical_value(
      table.rows[i][0],
      expected.0,
      expected.1,
      100,
      100,
    ).unwrap()
    assert_eq((got.weight, got.wire_bytes), expected)
  }
}

///|
test "logical measurement has independent host limits and large safe work allowance" {
  let value = logical_literal("[[1]]")
  assert_true(
    measure_logical_value(value, 100L, 100, 2, 100) is Err(HostMeasureLimit),
  )
  assert_true(
    measure_logical_value(value, 100L, 100, 100, 2) is Err(HostMeasureLimit),
  )
  assert_eq(
    measure_logical_value(value, 9007199254740991L, 100, 100, 100).unwrap().weight,
    3L,
  )
  assert_true(
    measure_logical_value(value, 9007199254740992L, 100, 100, 100)
    is Err(InvalidMeasureLimits),
  )
  let shared = logical_literal("{\"x\":1}")
  let first = measure_logical_value(shared, 3L, 17, 100, 100).unwrap()
  let second = measure_logical_value(shared, 3L, 17, 100, 100).unwrap()
  assert_eq(first.weight + second.weight, 6L)
  assert_eq(first.wire_bytes + second.wire_bytes, 34)
}
