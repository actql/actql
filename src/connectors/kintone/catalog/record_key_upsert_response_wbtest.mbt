///|
fn key_upsert_response_request(present : Bool) -> RecordKeyUpsertRequest {
  let catalog = key_upsert_catalog()
  prepare_record_key_upsert_request(
    key_upsert_lookup(catalog, present),
    key_upsert_values(catalog),
    write_test_limits(),
    mutation_limits(),
  ).unwrap()
}

///|
fn key_upsert_response_bytes(present : Bool) -> Bytes {
  if present {
    b"{\"records\":[{\"id\":\"9007199254740993\",\"revision\":\"0009007199254740995\"}]}"
  } else {
    b"{\"ids\":[\"9007199254740996\"],\"revisions\":[\"0009007199254740997\"]}"
  }
}

///|
test "keyed UPSERT response keeps the selected original branch and independent wide outcome vectors" {
  for present in [false, true] {
    let request = key_upsert_response_request(present)
    let bytes = key_upsert_response_bytes(present)
    let response = project_record_key_upsert_acknowledgement(
      request,
      200,
      bytes,
      mutation_limits(),
    ).unwrap()
    assert_true(record_key_upsert_acknowledgement_is_original(response))
    assert_true(
      record_key_upsert_acknowledgement_matches_request(response, request),
    )
    if present {
      assert_true(record_key_upsert_create_acknowledgement(response) is None)
      let ack = record_key_upsert_update_acknowledgement(response).unwrap()
      assert_true(
        physical_equal(
          record_update_acknowledgement_request(ack),
          record_key_upsert_update_request(request).unwrap(),
        ),
      )
      record_update_acknowledgement_records(ack).clear()
      assert_eq(record_update_acknowledgement_records(ack), [
        ("9007199254740993", "0009007199254740995"),
      ])
    } else {
      assert_true(record_key_upsert_update_acknowledgement(response) is None)
      let ack = record_key_upsert_create_acknowledgement(response).unwrap()
      assert_true(
        physical_equal(
          record_create_acknowledgement_request(ack),
          record_key_upsert_create_request(request).unwrap(),
        ),
      )
      record_create_acknowledgement_records(ack).clear()
      assert_eq(record_create_acknowledgement_records(ack), [
        ("9007199254740996", "0009007199254740997"),
      ])
    }
    let outcome = project_record_key_upsert_effect_outcome(
      request,
      response,
      mutation_limits(),
    ).unwrap()
    // The protocol shape reader admits DATA only; the original request's
    // confirmed branch independently determines the required UPSERT action.
    let admitted = @publication.parse_effect_outcome_shape(
      record_key_upsert_effect_outcome_wire(outcome),
      4096,
      100,
      10,
    ).unwrap()
    assert_true(
      @json.object_field(admitted, "action") is Some(@json.String(action)) &&
      action == (if present { "updated" } else { "created" }),
    )
    assert_eq(
      record_key_upsert_effect_outcome_wire(outcome),
      if present {
        "{\"action\":\"updated\",\"result\":{\"record_id\":\"9007199254740993\",\"revision\":\"0009007199254740995\"},\"state\":\"applied\"}"
      } else {
        "{\"action\":\"created\",\"result\":{\"created\":true,\"record_id\":\"9007199254740996\",\"revision\":\"0009007199254740997\"},\"state\":\"applied\"}"
      },
    )
    assert_true(
      record_key_upsert_effect_outcome_matches_request(outcome, request),
    )
    assert_false(
      record_key_upsert_effect_outcome_matches_request(
        outcome,
        key_upsert_response_request(present),
      ),
    )
  }
}

///|
test "keyed UPSERT response cannot choose a successful other codec after a branch failure" {
  for present in [false, true] {
    let request = key_upsert_response_request(present)
    assert_true(
      project_record_key_upsert_acknowledgement(
        request,
        200,
        key_upsert_response_bytes(!present),
        mutation_limits(),
      )
      is Err(UncorrelatedResult),
    )
    for status in [0, 202, 400, 500] {
      assert_true(
        project_record_key_upsert_acknowledgement(
          request,
          status,
          key_upsert_response_bytes(present),
          mutation_limits(),
        )
        is Err(UnexpectedStatus),
      )
    }
    assert_true(
      project_record_key_upsert_acknowledgement(
        request,
        200,
        b"{",
        mutation_limits(),
      )
      is Err(InvalidResponse),
    )
    assert_eq(
      record_key_upsert_request_operation(request),
      if present {
        Update
      } else {
        Insert
      },
    )
  }
  let update = key_upsert_response_request(true)
  for
    bytes in [
      b"{\"records\":[{\"id\":\"9007199254740994\",\"revision\":\"9\"}]}", b"{\"records\":[{\"id\":9007199254740993,\"revision\":\"9\"}]}",
      b"{\"records\":[{\"id\":\"9007199254740993\",\"revision\":\"9\"}],\"extra\":true}",
    ] {
    assert_true(
      project_record_key_upsert_acknowledgement(
        update,
        200,
        bytes,
        mutation_limits(),
      )
      is Err(_),
    )
  }
}

