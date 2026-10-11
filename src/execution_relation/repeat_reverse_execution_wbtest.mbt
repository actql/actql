///|
test "reverse preserves scalar sequence including supplementary decomposed ZWJ NUL and CRLF" {
  for
    (input, expected) in [
      ("", ""),
      ("abc", "cba"),
      ("é", "é"),
      ("é", "́e"),
      ("A😀é", "́e😀A"),
      ("👩‍💻", "💻‍👩"),
      (
        "\u{d7ff}\u{e000}\u{10000}\u{10ffff}", "\u{10ffff}\u{10000}\u{e000}\u{d7ff}",
      ),
    ] {
    assert_true(
      run_expr("\"reverse('" + input + "')\"") is Ok(Text(actual)) &&
      actual == expected,
      msg=input,
    )
    assert_true(
      run_expr("\"reverse(reverse('" + input + "'))\"") is Ok(Text(actual)) &&
      actual == input,
      msg=input,
    )
  }
  assert_true(
    run_expr("{\"reverse\":{\"literal\":\"A\\u0000\\r\\n😀\"}}")
    is Ok(Text("😀\n\r\u{0000}A")),
  )
}

///|
test "repeat keeps whole input sequence and accepts empty results for arbitrarily large integral Numbers" {
  for
    (source, expected) in [
      ("repeat('abc',3)", "abcabcabc"),
      ("repeat('😀é',2)", "😀é😀é"),
      ("repeat('a',0)", ""),
      ("repeat('',0)", ""),
      ("repeat('',1)", ""),
      ("repeat('',4294967296)", ""),
      ("repeat('',9007199254740992)", ""),
      ("repeat('',9223372036854775808)", ""),
      ("repeat('',1e100)", ""),
      ("repeat('',1.7976931348623157e308)", ""),
      ("reverse(repeat('A😀é',2))", "́e😀Áe😀A"),
    ] {
    assert_true(
      run_expr("\"" + source + "\"") is Ok(Text(actual)) && actual == expected,
      msg=source,
    )
  }
  assert_true(
    run_expr("{\"repeat\":[{\"literal\":\"\\u0000\\r\\n\"},{\"literal\":2}]}")
    is Ok(Text("\u{0000}\r\n\u{0000}\r\n")),
  )
  for input in ["", "a"] {
    for count in ["-1", "-0.5", "0.5", "1.5"] {
      assert_true(
        run_expr("\"repeat('" + input + "'," + count + ")\"")
        is Err({ kind: Scalar(InvalidOperand), .. }),
        msg=input + count,
      )
    }
  }
}

///|
test "repeat reverse strict children precede null and zero shortcuts while lazy parents preserve demand" {
  for
    source in [
      "repeat(NULL,-1)", "repeat(NULL,0.5)", "repeat('',NULL)", "repeat(NULL,NULL)",
      "reverse(NULL)",
    ] {
    assert_true(run_expr("\"" + source + "\"") is Ok(Null), msg=source)
  }
  for
    source in [
      "repeat(NULL,1/0)", "repeat(to_string(1/0),0)", "repeat(to_string(1/0),NULL)",
      "reverse(to_string(1/0))",
    ] {
    guard run_expr("\"" + source + "\"") is Err(issue) else { fail(source) }
    assert_true(issue.kind is Scalar(ArithmeticFailure))
    assert_true(
      @lower.expression_body(issue.expression)
      is @lower.Binary(@lower.Divide, _, _),
    )
  }
  guard run_expr("\"repeat(to_string(sqrt(-1)),1/0)\"") is Err(issue) else {
    fail("first child failure")
  }
  assert_true(
    @lower.expression_body(issue.expression) is @lower.Unary(@lower.Sqrt, _),
  )
  for
    (source, expected) in [
      ("if(false,repeat('a',-1),'safe')", "safe"),
      ("coalesce('safe',reverse(to_string(1/0)))", "safe"),
      ("repeat(if(true,'😀',to_string(1/0)),if(true,2,1/0))", "😀😀"),
      ("reverse(if(true,'é',to_string(1/0)))", "́e"),
    ] {
    assert_true(
      run_expr("\"" + source + "\"") is Ok(Text(actual)) && actual == expected,
      msg=source,
    )
  }
}

