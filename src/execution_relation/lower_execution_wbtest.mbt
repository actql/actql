///|
test "lower preserves independent default mappings and original-input sigma context" {
  let expression = lower_text_expression()
  for
    (input, expected) in [
      ("Σ", "σ"),
      ("ΣΣΣ", "σσς"),
      ("AΣ", "aς"),
      ("AΣB", "aσb"),
      ("AΣ Σ", "aς σ"),
      ("ͅΣ", "ͅσ"),
      ("AͅΣ", "aͅς"),
      ("AΣͅ", "aςͅ"),
      ("AΣͅB", "aσͅb"),
      ("ʰΣ", "ʰσ"),
      ("AʰΣ", "aʰς"),
      ("AΣʰ", "aςʰ"),
      ("AΣʰB", "aσʰb"),
      ("AΣ.B", "aσ.b"),
      ("AΣ:B", "aσ:b"),
      ("AΣ'B", "aσ'b"),
      ("AΣ,B", "aς,b"),
      ("AΣ-B", "aς-b"),
      ("A.Σ", "a.ς"),
      ("A,Σ", "a,σ"),
      ("ÁΣ", "áς"),
      ("AΣ́B", "aσ́b"),
      ("AΣ‍B", "aσ‍b"),
      ("🄰Σ", "🄰ς"),
      ("AΣ🄰", "aσ🄰"),
      ("I İ ı i", "i i̇ ı i"),
      ("İ", "i̇"),
      ("Í", "í"),
      ("Ị̇", "ị̇"),
      ("É", "é"),
      ("É", "é"),
      ("ẞ ß ﬃ", "ß ß ﬃ"),
      ("Ꭰ", "ꭰ"),
      ("ǲ", "ǳ"),
      ("Ᲊ", "ᲊ"),
      ("𐐀", "𐐨"),
      ("𐵐", "𐵰"),
      ("日本😀!?\r\n", "日本😀!?\r\n"),
      ("", ""),
    ] {
    guard evaluate_expression(expression, Map([("payload", Text(input))]), [], {
        remaining: 100000,
        max_frames: 10,
      })
      is Ok(Text(actual)) else {
      fail("checked full lowercase expression failed")
    }
    assert_eq(actual, expected)
  }
}

///|
test "lower preserves NULL lazy demand and foreign-domain refusal" {
  assert_true(run_expr("\"lower(NULL)\"") is Ok(Null))
  assert_true(
    run_expr("\"if(FALSE, lower(to_string(1 / 0)), 'safe')\"")
    is Ok(Text("safe")),
  )
  assert_true(
    run_expr("\"lower(to_string(1 / 0))\"")
    is Err({ kind: Scalar(ArithmeticFailure), .. }),
  )
  for value in [Number(9), Boolean(true)] {
    assert_true(
      evaluate_expression(
        lower_text_expression(),
        Map([("payload", value)]),
        [],
        { remaining: 10000, max_frames: 10, },
      )
      is Err({ kind: Scalar(InvalidOperand), .. }),
    )
  }
}

///|
fn lower_text_expression() -> @lower.Expression {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"payload\":{\"type\":\"string\",\"nullable\":false}},\"rows\":[]},\"as\":\"seed\"},{\"derive\":{\"result\":{\"lower\":{\"field\":\"payload\"}}}}]",
  )
  @lower.lower_expression(owner, 1, 0, {
    max_nodes: 100,
    max_work: 10000,
    max_depth: 20,
    max_literal_nodes: 100,
    max_literal_text_bytes: 10000,
  }).unwrap()
}

///|
fn lower_text_frame(
  logical : LogicalBudget,
  workspace : RowWorkspace,
  input? : String = String::make(128, 'İ'),
) -> ExpressionFrame {
  expression_frame(
    lower_text_expression(),
    Map([("payload", Text(input))]),
    [],
    { remaining: 100000, max_frames: 10, },
    workspace,
    Some(expression_roots(logical, 10)),
  ).unwrap()
}

