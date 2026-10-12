///|
// Fixed independently authored GoogleSQL STRING examples, extended with
// ActQL finite-integral Number parameters. No product-derived expectations.
test "translate fixed simultaneous deletion surplus target and Unicode scalar semantics" {
  assert_true(
    run_expr(
      "{\"translate\":[{\"literal\":\"ab\"},{\"literal\":\"ab\"},{\"literal\":\"ba\"}]}",
    )
    is Ok(Text(actual)) &&
    actual == "ba",
  )
  assert_true(
    run_expr(
      "{\"translate\":[{\"literal\":\"abcabc\"},{\"literal\":\"abc\"},{\"literal\":\"x\"}]}",
    )
    is Ok(Text(actual)) &&
    actual == "xx",
  )
  assert_true(
    run_expr(
      "{\"translate\":[{\"literal\":\"banana\"},{\"literal\":\"an\"},{\"literal\":\"xy\"}]}",
    )
    is Ok(Text(actual)) &&
    actual == "bxyxyx",
  )
  assert_true(
    run_expr(
      "{\"translate\":[{\"literal\":\"This is a cookie\"},{\"literal\":\"sco\"},{\"literal\":\"zku\"}]}",
    )
    is Ok(Text(actual)) &&
    actual == "Thiz iz a kuukie",
  )
  assert_true(
    run_expr(
      "{\"translate\":[{\"literal\":\"abc\"},{\"literal\":\"a\"},{\"literal\":\"XYZ\"}]}",
    )
    is Ok(Text(actual)) &&
    actual == "Xbc",
  )
  assert_true(
    run_expr(
      "{\"translate\":[{\"literal\":\"abc\"},{\"literal\":\"\"},{\"literal\":\"XYZ\"}]}",
    )
    is Ok(Text(actual)) &&
    actual == "abc",
  )
  assert_true(
    run_expr(
      "{\"translate\":[{\"literal\":\"abc\"},{\"literal\":\"abc\"},{\"literal\":\"\"}]}",
    )
    is Ok(Text(actual)) &&
    actual == "",
  )
  assert_true(
    run_expr(
      "{\"translate\":[{\"literal\":\"\"},{\"literal\":\"ab\"},{\"literal\":\"ba\"}]}",
    )
    is Ok(Text(actual)) &&
    actual == "",
  )
  assert_true(
    run_expr(
      "{\"translate\":[{\"literal\":\"😀A😀\"},{\"literal\":\"😀A\"},{\"literal\":\"é💻\"}]}",
    )
    is Ok(Text(actual)) &&
    actual == "é💻é",
  )
  assert_true(
    run_expr(
      "{\"translate\":[{\"literal\":\"A😀é\"},{\"literal\":\"😀é\"},{\"literal\":\"xE!\"}]}",
    )
    is Ok(Text(actual)) &&
    actual == "AxE!",
  )
  assert_true(
    run_expr(
      "{\"translate\":[{\"literal\":\"é é\"},{\"literal\":\"é\"},{\"literal\":\"X\"}]}",
    )
    is Ok(Text(actual)) &&
    actual == "X é",
  )
  assert_true(
    run_expr(
      "{\"translate\":[{\"literal\":\"é é\"},{\"literal\":\"é\"},{\"literal\":\"E!\"}]}",
    )
    is Ok(Text(actual)) &&
    actual == "é E!",
  )
  assert_true(
    run_expr(
      "{\"translate\":[{\"literal\":\"A\\u0000\\r\\n😀\"},{\"literal\":\"\\u0000😀\"},{\"literal\":\"Z💻\"}]}",
    )
    is Ok(Text(actual)) &&
    actual == "AZ\r\n💻",
  )
  assert_true(
    run_expr(
      "{\"translate\":[{\"literal\":\"aaab\"},{\"literal\":\"ab\"},{\"literal\":\"xx\"}]}",
    )
    is Ok(Text(actual)) &&
    actual == "xxxx",
  )
  assert_true(
    run_expr(
      "{\"translate\":[{\"literal\":\"a\"},{\"literal\":\"a\"},{\"literal\":\"😀\"}]}",
    )
    is Ok(Text(actual)) &&
    actual == "😀",
  )
  assert_true(
    run_expr(
      "{\"translate\":[{\"literal\":\"퟿𐀀􏿿\"},{\"literal\":\"퟿􏿿\"},{\"literal\":\"😀A\"}]}",
    )
    is Ok(Text(actual)) &&
    actual == "😀𐀀A",
  )
}