///|
fn repeat_reverse_field_expression(tag : String) -> @lower.Expression {
  let body = if tag == "repeat" {
    "{\"repeat\":[{\"field\":\"payload\"},{\"field\":\"count\"}]}"
  } else {
    "{\"reverse\":{\"field\":\"payload\"}}"
  }
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"payload\":{\"type\":\"string\",\"nullable\":false},\"count\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[]},\"as\":\"seed\"},{\"derive\":{\"result\":" +
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
test "repeat validates internal nonfinite counts before empty shortcut and preserves signed zero" {
  let maximum = 1.7976931348623157e308
  let infinity = maximum * 2.0
  for text in ["", "a"] {
    for number in [infinity, -infinity, infinity - infinity, -1.0, 0.5] {
      let workspace = row_workspace(100)
      assert_true(
        evaluate_expression_with_workspace(
          repeat_reverse_field_expression("repeat"),
          Map([("payload", Text(text)), ("count", Number(number))]),
          [],
          { remaining: 1000, max_frames: 20, },
          workspace,
        )
        is Err({ kind: Scalar(InvalidOperand), .. }),
      )
      assert_eq(workspace.live, 0)
    }
    let workspace = row_workspace(100)
    assert_true(
      evaluate_expression_with_workspace(
        repeat_reverse_field_expression("repeat"),
        Map([("payload", Text(text)), ("count", Number(-0.0))]),
        [],
        { remaining: 1000, max_frames: 20, },
        workspace,
      )
      is Ok(Text("")),
    )
    assert_eq(workspace.live, 0)
  }
}

///|
test "repeat reverse exact logical work live canonical bytes and host caps survive schedules" {
  // Independent formula: n+1 entries, twice each operand weight, one output
  // weight. String weight = 1 + UTF-8 payload bytes; wire bytes include JSON
  // escaping. Both operands and output coexist through construction.
  for
    (source, expected, work, live, value_bytes, output_bytes) in [
      ("\"reverse('')\"", "\"\"", 5L, 4L, 2, 2L),
      ("\"reverse('😀é')\"", "\"́e😀\"", 26L, 18L, 9, 9L),
      (
        "{\"reverse\":{\"literal\":\"\\u0000\\r\\n\"}}", "\"\\n\\r\\u0000\"", 14L,
        24L, 12, 12L,
      ),
      ("\"repeat('',0)\"", "\"\"", 8L, 5L, 2, 2L),
      ("\"repeat('a',0)\"", "\"\"", 10L, 6L, 3, 2L),
      ("\"repeat('a',3)\"", "\"aaa\"", 13L, 9L, 5, 5L),
      ("\"repeat('😀é',2)\"", "\"😀é😀é\"", 36L, 26L, 16, 16L),
      (
        "{\"repeat\":[{\"literal\":\"\\u0000\\r\\n\"},{\"literal\":2}]}", "\"\\u0000\\r\\n\\u0000\\r\\n\"",
        20L, 35L, 22, 22L,
      ),
    ] {
    for quantum in [1, 7, 256] {
      for drain in [false, true] {
        for short in 0..<5 {
          let logical = logical_budget(
            {
              max_input_rows: 1L,
              max_value_bytes: value_bytes.to_int64() -
              (if short == 3 { 1L } else { 0L }),
              max_live_value_bytes: live - (if short == 2 { 1L } else { 0L }),
              max_work: work - (if short == 1 { 1L } else { 0L }),
            },
            value_bytes - (if short == 4 { 1 } else { 0 }),
            1,
            1,
          ).unwrap()
          let result = resume_test_expression(source, logical, quantum, drain~)
          if short == 0 {
            let result = result.unwrap()
            assert_eq(object_result_wire(result.value), expected, msg=source)
            assert_eq(
              (logical.work, logical.peak, logical.live),
              (work, live, output_bytes),
              msg=source,
            )
            release_logical_root(logical, result.root.unwrap()).unwrap()
          } else {
            assert_true(result is Err(_), msg=source)
            assert_true(logical.failed)
          }
          assert_eq(logical.live, 0L)
        }
      }
    }
  }
}

///|
test "repeat reverse exact long String workspace boundaries clean up one short failures" {
  // 64 supplementary characters: input wire=258, weight=257. REVERSE
  // storage=2 continuation slots+128 UTF-16 units. REPEAT count=2 has nine
  // continuation slots+256 units. These fixed bounds dominate input cursors.
  for
    (tag, work, live, slots, expected) in [
      ("reverse", 773L, 516L, 130, String::make(64, '😀')),
      ("repeat", 1032L, 773L, 265, String::make(128, '😀')),
    ] {
    for short in 0..<4 {
      let logical = text_expression_budget(
        work - (if short == 1 { 1L } else { 0L }),
        live - (if short == 2 { 1L } else { 0L }),
      )
      let workspace = row_workspace(slots - (if short == 3 { 1 } else { 0 }))
      let result = evaluate_expression_with_workspace(
        repeat_reverse_field_expression(tag),
        Map([("payload", Text(String::make(64, '😀'))), ("count", Number(2))]),
        [],
        { remaining: 100000, max_frames: 20, },
        workspace,
        logical_work=Some(logical),
      )
      match short {
        0 => {
          assert_true(result is Ok(Text(actual)) && actual == expected, msg=tag)
          assert_eq(
            (logical.work, logical.peak, workspace.peak),
            (work, live, slots),
            msg=tag,
          )
        }
        1 =>
          assert_true(
            result
            is Err({ kind: LogicalValue(ValueMeasure(LogicalWorkLimit)), .. }),
            msg=tag,
          )
        2 =>
          assert_true(
            result is Err({ kind: LogicalValue(LiveValueLimit), .. }),
            msg=tag,
          )
        3 => assert_true(result is Err({ kind: WorkspaceLimit, .. }), msg=tag)
        _ => fail("resource selection")
      }
      assert_eq((logical.live, workspace.live), (0L, 0))
    }
  }
}

///|
test "huge nonempty repeat fails as bounded resource before builder allocation or integer narrowing" {
  for
    count in [
      4294967296.0, 9007199254740992.0, 9223372036854775808.0, 1.0e100, 1.7976931348623157e308,
    ] {
    let logical = text_expression_budget(10000L, 10000L)
    let borrowed = retain_logical_value(logical, Number(9)).unwrap()
    let workspace = row_workspace(100)
    let frame = expression_frame(
      repeat_reverse_field_expression("repeat"),
      Map([("payload", Text("😀")), ("count", Number(count))]),
      [],
      { remaining: 1000, max_frames: 20, },
      workspace,
      Some(expression_roots(logical, 20)),
    ).unwrap()
    let mut failed = false
    for _ in 0..<1000 {
      match advance_expression_frame(frame) {
        Err(issue) => {
          assert_true(
            issue.kind is WorkspaceLimit || issue.kind is LogicalValue(_),
          )
          failed = true
          break
        }
        Ok(Some(_)) => fail("huge nonempty output cannot fit")
        Ok(None) =>
          if frame.state is TextFunction(state) {
            assert_false(state.building)
            assert_true(state.builder is None)
          }
      }
    }
    assert_true(failed)
    let work = logical.work
    close_expression_frame(frame)
    close_expression_frame(frame)
    assert_eq((logical.work, logical.live, workspace.live), (work, 1L, 0))
    assert_false(borrowed.released)
    release_logical_root(logical, borrowed).unwrap()
  }
}

///|
test "repeat reverse reject escaped output caps before allocating builders" {
  for
    (source, cap) in [
      ("{\"reverse\":{\"literal\":\"\\u0000\\r\\n\"}}", 11L),
      ("{\"repeat\":[{\"literal\":\"\\u0000\\r\\n\"},{\"literal\":2}]}", 21L),
    ] {
    let logical = logical_budget(
      {
        max_input_rows: 1L,
        max_value_bytes: cap,
        max_live_value_bytes: 100L,
        max_work: 100L,
      },
      100,
      1,
      1,
    ).unwrap()
    let workspace = row_workspace(100)
    let frame = expression_frame(
      lowered(source),
      Map([]),
      [],
      { remaining: 1000, max_frames: 20, },
      workspace,
      Some(expression_roots(logical, 20)),
    ).unwrap()
    let mut failed = false
    for _ in 0..<1000 {
      match advance_expression_frame(frame) {
        Err(_) => {
          failed = true
          break
        }
        Ok(Some(_)) => fail("escaped output cap must fail")
        Ok(None) =>
          if frame.state is TextFunction(state) {
            assert_false(state.building)
            assert_true(state.builder is None)
          }
      }
    }
    assert_true(failed)
    assert_eq((logical.live, workspace.live), (0L, 0))
  }
}

///|
test "repeat reverse success and failures are invariant under drain scheduling" {
  for
    source in [
      "\"repeat('😀é',3)\"", "\"reverse('A😀é')\"", "\"repeat('',1e100)\"",
      "\"repeat('a',-1)\"",
    ] {
    for control in [0, 1, 5, 10, 20, 40, 100, 1000] {
      let a = test_logical_budget(1000L, 1000L)
      let b = test_logical_budget(1000L, 1000L)
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
          assert_eq(object_result_wire(x.value), object_result_wire(y.value))
          release_logical_root(a, x.root.unwrap()).unwrap()
          release_logical_root(b, y.root.unwrap()).unwrap()
        }
        (Err(x), Err(y)) => assert_eq(x.kind, y.kind)
        _ => fail("drain changed repeat reverse outcome")
      }
      assert_eq((a.work, a.peak, a.live), (b.work, b.peak, b.live))
      assert_eq(a.live, 0L)
    }
  }
}

