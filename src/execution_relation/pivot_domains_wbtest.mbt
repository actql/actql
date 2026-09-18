///|
fn pivot_domain_owner_with(
  key : @contract.Contract,
  value : @contract.Contract,
  function : String,
) -> @lower.BoundPrepared {
  let row = @schema.from_fields(
    [
      (@schema.Unqualified("id"), key),
      (
        @schema.Unqualified("status"),
        @contract.primitive(StringType, nullable=false),
      ),
      (@schema.Unqualified("amount"), value),
    ],
    max_fields=3,
    max_name_bytes=100,
  ).unwrap()
  let carrier = @carrier.relation(@carrier.typed_rows(row))
  sort_input_owner(
    @pipeline.CarrierInput(carrier),
    "[{\"pivot\":{" +
    "\"index\":[\"id\"],\"column\":\"status\"," +
    "\"values\":[\"open\"],\"value\":\"amount\"," +
    "\"aggregate\":\"" +
    function +
    "\"}}]",
  )
}

///|
fn pivot_domain_owner(value : @contract.Contract) -> @lower.BoundPrepared {
  pivot_domain_owner_with(
    @contract.primitive(NumberType, nullable=false),
    value,
    "min",
  )
}

///|
fn run_pivot_domain(
  owner : @lower.BoundPrepared,
  rows : Array[Array[Value]],
) -> Table {
  let kernel = row_kernel(owner, 0)
  let input : Table = {
    owner,
    id: @lower.kernel_input(kernel),
    names: ["id", "status", "amount"],
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
fn pivot_domain_value_equal(
  actual : Value,
  expected : @admitted.Value,
) -> Bool raise {
  match (actual, expected) {
    (Null, @admitted.Null) => true
    (Number(a), @admitted.Number(b)) => a == b
    (Boolean(a), @admitted.Boolean(b)) => a == b
    (Text(a), @admitted.Text(b)) => a == b
    (Captured(a), b) => {
      let actual_wire = @encode.writer(10000, 1000, 100)
      @admitted.emit_wire_value(a, actual_wire)
      let expected_wire = @encode.writer(10000, 1000, 100)
      @admitted.emit_wire_value(b, expected_wire)
      @encode.finish(actual_wire) == @encode.finish(expected_wire)
    }
    _ => false
  }
}

///|
test "pivot min and max cover every AuthorOrderable value domain" {
  let cases = [
    ("{\"type\":\"string\",\"nullable\":true}", "\"a\"", "\"z\""),
    ("{\"type\":\"number\",\"nullable\":true}", "1", "2"),
    (
      "{\"type\":\"decimal\",\"precision\":4," +
      "\"scale\":2,\"nullable\":true}",
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
  for (body, low, high) in cases {
    let contract = select_checked_contract(body)
    for (function, expected_wire) in [("min", low), ("max", high)] {
      let owner = pivot_domain_owner(contract)
      let operation = if function == "min" {
        owner
      } else {
        let row = @schema.from_fields(
          [
            (
              @schema.Unqualified("id"),
              @contract.primitive(NumberType, nullable=false),
            ),
            (
              @schema.Unqualified("status"),
              @contract.primitive(StringType, nullable=false),
            ),
            (@schema.Unqualified("amount"), contract),
          ],
          max_fields=3,
          max_name_bytes=100,
        ).unwrap()
        let carrier = @carrier.relation(@carrier.typed_rows(row))
        sort_input_owner(
          @pipeline.CarrierInput(carrier),
          "[{\"pivot\":{" +
          "\"index\":[\"id\"],\"column\":\"status\"," +
          "\"values\":[\"open\"],\"value\":\"amount\"," +
          "\"aggregate\":\"max\"}}]",
        )
      }
      let input = capture_input(
        operation,
        0,
        [
          input_cursor("{\"id\":1,\"status\":\"open\",\"amount\":" + high + "}"),
          input_cursor("{\"id\":1,\"status\":\"open\",\"amount\":null}"),
          input_cursor("{\"id\":1,\"status\":\"open\",\"amount\":" + low + "}"),
        ],
        max_rows=3,
        run_limits().input_values,
      ).unwrap()
      let completed = execute_generated_sequence(
        pivot_generated(operation),
        [input],
        { rows: run_limits(), max_work: 100000, max_frames: 100, },
      ).unwrap()
      let table = test_row_output(completed_output(completed, Step(0)).unwrap())
      let expected = @admitted.admit(contract, input_cursor(expected_wire), {
          max_nodes: 100,
          max_depth: 10,
          max_text_bytes: 1000,
        }).unwrap().value
      assert_eq(table.names, ["id", "open"])
      assert_eq(table.rows.length(), 1)
      assert_true(pivot_domain_value_equal(table.rows[0][1], expected))
    }
  }
}

///|
test "pivot compares every key domain including owned references" {
  let cases = [
    ("{\"type\":\"string\",\"nullable\":false}", "\"k\"", "ordinary"),
    ("{\"type\":\"number\",\"nullable\":false}", "1", "ordinary"),
    (
      "{\"type\":\"decimal\",\"precision\":4," +
      "\"scale\":2,\"nullable\":false}",
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
    let expected = assertion_admitted_value(key, wire, kind, live)
    let owner = pivot_domain_owner_with(key, number, "count")
    let table = run_pivot_domain(owner, [
      [expected, Text("open"), Number(10)],
      [expected, Text("open"), Number(20)],
    ])
    assert_eq(table.rows.length(), 1)
    assert_true(append_value_equal(table.rows[0][0], expected))
    assert_true(table.rows[0][1] is Number(2))
    if kind != "ordinary" {
      live.val = false
      assert_true(
        table.rows[0][0] is Captured(@admitted.Reference(reference)) &&
        !@admitted.reference_available(reference),
      )
    }
  }
}

///|
test "pivot first preserves every relation value domain" {
  let cases = [
    ("{\"type\":\"string\",\"nullable\":true}", "\"é\"", "ordinary"),
    ("{\"type\":\"number\",\"nullable\":true}", "1", "ordinary"),
    (
      "{\"type\":\"decimal\",\"precision\":4," +
      "\"scale\":2,\"nullable\":true}",
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
    let owner = pivot_domain_owner_with(key, value, "first")
    let table = run_pivot_domain(owner, [
      [Number(1), Text("open"), expected],
      [Number(1), Text("open"), Null],
    ])
    assert_eq(table.rows.length(), 1)
    assert_true(append_value_equal(table.rows[0][1], expected))
    if kind != "ordinary" {
      live.val = false
      assert_true(
        table.rows[0][1] is Captured(@admitted.Reference(reference)) &&
        !@admitted.reference_available(reference),
      )
    }
  }
}
