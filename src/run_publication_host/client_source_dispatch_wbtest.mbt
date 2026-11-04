///|
fn original_dispatch_source(text : String) -> ClientSourcePreparation {
  let environment = admit_client_check_environment(
    multi_source_environment,
    "sha256:c9cf17f3e181c97a69e3419d4543e98c9a04af6da9490b359511a673a64c49a7",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let intent = prepare_client_submitted_intent(
    "{\"kind\":\"aql\",\"input\":{\"text\":\"" +
    text +
    "\",\"format\":\"sql\"},\"parameters\":null}",
    65536,
    8192,
    64,
  ).unwrap()
  let publication = "{\"environmentCid\":\"" +
    @checked.checking_environment_cid(environment) +
    "\",\"aliases\":[{\"name\":\"records\",\"sourceRef\":\"connector://crm/main/r#v\",\"sourceViewContractCid\":\"sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3\",\"schemaContractCid\":\"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4\"}]}"
  prepare_client_source_computation(intent, environment, publication).unwrap()
}

///|
test "Source dispatch matches only its original nominal computation and request" {
  let original = original_dispatch_source(
    "SELECT id FROM records WHERE id > 0 ORDER BY id",
  )
  guard original.preparation is Pure(prepared) else { fail("Expected Pure") }
  let request = client_source_computation_request(
    original,
    retained_input_cid("c"),
    "original-request",
  ).unwrap()
  assert_true(
    client_task_dispatch_source_request_matches(
      prepared,
      request,
      Some(original),
    ),
  )
  assert_false(
    client_task_dispatch_source_request_matches(prepared, request, None),
  )
  let equal_source = original_dispatch_source(
    "SELECT id FROM records WHERE id > 0 ORDER BY id",
  )
  assert_false(
    client_task_dispatch_source_request_matches(
      prepared,
      request,
      Some(equal_source),
    ),
  )
  let changed_source = original_dispatch_source(
    "SELECT id FROM records WHERE id > 0 ORDER BY id ",
  )
  assert_false(
    client_task_dispatch_source_request_matches(
      prepared,
      request,
      Some(changed_source),
    ),
  )
  guard changed_source.preparation is Pure(changed) else {
    fail("Expected Pure")
  }
  assert_false(
    client_task_dispatch_source_request_matches(
      changed,
      request,
      Some(changed_source),
    ),
  )
  let arbitrary = prepare_client_request_identity(
    prepared,
    retained_input_cid("c"),
    "original-request",
    retained_input_cid("f"),
  ).unwrap()
  assert_false(
    client_task_dispatch_source_request_matches(prepared, arbitrary, None),
  )
  assert_false(
    client_task_dispatch_source_request_matches(
      prepared,
      arbitrary,
      Some(original),
    ),
  )
}

///|
test "absent Source dispatch keeps the exact legacy source-free request law" {
  let (prepared, _, _, _) = retained_input_run("legacy-dispatch")
  let request = prepare_client_request_identity(
    prepared,
    retained_input_cid("c"),
    "legacy-request",
    source_free_caller_input_intent_cid(),
  ).unwrap()
  assert_true(
    client_task_dispatch_source_request_matches(prepared, request, None),
  )
  let source = original_dispatch_source(
    "SELECT id FROM records WHERE id > 0 ORDER BY id",
  )
  assert_false(
    client_task_dispatch_source_request_matches(prepared, request, Some(source)),
  )
}
