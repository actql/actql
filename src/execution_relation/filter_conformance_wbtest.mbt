///|
fn filter_input_owner(
  payload : @contract.Contract,
  predicate : String,
) -> @lower.BoundPrepared {
  let schema = @schema.from_fields(
    [(@schema.Unqualified("payload"), payload)],
    max_fields=1,
    max_name_bytes=100,
  ).unwrap()
  let carrier = @carrier.relation(@carrier.typed_rows(schema))
  let checked = @pipeline.check_with_evidence(
    input_cursor("[{\"filter\":" + predicate + "}]"),
    [("seed", @pipeline.CarrierInput(carrier))],
    None,
    Some(input_cursor("\"seed\"")),
    {
      max_steps: 10,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  @lower.bind_parameters(
    @lower.prepare(checked, {
      max_nodes: 100,
      max_references: 100,
      max_work: 1000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}

///|
fn run_filter_value(
  contract : @contract.Contract,
  predicate : String,
  value : Value,
) -> Result[Table, RowIssue] {
  let owner = filter_input_owner(contract, predicate)
  let kernel = row_kernel(owner, 0)
  evaluate_rows(
    kernel,
    {
      owner,
      id: @lower.kernel_input(kernel),
      names: ["payload"],
      rows: [[value]],
    },
    1,
    { remaining: 100000, max_frames: 100, },
    value_budget(run_limits().output_values).unwrap(),
  )
}

///|
test "filter preserves every relation value domain through a true predicate" {
  let cases = [
    ("{\"type\":\"string\",\"nullable\":true}", "\"é\"", "ordinary"),
    ("{\"type\":\"number\",\"nullable\":true}", "1", "ordinary"),
    (
      "{\"type\":\"decimal\",\"precision\":4,\"scale\":2,\"nullable\":true}", "\"1.20\"",
      "ordinary",
    ),
    ("{\"type\":\"boolean\",\"nullable\":true}", "true", "ordinary"),
    (
      "{\"type\":\"timestamp\",\"nullable\":true}", "\"2000-02-29T12:30:00.000Z\"",
      "ordinary",
    ),
    ("{\"type\":\"date\",\"nullable\":true}", "\"0000-02-29\"", "ordinary"),
    (
      "{\"type\":\"json\",\"nullable\":true}", "{\"z\":[1,null],\"a\":\"x\"}", "ordinary",
    ),
    (
      "{\"type\":\"object\",\"nullable\":true,\"additional_properties\":false,\"fields\":{\"x\":{\"type\":\"string\",\"nullable\":false}}}",
      "{\"x\":\"v\"}", "ordinary",
    ),
    (
      "{\"type\":\"array\",\"nullable\":true,\"items\":{\"type\":\"number\",\"nullable\":true},\"max_items\":2}",
      "[1,null]", "ordinary",
    ),
    (
      "{\"type\":\"vector\",\"nullable\":true,\"dimensions\":2,\"element_type\":\"f32\"}",
      "[1,2]", "ordinary",
    ),
    (
      "{\"type\":\"resource_ref\",\"nullable\":true,\"resource_kind\":\"mail/message\"}",
      "", "resource",
    ),
    (
      "{\"type\":\"artifact_ref\",\"nullable\":true,\"media_type\":\"application/json\"}",
      "", "artifact",
    ),
  ]
  for (body, wire, kind) in cases {
    let contract = select_checked_contract(body)
    let live = Ref(true)
    let value = assertion_admitted_value(contract, wire, kind, live)
    let output = run_filter_value(contract, "{\"literal\":true}", value).unwrap()
    assert_eq(output.names, ["payload"])
    assert_eq(output.rows.length(), 1)
    assert_true(append_value_equal(output.rows[0][0], value))
    live.val = false
  }
}

///|
test "filter compares every admitted key and order domain" {
  let cases = [
    ("{\"type\":\"string\",\"nullable\":false}", "\"é\"", "ordinary"),
    ("{\"type\":\"number\",\"nullable\":false}", "1", "ordinary"),
    (
      "{\"type\":\"decimal\",\"precision\":4,\"scale\":2,\"nullable\":false}", "\"1.20\"",
      "ordinary",
    ),
    ("{\"type\":\"boolean\",\"nullable\":false}", "true", "ordinary"),
    (
      "{\"type\":\"timestamp\",\"nullable\":false}", "\"2000-02-29T12:30:00.000Z\"",
      "ordinary",
    ),
    ("{\"type\":\"date\",\"nullable\":false}", "\"0000-02-29\"", "ordinary"),
    (
      "{\"type\":\"resource_ref\",\"nullable\":false,\"resource_kind\":\"mail/message\"}",
      "", "resource",
    ),
    (
      "{\"type\":\"artifact_ref\",\"nullable\":false,\"media_type\":\"application/json\"}",
      "", "artifact",
    ),
  ]
  for index, (body, wire, kind) in cases {
    let contract = select_checked_contract(body)
    let live = Ref(true)
    let value = assertion_admitted_value(contract, wire, kind, live)
    let equality = run_filter_value(contract, "\"payload = payload\"", value).unwrap()
    assert_eq(equality.rows.length(), 1)
    if index < 6 {
      let ordered = run_filter_value(contract, "\"payload <= payload\"", value).unwrap()
      assert_eq(ordered.rows.length(), 1)
    }
    live.val = false
    if kind != "ordinary" {
      assert_true(
        run_filter_value(contract, "\"payload = payload\"", value)
        is Err(Evaluation(0, 0, { kind: Scalar(InvalidOperand), .. })),
      )
    }
  }
}

///|
test "filter executes every base predicate operator with specified demand" {
  for
    predicate in [
      "TRUE", "NOT FALSE", "TRUE IS NOT NULL", "TRUE IS TRUE", "FALSE IS FALSE",
      "-1 < 0", "1 + 1 = 2", "3 - 1 = 2", "2 * 3 = 6", "5 / 2 = 2.5", "5 % 2 = 1",
      "1 = 1", "1 <> 2", "1 < 2", "1 <= 1", "2 > 1", "2 >= 2", "nullif(1, 1) IS NULL",
      "TRUE AND TRUE", "FALSE OR TRUE", "coalesce(NULL, TRUE)", "if(TRUE, TRUE, 1 / 0 > 0)",
      "CASE WHEN TRUE THEN TRUE ELSE 1 / 0 > 0 END",
    ] {
    let owner = row_owner(",{\"filter\":\"" + predicate + "\"}")
    let output = evaluate_rows(
      row_kernel(owner, 1),
      row_capture(owner),
      2,
      { remaining: 100000, max_frames: 100, },
      row_output(),
    ).unwrap()
    assert_eq(output.rows.length(), 2)
  }

  let nullable_boolean = select_checked_contract(
    "{\"type\":\"boolean\",\"nullable\":true}",
  )
  for predicate in ["\"payload IS NULL\"", "\"payload IS UNKNOWN\""] {
    let output = run_filter_value(nullable_boolean, predicate, Null).unwrap()
    assert_eq(output.rows.length(), 1)
  }

  let eager = row_owner(",{\"filter\":\"FALSE AND 1 / 0 > 0\"}")
  assert_true(
    evaluate_rows(
      row_kernel(eager, 1),
      row_capture(eager),
      2,
      { remaining: 100000, max_frames: 100, },
      row_output(),
    )
    is Err(Evaluation(0, 0, { kind: Scalar(ArithmeticFailure), .. })),
  )
}
