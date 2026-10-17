///|
fn request_values(
  catalog : FormFieldCatalog,
  text : String,
) -> RecordWriteValues {
  prepare_record_write_values(
    catalog,
    [("text", write_text(text))],
    write_test_limits(),
  ).unwrap()
}

///|
fn request_targets(catalog : FormFieldCatalog) -> Array[OriginalRecordTarget] {
  let page = mutation_page(catalog, [
    mutation_row("9007199254740992", revision="9007199254740993"),
    mutation_row("9007199254740994", revision="8"),
  ])
  [
    prepare_original_record_target(page, 0, 100).unwrap(),
    prepare_original_record_target(page, 1, 100).unwrap(),
  ]
}

///|
test "create requests embed exact checked values and retain their original Form and order" {
  let catalog = record_test_catalog()
  let first = request_values(catalog, "東京\r\n\"")
  let second = request_values(catalog, "")
  let inputs = [first, second]
  let request = prepare_record_create_request(
    catalog,
    inputs,
    mutation_limits(),
  ).unwrap()
  assert_eq(
    record_create_request_body(request),
    (
      #|{"app":"12","records":[{"text":{"value":"東京\r\n\""}},{"text":{"value":""}}]}
    ),
  )
  assert_true(physical_equal(record_create_request_values(request)[0], first))
  assert_true(physical_equal(request.catalog, catalog))
  assert_eq(record_create_request_app_id(request), "12")
  assert_eq(record_create_request_count(request), 2)
  inputs.clear()
  record_create_request_values(request).clear()
  assert_eq(record_create_request_values(request).length(), 2)
  assert_true(
    prepare_record_create_request(
      record_test_catalog(),
      [first],
      mutation_limits(),
    )
    is Err(ForeignCatalog),
  )
  assert_true(
    prepare_record_create_request(
      catalog,
      [first, request_values(record_test_catalog(), "foreign")],
      mutation_limits(),
    )
    is Err(ForeignCatalog),
  )
}

///|
test "updates retain each original target value pair and required wide revision with upsert false" {
  let catalog = record_test_catalog()
  let targets = request_targets(catalog)
  let first = request_values(catalog, "first")
  let second = request_values(catalog, "second")
  let pairs = [(targets[1], second), (targets[0], first)]
  let request = prepare_record_update_request(pairs, mutation_limits()).unwrap()
  assert_eq(
    record_update_request_body(request),
    (
      #|{"app":"12","records":[{"id":"9007199254740994","record":{"text":{"value":"second"}},"revision":"8"},{"id":"9007199254740992","record":{"text":{"value":"first"}},"revision":"9007199254740993"}],"upsert":false}
    ),
  )
  let originals = record_update_request_values(request)
  assert_true(physical_equal(originals[0].0, targets[1]))
  assert_true(physical_equal(originals[0].1, second))
  assert_true(physical_equal(originals[1].0, targets[0]))
  assert_eq(record_update_request_app_id(request), "12")
  assert_eq(record_update_request_count(request), 2)
  pairs.clear()
  originals.clear()
  assert_eq(record_update_request_values(request).length(), 2)
}

///|
test "updates refuse foreign target or value Forms and duplicate numeric ID aliases" {
  let catalog = record_test_catalog()
  let first = request_targets(catalog)[0]
  let values = request_values(catalog, "x")
  let foreign = request_targets(record_test_catalog())[1]
  assert_true(
    prepare_record_update_request(
      [(first, values), (foreign, values)],
      mutation_limits(),
    )
    is Err(ForeignCatalog),
  )
  assert_true(
    prepare_record_update_request(
      [(first, request_values(record_test_catalog(), "x"))],
      mutation_limits(),
    )
    is Err(ForeignCatalog),
  )
  assert_true(
    prepare_record_update_request(
      [(first, values), (first, values)],
      mutation_limits(),
    )
    is Err(DuplicateTarget),
  )
  let numeric_alias = prepare_original_record_target(
    mutation_page(catalog, [mutation_row("0009007199254740992")]),
    0,
    100,
  ).unwrap()
  assert_true(
    prepare_record_update_request(
      [(first, values), (numeric_alias, values)],
      mutation_limits(),
    )
    is Err(DuplicateTarget),
  )
}