///|
test "keyed UPSERT response refuses copied request acknowledgement and same wire foreign request" {
  for present in [false, true] {
    let request = key_upsert_response_request(present)
    let response = project_record_key_upsert_acknowledgement(
      request,
      200,
      key_upsert_response_bytes(present),
      mutation_limits(),
    ).unwrap()
    let copied_request : RecordKeyUpsertRequest = { ..request, }
    assert_true(
      project_record_key_upsert_acknowledgement(
        copied_request,
        200,
        key_upsert_response_bytes(present),
        mutation_limits(),
      )
      is Err(UncorrelatedResult),
    )
    let copied : RecordKeyUpsertAcknowledgement = { ..response, }
    assert_false(record_key_upsert_acknowledgement_is_original(copied))
    assert_true(record_key_upsert_create_acknowledgement(copied) is None)
    assert_true(record_key_upsert_update_acknowledgement(copied) is None)
    assert_true(
      project_record_key_upsert_effect_outcome(
        request,
        copied,
        mutation_limits(),
      )
      is Err(UncorrelatedResult),
    )
    let foreign = key_upsert_response_request(present)
    assert_false(
      record_key_upsert_acknowledgement_matches_request(response, foreign),
    )
    assert_true(
      project_record_key_upsert_effect_outcome(
        foreign,
        response,
        mutation_limits(),
      )
      is Err(UncorrelatedResult),
    )
  }
}

///|
test "keyed UPSERT response digest keeps distinct original wire spelling beside equal typed values" {
  let request = key_upsert_response_request(false)
  let bytes = key_upsert_response_bytes(false)
  let response = project_record_key_upsert_acknowledgement(
    request,
    200,
    bytes,
    mutation_limits(),
  ).unwrap()
  let outcome = project_record_key_upsert_effect_outcome(
    request,
    response,
    mutation_limits(),
  ).unwrap()
  assert_eq(
    record_key_upsert_effect_outcome_response_sha256(outcome),
    "3f5434178f3baf1986a093b843df032bb662e2e367504b562bf28205f15b49c2",
  )
  let spelled = b"{ \"ids\":[\"9007199254740996\"], \"revisions\":[\"0009007199254740997\"] }"
  let alternate = project_record_key_upsert_acknowledgement(
    request,
    200,
    spelled,
    mutation_limits(),
  ).unwrap()
  let projected = project_record_key_upsert_effect_outcome(
    request,
    alternate,
    mutation_limits(),
  ).unwrap()
  assert_eq(
    record_key_upsert_effect_outcome_wire(projected),
    record_key_upsert_effect_outcome_wire(outcome),
  )
  assert_eq(
    record_key_upsert_effect_outcome_response_sha256(projected),
    "344dc9a3b4d1b1624a182400d698f3f2ad0ccb8def6f328e8c78c582ad47cc6c",
  )
  assert_true(
    record_key_upsert_effect_outcome_response_sha256(outcome) !=
    record_key_upsert_effect_outcome_response_sha256(projected),
  )
  assert_true(
    record_key_upsert_effect_outcome_matches_request(outcome, request),
  )
}

///|
test "keyed UPSERT response encoding and identity budgets refuse without replacing original response" {
  for present in [false, true] {
    let request = key_upsert_response_request(present)
    let bytes = key_upsert_response_bytes(present)
    for
      limits in [
        { ..mutation_limits(), max_output_bytes: 1, },
        { ..mutation_limits(), max_identity_bytes: 1, },
        { ..mutation_limits(), max_output_nodes: 1, },
      ] {
      assert_true(
        project_record_key_upsert_acknowledgement(request, 200, bytes, limits)
        is Err(BudgetExceeded),
      )
    }
    let response = project_record_key_upsert_acknowledgement(
      request,
      200,
      bytes,
      mutation_limits(),
    ).unwrap()
    assert_true(
      project_record_key_upsert_effect_outcome(request, response, {
        ..mutation_limits(),
        max_output_bytes: 1,
      })
      is Err(BudgetExceeded),
    )
    assert_true(
      record_key_upsert_acknowledgement_matches_request(response, request),
    )
    assert_true(
      project_record_key_upsert_effect_outcome(request, response, {
        ..mutation_limits(),
        max_records: 0,
      })
      is Err(InvalidLimits),
    )
  }
}
