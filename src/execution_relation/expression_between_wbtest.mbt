///|
test "between preserves inclusive bounds NULL and eager third operand" {
  for
    (source, expected) in [
      ("1 BETWEEN 1 AND 2", Some(true)),
      ("2 BETWEEN 1 AND 2", Some(true)),
      ("3 BETWEEN 1 AND 2", Some(false)),
      ("1 BETWEEN 2 AND 0", Some(false)),
      ("NULL BETWEEN 1 AND 2", None),
      ("1 BETWEEN NULL AND 0", Some(false)),
      ("1 BETWEEN NULL AND 2", None),
      ("1 NOT BETWEEN 1 AND 2", Some(false)),
    ] {
    let result = evaluate_expression(
      lowered("\"" + source + "\""),
      Map([]),
      [],
      { remaining: 10000, max_frames: 20, },
    ).unwrap()
    match expected {
      None => assert_true(result is Null, msg=source)
      Some(b) => assert_true(result is Boolean(v) && v == b, msg=source)
    }
  }
  assert_true(
    evaluate_expression(lowered("\"1 BETWEEN 2 AND (1 / 0)\""), Map([]), [], {
      remaining: 10000,
      max_frames: 20,
    })
    is Err(_),
  )
}

///|
test "between semantic work counts one search evaluation at every quantum" {
  // Four entries, three Number results, three operand consumptions and one
  // Boolean result: eleven logical units, with no synthetic comparison nodes.
  for quantum in [1, 7, 256] {
    let logical = test_logical_budget(11L, 100L)
    let result = resume_test_expression(
      "\"1 BETWEEN 0 AND 2\"", logical, quantum,
    ).unwrap()
    assert_true(result.value is Boolean(true))
    assert_eq(logical.work, 11L)
    release_logical_root(logical, result.root.unwrap()).unwrap()
    assert_eq(logical.live, 0L)
    let short = test_logical_budget(10L, 100L)
    assert_true(
      resume_test_expression("\"1 BETWEEN 0 AND 2\"", short, quantum) is Err(_),
    )
    assert_eq(short.live, 0L)
  }
}

///|
test "between owns bounded comparison workspace and cancellation releases roots" {
  for slots in [11, 12] {
    let workspace = row_workspace(slots)
    let result = evaluate_expression_with_workspace(
      lowered("\"1 BETWEEN 0 AND 2\""),
      Map([]),
      [],
      { remaining: 10000, max_frames: 20, },
      workspace,
    )
    if slots == 12 {
      assert_true(result is Ok(Boolean(true)))
    } else {
      assert_true(result is Err({ kind: WorkspaceLimit, .. }))
    }
    assert_eq(workspace.live, 0)
  }
  for stop in 1..<18 {
    let logical = test_logical_budget(1000L, 100L)
    let workspace = row_workspace(100)
    let frame = expression_frame(
      lowered("\"1 BETWEEN 0 AND 2\""),
      Map([]),
      [],
      { remaining: 10000, max_frames: 20, },
      workspace,
      Some(expression_roots(logical, 20)),
    ).unwrap()
    for _ in 0..<stop {
      if advance_expression_frame(frame).unwrap() is Some(result) {
        release_logical_root(logical, result.root.unwrap()).unwrap()
        break
      }
    }
    let work = logical.work
    close_expression_frame(frame)
    close_expression_frame(frame)
    assert_eq(logical.live, 0L)
    assert_eq(logical.work, work)
    assert_eq(workspace.live, 0)
  }
}

///|
fn borrowed_between_expression() -> @lower.Expression {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"x\":{\"type\":\"string\",\"nullable\":true},\"lo\":{\"type\":\"string\",\"nullable\":true},\"hi\":{\"type\":\"string\",\"nullable\":true}},\"rows\":[]},\"as\":\"seed\"},{\"derive\":{\"result\":{\"between\":[{\"field\":\"x\"},{\"field\":\"lo\"},{\"field\":\"hi\"}]}}}]",
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
test "between long Text shares bounded comparison and independent exact bounds" {
  // Four entries + three Text results/consumptions of weight 257 + Boolean.
  // Three 258-byte roots remain live through both comparisons. Ten persistent
  // argument slots overlap a ten-slot value measurement; comparisons use twelve.
  for
    (work, live, slots, succeeds) in [
      (1547L, 774L, 20, true),
      (1546L, 774L, 20, false),
      (1547L, 773L, 20, false),
      (1547L, 774L, 19, false),
    ] {
    let logical = text_expression_budget(work, live)
    let workspace = row_workspace(slots)
    let control = { remaining: 10000, max_frames: 20, }
    let text = Text(String::make(256, 'g'))
    let frame = expression_frame(
      borrowed_between_expression(),
      Map([("x", text), ("lo", text), ("hi", text)]),
      [],
      control,
      workspace,
      Some(expression_roots(logical, 20)),
    ).unwrap()
    let mut outcome : Result[EvaluatedValue?, EvalIssue] = Ok(None)
    for _ in 0..<10000 {
      let before = control.remaining
      outcome = advance_expression_frame(frame)
      assert_true(before - control.remaining <= 64)
      if !(outcome is Ok(None)) {
        break
      }
    }
    if succeeds {
      guard outcome is Ok(Some(result)) else { fail("exact between boundary") }
      assert_true(result.value is Boolean(true))
      assert_eq((logical.work, logical.peak, workspace.peak), (1547L, 774L, 20))
      release_logical_root(logical, result.root.unwrap()).unwrap()
    } else {
      assert_true(outcome is Err(_))
    }
    assert_eq(logical.live, 0L)
    assert_eq(workspace.live, 0)
  }
}

///|
test "between cancellation during either Text comparison retains no owned roots" {
  for upper in [false, true] {
    let logical = text_expression_budget(10000L, 10000L)
    let workspace = row_workspace(100)
    let text = Text(String::make(256, 'g'))
    let frame = expression_frame(
      borrowed_between_expression(),
      Map([("x", text), ("lo", text), ("hi", text)]),
      [],
      { remaining: 10000, max_frames: 20, },
      workspace,
      Some(expression_roots(logical, 20)),
    ).unwrap()
    let mut reached = false
    for _ in 0..<10000 {
      assert_true(advance_expression_frame(frame) is Ok(None))
      if frame.state is CompareBetween(_, comparison, first) &&
        comparison.phase == 2 &&
        comparison.offset > 0 &&
        (first is Some(_)) == upper {
        reached = true
        break
      }
    }
    assert_true(reached)
    assert_true(logical.live > 0L)
    let work = logical.work
    close_expression_frame(frame)
    close_expression_frame(frame)
    assert_eq((logical.live, workspace.live), (0L, 0))
    assert_eq(logical.work, work)
  }
}
