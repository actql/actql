///|
test "array constructors preserve child order duplicates NULL and machine recursion" {
  for
    (source, expected) in [
      (
        (
          #|{"array":[{"literal":2},{"literal":1},{"literal":2}]}
        ),
        "[2,1,2]",
      ),
      (
        (
          #|{"array":[{"literal":true},{"literal":null}]}
        ),
        "[true,null]",
      ),
      (
        (
          #|{"empty_array":{"items":{"type":"string","nullable":false}}}
        ),
        "[]",
      ),
      (
        (
          #|{"array":[{"array":[{"literal":2},{"literal":1}]},{"array":[{"literal":2}]}]}
        ),
        "[[2,1],[2]]",
      ),
    ] {
    let result = evaluate_expression(lowered(source), Map([]), [], {
      remaining: 10000,
      max_frames: 100,
    }).unwrap()
    assert_eq(object_result_wire(result), expected)
  }
}

///|
test "array constructors evaluate only the selected branch and retain child failures" {
  let source =
    #|{"array":[{"if":[{"literal":true},{"literal":7},{"divide":[{"literal":1},{"literal":0}]}]},{"literal":7}]}
  assert_eq(
    object_result_wire(
      evaluate_expression(lowered(source), Map([]), [], {
        remaining: 1000,
        max_frames: 100,
      }).unwrap(),
    ),
    "[7,7]",
  )
  let bad = lowered(
    (
      #|{"array":[{"literal":7},{"divide":[{"literal":1},{"literal":0}]}]}
    ),
  )
  let budget = test_logical_budget(1000L, 1000L)
  let workspace = row_workspace(100)
  guard evaluate_expression_with_workspace(
      bad,
      Map([]),
      [],
      { remaining: 1000, max_frames: 100, },
      workspace,
      logical_work=Some(budget),
    )
    is Err(issue) else {
    fail("demanded child must fail")
  }
  assert_true(issue.kind is Scalar(ArithmeticFailure))
  assert_true(
    @lower.expression_body(issue.expression)
    is @lower.Binary(@lower.Divide, _, _),
  )
  assert_eq((budget.live, workspace.live), (0L, 0))
}

///|
test "array constructors preserve independent logical work under quantum and drain" {
  let source =
    #|{"array":[{"literal":2},{"literal":1}]}
  // Three expression entries, two scalar productions and consumptions,
  // then an array production with weight 1 + 1 + 1: exactly ten.
  for quantum in [1, 7, 256] {
    for drain in [false, true] {
      let exact = test_logical_budget(10L, 100L)
      let result = resume_test_expression(source, exact, quantum, drain~).unwrap()
      assert_eq(object_result_wire(result.value), "[2,1]")
      assert_eq(exact.work, 10L)
      assert_eq(exact.live, 5L)
      release_logical_root(exact, result.root.unwrap()).unwrap()
      assert_eq(exact.live, 0L)
      let short = test_logical_budget(9L, 100L)
      assert_true(
        resume_test_expression(source, short, quantum, drain~) is Err(_),
      )
      assert_true(short.failed)
      assert_eq(short.live, 0L)
    }
  }
}

///|
test "array constructor rejects workspace before copying or appending" {
  let source =
    #|{"array":[{"literal":2},{"literal":1}]}
  // Two retained views, continuation and builder, two element/root pairs.
  for slots in [8, 7, 1] {
    let workspace = row_workspace(slots)
    let result = evaluate_expression_with_workspace(
      lowered(source),
      Map([]),
      [],
      { remaining: 1000, max_frames: 100, },
      workspace,
    )
    if slots == 8 {
      assert_eq(object_result_wire(result.unwrap()), "[2,1]")
      assert_eq(workspace.peak, 8)
    } else {
      assert_true(result is Err({ kind: WorkspaceLimit, .. }))
    }
    assert_eq(workspace.live, 0)
  }
}

