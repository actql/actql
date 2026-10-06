///|
test "common lowering executes independent REPLACE and Unicode LENGTH expressions" {
  assert_true(
    run_expr("\"replace('banana', 'ana', 'X')\"").unwrap() is Text("bXna"),
  )
  assert_true(run_expr("\"len('é😀')\"").unwrap() is Number(3.0))
}

///|
test "Text calls preserve NULL eager demand nonoverlap and raw Unicode" {
  for
    (source, expected) in [
      ("replace('aaaaa','aa','X')", Text("XXa")),
      ("replace('abc','','X')", Text("abc")),
      ("replace('abc','b','')", Text("ac")),
      ("replace('😀é😀','😀','é')", Text("ééé")),
      ("replace('a\\r\\nb','a','é')", Text("é\r\nb")),
      ("replace(NULL,'a','b')", Null),
      ("replace('a',NULL,'b')", Null),
      ("replace('a','b',NULL)", Null),
      ("len('')", Number(0.0)),
      ("len(NULL)", Null),
      ("len('é')", Number(1.0)),
      ("len('é')", Number(2.0)),
      ("len('😀')", Number(1.0)),
    ] {
    let actual = run_expr("\"" + source + "\"").unwrap()
    match (actual, expected) {
      (Text(a), Text(b)) => assert_eq(a, b)
      (Number(a), Number(b)) => assert_eq(a, b)
      (Null, Null) => ()
      _ => fail("Text call returned the wrong kind")
    }
  }
  assert_true(
    run_expr("\"replace(NULL, 'x', to_string(1 / 0))\"")
    is Err({ kind: Scalar(ArithmeticFailure), .. }),
  )
}

///|
fn borrowed_text_function(replace : Bool) -> @lower.Expression {
  let body = if replace {
    "{\"replace\":[{\"field\":\"payload\"},{\"literal\":\"a\"},{\"literal\":\"bb\"}]}"
  } else {
    "{\"len\":{\"field\":\"payload\"}}"
  }
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"payload\":{\"type\":\"string\",\"nullable\":false}},\"rows\":[]},\"as\":\"seed\"},{\"derive\":{\"result\":" +
    body +
    "}}]",
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
test "long literal match candidates yield inside a shared prefix" {
  let needle = String::make(128, 'a') + "b"
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"payload\":{\"type\":\"string\",\"nullable\":false}},\"rows\":[]},\"as\":\"seed\"},{\"derive\":{\"result\":{\"replace\":[{\"field\":\"payload\"},{\"literal\":\"" +
    needle +
    "\"},{\"literal\":\"X\"}]}}}]",
  )
  let expression = @lower.lower_expression(owner, 1, 0, {
    max_nodes: 100,
    max_work: 10000,
    max_depth: 20,
    max_literal_nodes: 100,
    max_literal_text_bytes: 10000,
  }).unwrap()
  let logical = text_expression_budget(10000L, 10000L)
  let workspace = row_workspace(1000)
  let frame = expression_frame(
    expression,
    Map([("payload", Text(String::make(256, 'a')))]),
    [],
    { remaining: 100000, max_frames: 10, },
    workspace,
    Some(expression_roots(logical, 10)),
  ).unwrap()
  let mut reached = false
  for _ in 0..<10000 {
    assert_true(advance_expression_frame(frame) is Ok(None))
    if frame.state is TextFunction(state) && state.matched == 64 {
      assert_eq(state.position, 0)
      assert_eq(state.units, 0)
      reached = true
      break
    }
  }
  assert_true(reached)
  close_expression_frame(frame)
  assert_eq((logical.live, workspace.live), (0L, 0))
}

///|
test "Unicode LENGTH can stop after scalar progress without losing borrowed input" {
  let logical = text_expression_budget(10000L, 10000L)
  let borrowed = retain_logical_value(logical, Number(9)).unwrap()
  let workspace = row_workspace(100)
  let frame = text_function_frame(false, logical, workspace)
  let mut reached = false
  for _ in 0..<10000 {
    assert_true(advance_expression_frame(frame) is Ok(None))
    if frame.state is TextFunction(state) && state.count == 64 {
      reached = true
      break
    }
  }
  assert_true(reached)
  let work = logical.work
  close_expression_frame(frame)
  close_expression_frame(frame)
  assert_eq(
    (logical.work, logical.live, workspace.live),
    (work, borrowed.bytes, 0),
  )
  assert_false(borrowed.released)
  release_logical_root(logical, borrowed).unwrap()
}

