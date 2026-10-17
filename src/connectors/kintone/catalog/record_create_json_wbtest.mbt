///|
fn create_json_form() -> FormFieldCatalog {
  eligibility_catalog(
    (
      #|{"Subject":{"type":"SINGLE_LINE_TEXT","code":"Subject","expression":"","required":true},"Tags":{"type":"MULTI_SELECT","code":"Tags","required":false},"Date":{"type":"DATE","code":"Date","required":false},"Stamp":{"type":"DATETIME","code":"Stamp","required":false},"é":{"type":"MULTI_LINE_TEXT","code":"é","required":false},"é":{"type":"MULTI_LINE_TEXT","code":"é","required":false}}
    ),
  )
}

///|
test "mapped CREATE values become exact native requests without fabricated records or defaults" {
  let request = prepare_record_create_request_json(
    create_json_form(),
    b"[{\"Subject\":\"next 東京\",\"Tags\":[\"東京\",\"red\",\"東京\"]},{\"Subject\":\"\"}]",
    8192,
    write_test_limits(),
    mutation_limits(),
  ).unwrap()
  assert_eq(
    record_create_request_body(request),
    "{\"app\":\"12\",\"records\":[{\"Subject\":{\"value\":\"next 東京\"},\"Tags\":{\"value\":[\"東京\",\"red\",\"東京\"]}},{\"Subject\":{\"value\":\"\"}}]}",
  )
  assert_eq(
    record_create_request_values_json(request, 8192, 1000, 16).unwrap(),
    "[{\"Subject\":\"next 東京\",\"Tags\":[\"東京\",\"red\",\"東京\"]},{\"Subject\":\"\"}]",
  )
}

///|
test "mapped CREATE date and timestamp keep Common carriers and exact native resolution" {
  let request = prepare_record_create_request_json(
    create_json_form(),
    b"[{\"Subject\":\"x\",\"Date\":\"2026-10-18\",\"Stamp\":\"2026-10-18T00:00:00.000Z\"}]",
    8192,
    write_test_limits(),
    mutation_limits(),
  ).unwrap()
  assert_true(
    record_create_request_body(request).contains("2026-10-18T00:00:00Z"),
  )
  assert_true(
    record_create_request_values_json(request, 8192, 1000, 16)
    .unwrap()
    .contains("2026-10-18T00:00:00.000Z"),
  )
  assert_true(
    prepare_record_create_request_json(
      create_json_form(),
      b"[{\"Stamp\":\"2026-10-18T00:00:00.001Z\"}]",
      8192,
      write_test_limits(),
      mutation_limits(),
    )
    is Err(Write(UnrepresentableValue("Stamp"))),
  )
}

///|
test "mapped CREATE exact data keys remain distinct and invalid original rows refuse" {
  let request = prepare_record_create_request_json(
    create_json_form(),
    @utf8.encode("[{\"é\":\"é\",\"é\":\"é\"}]"),
    8192,
    write_test_limits(),
    mutation_limits(),
  ).unwrap()
  assert_eq(
    record_create_request_values_json(request, 8192, 1000, 16).unwrap(),
    "[{\"é\":\"é\",\"é\":\"é\"}]",
  )
  for wire in ["{}", "[]", "[null]", "[{\"Subject\":1}]", "[{\"$id\":\"7\"}]"] {
    assert_true(
      prepare_record_create_request_json(
        create_json_form(),
        @utf8.encode(wire),
        8192,
        write_test_limits(),
        mutation_limits(),
      )
      is Err(_),
    )
  }
}

///|
test "mapped CREATE bounds apply before parse and across the complete record array" {
  let body = b"[{\"Subject\":\"x\"},{\"Subject\":\"y\"}]"
  let catalog = create_json_form()
  assert_true(
    prepare_record_create_request_json(
      catalog,
      body,
      body.length() - 1,
      write_test_limits(),
      mutation_limits(),
    )
    is Err(BudgetExceeded),
  )
  assert_true(
    prepare_record_create_request_json(
      catalog,
      body,
      8192,
      write_test_limits(),
      { ..mutation_limits(), max_records: 1, },
    )
    is Err(BudgetExceeded),
  )
  assert_true(
    prepare_record_create_request_json(
      catalog,
      body,
      8192,
      { ..write_test_limits(), max_nodes: 4, },
      mutation_limits(),
    )
    is Err(BudgetExceeded),
  )
  let request = prepare_record_create_request_json(
    catalog,
    body,
    8192,
    write_test_limits(),
    mutation_limits(),
  ).unwrap()
  let size = @utf8.encode(
    record_create_request_values_json(request, 8192, 1000, 16).unwrap(),
  ).length()
  assert_true(
    record_create_request_values_json(request, size - 1, 1000, 16)
    is Err(BudgetExceeded),
  )
  assert_true(
    record_create_request_values_json(request, size, 1000, 16) is Ok(_),
  )
}