///|
test "repeat reverse cancellation and control exhaustion preserve charged work and unrelated custody" {
  for tag in ["repeat", "reverse"] {
    for phase in 0..<3 {
      for exhaust in [false, true] {
        let logical = text_expression_budget(10000L, 10000L)
        let borrowed = retain_logical_value(logical, Number(9)).unwrap()
        let workspace = row_workspace(1000)
        assert_true(reserve_slots(workspace, 3))
        let frame = expression_frame(
          repeat_reverse_field_expression(tag),
          Map([
            ("payload", Text(String::make(64, '😀'))),
            ("count", Number(2)),
          ]),
          [],
          { remaining: 100000, max_frames: 20, },
          workspace,
          Some(expression_roots(logical, 20)),
        ).unwrap()
        let mut reached = false
        for _ in 0..<10000 {
          let before = frame.budget.remaining
          assert_true(advance_expression_frame(frame) is Ok(None))
          assert_true(before - frame.budget.remaining <= 64)
          if frame.state is TextFunction(state) &&
            (
              (phase == 0 && !state.building && state.units == 32) ||
              (
                phase == 1 &&
                state.building &&
                state.position == (if tag == "repeat" { 0 } else { 128 }) &&
                state.builder is Some(_)
              ) ||
              (
                phase == 2 &&
                state.building &&
                state.position == (if tag == "repeat" { 32 } else { 96 }) &&
                state.builder is Some(_)
              )
            ) {
            reached = true
            break
          }
        }
        assert_true(reached, msg=tag + phase.to_string())
        let work = logical.work
        assert_true(work > 257L)
        if exhaust {
          frame.budget.remaining = 0
          assert_true(
            advance_expression_frame(frame) is Err({ kind: ControlLimit, .. }),
          )
        }
        close_expression_frame(frame)
        close_expression_frame(frame)
        assert_eq((logical.work, logical.live, workspace.live), (work, 1L, 3))
        assert_false(borrowed.released)
        assert_true(
          advance_expression_frame(frame)
          is Err({ kind: InvalidControlLimits, .. }),
        )
        release_logical_root(logical, borrowed).unwrap()
        release_slots(workspace, 3)
        assert_eq((logical.live, workspace.live), (0L, 0))
      }
    }
  }
}

///|
test "backward scalar decoder rejects nonboundaries and isolated UTF16 surrogate units" {
  // Deliberately malformed internal Strings exercise the private decoder;
  // this does not admit malformed public STRING values.
  for (text, end) in [("", 0), ("a", -1), ("a", 0), ("a", 2), ("😀", 1)] {
    assert_true(text_function_previous_scalar(text, end) is None)
  }
  for unit in [0xd800, 0xdbff, 0xdc00, 0xdfff] {
    let malformed = String::from_array([unit.unsafe_to_char()])
    assert_true(text_function_previous_scalar(malformed, 1) is None)
  }
  assert_true(
    text_function_previous_scalar("A😀", 3) is Some(('😀', 1, 4, 4)),
  )
  assert_true(text_function_previous_scalar("é", 2) is Some(('́', 1, 2, 2)))
  assert_true(
    text_function_previous_scalar("\u{0000}", 1) is Some(('\u{0000}', 0, 1, 6)),
  )
}
