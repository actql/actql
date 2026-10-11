///|
fn subscript_source(receiver : String, index : String) -> String {
  "{\"subscript\":{\"value\":" + receiver + ",\"index\":" + index + "}}"
}

///|
test "typed subscripts preserve item type order NULL and safe out of range" {
  let array =
    #|{"array":[{"literal":2},{"literal":1},{"literal":2}]}
  let null_array =
    #|{"if":[{"literal":false},{"array":[{"literal":7}]},{"literal":null}]}
  for
    (receiver, index, expected) in [
      (array, "0", "2"),
      (array, "1", "1"),
      (array, "2", "2"),
      (array, "3", "null"),
      (array, "9007199254740991", "null"),
      (
        (
          #|{"empty_array":{"items":{"type":"number","nullable":false}}}
        ),
        "0",
        "null",
      ),
      (null_array, "0", "null"),
      (
        (
          #|{"array":[{"literal":7},{"literal":null}]}
        ),
        "1",
        "null",
      ),
    ] {
    let expression = lowered(
      subscript_source(receiver, "{\"literal\":" + index + "}"),
    )
    assert_eq(@lower.expression_contract(expression).nullable, true)
    let result = evaluate_expression(expression, Map([]), [], {
      remaining: 10000,
      max_frames: 100,
    }).unwrap()
    assert_eq(object_result_wire(result), expected)
  }
  let nested = lowered(
    (
      #|{"property":{"value":{"subscript":{"value":{"array":[{"object":{"sku":{"literal":"é\r\n😀"}}}]},"index":{"literal":0}}},"name":"sku"}}
    ),
  )
  assert_eq(
    object_result_wire(
      evaluate_expression(nested, Map([]), [], {
        remaining: 10000,
        max_frames: 100,
      }).unwrap(),
    ),
    "\"é\\r\\n😀\"",
  )
}

///|
test "subscript indexes fail eagerly even for NULL and preserve receiver priority" {
  let null_array =
    #|{"if":[{"literal":false},{"array":[{"literal":7}]},{"literal":null}]}
  for index in ["null", "-1", "0.5", "9007199254740992"] {
    let expression = lowered(
      subscript_source(null_array, "{\"literal\":" + index + "}"),
    )
    let result = evaluate_expression(expression, Map([]), [], {
      remaining: 1000,
      max_frames: 100,
    })
    assert_true(result is Err({ kind: Scalar(InvalidOperand), .. }))
  }
  let failing_receiver =
    #|{"array":[{"divide":[{"literal":1},{"literal":0}]}]}
  let logical = test_logical_budget(1000L, 1000L)
  let expression = lowered(
    subscript_source(failing_receiver, "{\"literal\":-1}"),
  )
  let result = evaluate_expression_with_workspace(
    expression,
    Map([]),
    [],
    { remaining: 1000, max_frames: 100, },
    row_workspace(100),
    logical_work=Some(logical),
  )
  guard result is Err(issue) else { fail("receiver must fail before index") }
  assert_true(issue.kind is Scalar(ArithmeticFailure))
  assert_true(
    @lower.expression_body(issue.expression)
    is @lower.Binary(@lower.Divide, _, _),
  )
  assert_eq(logical.live, 0L)
}

///|
test "subscript uses independent logical work across quantum and draining" {
  let source = subscript_source(
    (
      #|{"array":[{"literal":2},{"literal":1}]}
    ),
    "{\"literal\":1}",
  )
  // Array entries/results/consumptions: 10. Subscript/index entries: 2;
  // index result + consumption: 2; array consumption: 3; selection result: 1.
  let exact_work = 18L
  for quantum in [1, 7, 256] {
    for drain in [false, true] {
      let exact = test_logical_budget(exact_work, 100L)
      let result = resume_test_expression(source, exact, quantum, drain~).unwrap()
      assert_eq(object_result_wire(result.value), "1")
      assert_eq(exact.work, exact_work)
      release_logical_root(exact, result.root.unwrap()).unwrap()
      assert_eq(exact.live, 0L)
      let short = test_logical_budget(exact_work - 1L, 100L)
      assert_true(
        resume_test_expression(source, short, quantum, drain~)
        is Err({ kind: LogicalValue(ValueMeasure(LogicalWorkLimit)), .. }),
      )
      assert_eq(short.live, 0L)
    }
  }
}

