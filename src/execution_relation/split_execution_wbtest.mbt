///|
test "split preserves literal separators empty parts and Unicode scalar boundaries" {
  // Fixed independent outputs. No host split or product-derived expectations.
  for
    (source, expected) in [
      ("split('a,b,')", "[\"a\",\"b\",\"\"]"),
      ("split('a,,b,',',')", "[\"a\",\"\",\"b\",\"\"]"),
      ("split(',a',',')", "[\"\",\"a\"]"),
      ("split(',,,',',')", "[\"\",\"\",\"\",\"\"]"),
      ("split('aaa','aa')", "[\"\",\"a\"]"),
      ("split('aaaa','aa')", "[\"\",\"\",\"\"]"),
      ("split('aaabaaab','aab')", "[\"a\",\"a\",\"\"]"),
      ("split('a.*b.*','.*')", "[\"a\",\"b\",\"\"]"),
      ("split('ab','abcd')", "[\"ab\"]"),
      ("split('abc','x')", "[\"abc\"]"),
      ("split('')", "[\"\"]"),
      ("split('',',')", "[\"\"]"),
      ("split('','long')", "[\"\"]"),
      ("split('','')", "[\"\"]"),
      ("split('😀éx','')", "[\"😀\",\"e\",\"́\",\"x\"]"),
      ("split('x😀éy😀é','😀é')", "[\"x\",\"y\",\"\"]"),
      ("split('éé','é')", "[\"\",\"é\"]"),
      ("split(lower('A:B'),lower(':'))", "[\"a\",\"b\"]"),
    ] {
    assert_eq(
      object_result_wire(run_expr("\"" + source + "\"").unwrap()),
      expected,
      msg=source,
    )
  }
  assert_eq(
    object_result_wire(
      run_expr(
        "{\"split\":[{\"literal\":\"a\\u0000b\\u0000\"},{\"literal\":\"\\u0000\"}]}",
      ).unwrap(),
    ),
    "[\"a\",\"b\",\"\"]",
  )
  assert_eq(
    object_result_wire(
      run_expr(
        "{\"split\":[{\"literal\":\"\\u0000\\r\\n\"},{\"literal\":\"\"}]}",
      ).unwrap(),
    ),
    "[\"\\u0000\",\"\\r\",\"\\n\"]",
  )
}

///|
test "split strict NULL still demands children and lazy parents guard failures" {
  for args in ["NULL", "NULL,','", "'a',NULL", "NULL,NULL"] {
    assert_true(run_expr("\"split(" + args + ")\"") is Ok(Null))
  }
  for source in ["split(NULL,to_string(1/0))", "split(to_string(1/0),NULL)"] {
    guard run_expr("\"" + source + "\"") is Err(issue) else { fail(source) }
    assert_true(issue.kind is Scalar(ArithmeticFailure))
    assert_true(
      @lower.expression_body(issue.expression)
      is @lower.Binary(@lower.Divide, _, _),
    )
  }
  guard run_expr("\"split(to_string(sqrt(-1)),to_string(1/0))\"") is Err(issue) else {
    fail("first child failure")
  }
  assert_true(
    @lower.expression_body(issue.expression) is @lower.Unary(@lower.Sqrt, _),
  )
  for
    source in [
      "if(false,split(to_string(1/0)),split('safe'))", "coalesce(split('safe'),split(to_string(1/0)))",
    ] {
    assert_eq(
      object_result_wire(run_expr("\"" + source + "\"").unwrap()),
      "[\"safe\"]",
    )
  }
  assert_eq(
    object_result_wire(
      run_expr(
        "{\"array\":[{\"split\":[{\"literal\":\"a,b\"}]},{\"split\":[{\"literal\":\"\"}]}]}",
      ).unwrap(),
    ),
    "[[\"a\",\"b\"],[\"\"]]",
  )
}

