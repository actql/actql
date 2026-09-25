///|
fn target_observation_test_limits() -> TargetObservationLimits {
  { max_bytes: 1024, max_nodes: 32, max_depth: 5, max_identity_bytes: 1024, }
}

///|
test "target observation binds the exact record before a guard exists" {
  let update = prepare_single_write_request(
    write_request_body(WriteUpdateById),
    "v66.0",
    RecordId("001000000000001"),
    write_request_test_limits(),
  ).unwrap()
  let before = @utf8.encode(
    "{\"Id\":\"001000000000001AAA\",\"Optional_Value__c\":\"old\"}",
  )
  let observed = prepare_target_observation(
    update,
    200,
    before,
    target_observation_test_limits(),
  ).unwrap()
  assert_eq(target_observation_response_sha256(observed), @sha.hex(before))
  assert_eq(
    target_observation_before_value_wire(observed),
    "{\"Optional_Value__c\":\"old\"}",
  )
  let preview_row = prepare_observed_target_preview_row(update, observed, 1024).unwrap()
  assert_eq(target_preview_row_target_wire(preview_row), "\"001000000000001\"")
  assert_eq(
    target_preview_row_guard_cid(preview_row),
    target_observation_version_cid(observed),
  )
  assert_eq(
    target_preview_row_before_wire(preview_row),
    "{\"Optional_Value__c\":\"old\"}",
  )
  assert_eq(
    target_preview_row_after_wire(preview_row),
    "{\"Optional_Value__c\":\"value\"}",
  )
  assert_eq(
    target_preview_row_changes_wire(preview_row),
    target_preview_row_after_wire(preview_row),
  )
  let other_body = prepare_write_body(
    update.projection,
    @utf8.encode("{\"Optional_Value__c\":\"changed\"}"),
    write_body_test_limits(),
  ).unwrap()
  let other_request = prepare_single_write_request(
    other_body,
    "v66.0",
    RecordId("001000000000001"),
    write_request_test_limits(),
  ).unwrap()
  assert_true(
    prepare_observed_target_preview_row(other_request, observed, 1024)
    is Err(ForeignTarget),
  )
  let reordered = prepare_target_observation(
    update,
    200,
    @utf8.encode(
      "{\"Other\":7,\"Optional_Value__c\":\"old\",\"Id\":\"001000000000001AAA\"}",
    ),
    target_observation_test_limits(),
  ).unwrap()
  assert_eq(
    target_observation_before_value_wire(reordered),
    target_observation_before_value_wire(observed),
  )
  assert_true(
    target_observation_version_cid(reordered) !=
    target_observation_version_cid(observed),
  )
  assert_true(target_observation_version_cid(observed).has_prefix("sha256:"))
  let changed = prepare_target_observation(
    update,
    200,
    @utf8.encode(
      "{\"Id\":\"001000000000001AAA\",\"Optional_Value__c\":\"new\"}",
    ),
    target_observation_test_limits(),
  ).unwrap()
  assert_true(
    target_observation_version_cid(changed) !=
    target_observation_version_cid(observed),
  )
  assert_true(
    prepare_target_observation(
      update,
      200,
      @utf8.encode("{\"Id\":\"001000000000002\",\"Optional_Value__c\":\"old\"}"),
      target_observation_test_limits(),
    )
    is Err(ForeignTarget),
  )
  assert_true(
    prepare_target_observation(
      update,
      404,
      before,
      target_observation_test_limits(),
    )
    is Err(InvalidRecord),
  )
  assert_true(
    prepare_target_observation(
      update,
      200,
      @utf8.encode("{\"Id\":\"001000000000001\"}"),
      target_observation_test_limits(),
    )
    is Err(InvalidRecord),
  )
  assert_true(
    prepare_target_observation(update, 200, before, {
      ..target_observation_test_limits(),
      max_bytes: 8,
    })
    is Err(CapacityExceeded),
  )
}

///|
test "external-ID target observation rejects a different provider row" {
  let upsert = prepare_single_write_request(
    write_request_body(WriteUpsertByExternalId("External_Key__c")),
    "v66.0",
    ExternalText("key-1"),
    write_request_test_limits(),
  ).unwrap()
  assert_true(
    prepare_target_observation(
      upsert,
      200,
      @utf8.encode(
        "{\"Id\":\"001000000000001\",\"External_Key__c\":\"key-1\",\"Optional_Value__c\":\"old\"}",
      ),
      target_observation_test_limits(),
    )
    is Ok(_),
  )
  assert_true(
    prepare_target_observation(
      upsert,
      200,
      @utf8.encode(
        "{\"Id\":\"001000000000001\",\"External_Key__c\":\"key-2\",\"Optional_Value__c\":\"old\"}",
      ),
      target_observation_test_limits(),
    )
    is Err(ForeignTarget),
  )
  assert_true(
    prepare_target_observation(
      upsert,
      200,
      @utf8.encode("{\"Id\":\"001000000000001\",\"Optional_Value__c\":\"old\"}"),
      target_observation_test_limits(),
    )
    is Err(InvalidRecord),
  )
}