///|
test "write request limits count complete embedded documents and envelope without truncation" {
  let catalog = record_test_catalog()
  let values = request_values(catalog, "東京")
  let target = request_targets(catalog)[0]
  let limits = mutation_limits()
  assert_true(
    prepare_record_create_request(catalog, [], limits) is Err(InvalidRequest),
  )
  assert_true(prepare_record_update_request([], limits) is Err(InvalidRequest))
  for short in [{ ..limits, max_records: 0, }, { ..limits, max_records: 101, }] {
    assert_true(
      prepare_record_create_request(catalog, [values], short)
      is Err(InvalidLimits),
    )
    assert_true(
      prepare_record_update_request([(target, values)], short)
      is Err(InvalidLimits),
    )
  }
  for
    short in [
      { ..limits, max_identity_bytes: 1, },
      { ..limits, max_output_bytes: 1, },
      { ..limits, max_output_nodes: 1, },
      { ..limits, max_output_depth: 1, },
    ] {
    assert_true(
      prepare_record_create_request(catalog, [values], short)
      is Err(BudgetExceeded),
    )
    assert_true(
      prepare_record_update_request([(target, values)], short)
      is Err(BudgetExceeded),
    )
  }
  let create = prepare_record_create_request(catalog, [values], limits).unwrap()
  let update = prepare_record_update_request([(target, values)], limits).unwrap()
  let create_size = @utf8.encode(record_create_request_body(create)).length()
  let update_size = @utf8.encode(record_update_request_body(update)).length()
  assert_true(
    prepare_record_create_request(catalog, [values], {
      ..limits,
      max_output_bytes: create_size - 1,
    })
    is Err(BudgetExceeded),
  )
  assert_true(
    prepare_record_create_request(catalog, [values], {
      ..limits,
      max_output_bytes: create_size,
    })
    is Ok(_),
  )
  assert_true(
    prepare_record_update_request([(target, values)], {
      ..limits,
      max_output_bytes: update_size - 1,
    })
    is Err(BudgetExceeded),
  )
  assert_true(
    prepare_record_update_request([(target, values)], {
      ..limits,
      max_output_bytes: update_size,
    })
    is Ok(_),
  )
}

///|
test "write batches honor the original hundred record protocol bound without splitting" {
  let catalog = record_test_catalog()
  let values = request_values(catalog, "x")
  let records = Array::make(100, values)
  assert_true(
    prepare_record_create_request(catalog, records, mutation_limits()) is Ok(_),
  )
  records.push(values)
  assert_true(
    prepare_record_create_request(catalog, records, mutation_limits())
    is Err(BudgetExceeded),
  )
  let pairs = []
  for index in 0..<101 {
    let page = mutation_page(catalog, [mutation_row((index + 1).to_string())])
    pairs.push((prepare_original_record_target(page, 0, 100).unwrap(), values))
  }
  assert_true(
    prepare_record_update_request(pairs, mutation_limits())
    is Err(BudgetExceeded),
  )
  pairs.pop() |> ignore
  assert_true(prepare_record_update_request(pairs, mutation_limits()) is Ok(_))
  assert_true(
    prepare_record_update_request(pairs, {
      ..mutation_limits(),
      max_comparison_work: 1,
    })
    is Err(BudgetExceeded),
  )
}

///|
test "create response DATA preserves original request and positional new string IDs and revisions" {
  let catalog = record_test_catalog()
  let values = request_values(catalog, "x")
  let request = prepare_record_create_request(
    catalog,
    [values, values],
    mutation_limits(),
  ).unwrap()
  let bytes = b" {\"ids\":[\"9007199254740992\",\"9007199254740993\"],\"revisions\":[\"1\",\"9007199254740994\"]}\n"
  let response = project_record_create_acknowledgement(
    request,
    200,
    bytes,
    mutation_limits(),
  ).unwrap()
  assert_true(
    physical_equal(record_create_acknowledgement_request(response), request),
  )
  assert_eq(record_create_acknowledgement_records(response), [
    ("9007199254740992", "1"),
    ("9007199254740993", "9007199254740994"),
  ])
  assert_eq(response.response_sha256, @sha.hex(bytes))
  record_create_acknowledgement_records(response).clear()
  assert_eq(record_create_acknowledgement_records(response).length(), 2)
}

///|
test "update response DATA must cover every exact original ID once regardless of response order" {
  let catalog = record_test_catalog()
  let values = request_values(catalog, "x")
  let targets = request_targets(catalog)
  let request = prepare_record_update_request(
    [(targets[0], values), (targets[1], values)],
    mutation_limits(),
  ).unwrap()
  let bytes = b"{\"records\":[{\"id\":\"9007199254740994\",\"revision\":\"9\"},{\"id\":\"9007199254740992\",\"revision\":\"9007199254740994\"}]}"
  let response = project_record_update_acknowledgement(
    request,
    200,
    bytes,
    mutation_limits(),
  ).unwrap()
  assert_true(
    physical_equal(record_update_acknowledgement_request(response), request),
  )
  assert_eq(record_update_acknowledgement_records(response), [
    ("9007199254740994", "9"),
    ("9007199254740992", "9007199254740994"),
  ])
  assert_eq(response.response_sha256, @sha.hex(bytes))
  record_update_acknowledgement_records(response).clear()
  assert_eq(record_update_acknowledgement_records(response).length(), 2)
}

