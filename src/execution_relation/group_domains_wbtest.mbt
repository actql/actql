///|
fn group_domain_owner(
  key : @contract.Contract,
  value : @contract.Contract,
  aggregate : String,
) -> @lower.BoundPrepared {
  let number = @contract.primitive(NumberType, nullable=false)
  let schema = @schema.from_fields(
    [
      (@schema.Unqualified("id"), number),
      (@schema.Unqualified("key"), key),
      (@schema.Unqualified("value"), value),
    ],
    max_fields=3,
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
      "[{\"group\":{\"by\":[\"key\"],\"aggregates\":{" +
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
fn run_group_domain(
  owner : @lower.BoundPrepared,
  rows : Array[Array[Value]],
) -> Table {
  let kernel = row_kernel(owner, 0)
  let input : Table = {
    owner,
    id: @lower.kernel_input(kernel),
    names: ["id", "key", "value"],
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
fn group_domain_row(id : Int, key : Value, value : Value) -> Array[Value] {
  [Number(id.to_double()), key, value]
}

///|
test "group compares every key domain including owned references" {
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
    let owner = group_domain_owner(key, number, "{\"fn\":\"count\"}")
    let table = run_group_domain(owner, [
      group_domain_row(1, value, Number(10)),
      group_domain_row(2, value, Number(20)),
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
test "group discrete percentile covers every ordered domain" {
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
    let owner = group_domain_owner(
      key,
      value,
      "{\"fn\":\"percentile_disc\",\"field\":\"value\"," + "\"fraction\":0.5}",
    )
    let table = run_group_domain(owner, [
      group_domain_row(1, Number(1), high),
      group_domain_row(2, Number(1), Null),
      group_domain_row(3, Number(1), low),
    ])
    assert_eq(table.rows.length(), 1)
    assert_true(append_value_equal(table.rows[0][1], low))
  }
}