///|
test "split independently exact work bytes nodes depth and workspace" {
  // Input wire/weight=(6,5), delimiter=(3,2), output=(12,6).
  // Three entries + twice each operand weight + one output weight = 23.
  // Both inputs coexist with the full output: 6+3+12=21 live bytes.
  // 3*n+5 continuation slots + 2 UTF-16 units + 3 parts + 3 admission slots=19.
  let source = "\"split('a,b,',',')\""
  for quantum in [1, 7, 256] {
    for drain in [false, true] {
      let exact = logical_budget(
        {
          max_input_rows: 1L,
          max_value_bytes: 12L,
          max_live_value_bytes: 21L,
          max_work: 23L,
        },
        12,
        4,
        2,
      ).unwrap()
      let result = resume_test_expression(source, exact, quantum, drain~).unwrap()
      assert_eq(object_result_wire(result.value), "[\"a\",\"b\",\"\"]")
      assert_eq((exact.work, exact.peak, exact.live), (23L, 21L, 12L))
      release_logical_root(exact, result.root.unwrap()).unwrap()
      assert_eq(exact.live, 0L)
    }
  }
  for
    (work, bytes, live, nodes, depth, slots) in [
      (23, 12, 21, 4, 2, 19),
      (22, 12, 21, 4, 2, 19),
      (23, 11, 21, 4, 2, 19),
      (23, 12, 20, 4, 2, 19),
      (23, 12, 21, 3, 2, 19),
      (23, 12, 21, 4, 1, 19),
      (23, 12, 21, 4, 2, 18),
    ] {
    let logical = logical_budget(
      {
        max_input_rows: 1L,
        max_value_bytes: bytes.to_int64(),
        max_live_value_bytes: live.to_int64(),
        max_work: work.to_int64(),
      },
      bytes,
      nodes,
      depth,
    ).unwrap()
    let workspace = row_workspace(slots)
    let result = evaluate_expression_with_workspace(
      lowered(source),
      Map([]),
      [],
      { remaining: 10000, max_frames: 100, },
      workspace,
      logical_work=Some(logical),
    )
    if (work, bytes, live, nodes, depth, slots) == (23, 12, 21, 4, 2, 19) {
      assert_eq(object_result_wire(result.unwrap()), "[\"a\",\"b\",\"\"]")
      assert_eq(workspace.peak, 19)
    } else {
      assert_true(result is Err(_))
    }
    assert_eq((logical.live, workspace.live), (0L, 0))
  }
}

///|
test "split admits every empty element node and wire byte before construction" {
  // Empty input and delimiter each have weight 1; output weight is 2.
  // 3 entries + 2*(1+1) + 2 = 9. Live bytes = 2+2+4=8.
  for source in ["\"split('','')\"", "\"split('',',')\""] {
    let logical = test_logical_budget(100L, 100L)
    let result = retained_expression(source, logical).unwrap()
    assert_eq(object_result_wire(result.value), "[\"\"]")
    if source == "\"split('','')\"" {
      assert_eq((logical.work, logical.peak, logical.live), (9L, 8L, 4L))
    }
    release_logical_root(logical, result.root.unwrap()).unwrap()
  }
  let source = "\"split(',,,,',',')\""
  let logical = logical_budget(
    {
      max_input_rows: 1L,
      max_value_bytes: 16L,
      max_live_value_bytes: 100L,
      max_work: 100L,
    },
    16,
    5,
    2,
  ).unwrap()
  let frame = expression_frame(
    lowered(source),
    Map([]),
    [],
    { remaining: 10000, max_frames: 100, },
    row_workspace(100),
    Some(expression_roots(logical, 100)),
  ).unwrap()
  let mut failed = false
  for _ in 0..<1000 {
    match advance_expression_frame(frame) {
      Err(_) => {
        failed = true
        break
      }
      Ok(Some(_)) => fail("six nodes exceed five-node bound")
      Ok(None) => {
        assert_true(frame.arrays.is_empty())
        if frame.state is SplitFunction(state) {
          assert_true(state.text_builder is None)
        }
      }
    }
  }
  assert_true(failed)
  assert_eq((logical.live, frame.workspace.live), (0L, 0))
}

