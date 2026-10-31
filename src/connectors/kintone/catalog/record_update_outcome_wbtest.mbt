///|
fn update_outcome_request() -> RecordUpdateRequest {
  let catalog = record_test_catalog()
  prepare_record_update_request(
    [(request_targets(catalog)[0], request_values(catalog, "next"))],
    mutation_limits(),
  ).unwrap()
}

///|
test "UPDATE response outcome retains original request and exact wide response revision" {
  let request = update_outcome_request()
  let bytes = b"{\"records\":[{\"id\":\"9007199254740992\",\"revision\":\"0009007199254740994\"}]}"
  let response = project_record_update_acknowledgement(
    request,
    200,
    bytes,
    mutation_limits(),
  ).unwrap()
  let outcome = project_record_update_effect_outcome(
    request,
    response,
    mutation_limits(),
  ).unwrap()
  assert_true(record_update_acknowledgement_is_original(response))
  assert_true(record_update_effect_outcome_matches_request(outcome, request))
  assert_false(
    record_update_effect_outcome_matches_request(
      outcome,
      update_outcome_request(),
    ),
  )
  assert_eq(
    record_update_effect_outcome_wire(outcome),
    "{\"result\":{\"record_id\":\"9007199254740992\",\"revision\":\"0009007199254740994\"},\"state\":\"applied\"}",
  )
  assert_eq(
    record_update_effect_outcome_response_sha256(outcome),
    @sha.hex(bytes),
  )
  assert_true(
    project_record_update_effect_outcome(request, response, {
      ..mutation_limits(),
      max_output_bytes: 1,
    })
    is Err(BudgetExceeded),
  )
}

///|
test "UPDATE outcome refuses copied response request and multi-record aggregation as one row" {
  let request = update_outcome_request()
  let response = project_record_update_acknowledgement(
    request,
    200,
    b"{\"records\":[{\"id\":\"9007199254740992\",\"revision\":\"10\"}]}",
    mutation_limits(),
  ).unwrap()
  let copied_response : RecordUpdateAcknowledgement = { ..response, }
  let copied_request : RecordUpdateRequest = { ..request, }
  assert_false(record_update_acknowledgement_is_original(copied_response))
  assert_true(
    project_record_update_effect_outcome(
      request,
      copied_response,
      mutation_limits(),
    )
    is Err(UncorrelatedResult),
  )
  assert_true(
    project_record_update_effect_outcome(
      copied_request,
      response,
      mutation_limits(),
    )
    is Err(UncorrelatedResult),
  )
  assert_true(
    project_record_update_effect_outcome(
      update_outcome_request(),
      response,
      mutation_limits(),
    )
    is Err(UncorrelatedResult),
  )
  let catalog = record_test_catalog()
  let targets = request_targets(catalog)
  let batch = prepare_record_update_request(
    [
      (targets[0], request_values(catalog, "first")),
      (targets[1], request_values(catalog, "second")),
    ],
    mutation_limits(),
  ).unwrap()
  let batch_response = project_record_update_acknowledgement(
    batch,
    200,
    b"{\"records\":[{\"id\":\"9007199254740992\",\"revision\":\"10\"},{\"id\":\"9007199254740994\",\"revision\":\"11\"}]}",
    mutation_limits(),
  ).unwrap()
  assert_true(
    project_record_update_effect_outcome(
      batch,
      batch_response,
      mutation_limits(),
    )
    is Err(UncorrelatedResult),
  )
}
