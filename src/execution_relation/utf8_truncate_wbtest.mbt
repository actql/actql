///|
fn original_utf8_truncate_expression(
  expression? : String = "utf8_truncate(text, 6)",
) -> @lower.Expression {
  let request = original_string_fragment_request(expression~)
  @lower.root_at(
    @lower.fragment_pipeline_roots(@lower.fragment_request_pipeline(request)),
    0,
  ).unwrap().expression
}

///|
test "UTF8_TRUNCATE returns the greatest complete scalar prefix without normalization" {
  for
    (limit, expected) in [
      (0, ""),
      (1, ""),
      (2, "é"),
      (3, "é"),
      (5, "é"),
      (6, "é😀"),
      (7, "é😀e"),
      (8, "é😀e"),
      (9, "é😀é"),
      (10, "é😀éx"),
    ] {
    let expression = original_utf8_truncate_expression(
      expression="utf8_truncate(text, " + limit.to_string() + ")",
    )
    assert_true(
      evaluate_expression(expression, Map([("text", Text("é😀éx"))]), [], {
        remaining: 100000,
        max_frames: 100,
      })
      is Ok(Text(actual)) &&
      actual == expected,
      msg=limit.to_string(),
    )
  }
}

///|
test "UTF8_TRUNCATE checks the complete original input even beyond a zero-byte result" {
  let expression = original_utf8_truncate_expression(
    expression="utf8_truncate(text, 0)",
  )
  assert_true(
    evaluate_expression(expression, Map([("text", Text("x".repeat(65)))]), [], {
      remaining: 100000,
      max_frames: 100,
    })
    is Err({ kind: TextBounds(InputCeiling), .. }),
  )
  assert_true(
    evaluate_expression(
      expression,
      Map([("text", Text("😀".repeat(64)))]),
      [],
      { remaining: 100000, max_frames: 100, },
    )
    is Ok(Text("")),
  )
  assert_true(
    evaluate_expression(expression, Map([("text", Text("x".repeat(64)))]), [], {
      remaining: 2,
      max_frames: 100,
    })
    is Err({ kind: ControlLimit, .. }),
  )
}

///|
test "UTF8_TRUNCATE keeps original fragment envelope and rejects its omission" {
  let material = prepare_fragment_material(
    original_string_fragment_request(expression="utf8_truncate(text, 6)"),
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
    is Some(@identity.String("utf8_truncate")),
  )
  assert_true(
    @identity.object_field(envelope, "max_output_bytes")
    is Some(@identity.Number(6.0)),
  )
  let expected =
    #|{"arguments_cid":"sha256:c64b5549ed5d9179afaa6023fba7c411e932cf9249bf4c78121ee3ff790aa216","demand_path":[],"envelope_cid":"sha256:ba5a8a310e97a9cd5585cda851bc5ff058ec74bbd2e4ad98cb712a7142e54a0e","expression_pointer":"/roots/0/source","host_policy_profile_cid":"sha256:cc81cb2eff39b8fae7bb7ad6f67414fdce9bff9fccd641e25b080cbe2b0ed46f","input":{"evidence_cid":"sha256:43aad4b014c3beaa52074d3082135ec72cf135224163a510ad0408c74955bc71","max_codepoints":64,"max_utf8_bytes":256,"source":"runtime_preflight"},"max_output_bytes":6,"operation":"utf8_truncate","semantic_step_id":"derive_1","verification":"unit_preflight","version":"actql-text-time-evaluation-envelope/0.1"}
  assert_eq(@identity.stringify_value(envelope, 10000, 1000, 100), expected)
  let candidate = prepare_fragment_candidate(
    test_fragment_contract(),
    material,
    registry_limits(),
  ).unwrap()
  assert_true(
    check_generated_fragment(candidate, material_demands(), registry_limits())
    is Ok(_),
  )
  assert_true(
    check_generated_fragment(
      { ..candidate, material: { ..material, evaluations: [], }, },
      material_demands(),
      registry_limits(),
    )
    is Err(Integrity),
  )
}