///|
test "instr fixed overlaps backwards Unicode and empty n plus one boundaries" {
  assert_true(
    run_expr("{\"instr\":[{\"literal\":\"banana\"},{\"literal\":\"an\"}]}")
    is Ok(Number(2.0)),
  )
  assert_true(
    run_expr(
      "{\"instr\":[{\"literal\":\"banana\"},{\"literal\":\"an\"},{\"literal\":1}]}",
    )
    is Ok(Number(2.0)),
  )
  assert_true(
    run_expr(
      "{\"instr\":[{\"literal\":\"banana\"},{\"literal\":\"an\"},{\"literal\":1},{\"literal\":1}]}",
    )
    is Ok(Number(2.0)),
  )
  assert_true(
    run_expr(
      "{\"instr\":[{\"literal\":\"banana\"},{\"literal\":\"an\"},{\"literal\":1},{\"literal\":2}]}",
    )
    is Ok(Number(4.0)),
  )
  assert_true(
    run_expr(
      "{\"instr\":[{\"literal\":\"banana\"},{\"literal\":\"an\"},{\"literal\":1},{\"literal\":3}]}",
    )
    is Ok(Number(0.0)),
  )
  assert_true(
    run_expr(
      "{\"instr\":[{\"literal\":\"banana\"},{\"literal\":\"an\"},{\"literal\":3},{\"literal\":1}]}",
    )
    is Ok(Number(4.0)),
  )
  assert_true(
    run_expr(
      "{\"instr\":[{\"literal\":\"banana\"},{\"literal\":\"an\"},{\"literal\":-1},{\"literal\":1}]}",
    )
    is Ok(Number(4.0)),
  )
  assert_true(
    run_expr(
      "{\"instr\":[{\"literal\":\"banana\"},{\"literal\":\"an\"},{\"literal\":-3},{\"literal\":1}]}",
    )
    is Ok(Number(4.0)),
  )
  assert_true(
    run_expr(
      "{\"instr\":[{\"literal\":\"banana\"},{\"literal\":\"an\"},{\"literal\":-1},{\"literal\":2}]}",
    )
    is Ok(Number(2.0)),
  )
  assert_true(
    run_expr(
      "{\"instr\":[{\"literal\":\"banana\"},{\"literal\":\"an\"},{\"literal\":-4},{\"literal\":1}]}",
    )
    is Ok(Number(2.0)),
  )
  assert_true(
    run_expr(
      "{\"instr\":[{\"literal\":\"banana\"},{\"literal\":\"an\"},{\"literal\":-7},{\"literal\":1}]}",
    )
    is Ok(Number(0.0)),
  )
  assert_true(
    run_expr(
      "{\"instr\":[{\"literal\":\"aaaa\"},{\"literal\":\"aa\"},{\"literal\":1},{\"literal\":3}]}",
    )
    is Ok(Number(3.0)),
  )
  assert_true(
    run_expr(
      "{\"instr\":[{\"literal\":\"aaaa\"},{\"literal\":\"aa\"},{\"literal\":-1},{\"literal\":3}]}",
    )
    is Ok(Number(1.0)),
  )
  assert_true(
    run_expr(
      "{\"instr\":[{\"literal\":\"helloooo\"},{\"literal\":\"oo\"},{\"literal\":1},{\"literal\":2}]}",
    )
    is Ok(Number(6.0)),
  )
  assert_true(
    run_expr(
      "{\"instr\":[{\"literal\":\"😀a😀a\"},{\"literal\":\"😀a\"},{\"literal\":1},{\"literal\":2}]}",
    )
    is Ok(Number(3.0)),
  )
  assert_true(
    run_expr(
      "{\"instr\":[{\"literal\":\"😀a😀a\"},{\"literal\":\"😀a\"},{\"literal\":-1},{\"literal\":2}]}",
    )
    is Ok(Number(1.0)),
  )
  assert_true(
    run_expr("{\"instr\":[{\"literal\":\"éé\"},{\"literal\":\"é\"}]}")
    is Ok(Number(3.0)),
  )
  assert_true(
    run_expr("{\"instr\":[{\"literal\":\"é\"},{\"literal\":\"é\"}]}")
    is Ok(Number(0.0)),
  )
  assert_true(
    run_expr(
      "{\"instr\":[{\"literal\":\"A\\u0000😀\"},{\"literal\":\"\\u0000😀\"}]}",
    )
    is Ok(Number(2.0)),
  )
  assert_true(
    run_expr("{\"instr\":[{\"literal\":\"abc\"},{\"literal\":\"x\"}]}")
    is Ok(Number(0.0)),
  )
  assert_true(
    run_expr("{\"instr\":[{\"literal\":\"\"},{\"literal\":\"a\"}]}")
    is Ok(Number(0.0)),
  )
  assert_true(
    run_expr("{\"instr\":[{\"literal\":\"\"},{\"literal\":\"\"}]}")
    is Ok(Number(1.0)),
  )
  assert_true(
    run_expr(
      "{\"instr\":[{\"literal\":\"\"},{\"literal\":\"\"},{\"literal\":-1}]}",
    )
    is Ok(Number(1.0)),
  )
  assert_true(
    run_expr(
      "{\"instr\":[{\"literal\":\"\"},{\"literal\":\"\"},{\"literal\":2}]}",
    )
    is Ok(Number(0.0)),
  )
  assert_true(
    run_expr(
      "{\"instr\":[{\"literal\":\"ab\"},{\"literal\":\"\"},{\"literal\":1},{\"literal\":3}]}",
    )
    is Ok(Number(3.0)),
  )
  assert_true(
    run_expr(
      "{\"instr\":[{\"literal\":\"ab\"},{\"literal\":\"\"},{\"literal\":1},{\"literal\":4}]}",
    )
    is Ok(Number(0.0)),
  )
  assert_true(
    run_expr(
      "{\"instr\":[{\"literal\":\"ab\"},{\"literal\":\"\"},{\"literal\":3}]}",
    )
    is Ok(Number(3.0)),
  )
  assert_true(
    run_expr(
      "{\"instr\":[{\"literal\":\"ab\"},{\"literal\":\"\"},{\"literal\":4}]}",
    )
    is Ok(Number(0.0)),
  )
  assert_true(
    run_expr(
      "{\"instr\":[{\"literal\":\"ab\"},{\"literal\":\"\"},{\"literal\":-1}]}",
    )
    is Ok(Number(3.0)),
  )
  assert_true(
    run_expr(
      "{\"instr\":[{\"literal\":\"ab\"},{\"literal\":\"\"},{\"literal\":-2}]}",
    )
    is Ok(Number(2.0)),
  )
  assert_true(
    run_expr(
      "{\"instr\":[{\"literal\":\"ab\"},{\"literal\":\"\"},{\"literal\":-3}]}",
    )
    is Ok(Number(1.0)),
  )
  assert_true(
    run_expr(
      "{\"instr\":[{\"literal\":\"ab\"},{\"literal\":\"\"},{\"literal\":-4}]}",
    )
    is Ok(Number(0.0)),
  )
  assert_true(
    run_expr(
      "{\"instr\":[{\"literal\":\"ab\"},{\"literal\":\"\"},{\"literal\":-1},{\"literal\":3}]}",
    )
    is Ok(Number(1.0)),
  )
  assert_true(
    run_expr(
      "{\"instr\":[{\"literal\":\"ab\"},{\"literal\":\"\"},{\"literal\":-1},{\"literal\":4}]}",
    )
    is Ok(Number(0.0)),
  )
  assert_true(
    run_expr(
      "{\"instr\":[{\"literal\":\"😀a\"},{\"literal\":\"\"},{\"literal\":-2}]}",
    )
    is Ok(Number(2.0)),
  )
  assert_true(
    run_expr(
      "{\"instr\":[{\"literal\":\"a\"},{\"literal\":\"a\"},{\"literal\":1e+100}]}",
    )
    is Ok(Number(0.0)),
  )
  assert_true(
    run_expr(
      "{\"instr\":[{\"literal\":\"a\"},{\"literal\":\"a\"},{\"literal\":-1e+100}]}",
    )
    is Ok(Number(0.0)),
  )
  assert_true(
    run_expr(
      "{\"instr\":[{\"literal\":\"a\"},{\"literal\":\"a\"},{\"literal\":1},{\"literal\":1e+100}]}",
    )
    is Ok(Number(0.0)),
  )
  assert_true(
    run_expr(
      "{\"instr\":[{\"literal\":\"\"},{\"literal\":\"\"},{\"literal\":1},{\"literal\":1e+100}]}",
    )
    is Ok(Number(0.0)),
  )
  assert_true(
    run_expr(
      "{\"instr\":[{\"literal\":\"a\"},{\"literal\":\"a\"},{\"literal\":9007199254740992}]}",
    )
    is Ok(Number(0.0)),
  )
  assert_true(
    run_expr(
      "{\"instr\":[{\"literal\":\"a\"},{\"literal\":\"a\"},{\"literal\":-9223372036854775808}]}",
    )
    is Ok(Number(0.0)),
  )
}

