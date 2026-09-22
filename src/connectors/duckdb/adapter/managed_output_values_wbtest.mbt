///|
fn managed_physical_test_owner() -> @lower.BoundPrepared {
  let pipeline = @pipeline.check(
    result_cursor(
      "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"label\":{\"type\":\"string\",\"nullable\":true}},\"rows\":[]},\"as\":\"v\"},{\"select\":[\"id\",\"label\"]}]",
    ),
    [],
    None,
    None,
    {
      max_steps: 10,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 20,
    },
  ).unwrap()
  @lower.bind_parameters(
    @lower.prepare(pipeline, {
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
test "managed physical chunks admit reordered columns without row encoding or logical CID" {
  let owner = managed_physical_test_owner()
  let values = @execution.prepare_managed_output_values(
    owner,
    Step(1),
    2,
    { max_nodes: 100, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
    100,
    { max_work: 100, max_bytes: 1000, max_nodes: 100, max_depth: 10, },
  ).unwrap()
  for
    fields in [
      [("unknown", Varchar), ("id", Float64)],
      [("id", Float64), ("id", Float64)],
      [("id", Float64)],
    ] {
    assert_true(
      prepare_managed_physical_output(values, fields, result_limits(), 100)
      is Err(Physical(_)),
    )
  }
  let output = prepare_managed_physical_output(
    values,
    [("label", Varchar), ("id", Float64)],
    result_limits(),
    100,
  ).unwrap()
  for label in ["[\"é\"]", "[null]"] {
    append_managed_physical_output(output, 1, [
      result_cursor(label),
      result_cursor("[\"3ff0000000000000\"]"),
    ]).unwrap()
  }
  let receipt = finish_managed_physical_output(output).unwrap()
  assert_true(
    @execution.managed_output_value_receipt_matches(receipt, owner, Step(1)),
  )
  assert_eq(@execution.managed_output_value_row_count(receipt), 2)
  assert_eq(@execution.managed_output_value_measurement(receipt), (6, 10, 4))
  assert_true(finish_managed_physical_output(output) is Err(Closed))
}

///|
test "managed physical output admits compiler-owned transport names" {
  let owner = managed_physical_test_owner()
  let values = @execution.prepare_managed_output_values(
    owner,
    Step(1),
    1,
    { max_nodes: 100, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
    100,
    { max_work: 100, max_bytes: 1000, max_nodes: 100, max_depth: 10, },
  ).unwrap()
  let names = ["__actql_output_0", "__actql_output_1"]
  let fields = [("__actql_output_1", Varchar), ("__actql_output_0", Float64)]
  assert_eq(
    prepare_managed_output_storage_order_named(
      values,
      names,
      fields,
      result_limits(),
      1000,
    ).unwrap(),
    [1, 0],
  )
  let output = prepare_managed_physical_output_named(
    values,
    names,
    fields,
    result_limits(),
    1000,
  ).unwrap()
  append_managed_physical_output(output, 1, [
    result_cursor("[\"é\"]"),
    result_cursor("[\"3ff0000000000000\"]"),
  ]).unwrap()
  let receipt = finish_managed_physical_output(output).unwrap()
  assert_true(
    @execution.managed_output_value_receipt_matches(receipt, owner, Step(1)),
  )
}

///|
test "managed physical output rejects malformed later chunks and never returns a partial receipt" {
  let owner = managed_physical_test_owner()
  for mode in 0..<3 {
    let values = @execution.prepare_managed_output_values(
      owner,
      Step(1),
      2,
      { max_nodes: 100, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
      100,
      { max_work: 100, max_bytes: 1000, max_nodes: 100, max_depth: 10, },
    ).unwrap()
    let output = prepare_managed_physical_output(
      values,
      [("id", Float64), ("label", Varchar)],
      { ..result_limits(), max_rows: if mode == 1 { 1 } else { 2 }, },
      100,
    ).unwrap()
    append_managed_physical_output(output, 1, [
      result_cursor("[\"3ff0000000000000\"]"),
      result_cursor("[null]"),
    ]).unwrap()
    if mode == 2 {
      assert_true(cancel_managed_physical_output(output))
      assert_false(cancel_managed_physical_output(output))
    }
    assert_true(
      append_managed_physical_output(output, 1, [
        result_cursor(
          if mode == 0 {
            "[\"7ff0000000000000\"]"
          } else {
            "[\"3ff0000000000000\"]"
          },
        ),
        result_cursor("[null]"),
      ])
      is Err(_),
    )
    assert_true(finish_managed_physical_output(output) is Err(Closed))
    assert_true(@execution.finish_managed_output_values(values) is Err(Closed))
  }
}
