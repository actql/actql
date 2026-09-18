///|
fn analytic_domain_owner(
  key : @contract.Contract,
  ordered : @contract.Contract,
  value : @contract.Contract,
  body : String,
) -> @lower.BoundPrepared {
  let number = @contract.primitive(NumberType, nullable=false)
  let schema = @schema.from_fields(
    [
      (@schema.Unqualified("id"), number),
      (@schema.Unqualified("key"), key),
      (@schema.Unqualified("ordered"), ordered),
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
    input_cursor("[{" + body + "}]"),
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
fn run_analytic_domain(
  owner : @lower.BoundPrepared,
  rows : Array[Array[Value]],
) -> Table {
  let kernel = row_kernel(owner, 0)
  let input : Table = {
    owner,
    id: @lower.kernel_input(kernel),
    names: ["id", "key", "ordered", "value"],
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
fn analytic_domain_row(
  id : Int,
  key : Value,
  ordered : Value,
  value : Value,
) -> Array[Value] {
  [Number(id.to_double()), key, ordered, value]
}

///|
fn analytic_domain_column(table : Table, name : String) -> Int {
  for index, actual in table.names {
    if actual == name {
      return index
    }
  }
  abort("analytic domain column not found")
}

///|
fn analytic_domain_aggregate_body(call : String) -> String {
  "\"analytic\":{\"partition_by\":[]," +
  "\"order_by\":[{\"id\":\"asc\"}],\"frame\":{" +
  "\"start\":\"unbounded_preceding\"," +
  "\"end\":\"unbounded_following\"},\"functions\":{" +
  "\"result\":" +
  call +
  "}}"
}

///|
test "analytic partitions every key domain including owned references" {
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
    let partition = assertion_admitted_value(key, wire, kind, live)
    let owner = analytic_domain_owner(
      key,
      number,
      number,
      "\"analytic\":{\"partition_by\":[\"key\"]," +
      "\"order_by\":[{\"id\":\"asc\"}],\"functions\":{" +
      "\"position\":{\"fn\":\"row_number\"}}}",
    )
    let table = run_analytic_domain(owner, [
      analytic_domain_row(2, partition, Number(1), Number(10)),
      analytic_domain_row(1, partition, Number(2), Number(20)),
    ])
    let position = analytic_domain_column(table, "position")
    let key_index = analytic_domain_column(table, "key")
    assert_true(table.rows[0][position] is Number(2))
    assert_true(table.rows[1][position] is Number(1))
    if kind != "ordinary" {
      assert_true(
        table.rows[0][key_index] is Captured(@admitted.Reference(reference)) &&
        @admitted.reference_available(reference),
      )
      live.val = false
      assert_true(
        table.rows[0][key_index] is Captured(@admitted.Reference(reference)) &&
        !@admitted.reference_available(reference),
      )
    }
  }
}

///|
test "analytic orders every authored scalar domain" {
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
  let number = select_checked_contract(
    "{\"type\":\"number\",\"nullable\":false}",
  )
  for (body, low_wire, high_wire) in cases {
    let ordered = select_checked_contract(body)
    let live = Ref(true)
    let low = assertion_admitted_value(ordered, low_wire, "ordinary", live)
    let high = assertion_admitted_value(ordered, high_wire, "ordinary", live)
    let owner = analytic_domain_owner(
      number,
      ordered,
      number,
      "\"analytic\":{\"partition_by\":[]," +
      "\"order_by\":[{\"ordered\":\"asc\"}],\"functions\":{" +
      "\"dense\":{\"fn\":\"dense_rank\"}," +
      "\"position\":{\"fn\":\"row_number\"}," +
      "\"ranked\":{\"fn\":\"rank\"}}}",
    )
    let table = run_analytic_domain(owner, [
      analytic_domain_row(1, Number(1), high, Number(10)),
      analytic_domain_row(2, Number(1), low, Number(20)),
    ])
    for name in ["dense", "position", "ranked"] {
      let index = analytic_domain_column(table, name)
      assert_true(table.rows[0][index] is Number(2))
      assert_true(table.rows[1][index] is Number(1))
    }
  }
}

///|
test "analytic navigation and frame values preserve every value domain" {
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
  let number = select_checked_contract(
    "{\"type\":\"number\",\"nullable\":false}",
  )
  for (body, wire, kind) in cases {
    let value = select_checked_contract(body)
    let live = Ref(true)
    let expected = assertion_admitted_value(value, wire, kind, live)
    let owner = analytic_domain_owner(
      number,
      number,
      value,
      "\"analytic\":{\"partition_by\":[]," +
      "\"order_by\":[{\"id\":\"asc\"}],\"frame\":{" +
      "\"start\":\"unbounded_preceding\"," +
      "\"end\":\"unbounded_following\"},\"functions\":{" +
      "\"first\":{\"fn\":\"first_value\",\"expr\":\"value\"}," +
      "\"last\":{\"fn\":\"last_value\",\"expr\":\"value\"}," +
      "\"next\":{\"fn\":\"lead\",\"expr\":\"value\"}," +
      "\"previous\":{\"fn\":\"lag\",\"expr\":\"value\"}}}",
    )
    let table = run_analytic_domain(owner, [
      analytic_domain_row(1, Number(1), Number(1), expected),
      analytic_domain_row(2, Number(1), Number(2), expected),
    ])
    let first = analytic_domain_column(table, "first")
    let last = analytic_domain_column(table, "last")
    let next = analytic_domain_column(table, "next")
    let previous = analytic_domain_column(table, "previous")
    for row in 0..<2 {
      assert_true(append_value_equal(table.rows[row][first], expected))
      assert_true(append_value_equal(table.rows[row][last], expected))
    }
    assert_true(append_value_equal(table.rows[0][next], expected))
    assert_true(table.rows[0][previous] is Null)
    assert_true(table.rows[1][next] is Null)
    assert_true(append_value_equal(table.rows[1][previous], expected))
    if kind != "ordinary" {
      live.val = false
      assert_true(
        table.rows[0][first] is Captured(@admitted.Reference(reference)) &&
        !@admitted.reference_available(reference),
      )
    }
  }
}

///|
test "analytic frame aggregates order every scalar domain" {
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
  let number = select_checked_contract(
    "{\"type\":\"number\",\"nullable\":false}",
  )
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
      let owner = analytic_domain_owner(
        number,
        number,
        value,
        analytic_domain_aggregate_body(
          "{\"fn\":\"" + function + "\",\"field\":\"value\"" + fraction + "}",
        ),
      )
      let table = run_analytic_domain(owner, [
        analytic_domain_row(1, Number(1), Number(1), high),
        analytic_domain_row(2, Number(1), Number(2), Null),
        analytic_domain_row(3, Number(1), Number(3), low),
      ])
      let result = analytic_domain_column(table, "result")
      for row in table.rows {
        assert_true(append_value_equal(row[result], expected))
      }
    }
  }
}

///|
test "analytic first and last aggregates preserve every value domain" {
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
  let number = select_checked_contract(
    "{\"type\":\"number\",\"nullable\":false}",
  )
  for (body, wire, kind) in cases {
    let value = select_checked_contract(body)
    let live = Ref(true)
    let expected = assertion_admitted_value(value, wire, kind, live)
    for function in ["first", "last"] {
      let owner = analytic_domain_owner(
        number,
        number,
        value,
        analytic_domain_aggregate_body(
          "{\"fn\":\"" + function + "\",\"field\":\"value\"}",
        ),
      )
      let table = run_analytic_domain(owner, [
        analytic_domain_row(1, Number(1), Number(1), expected),
        analytic_domain_row(2, Number(1), Number(2), Null),
      ])
      let result = analytic_domain_column(table, "result")
      for row in table.rows {
        assert_true(append_value_equal(row[result], expected))
      }
      if kind != "ordinary" && function == "last" {
        live.val = false
        assert_true(
          table.rows[0][result] is Captured(@admitted.Reference(reference)) &&
          !@admitted.reference_available(reference),
        )
      }
    }
  }
}

///|
test "analytic array aggregate covers every constructible value domain" {
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
  let number = select_checked_contract(
    "{\"type\":\"number\",\"nullable\":false}",
  )
  for (body, wire) in cases {
    let value = select_checked_contract(body)
    let live = Ref(true)
    let expected = assertion_admitted_value(value, wire, "ordinary", live)
    let owner = analytic_domain_owner(
      number,
      number,
      value,
      analytic_domain_aggregate_body(
        "{\"fn\":\"array_agg\",\"field\":\"value\"," + "\"max_items\":2}",
      ),
    )
    let table = run_analytic_domain(owner, [
      analytic_domain_row(1, Number(1), Number(1), expected),
      analytic_domain_row(2, Number(1), Number(2), Null),
    ])
    let result = analytic_domain_column(table, "result")
    for row in table.rows {
      guard row[result] is Captured(@admitted.Array(items)) &&
        @admitted.element_at(items, 0) is Some(actual) else {
        fail("analytic array aggregate expected")
      }
      assert_eq(@admitted.element_count(items), 1)
      assert_true(pivot_domain_value_equal(expected, actual))
    }
  }
}