///|
test "translate source duplicate errors remain visible for empty input and unused characters" {
  assert_true(
    run_expr(
      "{\"translate\":[{\"literal\":\"\"},{\"literal\":\"aa\"},{\"literal\":\"x\"}]}",
    )
    is Err({ kind: Scalar(InvalidOperand), .. }),
  )
  assert_true(
    run_expr(
      "{\"translate\":[{\"literal\":\"\"},{\"literal\":\"😀😀\"},{\"literal\":\"x\"}]}",
    )
    is Err({ kind: Scalar(InvalidOperand), .. }),
  )
  assert_true(
    run_expr(
      "{\"translate\":[{\"literal\":\"\"},{\"literal\":\"ée\"},{\"literal\":\"x\"}]}",
    )
    is Err({ kind: Scalar(InvalidOperand), .. }),
  )
  assert_true(
    run_expr(
      "{\"translate\":[{\"literal\":\"\"},{\"literal\":\"\\u0000x\\u0000\"},{\"literal\":\"x\"}]}",
    )
    is Err({ kind: Scalar(InvalidOperand), .. }),
  )
  assert_true(
    run_expr(
      "{\"translate\":[{\"literal\":\"unrelated\"},{\"literal\":\"aa\"},{\"literal\":\"x\"}]}",
    )
    is Err({ kind: Scalar(InvalidOperand), .. }),
  )
  assert_true(
    run_expr(
      "{\"translate\":[{\"literal\":\"unrelated\"},{\"literal\":\"😀😀\"},{\"literal\":\"x\"}]}",
    )
    is Err({ kind: Scalar(InvalidOperand), .. }),
  )
  assert_true(
    run_expr(
      "{\"translate\":[{\"literal\":\"unrelated\"},{\"literal\":\"ée\"},{\"literal\":\"x\"}]}",
    )
    is Err({ kind: Scalar(InvalidOperand), .. }),
  )
  assert_true(
    run_expr(
      "{\"translate\":[{\"literal\":\"unrelated\"},{\"literal\":\"\\u0000x\\u0000\"},{\"literal\":\"x\"}]}",
    )
    is Err({ kind: Scalar(InvalidOperand), .. }),
  )
  assert_true(
    run_expr(
      "{\"translate\":[{\"literal\":\"a\"},{\"literal\":\"aa\"},{\"literal\":\"x\"}]}",
    )
    is Err({ kind: Scalar(InvalidOperand), .. }),
  )
  assert_true(
    run_expr(
      "{\"translate\":[{\"literal\":\"a\"},{\"literal\":\"😀😀\"},{\"literal\":\"x\"}]}",
    )
    is Err({ kind: Scalar(InvalidOperand), .. }),
  )
  assert_true(
    run_expr(
      "{\"translate\":[{\"literal\":\"a\"},{\"literal\":\"ée\"},{\"literal\":\"x\"}]}",
    )
    is Err({ kind: Scalar(InvalidOperand), .. }),
  )
  assert_true(
    run_expr(
      "{\"translate\":[{\"literal\":\"a\"},{\"literal\":\"\\u0000x\\u0000\"},{\"literal\":\"x\"}]}",
    )
    is Err({ kind: Scalar(InvalidOperand), .. }),
  )
}