///|
test "split resumes and cancels scan sizing emission and admission under borrowed roots" {
  let text = "a".repeat(256) + "," + "😀é".repeat(128)
  let source = "{\"split\":[{\"literal\":\"" +
    text +
    "\"},{\"literal\":\",\"}]}"
  for phase in [0, 1, 2, 3] {
    let logical = logical_budget(
      {
        max_input_rows: 1L,
        max_value_bytes: 10000L,
        max_live_value_bytes: 100000L,
        max_work: 100000L,
      },
      10000,
      10000,
      100,
    ).unwrap()
    let borrowed = retain_logical_value(logical, Number(7)).unwrap()
    let workspace = row_workspace(10000)
    assert_true(reserve_slots(workspace, 2))
    let frame = expression_frame(
      lowered(source),
      Map([]),
      [],
      { remaining: 100000, max_frames: 100, },
      workspace,
      Some(expression_roots(logical, 100)),
    ).unwrap()
    let mut found = false
    for _ in 0..<30000 {
      assert_true(advance_expression_frame(frame).unwrap() is None)
      if frame.state is SplitFunction(state) &&
        (
          (phase == 0 && !state.building && state.position == 64) ||
          (phase == 1 && state.building && state.position == 64) ||
          (phase == 2 && state.text_builder is Some(_) && state.emission == 64) ||
          (phase == 3 && state.admission is Some(_))
        ) {
        found = true
        break
      }
    }
    assert_true(found)
    let consumed = logical.work
    close_expression_frame(frame)
    close_expression_frame(frame)
    assert_eq((logical.work, logical.live, workspace.live), (consumed, 1L, 2))
    assert_false(borrowed.released)
    assert_true(
      advance_expression_frame(frame) is Err({ kind: InvalidControlLimits, .. }),
    )
    assert_eq((logical.work, logical.live, workspace.live), (consumed, 1L, 2))
    assert_true(frame.arrays.is_empty())
    release_logical_root(logical, borrowed).unwrap()
    release_slots(workspace, 2)
  }
}

///|
test "split repeated-prefix delimiter comparisons remain control bounded" {
  let input = "a".repeat(256)
  let delimiter = "a".repeat(64) + "b"
  let source = "{\"split\":[{\"literal\":\"" +
    input +
    "\"},{\"literal\":\"" +
    delimiter +
    "\"}]}"
  let logical = logical_budget(
    {
      max_input_rows: 1L,
      max_value_bytes: 10000L,
      max_live_value_bytes: 100000L,
      max_work: 100000L,
    },
    10000,
    10000,
    100,
  ).unwrap()
  let workspace = row_workspace(10000)
  let result = evaluate_expression_with_workspace(
    lowered(source),
    Map([]),
    [],
    { remaining: 3000, max_frames: 100, },
    workspace,
    logical_work=Some(logical),
  )
  assert_true(result is Err({ kind: ControlLimit, .. }))
  assert_eq((logical.live, workspace.live), (0L, 0))
}

///|
test "split large parts finish with exact independent measurement across resume schedules" {
  let first = "a".repeat(256)
  let second = "😀é".repeat(128)
  let source = "{\"split\":[{\"literal\":\"" +
    first +
    "," +
    second +
    "\"},{\"literal\":\",\"}]}"
  // Input: 1153 UTF-8 bytes, wire 1155, weight 1154. Delimiter: (3,2).
  // Output: wire 2 + 258 + 1 + 898 = 1159; weight 1+257+897=1155.
  // Work: 3+2*(1154+2)+1155=3470. Live: 1155+3+1159=2317.
  // Workspace: 11+768 UTF-16 units+2 elements+3 admission slots=784.
  for quantum in [1, 7, 256] {
    for drain in [false, true] {
      let logical = logical_budget(
        {
          max_input_rows: 1L,
          max_value_bytes: 1159L,
          max_live_value_bytes: 2317L,
          max_work: 3470L,
        },
        1159,
        3,
        2,
      ).unwrap()
      let result = resume_test_expression(
        source,
        logical,
        quantum,
        drain~,
        max_control=100000,
      ).unwrap()
      assert_eq(
        object_result_wire(result.value),
        "[\"" + first + "\",\"" + second + "\"]",
      )
      assert_eq(
        (logical.work, logical.peak, logical.live),
        (3470L, 2317L, 1159L),
      )
      release_logical_root(logical, result.root.unwrap()).unwrap()
      assert_eq(logical.live, 0L)
    }
  }
  let workspace = row_workspace(784)
  let logical = logical_budget(
    {
      max_input_rows: 1L,
      max_value_bytes: 1159L,
      max_live_value_bytes: 2317L,
      max_work: 3470L,
    },
    1159,
    3,
    2,
  ).unwrap()
  assert_true(
    evaluate_expression_with_workspace(
      lowered(source),
      Map([]),
      [],
      { remaining: 100000, max_frames: 100, },
      workspace,
      logical_work=Some(logical),
    )
    is Ok(_),
  )
  assert_eq((workspace.peak, workspace.live, logical.live), (784, 0, 0L))
}

