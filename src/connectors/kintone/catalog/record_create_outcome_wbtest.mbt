///|
fn create_outcome_request() -> RecordCreateRequest {
  let catalog = record_test_catalog()
  prepare_record_create_request(
    catalog,
    [request_values(catalog, "東京")],
    mutation_limits(),
  ).unwrap()
}

///|
test "CREATE typed outcome retains exact wide API ID revision and original request" {
  let request = create_outcome_request()
  let bytes = b"{\"ids\":[\"9007199254740993\"],\"revisions\":[\"0009007199254740994\"]}"
  let response = project_record_create_acknowledgement(
    request,
    200,
    bytes,
    mutation_limits(),
  ).unwrap()
  let outcome = project_record_create_effect_outcome(
    request,
    response,
    mutation_limits(),
  ).unwrap()
  assert_eq(
    record_create_effect_outcome_wire(outcome),
    "{\"result\":{\"created\":true,\"record_id\":\"9007199254740993\",\"revision\":\"0009007199254740994\"},\"state\":\"applied\"}",
  )
  assert_eq(
    record_create_effect_outcome_response_sha256(outcome),
    @sha.hex(bytes),
  )
  assert_true(record_create_effect_outcome_matches_request(outcome, request))
  assert_false(
    record_create_effect_outcome_matches_request(
      outcome,
      create_outcome_request(),
    ),
  )
}

///|
test "CREATE outcome refuses copied equal request and a multi-record response as one row" {
  let request = create_outcome_request()
  let response = project_record_create_acknowledgement(
    request,
    200,
    b"{\"ids\":[\"1\"],\"revisions\":[\"2\"]}",
    mutation_limits(),
  ).unwrap()
  let copied_response : RecordCreateAcknowledgement = { ..response, }
  assert_false(record_create_acknowledgement_is_original(copied_response))
  assert_true(
    project_record_create_effect_outcome(
      request,
      copied_response,
      mutation_limits(),
    )
    is Err(UncorrelatedResult),
  )
  let copied : RecordCreateRequest = { ..request, }
  assert_true(
    project_record_create_effect_outcome(copied, response, mutation_limits())
    is Err(UncorrelatedResult),
  )
  let catalog = record_test_catalog()
  let batch = prepare_record_create_request(
    catalog,
    [request_values(catalog, "one"), request_values(catalog, "two")],
    mutation_limits(),
  ).unwrap()
  let batch_response = project_record_create_acknowledgement(
    batch,
    200,
    b"{\"ids\":[\"1\",\"2\"],\"revisions\":[\"3\",\"4\"]}",
    mutation_limits(),
  ).unwrap()
  assert_true(
    project_record_create_effect_outcome(
      batch,
      batch_response,
      mutation_limits(),
    )
    is Err(UncorrelatedResult),
  )
  assert_true(
    project_record_create_acknowledgement(
      request,
      500,
      b"{}",
      mutation_limits(),
    )
    is Err(UnexpectedStatus),
  )
}

///|
test "CREATE row value matching ignores field order but preserves exact names array order and omission" {
  let request = prepare_record_create_request_json(
    create_json_form(),
    b"[{\"Subject\":\"東京\",\"Tags\":[\"東京\",\"red\",\"東京\"],\"é\":\"decomposed\",\"é\":\"composed\"}]",
    8192,
    write_test_limits(),
    mutation_limits(),
  ).unwrap()
  assert_true(
    record_create_request_matches_value_wire(
      request,
      "{\"é\":\"composed\",\"é\":\"decomposed\",\"Tags\":[\"東京\",\"red\",\"東京\"],\"Subject\":\"東京\"}",
      8192,
      write_test_limits(),
      mutation_limits(),
    ).unwrap(),
  )
  for
    wire in [
      "{\"Subject\":\"東京\",\"Tags\":[\"東京\",\"東京\",\"red\"],\"é\":\"decomposed\",\"é\":\"composed\"}",
      "{\"Subject\":\"東京\",\"Tags\":[\"東京\",\"red\"],\"é\":\"decomposed\",\"é\":\"composed\"}",
      "{\"Subject\":\"東京\",\"Tags\":[\"東京\",\"red\",\"東京\"],\"é\":\"composed\"}",
    ] {
    assert_false(
      record_create_request_matches_value_wire(
        request,
        wire,
        8192,
        write_test_limits(),
        mutation_limits(),
      ).unwrap(),
    )
  }
}

///|
test "CREATE row matching and typed outcome obey supplied comparison and encoding bounds" {
  let request = create_outcome_request()
  assert_true(
    record_create_request_matches_value_wire(
      request,
      "{\"text\":\"東京\"}",
      8192,
      write_test_limits(),
      { ..mutation_limits(), max_comparison_work: 1, },
    )
    is Err(BudgetExceeded),
  )
  assert_true(
    record_create_request_matches_value_wire(
      request,
      "{\"text\":\"東京\"}",
      3,
      write_test_limits(),
      mutation_limits(),
    )
    is Err(BudgetExceeded),
  )
  let response = project_record_create_acknowledgement(
    request,
    200,
    b"{\"ids\":[\"1\"],\"revisions\":[\"2\"]}",
    mutation_limits(),
  ).unwrap()
  assert_true(
    project_record_create_effect_outcome(request, response, {
      ..mutation_limits(),
      max_output_bytes: 2,
    })
    is Err(BudgetExceeded),
  )
}