///|
test "translate instr strict children precede NULL or domain shortcuts and retain child blame" {
  assert_true(run_expr("\"translate(NULL,'aa','x')\"") is Ok(Null))
  assert_true(run_expr("\"translate('a',NULL,'x')\"") is Ok(Null))
  assert_true(run_expr("\"translate('a','aa',NULL)\"") is Ok(Null))
  assert_true(run_expr("\"instr(NULL,'a',0,-1)\"") is Ok(Null))
  assert_true(run_expr("\"instr('a',NULL,0,-1)\"") is Ok(Null))
  assert_true(run_expr("\"instr('a','a',NULL,-1)\"") is Ok(Null))
  assert_true(run_expr("\"instr('a','a',0,NULL)\"") is Ok(Null))
  {
    guard run_expr("\"translate(NULL,to_string(1/0),'x')\"") is Err(issue) else {
      fail("strict child must fail")
    }
    assert_true(issue.kind is Scalar(ArithmeticFailure))
    assert_true(
      @lower.expression_body(issue.expression)
      is @lower.Binary(@lower.Divide, _, _),
    )
  }
  {
    guard run_expr("\"translate('','aa',to_string(1/0))\"") is Err(issue) else {
      fail("strict child must fail")
    }
    assert_true(issue.kind is Scalar(ArithmeticFailure))
    assert_true(
      @lower.expression_body(issue.expression)
      is @lower.Binary(@lower.Divide, _, _),
    )
  }
  {
    guard run_expr("\"instr(NULL,'a',1/0)\"") is Err(issue) else {
      fail("strict child must fail")
    }
    assert_true(issue.kind is Scalar(ArithmeticFailure))
    assert_true(
      @lower.expression_body(issue.expression)
      is @lower.Binary(@lower.Divide, _, _),
    )
  }
  {
    guard run_expr("\"instr('','',NULL,1/0)\"") is Err(issue) else {
      fail("strict child must fail")
    }
    assert_true(issue.kind is Scalar(ArithmeticFailure))
    assert_true(
      @lower.expression_body(issue.expression)
      is @lower.Binary(@lower.Divide, _, _),
    )
  }
  guard run_expr("\"translate(to_string(sqrt(-1)),to_string(1/0),NULL)\"")
    is Err(issue) else {
    fail("first strict child")
  }
  assert_true(
    @lower.expression_body(issue.expression) is @lower.Unary(@lower.Sqrt, _),
  )
}

