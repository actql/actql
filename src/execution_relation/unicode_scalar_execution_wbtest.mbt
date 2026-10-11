///|
test "byte length counts fixed UTF8 widths while Unicode observes only first scalar" {
  // Independent expected bytes/code points, never host-derived answers.
  for
    (input, bytes, point) in [
      ("", 0.0, 0.0),
      ("abc", 3.0, 97.0),
      ("é", 2.0, 233.0),
      ("é", 3.0, 101.0),
      ("́e", 3.0, 769.0),
      ("😀é", 7.0, 128512.0),
      ("абвгд", 10.0, 1072.0),
      ("\u{d7ff}", 3.0, 55295.0),
      ("\u{e000}", 3.0, 57344.0),
      ("\u{10ffff}", 4.0, 1114111.0),
    ] {
    for tag in ["byte_length", "octet_length"] {
      assert_true(
        run_expr("\"" + tag + "('" + input + "')\"") is Ok(Number(actual)) &&
        actual == bytes,
        msg=tag + input,
      )
    }
    assert_true(
      run_expr("\"unicode('" + input + "')\"") is Ok(Number(actual)) &&
      actual == point,
      msg=input,
    )
  }
  for
    (input, bytes, point) in [
      ("\\u0000\\r\\n", 3.0, 0.0),
      ("\\r\\n", 2.0, 13.0),
      ("\\u0000x", 2.0, 0.0),
    ] {
    for (tag, expected) in [("byte_length", bytes), ("unicode", point)] {
      assert_true(
        run_expr("{\"" + tag + "\":{\"literal\":\"" + input + "\"}}")
        is Ok(Number(actual)) &&
        actual == expected,
      )
    }
  }
}

///|
test "CHR fixed scalar boundaries controls supplementary values and zero" {
  for
    (number, expected) in [
      ("0", ""),
      ("1", "\u{0001}"),
      ("9", "\t"),
      ("10", "\n"),
      ("13", "\r"),
      ("34", "\""),
      ("92", "\\"),
      ("65", "A"),
      ("127", "\u{007f}"),
      ("128", "\u{0080}"),
      ("255", "ÿ"),
      ("513", "ȁ"),
      ("1024", "Ѐ"),
      ("2047", "\u{07ff}"),
      ("2048", "\u{0800}"),
      ("55295", "\u{d7ff}"),
      ("57344", "\u{e000}"),
      ("65535", "\u{ffff}"),
      ("65536", "\u{10000}"),
      ("128512", "😀"),
      ("1114111", "\u{10ffff}"),
    ] {
    guard run_expr("\"chr(" + number + ")\"") is Ok(Text(actual)) else {
      fail(number)
    }
    assert_eq(actual, expected, msg=number)
  }
  for
    number in [
      "-1", "-0.5", "0.5", "65.5", "55296", "56319", "56320", "57343", "1114112",
      "4294967361", "9007199254740991", "1e100",
    ] {
    assert_true(
      run_expr("\"chr(" + number + ")\"")
      is Err({ kind: Scalar(InvalidOperand), .. }),
      msg=number,
    )
  }
}

///|
test "Unicode scalar strict children fail at child and outer lazy guards retain demand" {
  for tag in ["byte_length", "octet_length", "unicode", "chr"] {
    assert_true(run_expr("\"" + tag + "(NULL)\"") is Ok(Null))
    let child = if tag == "chr" { "1/0" } else { "to_string(1/0)" }
    guard run_expr("\"" + tag + "(" + child + ")\"") is Err(issue) else {
      fail(tag)
    }
    assert_true(issue.kind is Scalar(ArithmeticFailure))
    assert_true(
      @lower.expression_body(issue.expression)
      is @lower.Binary(@lower.Divide, _, _),
    )
  }
  for
    source in [
      "if(false,chr(-1),'safe')", "coalesce('safe',chr(55296))", "chr(if(true,65,1/0))",
    ] {
    assert_true(run_expr("\"" + source + "\"") is Ok(Text(_)))
  }
  for
    source in [
      "if(false,byte_length(to_string(1/0)),7)", "coalesce(7,unicode(to_string(1/0)))",
      "byte_length(if(true,'😀',to_string(1/0)))",
    ] {
    assert_true(run_expr("\"" + source + "\"") is Ok(Number(_)))
  }
  // No normalization; NUL and CHR(0) differ in byte length despite UNICODE=0.
  assert_true(run_expr("\"byte_length(chr(0))\"") is Ok(Number(0.0)))
  assert_true(run_expr("\"unicode(chr(128512))\"") is Ok(Number(128512.0)))
}

