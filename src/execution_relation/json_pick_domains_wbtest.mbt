///|
fn checked_json_pick_operation(schema : @schema.Schema) -> @lower.BoundPrepared {
  let checked = @pipeline.check(
    input_cursor(
      "[{\"json_pick\":{\"column\":\"payload\",\"path\":[\"leaf\"],\"output\":\"picked\"}}]",
    ),
    [("seed", schema)],
    None,
    Some(input_cursor("\"seed\"")),
    {
      max_steps: 10,
      max_work: 10000,
      max_nodes: 1000,
      max_text_bytes: 10000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  @lower.bind_parameters(
    @lower.prepare(checked, {
      max_nodes: 1000,
      max_references: 1000,
      max_work: 10000,
      max_identifier_bytes: 10000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}

///|
fn json_pick_contract(body : String) -> @contract.Contract {
  select_checked_contract(
    "{\"type\":\"object\",\"nullable\":true," +
    "\"additional_properties\":false,\"fields\":{\"leaf\":" +
    body +
    "}}",
  )
}

///|
fn json_pick_value_equal(
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
test "json pick preserves every directly admitted leaf domain and NULL" {
  let cases = [
    ("{\"type\":\"string\",\"nullable\":true}", "\"é\""),
    ("{\"type\":\"number\",\"nullable\":true}", "1"),
    (
      "{\"type\":\"decimal\",\"precision\":4,\"scale\":2,\"nullable\":true}", "\"1.20\"",
    ),
    ("{\"type\":\"boolean\",\"nullable\":true}", "true"),
    (
      "{\"type\":\"timestamp\",\"nullable\":true}", "\"2000-02-29T12:30:00.000Z\"",
    ),
    ("{\"type\":\"date\",\"nullable\":true}", "\"0000-02-29\""),
    ("{\"type\":\"json\",\"nullable\":true}", "{\"z\":[1,null]}"),
    (
      "{\"type\":\"object\",\"nullable\":true,\"additional_properties\":false,\"fields\":{\"x\":{\"type\":\"string\",\"nullable\":false}}}",
      "{\"x\":\"v\"}",
    ),
    (
      "{\"type\":\"array\",\"nullable\":true,\"items\":{\"type\":\"number\",\"nullable\":true},\"max_items\":2}",
      "[1,null]",
    ),
    (
      "{\"type\":\"vector\",\"nullable\":true,\"dimensions\":2,\"element_type\":\"f32\"}",
      "[1,2]",
    ),
  ]
  for (leaf_body, wire) in cases {
    let leaf = select_checked_contract(leaf_body)
    let payload = json_pick_contract(leaf_body)
    let schema = @schema.from_fields(
      [(@schema.Unqualified("payload"), payload)],
      max_fields=1,
      max_name_bytes=100,
    ).unwrap()
    let owner = checked_json_pick_operation(schema)
    let value = @admitted.admit(leaf, input_cursor(wire), {
        max_nodes: 100,
        max_depth: 10,
        max_text_bytes: 1000,
      }).unwrap().value
    let object = @admitted.admit(
        payload,
        input_cursor("{\"leaf\":" + wire + "}"),
        { max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
      ).unwrap().value
    let null_payload = @admitted.admit(payload, input_cursor("null"), {
        max_nodes: 1,
        max_depth: 0,
        max_text_bytes: 0,
      }).unwrap().value
    let input : CompletedTable = AdmittedTable({
      owner,
      id: @lower.input_id(@lower.bound_preparation(owner), 0).unwrap(),
      names: ["payload"],
      rows: [[object], [null_payload]],
    })
    let result = evaluate_completed_body(
      PreparedBody(row_kernel(owner, 0)),
      input,
      "picked",
      2,
      { remaining: 100000, max_frames: 100, },
      value_budget({
        max_nodes: 1000,
        max_text_bytes: 10000,
        max_depth: 10,
        max_work: 100000,
      }).unwrap(),
      { limit: 10000, live: 0, peak: 0, },
      None,
    ).unwrap()
    guard result is RowTable(table) else {
      fail("json pick did not return its row result")
    }
    assert_eq(table.names, ["payload", "picked"])
    assert_true(json_pick_value_equal(table.rows[0][1], value))
    assert_true(table.rows[1][1] is Null)
  }
}

///|
test "json pick rejects a retained object outside its checked path" {
  let payload = json_pick_contract("{\"type\":\"number\",\"nullable\":false}")
  let schema = @schema.from_fields(
    [(@schema.Unqualified("payload"), payload)],
    max_fields=1,
    max_name_bytes=100,
  ).unwrap()
  let owner = checked_json_pick_operation(schema)
  let wrong_contract = select_checked_contract(
    "{\"type\":\"object\",\"nullable\":false," +
    "\"additional_properties\":false,\"fields\":{" +
    "\"other\":{\"type\":\"number\",\"nullable\":false}}}",
  )
  let wrong = @admitted.admit(wrong_contract, input_cursor("{\"other\":1}"), {
      max_nodes: 10,
      max_depth: 3,
      max_text_bytes: 100,
    }).unwrap().value
  let input : Table = {
    owner,
    id: @lower.input_id(@lower.bound_preparation(owner), 0).unwrap(),
    names: ["payload"],
    rows: [[capture(wrong)]],
  }
  assert_true(
    evaluate_rows(
      row_kernel(owner, 0),
      input,
      1,
      { remaining: 1000, max_frames: 100, },
      row_output(),
    )
    is Err(InvalidRows),
  )
}
