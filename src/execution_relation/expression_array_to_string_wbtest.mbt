///|
test "array to string skips or replaces NULL elements with original scalar bytes" {
  for
    (source, expected) in [
      (
        "{\"array_to_string\":[{\"array\":[{\"literal\":null},{\"literal\":\"e\\u0301\"},{\"literal\":null},{\"literal\":\"😀\"},{\"literal\":null}]},{\"literal\":\"/\\u0000\"}]}",
        "e\u{0301}/\u0000😀",
      ),
      (
        "{\"array_to_string\":[{\"array\":[{\"literal\":null},{\"literal\":\"\"},{\"literal\":null}]},{\"literal\":\",\"},{\"literal\":\"missing\"}]}",
        "missing,,missing",
      ),
      ("{\"array_to_string\":[{\"array\":[]},{\"literal\":\",\"}]}", ""),
      (
        "{\"array_to_string\":[{\"array\":[{\"literal\":null}]},{\"literal\":\",\"}]}",
        "",
      ),
    ] {
    let budget = test_logical_budget(10000L, 10000L)
    let workspace = row_workspace(1000)
    assert_true(
      evaluate_expression_with_workspace(
        lowered(source),
        {},
        [],
        { remaining: 1000, max_frames: 100, },
        workspace,
        logical_work=Some(budget),
      )
      is Ok(Text(result)) &&
      result == expected,
      msg=source,
    )
    assert_eq((budget.live, workspace.live), (0L, 0))
  }
}

///|
test "array to string distinguishes a NULL argument from an omitted replacement" {
  for
    source in [
      "{\"array_to_string\":[{\"literal\":null},{\"literal\":\",\"}]}", "{\"array_to_string\":[{\"array\":[{\"literal\":\"a\"}]},{\"literal\":null}]}",
      "{\"array_to_string\":[{\"array\":[{\"literal\":\"a\"}]},{\"literal\":\",\"},{\"literal\":null}]}",
    ] {
    assert_true(run_expr(source) is Ok(Null), msg=source)
  }
  let later_failure = "{\"array_to_string\":[{\"literal\":null},{\"cast\":{\"value\":{\"divide\":[{\"literal\":1},{\"literal\":0}]},\"target\":{\"type\":\"string\"}}}]}"
  assert_true(
    run_expr(later_failure) is Err({ kind: Scalar(ArithmeticFailure), .. }),
  )
}

///|
test "array to string cancels a partially built result and preserves the caller root" {
  let expression = lowered(
    "{\"array_to_string\":[{\"array\":[{\"literal\":\"hello\"},{\"literal\":\"world\"}]},{\"literal\":\",\"}]}",
  )
  let budget = test_logical_budget(10000L, 10000L)
  let caller = retain_logical_value(budget, Number(8.0)).unwrap()
  let frame = expression_frame(
    expression,
    {},
    [],
    { remaining: 1000, max_frames: 100, },
    row_workspace(120),
    Some(expression_roots(budget, 120)),
  ).unwrap()
  let mut reached = false
  for _ in 0..<200 {
    assert_true(advance_expression_frame(frame) is Ok(None))
    if frame.state is ArrayTextJoin(state, _) &&
      state.builder is Some(_) &&
      state.position > 0 {
      reached = true
      break
    }
  }
  assert_true(reached)
  let charged = budget.work
  close_expression_frame(frame)
  assert_eq((budget.live, frame.workspace.live, budget.work), (1L, 0, charged))
  assert_false(caller.released)
  release_logical_root(budget, caller).unwrap()
}

///|
test "array to string checks the complete output allowance before building" {
  let expression = lowered(
    "{\"array_to_string\":[{\"array\":[{\"literal\":\"a\"},{\"literal\":\"b\"},{\"literal\":\"c\"}]},{\"literal\":\"------\"}]}",
  )
  // Inputs need 13 and 8 wire bytes. The result needs 17, including quotes.
  for limit in [16L, 17L] {
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
    let mut began_building = false
    for _ in 0..<300 {
      result = advance_expression_frame(frame)
      if frame.state is ArrayTextJoin(state, _) && state.builder is Some(_) {
        began_building = true
      }
      if !(result is Ok(None)) {
        break
      }
    }
    if limit == 16L {
      assert_true(
        result
        is Err({ kind: LogicalValue(ValueMeasure(WireMeasureFailure)), .. }),
      )
      assert_false(began_building)
    } else {
      guard result is Ok(Some(value)) else {
        fail("exact result extent was not admitted")
      }
      assert_true(value.value is Text("a------b------c"))
      assert_true(began_building)
      if value.root is Some(root) {
        release_logical_root(budget, root).unwrap()
      }
    }
    close_expression_frame(frame)
    assert_eq((budget.live, frame.workspace.live), (0L, 0))
  }
}
