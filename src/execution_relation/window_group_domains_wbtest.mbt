///|
fn window_group_domain_owner(
  key : @contract.Contract,
  value : @contract.Contract,
  aggregate : String,
) -> @lower.BoundPrepared {
  let number = @contract.primitive(NumberType, nullable=false)
  let schema = @schema.from_fields(
    [
      (@schema.Unqualified("at"), number),
      (@schema.Unqualified("id"), number),
      (@schema.Unqualified("key"), key),
      (@schema.Unqualified("value"), value),
    ],
    max_fields=4,
    max_name_bytes=100,
  ).unwrap()
  let carrier = @carrier.relation(@carrier.typed_rows(schema))
  let evidence = @evidence.declare_primary_key(
    input_cursor("[\"id\"]"),
    carrier,
    { max_fields: 1, max_name_bytes: 100, },
  ).unwrap()
  let checked = @pipeline.check_with_evidence(
    input_cursor(
      "[{\"row_window\":{\"kind\":\"fixed\",\"time\":\"at\"," +
      "\"size\":10},\"as\":\"windowed\"},{\"from\":\"windowed\"," +
      "\"window_group\":{\"by\":[\"key\"],\"aggregates\":{" +
      "\"result\":" +
      aggregate +
      "}}}]",
    ),
    [("seed", @pipeline.KeyedInput(evidence))],
    None,
    Some(input_cursor("\"seed\"")),
    {
      max_steps: 10,
      max_work: 100000,
      max_text_bytes: 10000,
      max_nodes: 10000,
      max_tokens: 10000,
      max_depth: 100,
    },
  ).unwrap()
  @lower.bind_parameters(
    @lower.prepare(checked, {
      max_nodes: 100,
      max_references: 100,
      max_work: 10000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}

///|
fn run_window_group_domain(
  owner : @lower.BoundPrepared,
  rows : Array[Array[Value]],
) -> Table {
  let kernel = row_kernel(owner, 1)
  let input : Table = {
    owner,
    id: @lower.kernel_input(kernel),
    names: ["at", "id", "key", "value", "window_end", "window_start"],
    rows,
  }
  evaluate_rows_with_workspace(
    kernel,
    input,
    100,
    { remaining: 1000000, max_frames: 100, },
    value_budget({
      max_nodes: 100000,
      max_text_bytes: 100000,
      max_depth: 100,
      max_work: 1000000,
    }).unwrap(),
    { limit: 100000, live: 0, peak: 0, },
  ).unwrap()
}

///|
fn window_group_domain_row(
  id : Int,
  key : Value,
  value : Value,
) -> Array[Value] {
  [
    Number(id.to_double()),
    Number(id.to_double()),
    key,
    value,
    Number(10),
    Number(0),
  ]
}

///|
test "window group compares every key domain including owned references" {
  let cases = [
    ("{\"type\":\"string\",\"nullable\":false}", "\"k\"", "ordinary"),
    ("{\"type\":\"number\",\"nullable\":false}", "1", "ordinary"),
    (
      "{\"type\":\"decimal\",\"precision\":4,\"scale\":2," +
      "\"nullable\":false}",
      "\"1.20\"",
      "ordinary",
    ),
    ("{\"type\":\"boolean\",\"nullable\":false}", "true", "ordinary"),
    (
      "{\"type\":\"timestamp\",\"nullable\":false}", "\"2000-02-29T12:30:00.000Z\"",
      "ordinary",
    ),
    ("{\"type\":\"date\",\"nullable\":false}", "\"0000-02-29\"", "ordinary"),
    (
      "{\"type\":\"resource_ref\",\"nullable\":false," +
      "\"resource_kind\":\"mail/message\"}",
      "",
      "resource",
    ),
    (
      "{\"type\":\"artifact_ref\",\"nullable\":false," +
      "\"media_type\":\"application/json\"}",
      "",
      "artifact",
    ),
  ]
  let number = select_checked_contract(
    "{\"type\":\"number\",\"nullable\":false}",
  )
  for (body, wire, kind) in cases {
    let key = select_checked_contract(body)
    let live = Ref(true)
    let value = assertion_admitted_value(key, wire, kind, live)
    let owner = window_group_domain_owner(key, number, "{\"fn\":\"count\"}")
    let table = run_window_group_domain(owner, [
      window_group_domain_row(1, value, Number(10)),
      window_group_domain_row(2, value, Number(20)),
    ])
    assert_eq(table.rows.length(), 1)
    assert_true(table.rows[0][1] is Number(2))
    if kind != "ordinary" {
      assert_true(
        table.rows[0][0] is Captured(@admitted.Reference(reference)) &&
        @admitted.reference_available(reference),
      )
      live.val = false
      assert_true(
        table.rows[0][0] is Captured(@admitted.Reference(reference)) &&
        !@admitted.reference_available(reference),
      )
    }
  }
}

///|
test "window group min max and percentile cover every ordered domain" {
  let cases = [
    ("{\"type\":\"string\",\"nullable\":true}", "\"a\"", "\"z\""),
    ("{\"type\":\"number\",\"nullable\":true}", "1", "2"),
    (
      "{\"type\":\"decimal\",\"precision\":4,\"scale\":2," +
      "\"nullable\":true}",
      "\"1.20\"",
      "\"2.00\"",
    ),
    ("{\"type\":\"boolean\",\"nullable\":true}", "false", "true"),
    (
      "{\"type\":\"timestamp\",\"nullable\":true}", "\"2000-02-29T12:30:00.000Z\"",
      "\"2001-01-01T00:00:00.000Z\"",
    ),
    (
      "{\"type\":\"date\",\"nullable\":true}", "\"0000-02-29\"", "\"2000-02-29\"",
    ),
  ]
  let key = select_checked_contract("{\"type\":\"number\",\"nullable\":false}")
  for (body, low_wire, high_wire) in cases {
    let value = select_checked_contract(body)
    let live = Ref(true)
    let low = assertion_admitted_value(value, low_wire, "ordinary", live)
    let high = assertion_admitted_value(value, high_wire, "ordinary", live)
    for
      (function, expected) in [
        ("min", low),
        ("max", high),
        ("percentile_disc", low),
      ] {
      let fraction = if function == "percentile_disc" {
        ",\"fraction\":0.5"
      } else {
        ""
      }
      let owner = window_group_domain_owner(
        key,
        value,
        "{\"fn\":\"" + function + "\",\"field\":\"value\"" + fraction + "}",
      )
      let table = run_window_group_domain(owner, [
        window_group_domain_row(1, Number(1), high),
        window_group_domain_row(2, Number(1), Null),
        window_group_domain_row(3, Number(1), low),
      ])
      assert_eq(table.rows.length(), 1)
      assert_true(append_value_equal(table.rows[0][1], expected))
    }
  }
}

///|
test "window group first and last preserve every relation value domain" {
  let cases = [
    ("{\"type\":\"string\",\"nullable\":true}", "\"é\"", "ordinary"),
    ("{\"type\":\"number\",\"nullable\":true}", "1", "ordinary"),
    (
      "{\"type\":\"decimal\",\"precision\":4,\"scale\":2," +
      "\"nullable\":true}",
      "\"1.20\"",
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
      "{\"type\":\"object\",\"nullable\":true," +
      "\"additional_properties\":false,\"fields\":{" +
      "\"x\":{\"type\":\"string\",\"nullable\":false}}}",
      "{\"x\":\"v\"}",
      "ordinary",
    ),
    (
      "{\"type\":\"array\",\"nullable\":true,\"items\":{" +
      "\"type\":\"number\",\"nullable\":true},\"max_items\":2}",
      "[1,null]",
      "ordinary",
    ),
    (
      "{\"type\":\"vector\",\"nullable\":true,\"dimensions\":2," +
      "\"element_type\":\"f32\"}",
      "[1,2]",
      "ordinary",
    ),
    (
      "{\"type\":\"resource_ref\",\"nullable\":true," +
      "\"resource_kind\":\"mail/message\"}",
      "",
      "resource",
    ),
    (
      "{\"type\":\"artifact_ref\",\"nullable\":true," +
      "\"media_type\":\"application/json\"}",
      "",
      "artifact",
    ),
  ]
  let key = select_checked_contract("{\"type\":\"number\",\"nullable\":false}")
  for (body, wire, kind) in cases {
    let value = select_checked_contract(body)
    let live = Ref(true)
    let expected = assertion_admitted_value(value, wire, kind, live)
    for function in ["first", "last"] {
      let owner = window_group_domain_owner(
        key,
        value,
        "{\"fn\":\"" +
        function +
        "\",\"field\":\"value\",\"order_by\":[{\"id\":\"asc\"}]}",
      )
      let table = run_window_group_domain(owner, [
        window_group_domain_row(1, Number(1), expected),
        window_group_domain_row(2, Number(1), Null),
      ])
      assert_eq(table.rows.length(), 1)
      assert_true(append_value_equal(table.rows[0][1], expected))
    }
    live.val = false
  }
}

///|
test "window group array aggregate covers every constructible value domain" {
  let cases = [
    ("{\"type\":\"string\",\"nullable\":true}", "\"é\""),
    ("{\"type\":\"number\",\"nullable\":true}", "1"),
    (
      "{\"type\":\"decimal\",\"precision\":4,\"scale\":2," +
      "\"nullable\":true}",
      "\"1.20\"",
    ),
    ("{\"type\":\"boolean\",\"nullable\":true}", "true"),
    (
      "{\"type\":\"timestamp\",\"nullable\":true}", "\"2000-02-29T12:30:00.000Z\"",
    ),
    ("{\"type\":\"date\",\"nullable\":true}", "\"0000-02-29\""),
    (
      "{\"type\":\"object\",\"nullable\":true," +
      "\"additional_properties\":false,\"fields\":{" +
      "\"x\":{\"type\":\"string\",\"nullable\":false}}}",
      "{\"x\":\"v\"}",
    ),
    (
      "{\"type\":\"array\",\"nullable\":true,\"items\":{" +
      "\"type\":\"number\",\"nullable\":true},\"max_items\":2}",
      "[1,null]",
    ),
    (
      "{\"type\":\"vector\",\"nullable\":true,\"dimensions\":2," +
      "\"element_type\":\"f32\"}",
      "[1,2]",
    ),
  ]
  let key = select_checked_contract("{\"type\":\"number\",\"nullable\":false}")
  for (body, wire) in cases {
    let value = select_checked_contract(body)
    let live = Ref(true)
    let expected = assertion_admitted_value(value, wire, "ordinary", live)
    let owner = window_group_domain_owner(
      key,
      value,
      "{\"fn\":\"array_agg\",\"field\":\"value\"," +
      "\"order_by\":[{\"id\":\"asc\"}],\"max_items\":2}",
    )
    let table = run_window_group_domain(owner, [
      window_group_domain_row(1, Number(1), expected),
      window_group_domain_row(2, Number(1), Null),
    ])
    guard table.rows[0][1] is Captured(@admitted.Array(items)) &&
      @admitted.element_at(items, 0) is Some(actual) else {
      fail("window array aggregate expected")
    }
    assert_eq(@admitted.element_count(items), 1)
    assert_true(pivot_domain_value_equal(expected, actual))
  }
}

///|
test "window group string and statistical aggregates retain closed laws" {
  let key = select_checked_contract("{\"type\":\"number\",\"nullable\":false}")
  let text = select_checked_contract("{\"type\":\"string\",\"nullable\":true}")
  let strings = window_group_domain_owner(
    key,
    text,
    "{\"fn\":\"string_agg\",\"field\":\"value\"," +
    "\"order_by\":[{\"id\":\"asc\"}],\"delimiter\":\"|\"," +
    "\"max_bytes\":10}",
  )
  let string_table = run_window_group_domain(strings, [
    window_group_domain_row(1, Number(1), Text("a")),
    window_group_domain_row(2, Number(1), Null),
    window_group_domain_row(3, Number(1), Text("b")),
  ])
  assert_true(string_table.rows[0][1] is Text("a|b"))

  let number = select_checked_contract(
    "{\"type\":\"number\",\"nullable\":true}",
  )
  for
    (function, expected) in [
      ("percentile_cont", 2.0),
      ("var_pop", 0.6666666666666666),
      ("var_samp", 1.0),
      ("stddev_pop", 0.816496580927726),
      ("stddev_samp", 1.0),
    ] {
    let fraction = if function == "percentile_cont" {
      ",\"fraction\":0.5"
    } else {
      ""
    }
    let owner = window_group_domain_owner(
      key,
      number,
      "{\"fn\":\"" + function + "\",\"field\":\"value\"" + fraction + "}",
    )
    let table = run_window_group_domain(owner, [
      window_group_domain_row(1, Number(1), Number(1)),
      window_group_domain_row(2, Number(1), Number(2)),
      window_group_domain_row(3, Number(1), Number(3)),
    ])
    assert_true(table.rows[0][1] is Number(value) && value == expected)
  }
}
