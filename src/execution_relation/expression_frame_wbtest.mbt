///|
// Suspension granularity is not a batch kernel. These tests establish that the
// extracted semantic transition boundary does not reset or replay accounting.
fn resume_test_expression(
  source : String,
  logical : LogicalBudget,
  quantum : Int,
) -> Result[EvaluatedValue, EvalIssue] {
  let frame = expression_frame(
    lowered(source),
    Map([]),
    [],
    { remaining: 10000, max_frames: 100, },
    { limit: 10000, live: 0, peak: 0, },
    Some(expression_roots(logical, 100)),
  ).unwrap()
  while true {
    for _i in 0..<quantum {
      match advance_expression_frame(frame) {
        Ok(None) => ()
        Ok(Some(value)) => return Ok(value)
        Err(issue) => return Err(issue)
      }
    }
  } nobreak {
    Err({ kind: ControlLimit, expression: frame.root, })
  }
}

///|
test "frame suspension preserves independent lazy and arithmetic work vectors" {
  for
    (source, expected, work) in [
      ("\"if(TRUE, 7, 1 / 0)\"", 7.0, 8L),
      ("\"coalesce(NULL, 7, 1 / 0)\"", 7.0, 8L),
      ("\"-(1 + 2)\"", -3.0, 11L),
      (
        "\"CASE WHEN FALSE THEN 1 / 0 WHEN TRUE THEN 7 ELSE 1 / 0 END\"", 7.0, 11L,
      ),
    ] {
    for quantum in [1, 7, 1000] {
      let b = test_logical_budget(work, 100L)
      let value = resume_test_expression(source, b, quantum).unwrap()
      assert_true(value.value is Number(n) && n == expected)
      assert_eq(b.work, work)
      assert_false(b.failed)
      release_logical_root(b, value.root.unwrap()).unwrap()
      assert_eq(b.live, 0L)
      let short = test_logical_budget(work - 1L, 100L)
      assert_true(
        resume_test_expression(source, short, quantum)
        is Err({ kind: LogicalValue(ValueMeasure(LogicalWorkLimit)), .. }),
      )
      assert_true(short.failed)
      assert_eq(short.live, 0L)
    }
  }
}

///|
test "frame close releases retained operands without releasing caller roots" {
  let b = test_logical_budget(100L, 100L)
  let borrowed = retain_logical_value(b, Number(9)).unwrap()
  let frame = expression_frame(
    lowered("\"1 + (2 + 3)\""),
    Map([]),
    [],
    { remaining: 10000, max_frames: 100, },
    { limit: 10000, live: 0, peak: 0, },
    Some(expression_roots(b, 100)),
  ).unwrap()
  // Enter binary, enter left literal, return left and retain it across RHS.
  for _i in 0..<3 {
    assert_true(advance_expression_frame(frame) is Ok(None))
  }
  assert_eq(b.live, 2L)
  let work = b.work
  close_expression_frame(frame)
  assert_eq((b.live, b.work), (1L, work))
  assert_false(borrowed.released)
  assert_eq(frame.stack.length(), 0)
  assert_true(frame.current_root is None)
  assert_true(
    advance_expression_frame(frame) is Err({ kind: InvalidControlLimits, .. }),
  )
  assert_eq((b.live, b.work), (1L, work))
  close_expression_frame(frame)
  release_logical_root(b, borrowed).unwrap()
  assert_eq(b.live, 0L)
}

///|
test "frame failure is terminal and preserves eager failure and budget priority" {
  for quantum in [1, 7, 1000] {
    let b = test_logical_budget(100L, 100L)
    assert_true(
      resume_test_expression("\"FALSE AND (1 / 0 > 0)\"", b, quantum)
      is Err({ kind: Scalar(ArithmeticFailure), .. }),
    )
    assert_eq((b.work, b.live), (12L, 0L))
    let capped = test_logical_budget(1L, 100L)
    assert_true(
      resume_test_expression("\"FALSE AND (1 / 0 > 0)\"", capped, quantum)
      is Err({ kind: LogicalEntry(WorkLimit), .. }),
    )
    assert_eq(capped.live, 0L)
    assert_true(capped.failed)
  }
  let b = test_logical_budget(100L, 100L)
  let frame = expression_frame(
    lowered("\"7\""),
    Map([]),
    [],
    { remaining: 10000, max_frames: 100, },
    { limit: 10000, live: 0, peak: 0, },
    Some(expression_roots(b, 100)),
  ).unwrap()
  assert_true(advance_expression_frame(frame) is Ok(None))
  let result = advance_expression_frame(frame).unwrap().unwrap()
  let work = b.work
  assert_eq(b.live, 1L)
  assert_true(
    advance_expression_frame(frame) is Err({ kind: InvalidControlLimits, .. }),
  )
  assert_eq((b.work, b.live), (work, 1L))
  release_logical_root(b, result.root.unwrap()).unwrap()
}
