///|
test "upper preserves independent Unicode 16 full-mapping vectors" {
  for
    (input, expected) in [
      ("straße", "STRASSE"),
      ("ẞ", "ẞ"),
      ("ﬃ", "FFI"),
      ("ǳ", "Ǳ"),
      ("ᾀ", "ἈΙ"),
      ("ΐ", "Ϊ́"),
      ("ͅ", "Ι"),
      ("ǰ̣", "J̣̌"),
      ("é", "É"),
      ("é", "É"),
      ("i̇", "İ"),
      ("i I ı İ", "I I I İ"),
      ("σ ς Σ", "Σ Σ Σ"),
      ("𐐨", "𐐀"),
      ("𐵰", "𐵐"),
      ("ᲊ", "Ᲊ"),
      ("日本😀!?", "日本😀!?"),
      ("", ""),
    ] {
    guard run_expr("\"upper('" + input + "')\"") is Ok(Text(actual)) else {
      fail("checked full uppercase expression failed")
    }
    assert_eq(actual, expected)
  }
}

///|
test "upper preserves NULL and lazy demand without interpreting other strings" {
  assert_true(run_expr("\"upper(NULL)\"") is Ok(Null))
  assert_true(run_expr("\"upper('a\\r\\nb')\"") is Ok(Text("A\r\nB")))
  assert_true(
    run_expr("\"if(FALSE, upper(to_string(1 / 0)), 'safe')\"")
    is Ok(Text("safe")),
  )
  assert_true(
    run_expr("\"upper(to_string(1 / 0))\"")
    is Err({ kind: Scalar(ArithmeticFailure), .. }),
  )
}

///|
fn upper_text_expression() -> @lower.Expression {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"payload\":{\"type\":\"string\",\"nullable\":false}},\"rows\":[]},\"as\":\"seed\"},{\"derive\":{\"result\":{\"upper\":{\"field\":\"payload\"}}}}]",
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
fn upper_text_frame(
  logical : LogicalBudget,
  workspace : RowWorkspace,
) -> ExpressionFrame {
  expression_frame(
    upper_text_expression(),
    Map([("payload", Text(String::make(128, 'ΐ')))]),
    [],
    { remaining: 100000, max_frames: 10, },
    workspace,
    Some(expression_roots(logical, 10)),
  ).unwrap()
}

///|
test "upper sizes every expanded scalar with exact independent resource ledgers" {
  // 128 U+0390 scalars: input weight 257/wire 258; output weight 769/wire 770.
  // Two entries + twice the input weight + output weight = 1285 work.
  // Both roots overlap at 1028 bytes; two frame slots + 384 output UTF-16 units.
  for quantum in [1, 7, 256] {
    for failure in 0..<4 {
      let logical = text_expression_budget(
        1285L - (if failure == 1 { 1L } else { 0L }),
        1028L - (if failure == 2 { 1L } else { 0L }),
      )
      let workspace = row_workspace(386 - (if failure == 3 { 1 } else { 0 }))
      let frame = upper_text_frame(logical, workspace)
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
            fail("exact uppercase resource boundary")
          }
          let expected = StringBuilder()
          for _ in 0..<128 {
            expected.write_string("Ϊ́")
          }
          assert_true(value.value is Text(text) && text == expected.to_string())
          assert_eq(
            (logical.work, logical.peak, workspace.peak),
            (1285L, 1028L, 386),
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
test "upper rejects expanded output bytes before allocating the text buffer" {
  let logical = logical_budget(
    {
      max_input_rows: 1L,
      max_value_bytes: 769L,
      max_live_value_bytes: 10000L,
      max_work: 10000L,
    },
    4100,
    10000,
    100,
  ).unwrap()
  let workspace = row_workspace(1000)
  let frame = upper_text_frame(logical, workspace)
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
test "upper cancellation releases sizing and construction state without releasing borrowed roots" {
  for phase in 0..<3 {
    let logical = text_expression_budget(10000L, 10000L)
    let borrowed = retain_logical_value(logical, Number(9)).unwrap()
    let workspace = row_workspace(1000)
    let frame = upper_text_frame(logical, workspace)
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