///|
test "translate instr enclosing and child-local demand stays lazy" {
  assert_eq(
    object_result_wire(
      run_expr("\"if(false,translate('','aa','x'),'safe')\"").unwrap(),
    ),
    "\"safe\"",
  )
  assert_eq(
    object_result_wire(run_expr("\"coalesce(7,instr(NULL,'a',1/0))\"").unwrap()),
    "7",
  )
  assert_eq(
    object_result_wire(
      run_expr("\"translate(if(true,'a',to_string(1/0)),'a','😀')\"").unwrap(),
    ),
    "\"😀\"",
  )
  assert_eq(
    object_result_wire(
      run_expr("\"instr('aaaa','aa',if(true,-1,1/0),2)\"").unwrap(),
    ),
    "2",
  )
}

///|
fn translate_instr_field_expression(tag : String) -> @lower.Expression {
  let body = if tag == "translate" {
    "{\"translate\":[{\"field\":\"payload\"},{\"field\":\"source\"},{\"field\":\"target\"}]}"
  } else {
    "{\"instr\":[{\"field\":\"payload\"},{\"field\":\"pattern\"},{\"field\":\"position\"},{\"field\":\"occurrence\"}]}"
  }
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"payload\":{\"type\":\"string\",\"nullable\":false},\"source\":{\"type\":\"string\",\"nullable\":false},\"target\":{\"type\":\"string\",\"nullable\":false},\"pattern\":{\"type\":\"string\",\"nullable\":false},\"position\":{\"type\":\"number\",\"nullable\":false},\"occurrence\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[]},\"as\":\"seed\"},{\"derive\":{\"result\":" +
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
test "instr internal numeric admission validates full values before narrowing or empty shortcuts" {
  let maximum = 1.7976931348623157e308
  let infinity = maximum * 2.0
  for text in ["", "a"] {
    for slot in ["position", "occurrence"] {
      for
        number in [
          infinity,
          -infinity,
          infinity - infinity,
          0.0,
          -0.0,
          0.5,
          -0.5,
        ] {
        let workspace = row_workspace(100)
        let result = evaluate_expression_with_workspace(
          translate_instr_field_expression("instr"),
          Map([
            ("payload", Text(text)),
            ("pattern", Text("")),
            ("position", Number(if slot == "position" { number } else { 1.0 })),
            (
              "occurrence",
              Number(if slot == "occurrence" { number } else { 1.0 }),
            ),
          ]),
          [],
          { remaining: 10000, max_frames: 20, },
          workspace,
        )
        assert_true(result is Err({ kind: Scalar(InvalidOperand), .. }))
        assert_eq(workspace.live, 0)
      }
    }
    for
      (position, occurrence, expected) in [
        (maximum, 1.0, 0.0),
        (-maximum, 1.0, 0.0),
        (1.0, maximum, 0.0),
        (9007199254740992.0, 1.0, 0.0),
        (1.0, 9223372036854775808.0, 0.0),
      ] {
      let workspace = row_workspace(100)
      assert_true(
        evaluate_expression_with_workspace(
          translate_instr_field_expression("instr"),
          Map([
            ("payload", Text(text)),
            ("pattern", Text("")),
            ("position", Number(position)),
            ("occurrence", Number(occurrence)),
          ]),
          [],
          { remaining: 10000, max_frames: 20, },
          workspace,
        )
        is Ok(Number(actual)) &&
        actual == expected,
      )
      assert_eq(workspace.live, 0)
    }
  }
  assert_true(
    run_expr("\"instr('a','a',1,-1)\"")
    is Err({ kind: Scalar(InvalidOperand), .. }),
  )
}

///|
test "translate instr exact logical work live escaped bytes and value caps survive schedules" {
  // Independent ledger: arity+1 entries + twice each operand weight + one
  // output weight. String weight=1+UTF8 bytes; Number weight=1. TRANSLATE
  // operands coexist with pending output; INSTR releases operands first.
  for
    (source, expected, work, live, value_bytes, output_bytes) in [
      (
        "{\"translate\":[{\"literal\":\"\"},{\"literal\":\"\"},{\"literal\":\"\"}]}",
        "\"\"", 11L, 8L, 2, 2L,
      ),
      (
        "{\"translate\":[{\"literal\":\"a\"},{\"literal\":\"a\"},{\"literal\":\"😀\"}]}",
        "\"😀\"", 27L, 18L, 6, 6L,
      ),
      (
        "{\"translate\":[{\"literal\":\"abc\"},{\"literal\":\"abc\"},{\"literal\":\"\"}]}",
        "\"\"", 23L, 14L, 5, 2L,
      ),
      (
        "{\"translate\":[{\"literal\":\"ab\"},{\"literal\":\"ab\"},{\"literal\":\"ba\"}]}",
        "\"ba\"", 25L, 16L, 4, 4L,
      ),
      (
        "{\"translate\":[{\"literal\":\"\\u0000\"},{\"literal\":\"\\u0000\"},{\"literal\":\"\\r\\n\"}]}",
        "\"\\r\"", 20L, 26L, 8, 4L,
      ),
      (
        "{\"instr\":[{\"literal\":\"banana\"},{\"literal\":\"an\"}]}", "2", 24L,
        12L, 8, 1L,
      ),
      (
        "{\"instr\":[{\"literal\":\"banana\"},{\"literal\":\"an\"},{\"literal\":1},{\"literal\":2}]}",
        "4", 30L, 14L, 8, 1L,
      ),
      (
        "{\"instr\":[{\"literal\":\"\"},{\"literal\":\"\"}]}", "1", 8L, 4L, 2, 1L,
      ),
      (
        "{\"instr\":[{\"literal\":\"ab\"},{\"literal\":\"\"},{\"literal\":-1}]}",
        "3", 15L, 8L, 4, 1L,
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
test "translate instr exact long String workspace and logical bounds clean up one short failures" {
  // TRANSLATE: weights257+5+2, output65, four entries; canonical roots
  // 258+6+3+66=333; 12 continuation slots +64 UTF16 output units=76.
  // INSTR: weights257+5+1+1, five entries, Number output1; operand wire
  // 258+6+1+2=267. Long input measurement retains13 parent+10 cursor slots.
  for
    (tag, work, live, slots, expected) in [
      ("translate", 597L, 333L, 76, "\"" + String::make(64, 'a') + "\""),
      ("instr", 534L, 267L, 23, "64"),
    ] {
    for short in 0..<4 {
      let logical = text_expression_budget(
        work - (if short == 1 { 1L } else { 0L }),
        live - (if short == 2 { 1L } else { 0L }),
      )
      let workspace = row_workspace(slots - (if short == 3 { 1 } else { 0 }))
      let result = evaluate_expression_with_workspace(
        translate_instr_field_expression(tag),
        Map([
          ("payload", Text(String::make(64, '😀'))),
          ("source", Text("😀")),
          ("target", Text("a")),
          ("pattern", Text("😀")),
          ("position", Number(1.0)),
          ("occurrence", Number(64.0)),
        ]),
        [],
        { remaining: 100000, max_frames: 20, },
        workspace,
        logical_work=Some(logical),
      )
      match short {
        0 => {
          assert_eq(object_result_wire(result.unwrap()), expected)
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
        _ => fail("boundary selection")
      }
      assert_eq((logical.live, workspace.live), (0L, 0))
    }
  }
}

///|
test "translate escaped output cap is enforced before builder allocation" {
  let logical = logical_budget(
    {
      max_input_rows: 1L,
      max_value_bytes: 12L,
      max_live_value_bytes: 100L,
      max_work: 100L,
    },
    100,
    10,
    10,
  ).unwrap()
  let workspace = row_workspace(100)
  let frame = expression_frame(
    lowered(
      "{\"translate\":[{\"literal\":\"aaa\"},{\"literal\":\"a\"},{\"literal\":\"\\u0000\"}]}",
    ),
    Map([]),
    [],
    { remaining: 10000, max_frames: 20, },
    workspace,
    Some(expression_roots(logical, 20)),
  ).unwrap()
  let mut failed = false
  for _ in 0..<1000 {
    match advance_expression_frame(frame) {
      Err(issue) => {
        assert_true(issue.kind is LogicalValue(_))
        failed = true
        break
      }
      Ok(Some(_)) => fail("escaped output cannot fit")
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
test "translate instr outcomes and charged accounting remain invariant under drain schedules" {
  for
    source in [
      "\"translate('😀a😀','😀a','A')\"", "\"translate('','aa','x')\"", "\"instr('aaaa','aa',-1,3)\"",
      "\"instr('ab','',-1,4)\"", "\"instr('a','a',0)\"",
    ] {
    for control in [0, 1, 5, 10, 20, 40, 100, 1000] {
      let a = text_expression_budget(1000L, 1000L)
      let b = text_expression_budget(1000L, 1000L)
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
        _ => fail("drain changed outcome")
      }
      assert_eq((a.work, a.peak, a.live), (b.work, b.peak, b.live))
      assert_eq(a.live, 0L)
    }
  }
}

///|
test "translate validation lookup sizing and build can cancel without leaking unrelated custody" {
  let unique_source = "!\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"
  for phase in 0..<5 {
    for exhaust in [false, true] {
      let logical = text_expression_budget(10000L, 10000L)
      let borrowed = retain_logical_value(logical, Number(9)).unwrap()
      let workspace = row_workspace(2000)
      assert_true(reserve_slots(workspace, 3))
      let frame = expression_frame(
        translate_instr_field_expression("translate"),
        Map([
          ("payload", Text(String::make(64, 'a'))),
          ("source", Text(unique_source)),
          ("target", Text(String::make(94, '😀'))),
        ]),
        [],
        { remaining: 100000, max_frames: 20, },
        workspace,
        Some(expression_roots(logical, 20)),
      ).unwrap()
      let mut reached = false
      for _ in 0..<30000 {
        let before = frame.budget.remaining
        assert_true(advance_expression_frame(frame) is Ok(None))
        assert_true(before - frame.budget.remaining <= 64)
        if frame.state is TextFunction(state) &&
          (
            (
              phase == 0 &&
              !state.translate_validated &&
              state.translate_outer == 0 &&
              state.translate_inner == 32
            ) ||
            (
              phase == 1 &&
              state.translate_validated &&
              !state.building &&
              state.position == 0 &&
              state.matched == 32
            ) ||
            (phase == 2 && !state.building && state.units == 32) ||
            (
              phase == 3 &&
              state.building &&
              state.position == 0 &&
              state.builder is Some(_)
            ) ||
            (
              phase == 4 &&
              state.building &&
              state.position == 16 &&
              state.builder is Some(_)
            )
          ) {
          reached = true
          break
        }
      }
      assert_true(reached, msg=phase.to_string())
      let work = logical.work
      assert_true(work > 0L)
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

///|
test "instr long scans and repeated prefix comparisons yield in both directions and clean up" {
  for direction in [1.0, -1.0] {
    for phase in 0..<3 {
      for exhaust in [false, true] {
        let logical = text_expression_budget(10000L, 10000L)
        let borrowed = retain_logical_value(logical, Number(9)).unwrap()
        let workspace = row_workspace(1000)
        assert_true(reserve_slots(workspace, 3))
        let frame = expression_frame(
          translate_instr_field_expression("instr"),
          Map([
            ("payload", Text(String::make(256, 'a'))),
            ("pattern", Text(String::make(128, 'a') + "b")),
            ("position", Number(direction)),
            ("occurrence", Number(1.0)),
          ]),
          [],
          { remaining: 100000, max_frames: 20, },
          workspace,
          Some(expression_roots(logical, 20)),
        ).unwrap()
        let mut reached = false
        for _ in 0..<30000 {
          let before = frame.budget.remaining
          assert_true(advance_expression_frame(frame) is Ok(None))
          assert_true(before - frame.budget.remaining <= 64)
          if frame.state is TextFunction(state) &&
            (
              (phase == 0 && state.instr_phase == 0 && state.count == 32) ||
              (phase == 1 && state.instr_phase == 2 && state.matched == 64) ||
              (phase == 2 && state.instr_phase == 3 && state.matched == 128)
            ) {
            assert_true(state.builder is None)
            reached = true
            break
          }
        }
        assert_true(
          reached,
          msg=direction.to_string() + ":" + phase.to_string(),
        )
        let work = logical.work
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