///|
test "lower sizes every expanded scalar with exact independent resource ledgers" {
  // 128 U+0130 scalars: input weight 257/wire 258; output weight 385/wire 386.
  // Two entries + twice the input weight + output weight = 901 work.
  // Both roots overlap at 644 bytes; two frame slots + 256 output UTF-16 units.
  for quantum in [1, 7, 256] {
    for failure in 0..<4 {
      let logical = text_expression_budget(
        901L - (if failure == 1 { 1L } else { 0L }),
        644L - (if failure == 2 { 1L } else { 0L }),
      )
      let workspace = row_workspace(258 - (if failure == 3 { 1 } else { 0 }))
      let frame = lower_text_frame(logical, workspace)
      let mut result : Result[EvaluatedValue?, EvalIssue] = Ok(None)
      let mut polls = 0
      while polls < 10000 && result is Ok(None) {
        for _ in 0..<quantum {
          let before = frame.budget.remaining
          result = advance_expression_frame(frame)
          assert_true(before - frame.budget.remaining <= 64)
          polls += 1
          if !(result is Ok(None)) {
            break
          }
        }
      }
      match failure {
        0 => {
          guard result is Ok(Some(value)) else {
            fail("exact lowercase resource boundary")
          }
          let expected = StringBuilder()
          for _ in 0..<128 {
            expected.write_string("i̇")
          }
          assert_true(value.value is Text(text) && text == expected.to_string())
          assert_eq(
            (logical.work, logical.peak, workspace.peak),
            (901L, 644L, 258),
          )
          release_logical_root(logical, value.root.unwrap()).unwrap()
        }
        1 =>
          assert_true(
            result
            is Err({ kind: LogicalValue(ValueMeasure(LogicalWorkLimit)), .. }),
          )
        2 =>
          assert_true(result is Err({ kind: LogicalValue(LiveValueLimit), .. }))
        3 => assert_true(result is Err({ kind: WorkspaceLimit, .. }))
        _ => fail("unknown boundary case")
      }
      assert_eq((logical.live, workspace.live), (0L, 0))
    }
  }
}

///|
test "lower rejects expanded output bytes before allocating the text buffer" {
  let logical = logical_budget(
    {
      max_input_rows: 1L,
      max_value_bytes: 385L,
      max_live_value_bytes: 10000L,
      max_work: 10000L,
    },
    4100,
    10000,
    100,
  ).unwrap()
  let workspace = row_workspace(1000)
  let frame = lower_text_frame(logical, workspace)
  let mut result : Result[EvaluatedValue?, EvalIssue] = Ok(None)
  for _ in 0..<10000 {
    if frame.state is TextFunction(state) {
      assert_false(state.building)
      assert_true(state.builder is None)
      assert_eq(state.allocated, 0)
    }
    result = advance_expression_frame(frame)
    if !(result is Ok(None)) {
      break
    }
  }
  assert_true(
    result is Err({ kind: LogicalValue(ValueMeasure(WireMeasureFailure)), .. }),
  )
  assert_eq((logical.live, workspace.live), (0L, 0))
}

///|
test "lower cancellation releases sizing and construction state without releasing borrowed roots" {
  for phase in 0..<3 {
    let logical = text_expression_budget(10000L, 10000L)
    let borrowed = retain_logical_value(logical, Number(9)).unwrap()
    let workspace = row_workspace(1000)
    let frame = lower_text_frame(logical, workspace)
    let mut reached = false
    for _ in 0..<10000 {
      assert_true(advance_expression_frame(frame) is Ok(None))
      if frame.state is TextFunction(state) &&
        (if phase == 0 {
          !state.building && state.emitting && state.emission > 0
        } else if phase == 1 {
          state.building && state.position == 0
        } else {
          state.building &&
          state.position > 32 &&
          state.emitting &&
          state.emission > 0
        }) {
        reached = true
        break
      }
    }
    assert_true(reached)
    let consumed = logical.work
    close_expression_frame(frame)
    close_expression_frame(frame)
    assert_eq(
      (logical.work, logical.live, workspace.live),
      (consumed, borrowed.bytes, 0),
    )
    assert_false(borrowed.released)
    assert_true(
      advance_expression_frame(frame) is Err({ kind: InvalidControlLimits, .. }),
    )
    release_logical_root(logical, borrowed).unwrap()
    assert_eq(logical.live, 0L)
  }
}

