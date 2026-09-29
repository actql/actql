///|
fn capability_test_request() -> SingleWriteRequest {
  prepare_single_write_request(
    write_request_body(WriteUpdateById),
    "v66.0",
    RecordId("001000000000001"),
    write_request_test_limits(),
  ).unwrap()
}

///|
test "write capability has an independent profile identity" {
  let request = capability_test_request()
  let runtime = "sha256:" + "f".repeat(64)
  let evidence = prepare_write_capability_evidence(
    request,
    runtime,
    SerialRows,
    4096,
  ).unwrap()
  // Independent Node SHA-256 over the documented canonical field inventory.
  assert_eq(
    write_capability_identity(evidence),
    "sha256:3845b8b110f5abab0f7dddb2529fdbf10b53032ec3c89f95148d67107855df21",
  )
  assert_eq(write_capability_route(evidence), SerialRows)
  let other_row = {
    ..request,
    target: RecordId("001000000000002"),
    body: "{\"Optional_Value__c\":\"different\"}",
  }
  assert_true(
    check_write_capability_request(evidence, other_row, runtime) is Ok(_),
  )
  let row_evidence = prepare_write_capability_evidence(
    other_row,
    runtime,
    SerialRows,
    4096,
  ).unwrap()
  assert_eq(
    write_capability_identity(row_evidence),
    write_capability_identity(evidence),
  )
  let binding = {
    ..request.projection.binding,
    sync_occurrence: "sync-b",
    dispatch_request_cid: "sha256:" + "9".repeat(64),
  }
  let refreshed = { ..request, projection: { ..request.projection, binding, }, }
  let fresh = prepare_write_capability_evidence(
    refreshed,
    runtime,
    SerialRows,
    4096,
  ).unwrap()
  assert_eq(
    write_capability_identity(fresh),
    write_capability_identity(evidence),
  )
  assert_true(
    check_write_capability_request(evidence, refreshed, runtime) is Ok(_),
  )
}

///|
test "capability rejects runtime Site operation field and API substitution" {
  let request = capability_test_request()
  let runtime = "sha256:" + "f".repeat(64)
  let evidence = prepare_write_capability_evidence(
    request,
    runtime,
    SerialRows,
    4096,
  ).unwrap()
  for
    changed in [
      { ..request, api_version: "v65.0", },
      {
        ..request,
        projection: { ..request.projection, resource: "Other__c", },
      },
      {
        ..request,
        projection: { ..request.projection, operation: WriteCreate, },
      },
      { ..request, projection: { ..request.projection, fields: [], }, },
      {
        ..request,
        projection: {
          ..request.projection,
          binding: { ..request.projection.binding, site_generation: 5, },
        },
      },
    ] {
    assert_true(
      check_write_capability_request(evidence, changed, runtime)
      is Err(ForeignRequest),
    )
  }
  assert_true(
    check_write_capability_request(
      evidence,
      request,
      "sha256:" + "e".repeat(64),
    )
    is Err(ForeignRequest),
  )
  let collection = prepare_write_capability_evidence(
    request,
    runtime,
    ContinueCollection,
    4096,
  ).unwrap()
  assert_true(
    write_capability_identity(collection) != write_capability_identity(evidence),
  )
  assert_true(
    prepare_write_capability_evidence(request, runtime, SerialRows, 16)
    is Err(OutputLimit),
  )
}

///|
test "capability current use checks the observed write constraints" {
  let request = capability_test_request()
  let evidence = prepare_write_capability_evidence(
    request,
    "sha256:" + "f".repeat(64),
    SerialRows,
    4096,
  ).unwrap()
  let (observation, _) = write_test_observation()
  assert_true(recheck_write_capability(evidence, observation) is Ok(_))
  let wrong_generation = {
    ..observation,
    binding: { ..observation.binding, site_generation: 5, },
  }
  assert_true(
    recheck_write_capability(evidence, wrong_generation)
    is Err(CurrentCatalog(ForeignCurrentObservation)),
  )
}

///|
test "capability content reuse does not waive exact execution binding" {
  let request = capability_test_request()
  let runtime = "sha256:" + "f".repeat(64)
  let original = prepare_write_capability_evidence(
    request,
    runtime,
    SerialRows,
    4096,
  ).unwrap()
  let foreign_run = {
    ..request,
    projection: {
      ..request.projection,
      binding: {
        ..request.projection.binding,
        run_invocation_cid: "sha256:" + "9".repeat(64),
      },
    },
  }
  let same_profile = prepare_write_capability_evidence(
    foreign_run,
    runtime,
    SerialRows,
    4096,
  ).unwrap()
  assert_eq(
    write_capability_identity(original),
    write_capability_identity(same_profile),
  )
  assert_true(
    check_write_capability_request(original, foreign_run, runtime)
    is Err(ForeignRequest),
  )
  let field = request.projection.fields[0]
  let changed_field = { ..field, nullable: !field.nullable, }
  let changed = {
    ..request,
    projection: { ..request.projection, fields: [changed_field], },
  }
  let changed_profile = prepare_write_capability_evidence(
    changed,
    runtime,
    SerialRows,
    4096,
  ).unwrap()
  assert_true(
    write_capability_identity(original) !=
    write_capability_identity(changed_profile),
  )
  assert_true(
    check_write_capability_request(original, changed, runtime)
    is Err(ForeignRequest),
  )
}
