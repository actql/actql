///|
fn write_request_test_limits() -> WriteRequestLimits {
  { max_path_bytes: 500, max_target_bytes: 100, max_body_bytes: 1000, }
}

///|
fn write_request_body(operation : WriteOperation) -> WriteBody {
  let (observation, binding) = write_test_observation()
  let names = match operation {
    WriteCreate => ["External_Key__c"]
    _ => ["Optional_Value__c"]
  }
  let plan = prepare_write_projection(
    observation, binding, "ActQL_Test_Record__c", operation, names, 1,
  ).unwrap()
  let bytes = match operation {
    WriteCreate => @utf8.encode("{\"External_Key__c\":\"one\"}")
    _ => @utf8.encode("{\"Optional_Value__c\":\"value\"}")
  }
  prepare_write_body(plan, bytes, write_body_test_limits()).unwrap()
}

///|
test "RecordId identity validates the 18-character checksum" {
  assert_eq(
    canonical_write_record_id("001000000000001"),
    Some("001000000000001AAA"),
  )
  assert_eq(
    canonical_write_record_id("001000000000001AAA"),
    Some("001000000000001AAA"),
  )
  assert_true(canonical_write_record_id("001000000000001AAB") is None)
  assert_eq(
    canonical_write_record_id("00100000000000A"),
    Some("00100000000000AAAQ"),
  )
  assert_true(canonical_write_record_id("00100000000000aAAQ") is None)
}

///|
test "single write request derives method and path from selected operation" {
  let created = prepare_single_write_request(
    write_request_body(WriteCreate),
    "v66.0",
    NoWriteTarget,
    write_request_test_limits(),
  ).unwrap()
  assert_eq(single_write_request_method(created), "POST")
  assert_eq(
    single_write_request_grant_operation(created),
    "salesforce:record:create",
  )
  assert_eq(
    single_write_request_path(created),
    "/services/data/v66.0/sobjects/ActQL_Test_Record__c/",
  )
  assert_eq(single_write_request_body(created), "{\"External_Key__c\":\"one\"}")
  assert_eq(
    single_write_request_cid(created, "https://example.invalid", 1000).unwrap(),
    "sha256:0d32fc3f2f382c1b843d6516f48a7015ab6cc0a144a804564d48accc4aaeeb39",
  )
  assert_true(
    single_write_request_cid(created, "https://other.invalid", 1000).unwrap() !=
    single_write_request_cid(created, "https://example.invalid", 1000).unwrap(),
  )
  let (observation, binding) = write_test_observation()
  let plan = prepare_write_projection(
    observation,
    binding,
    "ActQL_Test_Record__c",
    WriteCreate,
    ["External_Key__c"],
    1,
  ).unwrap()
  let changed_body = prepare_write_body(
    plan,
    @utf8.encode("{\"External_Key__c\":\"two\"}"),
    write_body_test_limits(),
  ).unwrap()
  let changed = prepare_single_write_request(
    changed_body,
    "v66.0",
    NoWriteTarget,
    write_request_test_limits(),
  ).unwrap()
  assert_true(
    single_write_request_cid(changed, "https://example.invalid", 1000).unwrap() !=
    single_write_request_cid(created, "https://example.invalid", 1000).unwrap(),
  )
  assert_true(
    single_write_request_cid(created, "http://example.invalid", 1000)
    is Err(InvalidOrigin),
  )
  let updated = prepare_single_write_request(
    write_request_body(WriteUpdateById),
    "v66.0",
    RecordId("001000000000001"),
    write_request_test_limits(),
  ).unwrap()
  assert_eq(single_write_request_method(updated), "PATCH")
  assert_eq(
    single_write_request_grant_operation(updated),
    "salesforce:record:update",
  )
  assert_eq(
    single_write_request_path(updated),
    "/services/data/v66.0/sobjects/ActQL_Test_Record__c/001000000000001",
  )
  let upserted = prepare_single_write_request(
    write_request_body(WriteUpsertByExternalId("External_Key__c")),
    "v66.0",
    ExternalText("a/b é"),
    write_request_test_limits(),
  ).unwrap()
  assert_eq(single_write_request_method(upserted), "PATCH")
  assert_eq(
    single_write_request_grant_operation(upserted),
    "salesforce:record:upsert",
  )
  assert_eq(
    single_write_request_path(upserted),
    "/services/data/v66.0/sobjects/ActQL_Test_Record__c/External_Key__c/a%2Fb%20%C3%A9",
  )
}

