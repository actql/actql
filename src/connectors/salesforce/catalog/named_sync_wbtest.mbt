///|
fn named_describe_limits() -> DescribeLimits {
  {
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 10,
    max_fields: 20,
    max_name_units: 1000,
  }
}

///|
test "a named describe-only observation is incomplete and records no listing" {
  assert_true(begin_named_catalog_sync([]) is Err(InvalidLimits))
  assert_true(
    begin_named_catalog_sync(["A__c", "A__c"]) is Err(DuplicateResource("A__c")),
  )
  assert_true(begin_named_catalog_sync(["bad name"]) is Err(InvalidResponse))
  let sync = begin_named_catalog_sync(["Record__c", "Gone__c", "Later__c"]).unwrap()
  assert_true(catalog_sync_is_named(sync))
  let describe = "{\"name\":\"Record__c\",\"queryable\":true,\"createable\":true,\"updateable\":true,\"fields\":[{\"name\":\"Id\",\"type\":\"id\",\"nillable\":false}]}"
  catalog_sync_describe(
    sync,
    "Record__c",
    @utf8.encode(describe),
    named_describe_limits(),
  ).unwrap()
  // The provider does not find this name for the principal.
  catalog_sync_unavailable(sync, "Gone__c", NotFound).unwrap()
  // The last name is never described: it stays unobserved.
  cancel_catalog_sync(sync).unwrap()
  finish_catalog_sync(sync).unwrap()
  let binding = observation_test_binding()
  let digest = catalog_response_sha256(@utf8.encode(describe))
  assert_true(
    prepare_catalog_observation(
      sync,
      binding,
      "sha256:" + "c".repeat(64),
      [Some("sha256:" + "d".repeat(64)), None, None],
      [Some(digest), None, None],
      4096,
    )
    is Err(InvalidUseEvidence),
  )
  let observation = prepare_catalog_observation(
    sync,
    binding,
    "",
    [Some("sha256:" + "d".repeat(64)), None, None],
    [Some(digest), None, None],
    4096,
  ).unwrap()
  let body = catalog_observation_json(observation)
  assert_true(body.contains("\"listing_response_sha256\":null"))
  assert_true(body.contains("\"listing_use_cid\":null"))
  assert_true(body.contains("\"truncated\":true"))
  assert_true(body.contains("\"name\":\"Gone__c\",\"outcome\":\"not_found\""))
  assert_true(body.contains("\"name\":\"Later__c\",\"outcome\":\"cancelled\""))
  assert_false(catalog_observation_is_complete(observation))
  assert_true(
    catalog_observation_resource(observation, binding, "Record__c") is Ok(_),
  )
  assert_true(
    catalog_observation_resource(observation, binding, "Gone__c")
    is Err(DescribeUnavailable(NotFound)),
  )
  // Recovery reproduces the exact observation without provider I/O.
  let recovered = recover_named_catalog_observation(
    body,
    ["Record__c", "Gone__c", "Later__c"],
    [Some(@utf8.encode(describe)), None, None],
    [1, 8, 7],
    binding,
    [Some("sha256:" + "d".repeat(64)), None, None],
    [Some(digest), None, None],
    named_describe_limits(),
    4096,
  ).unwrap()
  assert_eq(catalog_observation_identity(recovered), observation.cid)
  assert_true(
    recover_named_catalog_observation(
      body,
      ["Record__c", "Gone__c", "Later__c"],
      [Some(@utf8.encode(describe)), None, None],
      [1, 8, 7],
      { ..binding, site_generation: 5, },
      [Some("sha256:" + "d".repeat(64)), None, None],
      [Some(digest), None, None],
      named_describe_limits(),
      4096,
    )
    is Err(ForeignObservation),
  )
  // A 404 describe is NotFound, distinct from a permission failure.
  assert_eq(catalog_http_failure(404, b"[]", 100), NotFound)
  assert_eq(catalog_http_failure(403, b"[]", 100), PermissionDenied)
}
