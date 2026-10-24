///|
test "SQL array offsets retain strict and safe outcomes with eager child demand" {
  for
    (op, index, expected) in [
      ("array_offset", "0", "7"),
      ("array_safe_offset", "0", "7"),
      ("array_safe_offset", "-1", "null"),
      ("array_safe_offset", "1e100", "null"),
      ("array_offset", "null", "null"),
    ] {
    let expression = lowered(
      "{\"" +
      op +
      "\":{\"value\":{\"array\":[{\"literal\":7}]},\"index\":{\"literal\":" +
      index +
      "}}}",
    )
    let result = evaluate_expression(expression, Map([]), [], {
      remaining: 10000,
      max_frames: 100,
    }).unwrap()
    assert_eq(object_result_wire(result), expected)
  }
  for
    (op, index) in [
      ("array_offset", "-1"),
      ("array_offset", "1"),
      ("array_offset", "1e100"),
      ("array_safe_offset", "0.5"),
    ] {
    let expression = lowered(
      "{\"" +
      op +
      "\":{\"value\":{\"array\":[{\"literal\":7}]},\"index\":{\"literal\":" +
      index +
      "}}}",
    )
    assert_true(
      evaluate_expression(expression, Map([]), [], {
        remaining: 10000,
        max_frames: 100,
      })
      is Err({ kind: Scalar(InvalidOperand), .. }),
    )
  }
}

///|
test "SQL array offsets preserve old subscript accounting and cancellation owner" {
  for op in ["subscript", "array_offset", "array_safe_offset"] {
    let source = "{\"" +
      op +
      "\":{\"value\":{\"array\":[{\"literal\":2},{\"literal\":1}]},\"index\":{\"literal\":1}}}"
    for quantum in [1, 7, 256] {
      let logical = test_logical_budget(18L, 1000L)
      let result = resume_test_expression(source, logical, quantum, drain=false).unwrap()
      assert_eq(object_result_wire(result.value), "1")
      release_logical_root(logical, result.root.unwrap()).unwrap()
      assert_eq(logical.work, 18L)
      assert_eq(logical.live, 0L)
    }
  }
}
