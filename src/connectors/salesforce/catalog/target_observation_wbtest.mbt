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
