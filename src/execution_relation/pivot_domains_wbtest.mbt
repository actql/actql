///|
fn pivot_domain_owner(value : @contract.Contract) -> @lower.BoundPrepared {
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
    "\"aggregate\":\"min\"}}]",
  )
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