///|
fn unicode_scalar_field_expression(
  tag : String,
  type_name : String,
) -> @lower.Expression {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"payload\":{\"type\":\"" +
    type_name +
    "\",\"nullable\":false}},\"rows\":[]},\"as\":\"seed\"},{\"derive\":{\"result\":{\"" +
    tag +
    "\":{\"field\":\"payload\"}}}}]",
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
test "CHR runtime validates finite integral domain before any integer narrowing" {
  let maximum = 1.7976931348623157e308
  let infinity = maximum * 2.0
  for
    number in [
      infinity,
      -infinity,
      infinity - infinity,
      maximum,
      4294967361.0,
      1114112.0,
      55296.0,
      65.5,
    ] {
    let workspace = row_workspace(100)
    assert_true(
      evaluate_expression_with_workspace(
        unicode_scalar_field_expression("chr", "number"),
        Map([("payload", Number(number))]),
        [],
        { remaining: 1000, max_frames: 20, },
        workspace,
      )
      is Err({ kind: Scalar(InvalidOperand), .. }),
    )
    assert_eq(workspace.live, 0)
  }
}

///|
test "CHR internal signed zero yields empty without admitting negative zero source" {
  // Canonical source rejects -0. This field value is deliberately injected
  // after source admission to exercise the existing internal Number boundary.
  let result = evaluate_expression_with_workspace(
    unicode_scalar_field_expression("chr", "number"),
    Map([("payload", Number(-0.0))]),
    [],
    { remaining: 1000, max_frames: 20, },
    row_workspace(100),
  ).unwrap()
  assert_true(result is Text(""))
}

///|
test "Unicode scalar exact logical ledgers survive all resume schedules" {
  // Entry charges=2, operand consumed twice, result weight once.
  // Number-returning functions release input before retaining the result.
  // CHR output root coexists with its numeric input through construction.
  for
    (source, expected, work, live, value_bytes, output_bytes) in [
      ("\"byte_length('😀é')\"", "7", 19L, 9L, 9, 1L),
      ("\"unicode('😀é')\"", "128512", 19L, 9L, 9, 6L),
      ("\"byte_length('')\"", "0", 5L, 2L, 2, 1L),
      (
        "{\"byte_length\":{\"literal\":\"\\u0000\\r\\n\"}}", "3", 11L, 12L, 12, 1L,
      ),
      ("\"chr(0)\"", "\"\"", 5L, 3L, 2, 2L),
      ("\"chr(65)\"", "\"A\"", 6L, 5L, 3, 3L),
      ("\"chr(1)\"", "\"\\u0001\"", 6L, 9L, 8, 8L),
      ("\"chr(13)\"", "\"\\r\"", 6L, 6L, 4, 4L),
      ("\"chr(128512)\"", "\"😀\"", 9L, 12L, 6, 6L),
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
test "byte length suspends during scalar scanning and preserves unrelated roots on cancellation" {
  let logical = text_expression_budget(10000L, 10000L)
  let borrowed = retain_logical_value(logical, Number(9)).unwrap()
  let workspace = row_workspace(100)
  let frame = expression_frame(
    unicode_scalar_field_expression("byte_length", "string"),
    Map([("payload", Text("😀é".repeat(128)))]),
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
    if frame.state is TextFunction(state) && state.count == 64 {
      reached = true
      break
    }
  }
  assert_true(reached)
  let work = logical.work
  close_expression_frame(frame)
  close_expression_frame(frame)
  assert_eq((logical.work, logical.live, workspace.live), (work, 1L, 0))
  assert_false(borrowed.released)
  assert_true(
    advance_expression_frame(frame) is Err({ kind: InvalidControlLimits, .. }),
  )
  release_logical_root(logical, borrowed).unwrap()
}

///|
test "CHR cancellation releases reserved output and builder without touching borrowed root" {
  for phase in 0..<3 {
    let logical = text_expression_budget(1000L, 1000L)
    let borrowed = retain_logical_value(logical, Number(9)).unwrap()
    let workspace = row_workspace(100)
    let frame = expression_frame(
      lowered("\"chr(128512)\""),
      Map([]),
      [],
      { remaining: 10000, max_frames: 20, },
      workspace,
      Some(expression_roots(logical, 20)),
    ).unwrap()
    let mut reached = false
    for _ in 0..<1000 {
      assert_true(advance_expression_frame(frame) is Ok(None))
      if frame.state is TextFunction(state) &&
        (
          (phase == 0 && !state.building && state.bytes == 6) ||
          (
            phase == 1 &&
            state.building &&
            state.position == 0 &&
            state.builder is Some(_)
          ) ||
          (
            phase == 2 &&
            state.building &&
            state.position == 1 &&
            state.builder is Some(_)
          )
        ) {
        reached = true
        break
      }
    }
    assert_true(reached)
    let work = logical.work
    close_expression_frame(frame)
    close_expression_frame(frame)
    assert_eq((logical.work, logical.live, workspace.live), (work, 1L, 0))
    assert_false(borrowed.released)
    release_logical_root(logical, borrowed).unwrap()
  }
}

///|
test "Unicode scalar success and control failures are invariant under drain scheduling" {
  for
    source in [
      "\"byte_length('😀é😀')\"", "\"unicode('😀é')\"", "\"chr(128512)\"",
      "\"chr(55296)\"",
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
        _ => fail("drain changed Unicode scalar outcome")
      }
      assert_eq((a.work, a.peak, a.live), (b.work, b.peak, b.live))
      assert_eq(a.live, 0L)
    }
  }
}

///|
test "Unicode scalar exact workspace caps reject one short and release every frame" {
  // The unary continuation plus eight cursor handles and two wire frames
  // require eleven slots while a String field input is measured. Number
  // input uses the immediate scalar path without that cursor. CHR therefore
  // peaks at two fixed slots plus two supplementary UTF-16 output units.
  for
    (tag, type_name, input, expected, work, live) in [
      ("byte_length", "string", Text("😀é".repeat(128)), "896", 1797L, 898L),
      ("unicode", "string", Text("😀é".repeat(128)), "128512", 1797L, 898L),
      ("chr", "number", Number(128512.0), "\"😀\"", 9L, 12L),
    ] {
    let exact_slots = if tag == "chr" { 4 } else { 11 }
    for slots in [exact_slots, exact_slots - 1] {
      let logical = text_expression_budget(work, live)
      let workspace = row_workspace(slots)
      let result = evaluate_expression_with_workspace(
        unicode_scalar_field_expression(tag, type_name),
        Map([("payload", input)]),
        [],
        { remaining: 100000, max_frames: 20, },
        workspace,
        logical_work=Some(logical),
      )
      if slots == exact_slots {
        assert_eq(object_result_wire(result.unwrap()), expected)
        assert_eq(
          (logical.work, logical.peak, workspace.peak),
          (work, live, exact_slots),
        )
      } else {
        assert_true(result is Err({ kind: WorkspaceLimit, .. }), msg=tag)
      }
      assert_eq((logical.live, workspace.live), (0L, 0))
    }
  }
}

///|
test "CHR escaped output over cap fails before allocating its builder" {
  let logical = logical_budget(
    {
      max_input_rows: 1L,
      max_value_bytes: 7L,
      max_live_value_bytes: 9L,
      max_work: 6L,
    },
    8,
    1,
    1,
  ).unwrap()
  let workspace = row_workspace(100)
  let frame = expression_frame(
    lowered("\"chr(1)\""),
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

///|
test "CHR exact canonical measurement covers every control escape and UTF8 transition" {
  // Fixed independent Unicode/JSON wire literals. Work = two entries, twice
  // the Number node weight, and one String node plus UTF-8 payload bytes.
  // Live bytes = decimal input wire plus quoted/escaped output wire.
  for
    (point, expected_wire, output_bytes, work, live, value_bytes) in [
      ("1", "\"\\u0001\"", 8, 6L, 9L, 8),
      ("2", "\"\\u0002\"", 8, 6L, 9L, 8),
      ("3", "\"\\u0003\"", 8, 6L, 9L, 8),
      ("4", "\"\\u0004\"", 8, 6L, 9L, 8),
      ("5", "\"\\u0005\"", 8, 6L, 9L, 8),
      ("6", "\"\\u0006\"", 8, 6L, 9L, 8),
      ("7", "\"\\u0007\"", 8, 6L, 9L, 8),
      ("8", "\"\\b\"", 4, 6L, 5L, 4),
      ("9", "\"\\t\"", 4, 6L, 5L, 4),
      ("10", "\"\\n\"", 4, 6L, 6L, 4),
      ("11", "\"\\u000b\"", 8, 6L, 10L, 8),
      ("12", "\"\\f\"", 4, 6L, 6L, 4),
      ("13", "\"\\r\"", 4, 6L, 6L, 4),
      ("14", "\"\\u000e\"", 8, 6L, 10L, 8),
      ("15", "\"\\u000f\"", 8, 6L, 10L, 8),
      ("16", "\"\\u0010\"", 8, 6L, 10L, 8),
      ("17", "\"\\u0011\"", 8, 6L, 10L, 8),
      ("18", "\"\\u0012\"", 8, 6L, 10L, 8),
      ("19", "\"\\u0013\"", 8, 6L, 10L, 8),
      ("20", "\"\\u0014\"", 8, 6L, 10L, 8),
      ("21", "\"\\u0015\"", 8, 6L, 10L, 8),
      ("22", "\"\\u0016\"", 8, 6L, 10L, 8),
      ("23", "\"\\u0017\"", 8, 6L, 10L, 8),
      ("24", "\"\\u0018\"", 8, 6L, 10L, 8),
      ("25", "\"\\u0019\"", 8, 6L, 10L, 8),
      ("26", "\"\\u001a\"", 8, 6L, 10L, 8),
      ("27", "\"\\u001b\"", 8, 6L, 10L, 8),
      ("28", "\"\\u001c\"", 8, 6L, 10L, 8),
      ("29", "\"\\u001d\"", 8, 6L, 10L, 8),
      ("30", "\"\\u001e\"", 8, 6L, 10L, 8),
      ("31", "\"\\u001f\"", 8, 6L, 10L, 8),
      ("34", "\"\\\"\"", 4, 6L, 6L, 4),
      ("92", "\"\\\\\"", 4, 6L, 6L, 4),
      ("127", "\"\"", 3, 6L, 6L, 3),
      ("128", "\"\"", 4, 7L, 7L, 4),
      ("2047", "\"߿\"", 4, 7L, 8L, 4),
      ("2048", "\"ࠀ\"", 5, 8L, 9L, 5),
      ("55295", "\"퟿\"", 5, 8L, 10L, 5),
      ("57344", "\"\"", 5, 8L, 10L, 5),
      ("65535", "\"￿\"", 5, 8L, 10L, 5),
      ("65536", "\"𐀀\"", 6, 9L, 11L, 6),
      ("1114111", "\"􏿿\"", 6, 9L, 13L, 7),
    ] {
    for drain in [false, true] {
      let logical = logical_budget(
        {
          max_input_rows: 1L,
          max_value_bytes: value_bytes.to_int64(),
          max_live_value_bytes: live,
          max_work: work,
        },
        value_bytes,
        1,
        1,
      ).unwrap()
      let result = resume_test_expression(
        "\"chr(" + point + ")\"",
        logical,
        1,
        drain~,
      ).unwrap()
      assert_eq(object_result_wire(result.value), expected_wire, msg=point)
      assert_eq(
        (logical.work, logical.peak, logical.live),
        (work, live, output_bytes.to_int64()),
        msg=point,
      )
      release_logical_root(logical, result.root.unwrap()).unwrap()
      assert_eq(logical.live, 0L)
    }
  }
}