///|
test "split default delimiter is not an invented authored child or retained root" {
  let logical = test_logical_budget(18L, 18L)
  let result = retained_expression("\"split('a,b,')\"", logical).unwrap()
  assert_eq(object_result_wire(result.value), "[\"a\",\"b\",\"\"]")
  // Two entries + twice input weight 5 + output weight 6; live 6+12.
  assert_eq((logical.work, logical.peak, logical.live), (18L, 18L, 12L))
  release_logical_root(logical, result.root.unwrap()).unwrap()
}

///|
test "split control failure and success are independent of drain scheduling" {
  for control in [0, 10, 25, 40, 70, 100, 200] {
    let a = test_logical_budget(1000L, 1000L)
    let b = test_logical_budget(1000L, 1000L)
    let source = "\"split('aaabaaab','aab')\""
    let stepped = resume_test_expression(source, a, 1, max_control=control)
    let drained = resume_test_expression(
      source,
      b,
      7,
      drain=true,
      max_control=control,
    )
    match (stepped, drained) {
      (Ok(x), Ok(y)) => {
        assert_eq(object_result_wire(x.value), "[\"a\",\"a\",\"\"]")
        assert_eq(object_result_wire(y.value), "[\"a\",\"a\",\"\"]")
        release_logical_root(a, x.root.unwrap()).unwrap()
        release_logical_root(b, y.root.unwrap()).unwrap()
      }
      (Err(x), Err(y)) => assert_eq(x.kind, y.kind)
      _ => fail("draining changed split success or failure")
    }
    assert_eq((a.work, a.peak, a.live), (b.work, b.peak, b.live))
    assert_eq(a.live, 0L)
  }
}

///|
test "nested split arrays retain existing root lifetimes and enclosing depth checks" {
  let source = "{\"array\":[{\"split\":[{\"literal\":\"a,b\"}]},{\"split\":[{\"literal\":\"\"}]}]}"
  // Outer entry + (first split 15 + consume 5) + (second 6 + consume 2)
  // + outer result weight 8 = 37. Final wire 16 + retained child roots 9+4=29.
  for depth in [3, 2] {
    let logical = logical_budget(
      {
        max_input_rows: 1L,
        max_value_bytes: 16L,
        max_live_value_bytes: 29L,
        max_work: 37L,
      },
      16,
      6,
      depth,
    ).unwrap()
    let result = resume_test_expression(source, logical, 1)
    if depth == 3 {
      let result = result.unwrap()
      assert_eq(object_result_wire(result.value), "[[\"a\",\"b\"],[\"\"]]")
      assert_eq((logical.work, logical.peak, logical.live), (37L, 29L, 16L))
      release_logical_root(logical, result.root.unwrap()).unwrap()
    } else {
      assert_true(result is Err(_))
    }
    assert_eq(logical.live, 0L)
  }
}

///|
test "NULL split does not allocate an Array or require Array depth" {
  let logical = logical_budget(
    {
      max_input_rows: 1L,
      max_value_bytes: 4L,
      max_live_value_bytes: 8L,
      max_work: 100L,
    },
    4,
    1,
    1,
  ).unwrap()
  let result = retained_expression("\"split(NULL,NULL)\"", logical).unwrap()
  assert_true(result.value is Null)
  release_logical_root(logical, result.root.unwrap()).unwrap()
  assert_eq(logical.live, 0L)
  let logical = test_logical_budget(1000L, 1000L)
  let workspace = row_workspace(100)
  assert_true(
    evaluate_expression_with_workspace(
      lowered("\"split(NULL,to_string(1/0))\""),
      Map([]),
      [],
      { remaining: 1000, max_frames: 100, },
      workspace,
      logical_work=Some(logical),
    )
    is Err({ kind: Scalar(ArithmeticFailure), .. }),
  )
  assert_eq((logical.live, workspace.live), (0L, 0))
}

