///|
fn null_array_context(type_name : String) -> String {
  "{\"if\":[{\"literal\":false},{\"empty_array\":{\"items\":{\"type\":\"" +
  type_name +
  "\",\"nullable\":false}}},{\"literal\":null}]}"
}

///|
test "typed NULL ARRAY peers preserve the actual NULL value and IS NULL distinction" {
  for type_name in ["number", "int64", "string", "boolean", "timestamp"] {
    let source = null_array_context(type_name)
    assert_true(run_expr(source) is Ok(Null), msg=type_name)
    assert_true(
      run_expr("{\"is_null\":" + source + "}") is Ok(Boolean(true)),
      msg=type_name,
    )
    let empty = "{\"empty_array\":{\"items\":{\"type\":\"" +
      type_name +
      "\",\"nullable\":false}}}"
    assert_eq(object_result_wire(run_expr(empty).unwrap()), "[]")
    assert_true(
      run_expr("{\"is_null\":" + empty + "}") is Ok(Boolean(false)),
      msg=type_name,
    )
  }
}

///|
test "typed NULL ARRAY membership uses the existing empty-set and exact int64 context" {
  let source = null_array_context("int64")
  for left in ["1", "null", "9007199254740992"] {
    for (op, expected) in [("in", false), ("not_in", true)] {
      assert_true(
        run_expr("{\"" + op + "\":[{\"literal\":" + left + "}," + source + "]}")
        is Ok(Boolean(value)) &&
        value == expected,
      )
    }
  }
}

///|
test "typed NULL ARRAY peers do not erase a NULL element in a nonempty array" {
  let source = "{\"if\":[{\"literal\":true},{\"array\":[{\"literal\":null}]},{\"empty_array\":{\"items\":{\"type\":\"int64\",\"nullable\":false}}}]}"
  assert_eq(object_result_wire(run_expr(source).unwrap()), "[null]")
  for op in ["in", "not_in"] {
    assert_true(
      run_expr("{\"" + op + "\":[{\"literal\":1}," + source + "]}") is Ok(Null),
    )
  }
}

///|
test "typed NULL ARRAY checked machine emission and source re-admission preserve NULL" {
  let original = lowered(null_array_context("int64"))
  let writer = @encode.writer(10000, 1000, 100)
  @lower.emit_expression(original, writer)
  let machine = @encode.finish(writer)
  assert_eq(
    machine, "{\"body\":[{\"body\":false,\"op\":\"literal\"},{\"body\":{\"items\":{\"nullable\":false,\"type\":\"int64\"}},\"op\":\"empty_array\"},{\"body\":{\"contract\":{\"items\":{\"nullable\":false,\"type\":\"int64\"},\"max_items\":0,\"nullable\":true,\"type\":\"array\"}},\"op\":\"typed_null\"}],\"op\":\"if\"}",
  )
  let source = @encode.writer(10000, 1000, 100)
  @lower.emit_expression_source(original, source)
  let readmitted = lowered(@encode.finish(source))
  let second = @encode.writer(10000, 1000, 100)
  @lower.emit_expression(readmitted, second)
  assert_eq(@encode.finish(second), machine)
  assert_true(
    evaluate_expression(readmitted, Map([]), [], {
      remaining: 100000,
      max_frames: 100,
    })
    is Ok(Null),
  )
}