///|
test "write responses reject omissions duplicates numeric identities and foreign IDs without partial ACK" {
  let catalog = record_test_catalog()
  let values = request_values(catalog, "x")
  let target = request_targets(catalog)[0]
  let create = prepare_record_create_request(
    catalog,
    [values],
    mutation_limits(),
  ).unwrap()
  let update = prepare_record_update_request(
    [(target, values)],
    mutation_limits(),
  ).unwrap()
  for
    text in [
      "{}", "{\"ids\":[],\"revisions\":[]}", "{\"ids\":[\"7\"],\"revisions\":[]}",
      "{\"ids\":[7],\"revisions\":[\"1\"]}", "{\"ids\":[\"7\"],\"revisions\":[\"-1\"]}",
      "{\"ids\":[\"7\"],\"revisions\":[\"1\"],\"extra\":true}",
    ] {
    assert_true(
      project_record_create_acknowledgement(
        create,
        200,
        @utf8.encode(text),
        mutation_limits(),
      )
      is Err(_),
    )
  }
  for
    text in [
      "{}", "{\"records\":[]}", "{\"records\":[{\"id\":\"7\",\"revision\":\"9\"}]}",
      "{\"records\":[{\"id\":\"0009007199254740992\",\"revision\":\"9\"}]}", "{\"records\":[{\"id\":9007199254740992,\"revision\":\"9\"}]}",
      "{\"records\":[{\"id\":\"9007199254740992\",\"revision\":\"-1\"}]}", "{\"records\":[{\"id\":\"9007199254740992\",\"revision\":\"9\",\"operation\":\"INSERT\"}]}",
    ] {
    assert_true(
      project_record_update_acknowledgement(
        update,
        200,
        @utf8.encode(text),
        mutation_limits(),
      )
      is Err(_),
    )
  }
  let twice = prepare_record_create_request(
    catalog,
    [values, values],
    mutation_limits(),
  ).unwrap()
  assert_true(
    project_record_create_acknowledgement(
      twice,
      200,
      b"{\"ids\":[\"7\",\"007\"],\"revisions\":[\"1\",\"1\"]}",
      mutation_limits(),
    )
    is Err(UncorrelatedResult),
  )
}

///|
test "non-success malformed lost and over-budget responses cannot become write observations" {
  let catalog = record_test_catalog()
  let values = request_values(catalog, "x")
  let target = request_targets(catalog)[0]
  let create = prepare_record_create_request(
    catalog,
    [values],
    mutation_limits(),
  ).unwrap()
  let update = prepare_record_update_request(
    [(target, values)],
    mutation_limits(),
  ).unwrap()
  for status in [201, 202, 204, 400, 403, 409, 429, 500] {
    assert_true(
      project_record_create_acknowledgement(
        create,
        status,
        b"{}",
        mutation_limits(),
      )
      is Err(UnexpectedStatus),
    )
    assert_true(
      project_record_update_acknowledgement(
        update,
        status,
        b"{}",
        mutation_limits(),
      )
      is Err(UnexpectedStatus),
    )
  }
  for bytes in [b"", b"{", b"{}{}", b"null", b"[]", b"\xff"] {
    assert_true(
      project_record_create_acknowledgement(
        create,
        200,
        bytes,
        mutation_limits(),
      )
      is Err(_),
    )
    assert_true(
      project_record_update_acknowledgement(
        update,
        200,
        bytes,
        mutation_limits(),
      )
      is Err(_),
    )
  }
  for
    short in [
      { ..mutation_limits(), max_records: 0, },
      { ..mutation_limits(), max_output_bytes: 1, },
      { ..mutation_limits(), max_output_nodes: 1, },
      { ..mutation_limits(), max_output_depth: 1, },
      { ..mutation_limits(), max_identity_bytes: 1, },
    ] {
    assert_true(
      project_record_create_acknowledgement(
        create, 200, b"{\"ids\":[\"7\"],\"revisions\":[\"1\"]}", short,
      )
      is Err(_),
    )
    assert_true(
      project_record_update_acknowledgement(
        update, 200, b"{\"records\":[{\"id\":\"9007199254740992\",\"revision\":\"9\"}]}",
        short,
      )
      is Err(_),
    )
  }
}

