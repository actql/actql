///|
test "TO_JSON_STRING preserves original scalar domains and SQL null semantics" {
  for
    (operand, output) in [
      ("{\"literal\":1}", "1"),
      ("{\"literal\":null}", "null"),
      ("{\"literal\":false}", "false"),
      (
        "{\"typed_literal\":{\"type\":\"json\",\"value\":\"[null,1]\"}}", "[null,1]",
      ),
      ("{\"typed_literal\":{\"type\":\"json\",\"value\":\"null\"}}", "null"),
      (
        "{\"literal\":\"e\\u0301🙂\\n\\u0000\\\"\"}", "\"e\u{0301}🙂\\n\\u0000\\\"\"",
      ),
      (
        "{\"cast\":{\"value\":{\"literal\":\"9007199254740992\"},\"target\":{\"type\":\"int64\"}}}",
        "9007199254740992",
      ),
      (
        "{\"cast\":{\"value\":{\"literal\":\"-9007199254740993\"},\"target\":{\"type\":\"int64\"}}}",
        "\"-9007199254740993\"",
      ),
      (
        "{\"cast\":{\"value\":{\"literal\":\"3.000\"},\"target\":{\"type\":\"decimal\",\"precision\":8,\"scale\":3}}}",
        "3",
      ),
      (
        "{\"cast\":{\"value\":{\"literal\":\"0.125\"},\"target\":{\"type\":\"decimal\",\"precision\":8,\"scale\":3}}}",
        "\"0.125\"",
      ),
    ] {
    let source = "{\"to_json_string\":[" + operand + "]}"
    assert_true(
      run_expr(source) is Ok(Text(text)) && text == output,
      msg=source,
    )
  }
  let null_flag = "{\"to_json_string\":[{\"literal\":1},{\"literal\":null}]}"
  assert_true(run_expr(null_flag) is Ok(Null))
  let failed_value = "{\"to_json_string\":[{\"divide\":[{\"literal\":1},{\"literal\":0}]},{\"literal\":null}]}"
  assert_true(
    run_expr(failed_value) is Err({ kind: Scalar(ArithmeticFailure), .. }),
  )
}

///|
test "TO_JSON_STRING retains array order and original object values in compact and pretty output" {
  let operand = "{\"object\":{\"b\":{\"array\":[{\"literal\":1},{\"literal\":2}]},\"a\":{\"literal\":true}}}"
  for
    (pretty, expected) in [
      (false, "{\"a\":true,\"b\":[1,2]}"),
      (true, "{\n  \"a\": true,\n  \"b\": [\n    1,\n    2\n  ]\n}"),
    ] {
    let source = "{\"to_json_string\":[" +
      operand +
      ",{\"literal\":" +
      pretty.to_string() +
      "}]}"
    assert_true(
      run_expr(source) is Ok(Text(text)) && text == expected,
      msg=source,
    )
  }
}

///|
test "TO_JSON_STRING checks both escape layers before allocating its output" {
  let expression = lowered(
    "{\"to_json_string\":[{\"object\":{\"label\":{\"literal\":\"🙂\"}}}]}",
  )
  for limit in [21L, 22L] {
    let budget = logical_budget(
      {
        max_input_rows: 1L,
        max_value_bytes: limit,
        max_live_value_bytes: 100L,
        max_work: 10000L,
      },
      100,
      100,
      100,
    ).unwrap()
    let frame = expression_frame(
      expression,
      {},
      [],
      { remaining: 1000, max_frames: 100, },
      row_workspace(120),
      Some(expression_roots(budget, 120)),
    ).unwrap()
    let mut result = Ok(None)
    let mut built = false
    for _ in 0..<300 {
      result = advance_expression_frame(frame)
      if frame.state is SqlJsonText(state, _) && state.builder is Some(_) {
        built = true
      }
      if !(result is Ok(None)) {
        break
      }
    }
    if limit == 21L {
      assert_true(
        result
        is Err({ kind: LogicalValue(ValueMeasure(WireMeasureFailure)), .. }),
      )
      assert_false(built)
    } else {
      guard result is Ok(Some(output)) else {
        fail("exact second escape extent refused")
      }
      assert_true(output.value is Text("{\"label\":\"🙂\"}"))
      assert_true(built)
      if output.root is Some(root) {
        release_logical_root(budget, root).unwrap()
      }
    }
    close_expression_frame(frame)
    assert_eq((budget.live, frame.workspace.live), (0L, 0))
  }
}
