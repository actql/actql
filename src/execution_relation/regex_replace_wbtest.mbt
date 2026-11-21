///|
fn original_regex_replace_request(source : String) -> @lower.FragmentRequest {
  original_string_fragment_request(
    expression=source,
    max_pattern_bytes=100,
    max_output_bytes=65536,
    max_replacements=65,
  )
}

///|
fn original_regex_replace_expression(source : String) -> @lower.Expression {
  let request = original_regex_replace_request(source)
  @lower.root_at(
    @lower.fragment_pipeline_roots(@lower.fragment_request_pipeline(request)),
    0,
  ).unwrap().expression
}

///|
test "checked regex replace preserves unmatched input and advances empty matches by a scalar" {
  for
    (source, input, expected) in [
      ("regex_replace(text, 'ana', 'X')", "banana", "bXna"),
      ("regex_replace(text, '(a)|(b)', '$2$1$$')", "ab", "a$b$"),
      ("regex_replace(text, '(a)', '$1-$1')", "aaZ", "a-aa-aZ"),
      ("regex_replace(text, '^|$', '🙂')", "🙃", "🙂🙃🙂"),
      ("regex_replace(text, '^|$', '!')", "", "!"),
      ("regex_replace(text, '^a$', 'Z', 'm')", "a\nx\na", "Z\nx\nZ"),
      ("regex_replace(text, 'abc', '')", "abcabc", ""),
      ("regex_replace(text, 'abc', '$$')", "🙂", "🙂"),
    ] {
    let expression = original_regex_replace_expression(source)
    let workspace = row_workspace(100)
    assert_true(
      evaluate_expression_with_workspace(
        expression,
        { "text": Text(input) },
        [],
        { remaining: 2000, max_frames: 100, },
        workspace,
      )
      is Ok(Text(actual)) &&
      actual == expected,
      msg=source,
    )
    assert_eq(workspace.live, 0)
  }
  let expression = original_regex_replace_expression(
    "regex_replace(NULL, 'a', 'x')",
  )
  assert_true(
    evaluate_expression(expression, {}, [], {
      remaining: 1000,
      max_frames: 100,
    })
    is Ok(Null),
  )
}

///|
test "checked regex replace seals its original replacement and both derived bounds" {
  let request = original_regex_replace_request(
    "regex_replace(text, '(a)', '$1$$', 'm')",
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
    is Some(@identity.String("regex_replace")),
  )
  assert_true(
    @identity.object_field(envelope, "max_replacements")
    is Some(@identity.Number(65.0)),
  )
  // Original UTF-8 ceiling 256 plus 65 occurrences of one literal byte and
  // one capture with the same 256-byte ceiling.
  assert_true(
    @identity.object_field(envelope, "max_output_bytes")
    is Some(@identity.Number(16961.0)),
  )
  let replacement = @identity.object_field(envelope, "replacement").unwrap()
  assert_true(
    @identity.object_field(replacement, "capture_reference_count")
    is Some(@identity.Number(1.0)),
  )
  assert_true(
    @identity.object_field(replacement, "max_capture_index")
    is Some(@identity.Number(1.0)),
  )
  assert_true(
    @identity.object_field(replacement, "literal_utf8_bytes")
    is Some(@identity.Number(1.0)),
  )
  let expression = @lower.root_at(
      @lower.fragment_pipeline_roots(@lower.fragment_request_pipeline(request)),
      0,
    ).unwrap().expression
  let bound = @lower.expression_text_bound(expression).unwrap()
  let (pattern, flags, replacement_ast) = @lower.text_bound_regex_replace(bound).unwrap()
  assert_eq(flags, Some("m"))
  let sealed_pattern = @identity.object_field(envelope, "pattern").unwrap()
  assert_true(
    @identity.object_field(sealed_pattern, "ast_cid")
    is Some(@identity.String(cid)) &&
    cid == @regex.cid(pattern),
  )
  assert_true(
    @identity.object_field(replacement, "ast_cid")
    is Some(@identity.String(cid)) &&
    cid == @replacement.cid(replacement_ast),
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
test "checked regex replace preserves input preflight and cancels the partially built output" {
  let expression = original_regex_replace_expression(
    "regex_replace(text, '(a)', '🙂$1')",
  )
  assert_true(
    evaluate_expression(
      expression,
      { "text": Text("a" + "x".repeat(64)) },
      [],
      { remaining: 1000, max_frames: 100, },
    )
    is Err({ kind: TextBounds(InputCeiling), .. }),
  )
  let workspace = row_workspace(100)
  let logical = text_expression_budget(100000L, 100000L)
  let original = retain_logical_value(logical, Number(9)).unwrap()
  let frame = expression_frame(
    expression,
    { "text": Text("aa") },
    [],
    { remaining: 1000, max_frames: 100, },
    workspace,
    Some(expression_roots(logical, 100)),
  ).unwrap()
  let mut reached = false
  for _ in 0..<256 {
    assert_true(advance_expression_frame(frame) is Ok(None))
    if frame.state is RegexReplacing(state) &&
      state.output.building &&
      state.phase is CopyReplacement(_, _, at, end) &&
      at == end {
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
test "checked regex replace funds simultaneous matcher backing and exact output storage" {
  let expression = original_regex_replace_expression(
    "regex_replace(text, 'a', '🙂')",
  )
  // Three copied child-view entries and seven argument slots stay live
  // with four text/copy slots, four matcher controls and eight backing slots
  // for the literal continuation (1984 bytes at 256 bytes per slot). Two
  // UTF-16 slots fund the astral output during the second search pass.
  for limit in [27, 28] {
    let workspace = row_workspace(limit)
    let run = evaluate_expression_with_workspace(
      expression,
      { "text": Text("a") },
      [],
      { remaining: 1000, max_frames: 100, },
      workspace,
    )
    if limit == 27 {
      assert_true(run is Err({ kind: WorkspaceLimit, .. }))
    } else {
      assert_true(run is Ok(Text("🙂")))
      assert_eq(workspace.peak, 28)
    }
    assert_eq(workspace.live, 0)
  }
}