///|
test "nested split one-short work live bytes and nodes fail without leaked roots" {
  let source = "{\"array\":[{\"split\":[{\"literal\":\"a,b\"}]},{\"split\":[{\"literal\":\"\"}]}]}"
  for (work, live, nodes) in [(36L, 29L, 6), (37L, 28L, 6), (37L, 29L, 5)] {
    for drain in [false, true] {
      let logical = logical_budget(
        {
          max_input_rows: 1L,
          max_value_bytes: 16L,
          max_live_value_bytes: live,
          max_work: work,
        },
        16,
        nodes,
        3,
      ).unwrap()
      assert_true(resume_test_expression(source, logical, 7, drain~) is Err(_))
      assert_true(logical.failed)
      assert_eq(logical.live, 0L)
    }
  }
}

///|
test "split rejects each logical output bound before allocating either builder" {
  // The independent exact output is ["a","b",""]: 12 wire bytes,
  // 4 nodes, depth 2, output weight 6 and total logical work 23.
  for
    (work, value_bytes, live_bytes, host_bytes, nodes, depth) in [
      (22L, 12L, 21L, 12, 4, 2),
      (23L, 11L, 21L, 12, 4, 2),
      (23L, 12L, 20L, 12, 4, 2),
      (23L, 12L, 21L, 11, 4, 2),
      (23L, 12L, 21L, 12, 3, 2),
      (23L, 12L, 21L, 12, 4, 1),
    ] {
    let logical = logical_budget(
      {
        max_input_rows: 1L,
        max_value_bytes: value_bytes,
        max_live_value_bytes: live_bytes,
        max_work: work,
      },
      host_bytes,
      nodes,
      depth,
    ).unwrap()
    let frame = expression_frame(
      lowered("\"split('a,b,',',')\""),
      Map([]),
      [],
      { remaining: 10000, max_frames: 100, },
      row_workspace(100),
      Some(expression_roots(logical, 100)),
    ).unwrap()
    let mut failed = false
    for _ in 0..<1000 {
      match advance_expression_frame(frame) {
        Err(_) => {
          failed = true
          break
        }
        Ok(Some(_)) => fail("one-short logical bound succeeded")
        Ok(None) => {
          assert_true(frame.arrays.is_empty())
          if frame.state is SplitFunction(state) {
            assert_false(state.building)
            assert_true(state.array is None)
            assert_true(state.text_builder is None)
          }
        }
      }
    }
    assert_true(failed)
    assert_eq((logical.live, frame.workspace.live), (0L, 0))
    close_expression_frame(frame)
    close_expression_frame(frame)
    assert_eq((logical.live, frame.workspace.live), (0L, 0))
  }
}

///|
test "split independently measures escaped controls and supplementary scalar parts" {
  // Fixed canonical wires and budgets, calculated directly from UTF-8 scalar
  // weights and JSON escaping. No runtime measurement supplies an expectation.
  for
    (input, expected, wire, work, live, slots) in [
      ("\\u0000\\r\\n", "[\"\\u0000\",\"\\r\",\"\\n\"]", 20, 20L, 34L, 20),
      ("😀é", "[\"😀\",\"e\",\"́\"]", 17, 32L, 28L, 21),
    ] {
    let source = "{\"split\":[{\"literal\":\"" +
      input +
      "\"},{\"literal\":\"\"}]}"
    let logical = logical_budget(
      {
        max_input_rows: 1L,
        max_value_bytes: wire.to_int64(),
        max_live_value_bytes: live,
        max_work: work,
      },
      wire,
      4,
      2,
    ).unwrap()
    let workspace = row_workspace(slots)
    let result = evaluate_expression_with_workspace(
      lowered(source),
      Map([]),
      [],
      { remaining: 10000, max_frames: 100, },
      workspace,
      logical_work=Some(logical),
    ).unwrap()
    assert_eq(object_result_wire(result), expected)
    assert_eq((logical.work, logical.peak, logical.live), (work, live, 0L))
    assert_eq((workspace.peak, workspace.live), (slots, 0))
  }
}
