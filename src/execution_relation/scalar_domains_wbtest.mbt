///|
fn admitted_scalar(contract : String, wire : String) -> Value {
  let c = @contract.read_checked(input_cursor(contract), {
    max_nodes: 100,
    max_depth: 10,
    max_text_bytes: 1000,
  }).unwrap()
  capture(
    @admitted.admit(c, input_cursor(wire), {
      max_nodes: 100,
      max_depth: 10,
      max_text_bytes: 1000,
    }).unwrap().value,
  )
}

///|
fn decimal_value(wire : String, scale : Int) -> Value {
  admitted_scalar(
    "{\"type\":\"decimal\",\"nullable\":false,\"precision\":38,\"scale\":" +
    scale.to_string() +
    "}",
    "\"" + wire + "\"",
  )
}

///|
test "decimal comparison is exact across scales signs zeros and precision 38" {
  for
    (a, sa, b, sb, expected) in [
      ("1.00", 2, "1", 0, 0),
      ("0.0", 1, "0.000", 3, 0),
      ("1.01", 2, "1.001", 3, 1),
      ("-1.01", 2, "-1.001", 3, -1),
      ("0.001", 3, "0.01", 2, -1),
      ("0", 0, "-0.001", 3, 1),
      ("-1", 0, "0", 0, -1),
      ("1", 0, "-1", 0, 1),
      (
        "99999999999999999999999999999999999999", 0, "99999999999999999999999999999999999998",
        0, 1,
      ),
      ("0.00000000000000000000000000000000000001", 38, "0", 0, 1),
    ] {
    let left = decimal_value(a, sa)
    let right = decimal_value(b, sb)
    assert_eq(compare(left, right).unwrap(), expected)
    assert_eq(compare(right, left).unwrap(), -expected)
    let coefficient_bytes = match left {
      Captured(@admitted.Decimal(d)) => d.coefficient.length()
      _ => abort("decimal fixture")
    }
    let exact = { remaining: coefficient_bytes, max_frames: 0, }
    assert_true(charge_comparison_operand(exact, left) is Ok(_))
    assert_eq(exact.remaining, 0)
    assert_true(
      charge_comparison_operand(
        { remaining: coefficient_bytes - 1, max_frames: 0, },
        left,
      )
      is Err(ComparisonChargeLimit),
    )
    guard binary(@lower.Equal, left, right).unwrap() is Boolean(equal) else {
      fail("boolean comparison")
    }
    assert_eq(equal, expected == 0)
  }
}

///|
test "admitted temporal comparison is chronological and does not compare across domains" {
  for
    (typ, a, b) in [
      ("date", "0000-02-29", "2026-01-01"),
      ("timestamp", "2026-01-01T23:59:59.999Z", "2026-01-02T00:00:00.000Z"),
    ] {
    let c = "{\"type\":\"" + typ + "\",\"nullable\":false}"
    let left = admitted_scalar(c, "\"" + a + "\"")
    let right = admitted_scalar(c, "\"" + b + "\"")
    assert_eq(compare(left, right).unwrap(), -1)
    assert_eq(compare(right, left).unwrap(), 1)
    assert_eq(compare(left, left).unwrap(), 0)
    assert_true(compare(left, Text(a)) is Err(ComparisonDomainNotImplemented))
    assert_true(binary(@lower.NullIf, left, left).unwrap() is Null)
    let budget = { remaining: a.length(), max_frames: 0, }
    assert_true(charge_comparison_operand(budget, left) is Ok(_))
    assert_eq(budget.remaining, 0)
    assert_true(
      charge_comparison_operand(budget, right) is Err(ComparisonChargeLimit),
    )
  }
}