///|
test "write response limits include every identity and duplicate or original-ID comparison" {
  let catalog = record_test_catalog()
  let values = request_values(catalog, "x")
  let targets = request_targets(catalog)
  let create = prepare_record_create_request(
    catalog,
    [values, values],
    mutation_limits(),
  ).unwrap()
  let update = prepare_record_update_request(
    [(targets[0], values), (targets[1], values)],
    mutation_limits(),
  ).unwrap()
  let created = b"{\"ids\":[\"7\",\"8\"],\"revisions\":[\"1\",\"1\"]}"
  let updated = b"{\"records\":[{\"id\":\"9007199254740992\",\"revision\":\"9\"},{\"id\":\"9007199254740994\",\"revision\":\"9\"}]}"
  for
    short in [
      { ..mutation_limits(), max_records: 1, },
      { ..mutation_limits(), max_identity_bytes: 3, },
      { ..mutation_limits(), max_comparison_work: 1, },
    ] {
    assert_true(
      project_record_create_acknowledgement(create, 200, created, short)
      is Err(BudgetExceeded),
    )
    assert_true(
      project_record_update_acknowledgement(update, 200, updated, short)
      is Err(BudgetExceeded),
    )
  }
  // Duplicate validation uses 32 units. Exact original-ID correlation needs
  // another 96; a separately reset comparison counter would wrongly accept.
  assert_true(
    project_record_update_acknowledgement(update, 200, updated, {
      ..mutation_limits(),
      max_comparison_work: 96,
    })
    is Err(BudgetExceeded),
  )
  assert_true(
    project_record_update_acknowledgement(
      update,
      200,
      b"{\"records\":[{\"id\":\"9007199254740992\",\"revision\":\"9\"},{\"id\":\"9007199254740992\",\"revision\":\"9\"}]}",
      mutation_limits(),
    )
    is Err(UncorrelatedResult),
  )
}

///|
test "physical preparation reuses the original Form and exact update observation targets" {
  let catalog = record_test_catalog()
  let values = request_values(catalog, "x")
  let create = prepare_record_create_request(
    catalog,
    [values],
    mutation_limits(),
  ).unwrap()
  let partial = b"{\"revision\":\"7\",\"properties\":{\"number\":{\"code\":\"number\",\"type\":\"RECORD_NUMBER\"},\"text\":{\"code\":\"text\",\"type\":\"SINGLE_LINE_TEXT\"}}}"
  assert_true(
    recheck_record_create_form(create, partial, form_test_limits())
    is Err(ForeignCatalog),
  )
  let body = @utf8.encode(
    (
      #|{"revision":"7","properties":{"number":{"type":"RECORD_NUMBER","code":"number"},"text":{"type":"SINGLE_LINE_TEXT","expression":"","code":"text"},"amount":{"type":"NUMBER","code":"amount","displayScale":"3"},"date":{"type":"DATE","code":"date"},"time":{"type":"TIME","code":"time"},"choices":{"type":"MULTI_SELECT","code":"choices","options":{"a":{"label":"a"}}},"owner":{"type":"CREATOR","code":"owner"},"users":{"type":"USER_SELECT","code":"users"},"files":{"type":"FILE","code":"files"},"table":{"type":"SUBTABLE","code":"table","fields":{"id_text":{"type":"SINGLE_LINE_TEXT","expression":"","code":"id_text"},"amount":{"type":"NUMBER","code":"amount"}}}}}
    ),
  )
  assert_true(
    recheck_record_create_form(create, body, form_test_limits()) is Ok(_),
  )
  assert_true(
    recheck_record_create_form(create, b"{", form_test_limits()) is Err(Form(_)),
  )
  let changed = @utf8.encode(
    @utf8.decode(body).replace(old="\"7\"", new="\"8\""),
  )
  assert_true(
    recheck_record_create_form(create, changed, form_test_limits())
    is Err(ForeignCatalog),
  )
  let targets = request_targets(catalog)
  let request = prepare_record_update_request(
    [(targets[1], values), (targets[0], values)],
    mutation_limits(),
  ).unwrap()
  let observation = record_update_request_observation(
    request,
    mutation_limits(),
  ).unwrap()
  let originals = record_delete_request_targets(observation)
  assert_true(physical_equal(originals[0], targets[1]))
  assert_true(physical_equal(originals[1], targets[0]))
  assert_eq(
    record_delete_request_body(observation),
    (
      #|{"app":"12","ids":["9007199254740994","9007199254740992"],"revisions":["8","9007199254740993"]}
    ),
  )
}
