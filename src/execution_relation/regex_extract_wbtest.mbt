///|
fn original_regex_extract_expression(
  source : String,
  structured? : Bool = false,
) -> @lower.Expression {
  // An unconstrained input field has the Host's 256-byte input extent.
  // Extraction may return the whole input, so Check needs that output ceiling.
  let request = original_string_fragment_request(
    expression=source,
    max_pattern_bytes=100,
    max_output_bytes=256,
    structured~,
  )
  @lower.root_at(
    @lower.fragment_pipeline_roots(@lower.fragment_request_pipeline(request)),
    0,
  ).unwrap().expression
}

///|
test "checked regex extract returns the original capture and preserves NULL" {
  for
    (source, text, expected) in [
      ("regex_extract(text, 'a(🙂)z', 0)", "xa🙂zy", Some("a🙂z")),
      ("regex_extract(text, '^a(.)z$', 1, 'ms')", "x\na\nz", Some("\n")),
      ("regex_extract(text, '(🙂)', 1)", "a🙂z", Some("🙂")),
      ("regex_extract(text, '(a?)b', 1)", "b", Some("")),
      ("regex_extract(text, '(a)?b', 1)", "b", None),
      ("regex_extract(text, '(a)', 1)", "b", None),
      ("regex_extract(NULL, '(a)', 1)", "a", None),
    ] {
    let expression = original_regex_extract_expression(source)
    let workspace = row_workspace(100)
    let actual = evaluate_expression_with_workspace(
      expression,
      { "text": Text(text) },
      [],
      { remaining: 1000, max_frames: 100, },
      workspace,
    ).unwrap()
    match actual {
      Text(text) => assert_eq(Some(text), expected)
      Null => assert_eq(None, expected)
      _ => fail("expected String or NULL")
    }
    assert_eq(workspace.live, 0)
  }
  let expression = original_regex_extract_expression(
    "regex_extract(text, '^(a)', 1)",
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
}

///|
test "checked regex extract seals the checked pattern and authored capture argument" {
  let request = original_string_fragment_request(
    expression="regex_extract(text, '(a)', 1, 'ms')",
    max_pattern_bytes=100,
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
    is Some(@identity.String("regex_extract")),
  )
  assert_true(
    @identity.object_field(envelope, "max_output_bytes")
    is Some(@identity.Number(256.0)),
  )
  // Canonical source arguments bind the capture and flags as authored.
  // Independently hashed {"capture":{"literal":1},"flags":"ms","pattern":
  // {"literal":"(a)"},"value":{"field":"text"}} without whitespace.
  assert_true(
    @identity.object_field(envelope, "arguments_cid")
    is Some(
      @identity.String(
        "sha256:266ae22a72aed8cdcb7b566ce651a13fb349cef9428664f27d3ae56d9cc85add"
      )
    ),
  )
  let sealed_pattern = @identity.object_field(envelope, "pattern").unwrap()
  let expression = @lower.root_at(
      @lower.fragment_pipeline_roots(@lower.fragment_request_pipeline(request)),
      0,
    ).unwrap().expression
  let bound = @lower.expression_text_bound(expression).unwrap()
  let (pattern, flags, capture) = @lower.text_bound_regex_extract(bound).unwrap()
  assert_eq((flags, capture), (Some("ms"), 1))
  assert_true(
    @identity.object_field(sealed_pattern, "ast_cid")
    is Some(@identity.String(cid)) &&
    cid == @regex.cid(pattern),
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
test "checked regex extract cancels a partial capture copy without releasing the caller root" {
  let expression = original_regex_extract_expression(
    "regex_extract(text, '(🙂z)', 1)",
  )
  let workspace = row_workspace(100)
  let logical = text_expression_budget(100000L, 100000L)
  let original = retain_logical_value(logical, Number(9)).unwrap()
  let frame = expression_frame(
    expression,
    { "text": Text("a🙂zb") },
    [],
    { remaining: 1000, max_frames: 100, },
    workspace,
    Some(expression_roots(logical, 100)),
  ).unwrap()
  let mut reached = false
  for _ in 0..<128 {
    assert_true(advance_expression_frame(frame) is Ok(None))
    if frame.state is RegexCaptureText(state, span) &&
      state.building &&
      span.position > span.start {
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
test "checked regex extract with omitted capture returns the same retained whole or sole group" {
  for (pattern, index, expected) in [("a.b", 0, "a🙂b"), ("a(.)b", 1, "🙂")] {
    let source =
      #|{"regex_extract":{"value":{"field":"text"},"pattern":{"literal":"PATTERN"}}}
    let expression = original_regex_extract_expression(
      source.replace(old="PATTERN", new=pattern),
      structured=true,
    )
    let (_, _, selected) = @lower.text_bound_regex_extract(
      @lower.expression_text_bound(expression).unwrap(),
    ).unwrap()
    assert_eq(selected, index)
    assert_true(
      evaluate_expression(expression, { "text": Text("a🙂bx") }, [], {
        remaining: 1000,
        max_frames: 100,
      })
      is Ok(Text(value)) &&
      value == expected,
    )
  }
}