///|
test "array constructor cancellation retains work and releases only owned roots" {
  let budget = test_logical_budget(10000L, 10000L)
  let borrowed = retain_logical_value(budget, Number(9)).unwrap()
  let frame = expression_frame(
    lowered(
      (
        #|{"array":[{"field":"id"},{"literal":1},{"literal":2}]}
      ),
    ),
    Map([("id", Number(9))]),
    [],
    { remaining: 1000, max_frames: 100, },
    row_workspace(100),
    Some(expression_roots(budget, 100)),
  ).unwrap()
  for _ in 0..<4 {
    assert_true(advance_expression_frame(frame).unwrap() is None)
  }
  assert_true(frame.arrays.length() == 1)
  let consumed = budget.work
  close_expression_frame(frame)
  close_expression_frame(frame)
  assert_eq(budget.work, consumed)
  assert_false(borrowed.released)
  assert_eq((budget.live, frame.workspace.live), (1L, 0))
  release_logical_root(budget, borrowed).unwrap()
  assert_eq(budget.live, 0L)
}

///|
test "array constructor resumes long Unicode admission and cancellation" {
  let text = "e\u{0301}😀".repeat(256)
  let source = "{\"array\":[{\"literal\":\"" + text + "\"}]}"
  for quantum in [1, 7, 256] {
    let budget = logical_budget(
      {
        max_input_rows: 1L,
        max_value_bytes: 1796L,
        max_live_value_bytes: 3590L,
        max_work: 5382L,
      },
      1796,
      100,
      100,
    ).unwrap()
    let result = resume_test_expression(source, budget, quantum).unwrap()
    assert_eq(object_result_wire(result.value), "[\"" + text + "\"]")
    // 1792 UTF-8 bytes: entry + child entry/production/consumption + array
    // production => 3 * (1 + 1792) + 3 = 5382 logical units.
    assert_eq(budget.work, 5382L)
    release_logical_root(budget, result.root.unwrap()).unwrap()
    assert_eq(budget.live, 0L)
  }
  let budget = logical_budget(
    {
      max_input_rows: 1L,
      max_value_bytes: 1796L,
      max_live_value_bytes: 3590L,
      max_work: 5382L,
    },
    1796,
    100,
    100,
  ).unwrap()
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
    if frame.state is ArrayText(_, _) {
      break
    }
  }
  assert_true(frame.state is ArrayText(_, _))
  let consumed = budget.work
  close_expression_frame(frame)
  assert_eq((budget.work, budget.live, frame.workspace.live), (consumed, 0L, 0))
}

///|
test "array constructor keeps exact byte live and node ceilings" {
  for (bytes, live, nodes) in [(5, 7, 3), (4, 7, 3), (5, 6, 3), (5, 7, 2)] {
    let budget = logical_budget(
      {
        max_input_rows: 1L,
        max_value_bytes: bytes.to_int64(),
        max_live_value_bytes: live.to_int64(),
        max_work: 1000L,
      },
      bytes,
      nodes,
      10,
    ).unwrap()
    let result = retained_expression(
      (
        #|{"array":[{"literal":2},{"literal":1}]}
      ),
      budget,
    )
    if (bytes, live, nodes) == (5, 7, 3) {
      let value = result.unwrap()
      assert_eq(object_result_wire(value.value), "[2,1]")
      assert_eq((budget.work, budget.peak, budget.live), (10L, 7L, 5L))
      release_logical_root(budget, value.root.unwrap()).unwrap()
    } else {
      assert_true(result is Err(_))
      assert_true(budget.failed)
    }
    assert_eq(budget.live, 0L)
  }
}

///|
test "array backend readiness checks unselected child branches before input execution" {
  let operation =
    #|{"derive":{"v":{"array":[{"if":[{"literal":true},{"literal":true},{"eq":[{"field":"d"},{"field":"d"}]}]}]}}}
  let request = capability_request("[]", operation)
  let roots = @lower.fragment_pipeline_roots(
    @lower.fragment_request_pipeline(request),
  )
  // Root entry 1, ARRAY visit/view/edge 3, IF visit/edges 4,
  // two literal visits 2, comparison visit/edges 3, two field visits 2.
  assert_true(check_backend_capabilities(roots, 15) is Ok(_))
  assert_true(
    check_backend_capabilities(roots, 14) is Err({ kind: PreparationLimit, .. }),
  )
}

