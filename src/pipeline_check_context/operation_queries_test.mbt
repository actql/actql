///|
fn query_fixture(query : String, supplied : String) -> ProgramOperationRanges {
  let parameters = "{\"p\":{\"type\":\"string\",\"default\":\"x\"},\"n\":{\"type\":\"array\",\"items\":{\"type\":\"number\"},\"default\":[1,2]}}"
  let steps = "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"embedding\":{\"type\":\"vector\",\"dimensions\":2,\"nullable\":false}},\"rows\":[{\"id\":1,\"embedding\":[1,0]}]},\"as\":\"seed\"},{\"derive\":{\"p\":\"$p\",\"n_copy\":\"$n\"}},{\"to_vectors\":{\"id\":\"id\",\"vector\":\"embedding\"}},{\"score_vectors\":{\"query\":" +
    query +
    ",\"metric\":\"dot\"}}]"
  let requirements = operation_order_fixture(
    steps,
    parameters~,
    supplied=Some(cursor("{\"n\":" + supplied + "}")),
    veca=true,
  )
  let orders = link_program_operation_orders(requirements, 10000000, 100).unwrap()
  let scalars = check_program_operation_scalars(orders, 10000000, 100).unwrap()
  let frames = check_program_operation_frames(scalars, 10000000, 100).unwrap()
  let fills = check_program_operation_fills(frames, 10000000, 100).unwrap()
  check_program_operation_ranges(fills, 10000000, 100).unwrap()
}

///|
test "bound vector queries retain components ownership and shared dimension resolution" {
  for values in ["[1,2]", "[0,0]", "[-1,0.5]", "[1e300,5e-324]"] {
    let ranges = query_fixture("{\"$param\":\"n\"}", values)
    let result = check_program_operation_queries(ranges, 10000000, 6).unwrap()
    assert_eq(operation_queries_count(result), 6)
    assert_true(physical_equal(operation_queries_ranges(result), ranges))
    for i in 0..<3 {
      let a = operation_query_resolution_at(result, i * 2).unwrap()
      let b = operation_query_resolution_at(result, i * 2 + 1).unwrap()
      assert_true(physical_equal(a.query, b.query))
      assert_eq(operation_query_count(a.query), 2)
      let symbolic = @vector.query(operation_query_operation(a.query)).unwrap()
      assert_true(@vector.query_value_count(symbolic) is None)
      assert_true(@vector.query_value_at(symbolic, 0) is None)
      let parameter = operation_query_parameter(a.query).unwrap()
      assert_eq(parameter.name, "n")
      assert_true(parameter.origin is Supplied)
      guard parameter.value.value is @value.Array(elements) else {
        abort("array")
      }
      for j in 0..<2 {
        guard @value.element_at(elements, j).unwrap() is @value.Number(n) else {
          abort("number")
        }
        assert_eq(operation_query_at(a.query, j), Some(n))
      }
      assert_true(operation_query_at(a.query, -1) is None)
      assert_true(operation_query_at(a.query, 2) is None)
      if i > 0 {
        assert_true(
          !physical_equal(
            a.query,
            operation_query_resolution_at(result, 0).unwrap().query,
          ),
        )
      }
    }
    let work = operation_queries_work(result)
    assert_true(check_program_operation_queries(ranges, work, 6) is Ok(_))
    assert_true(
      check_program_operation_queries(ranges, work - 1, 6)
      is Err(BudgetExceeded),
    )
    assert_true(
      check_program_operation_queries(ranges, work, 5) is Err(BudgetExceeded),
    )
    assert_true(
      check_program_operation_queries(ranges, -1, 6) is Err(InvalidLimits),
    )
    assert_true(
      check_program_operation_queries(ranges, work, -1) is Err(InvalidLimits),
    )
    assert_true(operation_query_resolution_at(result, -1) is None)
    assert_true(operation_query_resolution_at(result, 6) is None)
  }
}

///|
test "empty and mismatched bound queries fail even when array declaration is valid" {
  for (values, count) in [("[]", 0), ("[1]", 1), ("[1,2,3]", 3)] {
    let ranges = query_fixture("{\"$param\":\"n\"}", values)
    let result = check_program_operation_queries(ranges, 10000000, 100)
    if count == 0 {
      assert_true(result is Err(InvalidQuery(_)))
    } else {
      guard result is Err(DimensionMismatch(_, expected, actual)) else {
        abort("dimensions")
      }
      assert_eq(expected, 2.0)
      assert_eq(actual, count)
    }
  }
}

///|
test "literal query indexed reads share the same admission without a Parameter owner" {
  let ranges = query_fixture("[3,4]", "[1,2]")
  let result = check_program_operation_queries(ranges, 10000000, 3).unwrap()
  assert_eq(operation_queries_count(result), 3)
  for i in 0..<3 {
    let q = operation_query_resolution_at(result, i).unwrap().query
    assert_true(operation_query_parameter(q) is None)
    assert_eq(operation_query_at(q, 0), Some(3.0))
    assert_eq(operation_query_at(q, 1), Some(4.0))
    let literal = @vector.query(operation_query_operation(q)).unwrap()
    assert_eq(@vector.query_value_count(literal), Some(2))
    let copied = @vector.query_values(literal).unwrap()
    copied[0] = 99.0
    assert_eq(@vector.query_value_at(literal, 0), Some(3.0))
    assert_true(@vector.query_value_at(literal, -1) is None)
    assert_true(@vector.query_value_at(literal, 2) is None)
  }
}