///|
fn text_function_frame(
  replace : Bool,
  logical : LogicalBudget,
  workspace : RowWorkspace,
) -> ExpressionFrame {
  expression_frame(
    borrowed_text_function(replace),
    Map([("payload", Text(String::make(256, 'a')))]),
    [],
    { remaining: 100000, max_frames: 10, },
    workspace,
    Some(expression_roots(logical, 10)),
  ).unwrap()
}

///|
test "Text function exact work live bytes and workspace use independent ledgers" {
  // LENGTH: two entries + twice the input weight 257 + numeric result 1.
  // REPLACE: four entries + twice (257 + 2 + 3) + output weight 513.
  // Input roots are 258 + 3 + 4 bytes; pending output is 514 bytes.
  // Replace keeps 12 fixed slots and 512 output UTF-16 units. A long child
  // measures under ten parent slots, so its separate peak is only twenty.
  for
    (replace, work, live, slots) in [
      (false, 517L, 258L, 11),
      (true, 1041L, 779L, 524),
    ] {
    for quantum in [1, 7, 256] {
      for failure in 0..<4 {
        let logical = text_expression_budget(
          work - (if failure == 1 { 1L } else { 0L }),
          live - (if failure == 2 { 1L } else { 0L }),
        )
        let workspace = row_workspace(
          slots - (if failure == 3 { 1 } else { 0 }),
        )
        let frame = text_function_frame(replace, logical, workspace)
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
            guard result is Ok(Some(value)) else { fail("exact Text boundary") }
            if replace {
              assert_true(
                value.value is Text(text) && text == String::make(512, 'b'),
              )
            } else {
              assert_true(value.value is Number(256.0))
            }
            assert_eq(
              (logical.work, logical.peak, workspace.peak),
              (work, live, slots),
            )
            release_logical_root(logical, value.root.unwrap()).unwrap()
          }
          1 =>
            assert_true(
              result
              is Err({ kind: LogicalValue(ValueMeasure(LogicalWorkLimit)), .. }),
            )
          2 =>
            assert_true(
              result is Err({ kind: LogicalValue(LiveValueLimit), .. }),
            )
          3 => assert_true(result is Err({ kind: WorkspaceLimit, .. }))
          _ => fail("unknown Text boundary")
        }
        assert_eq((logical.live, workspace.live), (0L, 0))
      }
    }
  }
}

///|
test "Text frame stops in matching sizing and output construction without replay" {
  for phase in 0..<3 {
    let logical = text_expression_budget(10000L, 10000L)
    let borrowed = retain_logical_value(logical, Number(9)).unwrap()
    let workspace = row_workspace(1000)
    let frame = text_function_frame(true, logical, workspace)
    let mut reached = false
    for _ in 0..<10000 {
      assert_true(advance_expression_frame(frame) is Ok(None))
      if frame.state is TextFunction(state) &&
        (if phase == 0 {
          state.emitting
        } else if phase == 1 {
          !state.building && state.units > 32
        } else {
          state.building && state.position > 32
        }) {
        reached = true
        break
      }
    }
    assert_true(reached)
    let work = logical.work
    close_expression_frame(frame)
    close_expression_frame(frame)
    assert_eq(
      (logical.work, logical.live, workspace.live),
      (work, borrowed.bytes, 0),
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
test "REPLACE rejects output bytes before allocating its Text buffer" {
  let logical = logical_budget(
    {
      max_input_rows: 1L,
      max_value_bytes: 513L,
      max_live_value_bytes: 10000L,
      max_work: 10000L,
    },
    4100,
    10000,
    100,
  ).unwrap()
  let workspace = row_workspace(1000)
  let frame = text_function_frame(true, logical, workspace)
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
  assert_eq((logical.live, workspace.live, workspace.peak), (0L, 0, 20))
}