///|
test "lower sigma lookahead yields linearly without duplicating semantic work" {
  for quantum in [1, 7, 256] {
    for
      (copies, marks, suffix) in [
        (1, 64, ""),
        (2, 64, ""),
        (4, 64, ""),
        (8, 64, ""),
        (64, 16, ""),
        (64, 16, "B"),
        (64, 16, ","),
      ] {
      let input = StringBuilder()
      let expected = StringBuilder()
      input.write_string("A")
      expected.write_string("a")
      for index in 0..<copies {
        input.write_string("Σ")
        expected.write_string(
          if index + 1 == copies && suffix != "B" {
            "ς"
          } else {
            "σ"
          },
        )
        for _ in 0..<marks {
          input.write_string("́")
          expected.write_string("́")
        }
      }
      input.write_string(suffix)
      expected.write_string(if suffix == "B" { "b" } else { suffix })
      // ASCII prefix/suffix, two-byte sigmas and two-byte combining marks.
      let units = 1 + copies * (1 + marks) + suffix.length()
      let weight = (2 + copies * (2 + 2 * marks) + suffix.length()).to_int64()
      let logical = text_expression_budget(2L + 3L * weight, 2L * (weight + 1L))
      let workspace = row_workspace(2 + units)
      let frame = lower_text_frame(logical, workspace, input=input.to_string())
      let mut result : Result[EvaluatedValue?, EvalIssue] = Ok(None)
      let mut saw_sizing_probe = false
      let mut saw_building_probe = false
      let mut polls = 0
      while polls < 20000 && result is Ok(None) {
        for _ in 0..<quantum {
          let before = frame.budget.remaining
          let probe_before = match frame.state {
            TextFunction(state) if state.probing_sigma =>
              Some(state.probe_position)
            _ => None
          }
          result = advance_expression_frame(frame)
          assert_true(before - frame.budget.remaining <= 64)
          if frame.state is TextFunction(state) && state.probing_sigma {
            if probe_before is Some(offset) {
              // These probe scalars are single UTF-16-unit acute marks.
              assert_true(state.probe_position - offset <= 1)
            }
            if state.building {
              saw_building_probe = true
            } else {
              saw_sizing_probe = true
            }
          }
          polls += 1
          if !(result is Ok(None)) {
            break
          }
        }
      }
      guard result is Ok(Some(value)) else {
        fail("bounded final-sigma traversal")
      }
      assert_true(value.value is Text(text) && text == expected.to_string())
      assert_true(saw_sizing_probe && saw_building_probe)
      assert_true(100000 - frame.budget.remaining <= 32 * units + 128)
      assert_eq(
        (logical.work, logical.peak, workspace.peak),
        (2L + 3L * weight, 2L * (weight + 1L), 2 + units),
      )
      release_logical_root(logical, value.root.unwrap()).unwrap()
      assert_eq((logical.live, workspace.live), (0L, 0))
    }
  }
}

///|
test "lower sigma probes preserve caller roots on cancellation and control exhaustion" {
  for building in [false, true] {
    for exhaust in [false, true] {
      let logical = text_expression_budget(10000L, 10000L)
      let borrowed = retain_logical_value(logical, Number(9)).unwrap()
      let workspace = row_workspace(1000)
      let frame = lower_text_frame(
        logical,
        workspace,
        input="AΣ" + String::make(128, '́'),
      )
      let mut reached = false
      for _ in 0..<10000 {
        assert_true(advance_expression_frame(frame) is Ok(None))
        if frame.state is TextFunction(state) &&
          state.building == building &&
          state.probing_sigma &&
          state.probe_position == 66 {
          reached = true
          break
        }
      }
      assert_true(reached)
      let consumed = logical.work
      if exhaust {
        frame.budget.remaining = 0
        assert_true(
          advance_expression_frame(frame) is Err({ kind: ControlLimit, .. }),
        )
      }
      close_expression_frame(frame)
      close_expression_frame(frame)
      assert_eq(
        (logical.work, logical.live, workspace.live),
        (consumed, borrowed.bytes, 0),
      )
      assert_false(borrowed.released)
      release_logical_root(logical, borrowed).unwrap()
      assert_eq(logical.live, 0L)
    }
  }
}