///|
test "array result measurement reserves successor frames before allocation" {
  let source =
    #|{"array":[{"literal":2},{"literal":1}]}
  for slots in [11, 10] {
    let budget = test_logical_budget(100L, 100L)
    let workspace = row_workspace(slots)
    let result = evaluate_expression_with_workspace(
      lowered(source),
      Map([]),
      [],
      { remaining: 1000, max_frames: 100, },
      workspace,
      logical_work=Some(budget),
    )
    if slots == 11 {
      assert_eq(object_result_wire(result.unwrap()), "[2,1]")
      assert_eq(budget.work, 10L)
      assert_eq(workspace.peak, 11)
    } else {
      assert_true(result is Err({ kind: WorkspaceLimit, .. }))
    }
    assert_eq((budget.live, workspace.live), (0L, 0))
  }
}

///|
test "nested machine arrays retain one scope and quantum-independent work" {
  let source =
    #|{"array":[{"array":[{"literal":2},{"literal":1}]},{"array":[{"literal":2}]}]}
  // Outer entry + two child productions/consumptions + outer production:
  // 1 + (10 + 3) + (6 + 2) + 6 = 28. Wire bytes are 2 + 5 + 1 + 3 = 11.
  // Before finishing, outer 11 and child roots 5 + 3 coexist: peak live 19.
  for quantum in [1, 7, 256] {
    let exact = logical_budget(
      {
        max_input_rows: 1L,
        max_value_bytes: 11L,
        max_live_value_bytes: 19L,
        max_work: 28L,
      },
      11,
      6,
      3,
    ).unwrap()
    let result = resume_test_expression(source, exact, quantum).unwrap()
    assert_eq(object_result_wire(result.value), "[[2,1],[2]]")
    assert_eq((exact.work, exact.peak, exact.live), (28L, 19L, 11L))
    release_logical_root(exact, result.root.unwrap()).unwrap()
    assert_eq(exact.live, 0L)
    let short = test_logical_budget(27L, 100L)
    assert_true(resume_test_expression(source, short, quantum) is Err(_))
    assert_eq(short.live, 0L)
  }
}

///|
test "wide array roots use original workspace while continuation depth stays independent" {
  let source = "{\"array\":[" +
    Array::make(256, "{\"literal\":0}").join(",") +
    "]}"
  let expression = lowered(source)
  let expected = "[" + Array::make(256, "0").join(",") + "]"
  let execute = fn(workspace, frames) {
    let logical = logical_budget(
      {
        max_input_rows: 1L,
        max_value_bytes: 100000L,
        max_live_value_bytes: 100000L,
        max_work: 100000L,
      },
      100000,
      1000,
      100,
    ).unwrap()
    let result = evaluate_expression_retained(
      expression,
      Map([]),
      [],
      { remaining: 100000, max_frames: frames, },
      workspace,
      logical_work=Some(logical),
    )
    (result, logical)
  }
  let observed = row_workspace(10000)
  let (first, logical) = execute(observed, 1)
  let first = first.unwrap()
  assert_eq(object_result_wire(first.value), expected)
  release_logical_root(logical, first.root.unwrap()).unwrap()
  assert_eq((logical.live, observed.live), (0L, 0))
  assert_true(observed.peak > 256)
  let exact = row_workspace(observed.peak)
  let (ok, exact_logical) = execute(exact, 1)
  let ok = ok.unwrap()
  assert_eq(object_result_wire(ok.value), expected)
  assert_eq(exact.peak, observed.peak)
  release_logical_root(exact_logical, ok.root.unwrap()).unwrap()
  assert_eq((exact.live, exact_logical.live), (0, 0L))
  let short = row_workspace(observed.peak - 1)
  let (refused, short_logical) = execute(short, 1)
  assert_true(refused is Err({ kind: WorkspaceLimit, .. }))
  assert_eq((short.live, short_logical.live), (0, 0L))
  let (no_frame, no_frame_logical) = execute(row_workspace(10000), 0)
  assert_true(no_frame is Err({ kind: ControlLimit, .. }))
  assert_eq(no_frame_logical.live, 0L)
  let deep = lowered("{\"array\":[{\"array\":[{\"literal\":0}]}]}")
  let depth_logical = test_logical_budget(100000L, 100000L)
  assert_true(
    evaluate_expression_retained(
      deep,
      Map([]),
      [],
      { remaining: 100000, max_frames: 1, },
      row_workspace(10000),
      logical_work=Some(depth_logical),
    )
    is Err({ kind: ControlLimit, .. }),
  )
  assert_eq(depth_logical.live, 0L)
}
