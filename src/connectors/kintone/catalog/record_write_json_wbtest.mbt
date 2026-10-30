///|
test "mapped value JSON preserves exact names ordered arrays and Common carriers" {
  let catalog = create_json_form()
  let values = prepare_record_write_values_json(
    catalog,
    @utf8.encode(
      "{\"Subject\":\"next 東京\",\"Tags\":[\"東京\",\"red\",\"東京\"],\"é\":\"é\",\"é\":\"é\"}",
    ),
    8192,
    write_test_limits(),
  ).unwrap()
  let request = prepare_record_create_request(
    catalog,
    [values],
    mutation_limits(),
  ).unwrap()
  assert_eq(
    record_create_request_values_json(request, 8192, 1000, 16).unwrap(),
    "[{\"Subject\":\"next 東京\",\"Tags\":[\"東京\",\"red\",\"東京\"],\"é\":\"é\",\"é\":\"é\"}]",
  )
  assert_true(physical_equal(values.catalog, catalog))
}

///|
test "mapped value JSON refuses provider fields duplicate keys and incompatible carriers" {
  let catalog = create_json_form()
  for
    wire in [
      "[]", "null", "{\"Subject\":\"a\",\"Subject\":\"b\"}", "{\"$id\":\"7\"}", "{\"Subject\":{\"value\":\"x\"}}",
      "{\"Subject\":1}", "{\"Tags\":\"x\"}", "{\"Stamp\":\"2026-10-18T00:00:00.001Z\"}",
    ] {
    assert_true(
      prepare_record_write_values_json(
        catalog,
        @utf8.encode(wire),
        8192,
        write_test_limits(),
      )
      is Err(_),
    )
  }
}

///|
test "mapped value JSON enforces original input field text node and output bounds" {
  let catalog = create_json_form()
  let body = b"{\"Subject\":\"next\",\"Tags\":[\"red\"]}"
  let limits = write_test_limits()
  assert_true(
    prepare_record_write_values_json(catalog, body, 0, limits)
    is Err(InvalidLimits),
  )
  assert_true(
    prepare_record_write_values_json(catalog, body, body.length() - 1, limits)
    is Err(BudgetExceeded),
  )
  for
    bounded in [
      { ..limits, max_fields: 1, },
      { ..limits, max_name_bytes: 1, },
      { ..limits, max_nodes: 1, },
      { ..limits, max_depth: 1, },
      { ..limits, max_text_bytes: 1, },
      { ..limits, max_output_bytes: 1, },
    ] {
    assert_true(
      prepare_record_write_values_json(catalog, body, 8192, bounded) is Err(_),
    )
  }
  assert_true(
    prepare_record_write_values_json(catalog, body, body.length(), limits)
    is Ok(_),
  )
}
