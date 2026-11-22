///|
test "text FORMAT uses original Unicode arguments, padding and escaped percent" {
  for
    (source, expected) in [
      ("{\"format_strings\":[{\"literal\":\"%s\"},{\"literal\":\"a\"}]}", "a"),
      (
        "{\"format_strings\":[{\"literal\":\"%-4.2s/%%/%3s\"},{\"literal\":\"x🙂y\"},{\"literal\":\"é\"}]}",
        "x🙂  /%/  é",
      ),
      (
        "{\"format_strings\":[{\"literal\":\"%%%s:%.0s\"},{\"literal\":\"\"},{\"literal\":\"hello\"}]}",
        "%:",
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
test "text FORMAT preserves nullable operands and refuses malformed directives" {
  for
    source in [
      "{\"format_strings\":[{\"literal\":\"%s\"},{\"literal\":null}]}", "{\"format_strings\":[{\"literal\":null},{\"literal\":\"unused\"}]}",
    ] {
    assert_true(run_expr(source) is Ok(Null), msg=source)
  }
  for
    source in [
      "{\"format_strings\":[{\"literal\":\"%d\"},{\"literal\":\"1\"}]}", "{\"format_strings\":[{\"literal\":\"%s\"}]}",
      "{\"format_strings\":[{\"literal\":\"plain\"},{\"literal\":\"extra\"}]}", "{\"format_strings\":[{\"literal\":\"abc%.\"}]}",
    ] {
    assert_true(
      run_expr(source) is Err({ kind: Scalar(InvalidOperand), .. }),
      msg=source,
    )
  }
}

///|
test "text FORMAT admits the complete output before allocating its builder" {
  let expression = lowered(
    "{\"format_strings\":[{\"literal\":\"%12s\"},{\"literal\":\"🙂\"}]}",
  )
  // Eleven space bytes, one four-byte scalar, and two JSON quote bytes.
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
      if frame.state is FormatText(state, _) && state.builder is Some(_) {
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
      assert_true(value.value is Text("           🙂"))
      assert_true(began_building)
      if value.root is Some(root) {
        release_logical_root(budget, root).unwrap()
      }
    }
    close_expression_frame(frame)
    assert_eq((budget.live, frame.workspace.live), (0L, 0))
  }
}
