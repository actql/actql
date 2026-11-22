///|
fn original_split_part_expression(source : String) -> @lower.Expression {
  let request = original_string_fragment_request(
    expression=source,
    max_output_bytes=256,
  )
  @lower.root_at(
    @lower.fragment_pipeline_roots(@lower.fragment_request_pipeline(request)),
    0,
  ).unwrap().expression
}

///|
test "SPLIT_PART selects original nonoverlapping parts in both index directions" {
  for
    (source, input, expected) in [
      ("split_part(text, 'aa', 2)", "aaa", "a"),
      ("split_part(text, 'aa', -1)", "aaa", "a"),
      ("split_part(text, 'aa', -2)", "aaa", ""),
      ("split_part(text, '🙂', 2)", "🙂e\u0301\r\n🙂", "e\u0301\r\n"),
      ("split_part(text, '🙂', -1)", "🙂e\u0301\r\n🙂", ""),
      ("split_part(text, '|', 1)", "|a||b|", ""),
      ("split_part(text, '|', 3)", "|a||b|", ""),
      ("split_part(text, '|', -3)", "|a||b|", ""),
      ("split_part(text, '|', -4)", "|a||b|", "a"),
      ("split_part(text, '', -1)", "a🙂", "a🙂"),
      ("split_part(text, '', 2)", "a🙂", ""),
      ("split_part(text, ',', 1)", "", ""),
      ("split_part(text, ',', 9007199254740991)", "a,b", ""),
      ("split_part(text, ',', -9007199254740991)", "a,b", ""),
    ] {
    let expression = original_split_part_expression(source)
    let workspace = row_workspace(100)
    assert_true(
      evaluate_expression_with_workspace(
        expression,
        { "text": Text(input) },
        [],
        { remaining: 1000, max_frames: 100, },
        workspace,
      )
      is Ok(Text(actual)) &&
      actual == expected,
      msg=source,
    )
    assert_eq(workspace.live, 0)
  }
}

///|
test "SPLIT_PART keeps strict original argument demand and complete input admission" {
  for
    (source, input) in [
      ("split_part(text, ',', 0)", ""),
      ("split_part(text, ',', 1.5)", "x,y"),
      ("split_part(text, ',', 9007199254740992)", "x,y"),
      ("split_part(NULL, ',', 1 / 0)", ""),
    ] {
    assert_true(
      evaluate_expression(
        original_split_part_expression(source),
        { "text": Text(input) },
        [],
        { remaining: 1000, max_frames: 100, },
      )
      is Err(_),
      msg=source,
    )
  }
  assert_true(
    evaluate_expression(
      original_split_part_expression("split_part(NULL, ',', 1)"),
      Map([]),
      [],
      { remaining: 1000, max_frames: 100, },
    )
    is Ok(Null),
  )
  assert_true(
    evaluate_expression(
      original_split_part_expression(
        "if(TRUE, 'kept', split_part(text, ',', 0))",
      ),
      Map([]),
      [],
      { remaining: 1000, max_frames: 100, },
    )
    is Ok(Text("kept")),
  )
  let prefix = original_split_part_expression("split_part(text, ',', 1)")
  for
    (input, accepted) in [
      ("a," + "🙂".repeat(62), true),
      ("a," + "🙂".repeat(63), false),
    ] {
    let output = evaluate_expression(prefix, { "text": Text(input) }, [], {
      remaining: 1000,
      max_frames: 100,
    })
    if accepted {
      assert_true(output is Ok(Text("a")))
    } else {
      assert_true(output is Err({ kind: TextBounds(InputCeiling), .. }))
    }
  }
}

///|
test "SPLIT_PART cancellation releases its cursor and builder without releasing caller roots" {
  let expression = original_split_part_expression("split_part(text, ',', -1)")
  for cancel_build in [false, true] {
    let logical = text_expression_budget(1000000L, 1000000L)
    let borrowed = retain_logical_value(logical, Number(9)).unwrap()
    let workspace = row_workspace(250)
    let frame = expression_frame(
      expression,
      { "text": Text("a," + "🙂".repeat(29)) },
      [],
      { remaining: 1000, max_frames: 100, },
      workspace,
      Some(expression_roots(logical, 100)),
    ).unwrap()
    let mut reached = false
    for _ in 0..<1000 {
      assert_true(advance_expression_frame(frame).unwrap() is None)
      if frame.state is TextFunction(state) &&
        state.split_part is Some(cursor) &&
        (if cancel_build { state.building } else { cursor.phase is CountParts }) {
        reached = true
        break
      }
    }
    assert_true(reached)
    let work = logical.work
    close_expression_frame(frame)
    assert_eq(
      (logical.live, workspace.live, logical.work),
      (borrowed.bytes, 0, work),
    )
    assert_false(borrowed.released)
    release_logical_root(logical, borrowed).unwrap()
  }
}

///|
test "SPLIT_PART fragment retains named argument positions and the original output envelope" {
  let request = original_string_fragment_request(
    expression="split_part(text, ',', -1)",
    max_output_bytes=256,
  )
  let material = prepare_fragment_material(
    request,
    material_demands(),
    registry_limits(),
  ).unwrap()
  assert_eq(material.evaluations.length(), 1)
  let envelope = @identity.object_field(
    material.evaluations[0].value,
    "envelope",
  ).unwrap()
  assert_true(
    @identity.object_field(envelope, "operation")
    is Some(@identity.String("split_part")),
  )
  assert_true(
    @identity.object_field(envelope, "max_output_bytes")
    is Some(@identity.Number(256.0)),
  )
  let candidate = prepare_fragment_candidate(
    test_fragment_contract(),
    material,
    registry_limits(),
  ).unwrap()
  assert_true(
    check_generated_fragment(candidate, material_demands(), registry_limits())
    is Ok(_),
  )
}
