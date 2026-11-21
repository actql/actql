///|
fn original_regex_match_expression(source : String) -> @lower.Expression {
  let request = original_string_fragment_request(
    expression=source,
    max_pattern_bytes=100,
  )
  @lower.root_at(
    @lower.fragment_pipeline_roots(@lower.fragment_request_pipeline(request)),
    0,
  ).unwrap().expression
}

///|
test "checked regex match uses the original pattern flags and entire admitted input" {
  let expression = original_regex_match_expression(
    "regex_match(text, '^a.$', 'ms')",
  )
  for (text, result) in [("z\na🙂", true), ("a\n", true), ("abx\n", false)] {
    assert_true(
      evaluate_expression(expression, { "text": Text(text) }, [], {
        remaining: 1000,
        max_frames: 100,
      })
      is Ok(Boolean(actual)) &&
      actual == result,
    )
  }
  let prefix = original_regex_match_expression("regex_match(text, 'a')")
  assert_true(
    evaluate_expression(prefix, { "text": Text("a" + "x".repeat(64)) }, [], {
      remaining: 1000,
      max_frames: 100,
    })
    is Err({ kind: TextBounds(InputCeiling), .. }),
  )
  let nullable = original_regex_match_expression("regex_match(NULL, 'a')")
  assert_true(
    evaluate_expression(nullable, {}, [], { remaining: 1000, max_frames: 100, })
    is Ok(Null),
  )
}

///|
test "checked regex match emits original pattern custody and the same evaluation envelope" {
  let request = original_string_fragment_request(
    expression="regex_match(text, '(a)', 'sm')",
    max_pattern_bytes=100,
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
    is Some(@identity.String("regex_match")),
  )
  let pattern = @identity.object_field(envelope, "pattern").unwrap()
  assert_true(
    @identity.object_field(pattern, "max_pattern_bytes")
    is Some(@identity.Number(3.0)),
  )
  let expression = @lower.root_at(
      @lower.fragment_pipeline_roots(@lower.fragment_request_pipeline(request)),
      0,
    ).unwrap().expression
  let bound = @lower.expression_text_bound(expression).unwrap()
  let (ast, flags) = @lower.text_bound_regex_pattern(bound).unwrap()
  assert_eq(flags, Some("sm"))
  let cid = @regex.cid(ast)
  assert_true(
    @identity.object_field(pattern, "ast_cid") is Some(@identity.String(actual)) &&
    actual == cid,
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

///|
test "checked regex match releases workspace and preserves spent work on cancellation" {
  let expression = original_regex_match_expression("regex_match(text, '(a)')")
  let workspace = row_workspace(100)
  let logical = text_expression_budget(100000L, 100000L)
  let original = retain_logical_value(logical, Number(9)).unwrap()
  let frame = expression_frame(
    expression,
    { "text": Text("a") },
    [],
    { remaining: 1000, max_frames: 100, },
    workspace,
    Some(expression_roots(logical, 100)),
  ).unwrap()
  let mut reached = false
  for _ in 0..<128 {
    assert_true(advance_expression_frame(frame) is Ok(None))
    if frame.state is RegexMatching(state) && state.workspace.slots > 0 {
      reached = true
      break
    }
  }
  assert_true(reached)
  let work = logical.work
  frame.budget.remaining = 0
  assert_true(
    advance_expression_frame(frame) is Err({ kind: ControlLimit, .. }),
  )
  assert_eq(
    (logical.live, logical.work, workspace.live),
    (original.bytes, work, 0),
  )
  assert_false(original.released)
  release_logical_root(logical, original).unwrap()
}

///|
test "checked regex match reserves capture result growth on the same row workspace" {
  let expression = original_regex_match_expression("regex_match(text, '((a))')")
  // Five continuations plus two marks and two result capture slots.
  // The original corpus independently quotes 1872 bytes of fixed matcher
  // controls, 112 more per entry, and four enclosing expression slots.
  // Nine entries reach 2880 bytes (12 workspace slots); eight need 11.
  for limit in [15, 16] {
    let workspace = row_workspace(limit)
    let run = evaluate_expression_with_workspace(
      expression,
      { "text": Text("a") },
      [],
      { remaining: 1000, max_frames: 100, },
      workspace,
    )
    if limit == 15 {
      assert_true(run is Err({ kind: WorkspaceLimit, .. }))
    } else {
      assert_true(run is Ok(Boolean(true)))
    }
    assert_eq((workspace.peak, workspace.live), (limit, 0))
  }
}