///|
test "decimal comparison runs through checked map filter and immutable completion" {
  let sequence = prepared_sequence(
    bound_pipeline(
      "[{\"values\":{\"schema\":{\"a\":{\"type\":\"decimal\",\"precision\":38,\"scale\":2,\"nullable\":false},\"b\":{\"type\":\"decimal\",\"precision\":38,\"scale\":3,\"nullable\":false}},\"rows\":[{\"a\":\"1.01\",\"b\":\"1.001\"},{\"a\":\"1.00\",\"b\":\"1.000\"}]},\"as\":\"seed\"},{\"derive\":{\"greater\":\"a > b\"}},{\"filter\":\"greater\"},{\"select\":[\"a\",\"b\"]}]",
    ),
  )
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [
      sequence_fragment_context(sequence, 1, 2L),
      sequence_fragment_context(sequence, 2, 2L),
    ],
    ["select_3"],
    100000,
    10000,
  ).unwrap()
  let result = execute_generated_sequence(generated, [], {
    rows: run_limits(),
    max_work: 100000,
    max_frames: 100,
  }).unwrap()
  let table = test_row_output(completed_output(result, Step(3)).unwrap())
  assert_eq(table.names, ["a", "b"])
  assert_eq(table.rows.length(), 1)
  guard table.rows[0][0] is Captured(@admitted.Decimal(a)) else {
    fail("decimal output")
  }
  guard table.rows[0][1] is Captured(@admitted.Decimal(b)) else {
    fail("decimal output")
  }
  assert_eq(a.coefficient, "101")
  assert_eq(a.scale, 2)
  assert_eq(b.coefficient, "1001")
  assert_eq(b.scale, 3)
}

///|
test "reference equality is prepared in selected and lazy branches" {
  let c = @contract.read_checked(
    input_cursor(
      "{\"type\":\"resource_ref\",\"nullable\":false,\"resource_kind\":\"mail/message\"}",
    ),
    { max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  let schema = @schema.from_fields(
    [(@schema.Unqualified("r"), c)],
    max_fields=1,
    max_name_bytes=1,
  ).unwrap()
  for
    expression in [
      "r = r", "if(TRUE, TRUE, r = r)", "coalesce(TRUE, r = r)", "CASE WHEN TRUE THEN TRUE ELSE r = r END",
    ] {
    let checked = @pipeline.check(
      input_cursor("[{\"filter\":\"" + expression + "\"}]"),
      [("source", schema)],
      None,
      Some(input_cursor("\"source\"")),
      {
        max_steps: 100,
        max_work: 10000,
        max_text_bytes: 10000,
        max_nodes: 1000,
        max_tokens: 1000,
        max_depth: 100,
      },
    ).unwrap()
    let owner = @lower.bind_parameters(
      @lower.prepare(checked, {
        max_nodes: 100,
        max_work: 10000,
        max_references: 100,
        max_identifier_bytes: 1000,
      }).unwrap(),
      None,
      max_parameters=0,
      max_name_bytes=0,
    ).unwrap()
    let sequence = prepared_sequence(owner)
    let p = @lower.prepare_fragment_pipeline(sequence, 0, {
      max_roots: 100,
      max_pointer_bytes: 10000,
      max_work: 100000,
    }).unwrap()
    let req = @lower.prepare_fragment_request(p, 10L, 1000L).unwrap()
    guard prepare_runtime_fragment(
        req,
        test_fragment_contract(),
        material_demands(),
        registry_limits(),
        capability_limits(),
      )
      is Ok(_) else {
      fail("supported reference equality")
    }
  }
}

///|
test "artifact equality ignores compatible media restrictions" {
  let pdf = select_checked_contract(
    "{\"type\":\"artifact_ref\",\"nullable\":false,\"media_type\":\"application/pdf\"}",
  )
  let json = select_checked_contract(
    "{\"type\":\"artifact_ref\",\"nullable\":false,\"media_type\":\"application/json\"}",
  )
  assert_true(supported_comparison(pdf, json))
  assert_true(supported_binary_comparison(Equal, pdf, json))
  assert_true(supported_binary_comparison(NotEqual, pdf, json))
  assert_false(supported_binary_comparison(Less, pdf, json))
}