///|
test "subscript retains exact workspace and live-value boundaries" {
  let source = subscript_source(
    "{\"array\":[{\"literal\":2},{\"literal\":1}]}", "{\"literal\":1}",
  )
  // Array construction reserves eight slots plus the subscript continuation.
  // With logical retention, its measurement cursor needs eight fixed slots,
  // two traversal frames and a speculative successor plus that continuation.
  // The [2,1] root (five bytes) overlaps two scalar roots.
  for
    (retained, slots, live) in [
      (false, 9, 7L),
      (false, 8, 7L),
      (true, 12, 7L),
      (true, 11, 7L),
      (true, 12, 6L),
    ] {
    let workspace = row_workspace(slots)
    let budget = test_logical_budget(18L, live)
    let result = evaluate_expression_with_workspace(
      lowered(source),
      Map([]),
      [],
      { remaining: 1000, max_frames: 100, },
      workspace,
      logical_work=if retained { Some(budget) } else { None },
    )
    if slots == (if retained { 12 } else { 9 }) && live == 7L {
      assert_eq(object_result_wire(result.unwrap()), "1")
      assert_eq(workspace.peak, slots)
      if retained {
        assert_eq(budget.peak, 7L)
      }
    } else if retained && live == 6L {
      assert_true(result is Err({ kind: LogicalValue(LiveValueLimit), .. }))
    } else {
      assert_true(result is Err({ kind: WorkspaceLimit, .. }))
    }
    assert_eq((workspace.live, budget.live), (0, 0L))
  }
}

///|
test "subscript selection measures long Unicode incrementally and closes pending roots" {
  let text = "e\u{0301}😀".repeat(256)
  let source = subscript_source(
    "{\"array\":[{\"literal\":\"" + text + "\"}]}",
    "{\"literal\":0}",
  )
  // 1792 UTF-8 bytes: array work 5382, two extra entries and the index result
  // and consumption (four), array consumption 1794, selected production 1793.
  for quantum in [1, 7, 256] {
    let budget = logical_budget(
      {
        max_input_rows: 1L,
        max_value_bytes: 1796L,
        max_live_value_bytes: 3590L,
        max_work: 8973L,
      },
      1796,
      100,
      100,
    ).unwrap()
    let result = resume_test_expression(source, budget, quantum).unwrap()
    assert_eq(object_result_wire(result.value), "\"" + text + "\"")
    assert_eq((budget.work, budget.peak), (8973L, 3590L))
    release_logical_root(budget, result.root.unwrap()).unwrap()
    assert_eq(budget.live, 0L)
  }
  let budget = logical_budget(
    {
      max_input_rows: 1L,
      max_value_bytes: 1796L,
      max_live_value_bytes: 10000L,
      max_work: 100000L,
    },
    1796,
    100,
    100,
  ).unwrap()
  let borrowed = retain_logical_value(budget, Number(9)).unwrap()
  let frame = expression_frame(
    lowered(source),
    Map([]),
    [],
    { remaining: 100000, max_frames: 100, },
    row_workspace(100),
    Some(expression_roots(budget, 100)),
  ).unwrap()
  for _ in 0..<10000 {
    assert_true(advance_expression_frame(frame).unwrap() is None)
    if frame.selection_pending && frame.state is MeasureResult(_, _) {
      break
    }
  }
  assert_true(frame.selection_pending && frame.state is MeasureResult(_, _))
  assert_true(frame.selection_root is Some(_))
  assert_eq(budget.live, 1797L)
  let work = budget.work
  close_expression_frame(frame)
  close_expression_frame(frame)
  assert_eq((budget.work, budget.live, frame.workspace.live), (work, 1L, 0))
  assert_false(borrowed.released)
  assert_true(
    advance_expression_frame(frame) is Err({ kind: InvalidControlLimits, .. }),
  )
  release_logical_root(budget, borrowed).unwrap()
  assert_eq(budget.live, 0L)
}