///|
test "approved write values reconstruct the exact physical request" {
  let update_body = write_request_body(WriteUpdateById)
  let original = prepare_single_write_request(
    update_body,
    "v66.0",
    RecordId("001000000000001"),
    write_request_test_limits(),
  ).unwrap()
  let recovered = recover_single_write_request(
    write_body_projection(update_body),
    single_write_request_body(original),
    "\"001000000000001\"",
    "v66.0",
    write_body_test_limits(),
    write_request_test_limits(),
  ).unwrap()
  assert_eq(
    single_write_request_cid(recovered, "https://example.invalid", 1000),
    single_write_request_cid(original, "https://example.invalid", 1000),
  )
  assert_true(
    recover_single_write_request(
      write_body_projection(update_body),
      single_write_request_body(original),
      "\"foreign-target\"",
      "v66.0",
      write_body_test_limits(),
      write_request_test_limits(),
    )
    is Err(Request(InvalidTarget)),
  )
  assert_true(
    recover_single_write_request(
      write_body_projection(update_body),
      "{\"Foreign\":1}",
      "\"001000000000001\"",
      "v66.0",
      write_body_test_limits(),
      write_request_test_limits(),
    )
    is Err(Body(UnexpectedField(_))),
  )
  assert_true(
    recover_single_write_request(
      write_body_projection(update_body),
      single_write_request_body(original),
      "\"001000000000001\"",
      "v66.0",
      { max_bytes: -1, max_nodes: 1, max_depth: 1, },
      write_request_test_limits(),
    )
    is Err(Body(InvalidLimits)),
  )
  let create_body = write_request_body(WriteCreate)
  let created = recover_single_write_request(
    write_body_projection(create_body),
    "{\"External_Key__c\":\"one\"}",
    "\"source-row\"",
    "v66.0",
    write_body_test_limits(),
    write_request_test_limits(),
  ).unwrap()
  assert_eq(single_write_request_method(created), "POST")
  let upsert_body = write_request_body(
    WriteUpsertByExternalId("External_Key__c"),
  )
  let upserted = recover_single_write_request(
    write_body_projection(upsert_body),
    "{\"Optional_Value__c\":\"value\"}",
    "\"a/b é\"",
    "v66.0",
    write_body_test_limits(),
    write_request_test_limits(),
  ).unwrap()
  assert_eq(
    single_write_request_path(upserted),
    "/services/data/v66.0/sobjects/ActQL_Test_Record__c/External_Key__c/a%2Fb%20%C3%A9",
  )
}

///|
test "single write request rejects target confusion and invalid paths" {
  let create = write_request_body(WriteCreate)
  let update = write_request_body(WriteUpdateById)
  let upsert = write_request_body(WriteUpsertByExternalId("External_Key__c"))
  assert_true(
    prepare_single_write_request(
      create,
      "v66.0",
      RecordId("001000000000001"),
      write_request_test_limits(),
    )
    is Err(InvalidTarget),
  )
  assert_true(
    prepare_single_write_request(
      update,
      "v66.0",
      RecordId("../etc/passwd"),
      write_request_test_limits(),
    )
    is Err(InvalidTarget),
  )
  assert_true(
    prepare_single_write_request(
      upsert,
      "v66.0",
      ExternalInt(3),
      write_request_test_limits(),
    )
    is Err(TargetTypeMismatch),
  )
  assert_true(
    prepare_single_write_request(
      upsert,
      "v45.0",
      ExternalText("one"),
      write_request_test_limits(),
    )
    is Err(InvalidVersion),
  )
  assert_true(
    prepare_single_write_request(upsert, "v66.0", ExternalText("a/b"), {
      ..write_request_test_limits(),
      max_target_bytes: 4,
    })
    is Err(CapacityExceeded),
  )
  assert_true(
    prepare_single_write_request(create, "v66.0", NoWriteTarget, {
      ..write_request_test_limits(),
      max_body_bytes: 5,
    })
    is Err(CapacityExceeded),
  )
}

///|
test "single write request retains current Catalog and exact Site scope" {
  let (observation, binding) = write_test_observation()
  let projection = prepare_write_projection(
    observation,
    binding,
    "ActQL_Test_Record__c",
    WriteCreate,
    ["External_Key__c"],
    1,
  ).unwrap()
  let body = prepare_write_body(
    projection,
    @utf8.encode("{\"External_Key__c\":\"one\"}"),
    write_body_test_limits(),
  ).unwrap()
  let request = prepare_single_write_request(
    body,
    "v66.0",
    NoWriteTarget,
    write_request_test_limits(),
  ).unwrap()
  assert_true(recheck_single_write_request(request, observation) is Ok(_))
  assert_true(
    single_write_request_matches_site_scope(
      request,
      binding.namespace_id,
      binding.principal,
      binding.environment,
      binding.site_key,
      binding.site_generation,
      binding.connector_registration,
      binding.connector_revision,
      binding.resource_origin,
      binding.run_invocation_cid,
      "sha256:" + "e".repeat(64),
    ),
  )
  assert_false(
    single_write_request_matches_site_scope(
      request,
      binding.namespace_id,
      binding.principal,
      binding.environment,
      binding.site_key,
      binding.site_generation + 1,
      binding.connector_registration,
      binding.connector_revision,
      binding.resource_origin,
      binding.run_invocation_cid,
      "sha256:" + "e".repeat(64),
    ),
  )
  assert_true(
    recheck_single_write_request(
      request,
      write_test_observation_with(described(), {
        ..binding,
        site_generation: binding.site_generation + 1,
      }),
    )
    is Err(ForeignCurrentObservation),
  )
}
