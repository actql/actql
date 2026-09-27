///|
fn read_test_observation() -> (CatalogObservation, CatalogObservationBinding) {
  let sync = observation_test_sync()
  finish_catalog_sync(sync).unwrap()
  let binding = observation_test_binding()
  let response_digest = match catalog_sync_outcome(sync, "Account") {
    Some(Described(resource)) => resource.response_sha256
    _ => abort("expected described Account")
  }
  let observation = prepare_catalog_observation(
    sync,
    binding,
    "sha256:" + "c".repeat(64),
    [Some("sha256:" + "d".repeat(64))],
    [Some(response_digest)],
    4096,
  ).unwrap()
  (observation, binding)
}

///|
test "read projection uses only the supplied complete resource view" {
  let (observation, binding) = read_test_observation()
  let plan = prepare_read_projection(
    observation,
    binding,
    "Account",
    ["Id"],
    22,
  ).unwrap()
  assert_eq(read_projection_soql(plan), "SELECT Id FROM Account")
  assert_eq(
    read_projection_observation(plan),
    catalog_observation_identity(observation),
  )
  assert_eq(read_projection_fields(plan), ["Id"])
  assert_true(
    read_projection_matches_site_scope(
      plan,
      binding.tenant,
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
    read_projection_matches_site_scope(
      plan,
      binding.tenant,
      binding.principal,
      binding.environment,
      binding.site_key,
      binding.site_generation + 1,
      binding.connector_registration,
      binding.connector_revision,
      binding.resource_origin,
      binding.run_invocation_cid,
      binding.dispatch_request_cid,
    ),
  )
  assert_false(
    read_projection_matches_site_scope(
      plan,
      binding.tenant,
      binding.principal,
      binding.environment,
      binding.site_key,
      binding.site_generation,
      binding.connector_registration,
      binding.connector_revision,
      binding.resource_origin,
      binding.run_invocation_cid,
      "invalid-query-dispatch",
    ),
  )
  assert_true(
    prepare_read_projection(observation, binding, "Account", ["Id"], 21)
    is Err(QueryLimit),
  )
  assert_true(
    prepare_read_projection(observation, binding, "Account", [], 100)
    is Err(EmptyProjection),
  )
}

///|
test "integer comparison prefilter requires exact metadata and bounded SQL" {
  let listing = project_resource_listing(
    @utf8.encode(
      (
        #|{"sobjects":[{"name":"Account","queryable":true}]}
      ),
    ),
    {
      max_bytes: 1000,
      max_nodes: 100,
      max_depth: 10,
      max_resources: 10,
      max_selected: 10,
      max_name_units: 100,
    },
  ).unwrap()
  let sync = begin_catalog_sync(listing)
  let description = @utf8.encode(
    (
      #|{"name":"Account","queryable":true,"fields":[{"name":"Score__c","type":"int","nillable":true,"filterable":true}]}
    ),
  )
  catalog_sync_describe(sync, "Account", description, {
    max_bytes: 1000,
    max_nodes: 100,
    max_depth: 10,
    max_fields: 10,
    max_name_units: 100,
  }).unwrap()
  finish_catalog_sync(sync).unwrap()
  let binding = observation_test_binding()
  let observed = prepare_catalog_observation(
    sync,
    binding,
    "sha256:" + "c".repeat(64),
    [Some("sha256:" + "d".repeat(64))],
    [Some(catalog_response_sha256(description))],
    4096,
  ).unwrap()
  let broad = prepare_read_projection(
    observed,
    binding,
    "Account",
    ["Score__c"],
    100,
  ).unwrap()
  let filtered = with_exact_int_comparison(broad, "Score__c", GreaterEqual, 4).unwrap()
  assert_eq(
    read_projection_soql(filtered),
    "SELECT Score__c FROM Account WHERE Score__c >= 4",
  )
  assert_true(with_exact_int_comparison(filtered, "Score__c", Less, 8) is None)
  let negative = with_exact_int_comparison(broad, "Score__c", Less, -3).unwrap()
  assert_eq(
    query_read_next_path(
      begin_query_read(negative, "v62.0", query_test_limits(), 1, 10L).unwrap(),
    ).unwrap(),
    Some(
      "/services/data/v62.0/query?q=SELECT%20Score__c%20FROM%20Account%20WHERE%20Score__c%20%3C%20%2D3",
    ),
  )
  assert_eq(
    query_read_next_path(
      begin_query_read(filtered, "v62.0", query_test_limits(), 1, 10L).unwrap(),
    ).unwrap(),
    Some(
      "/services/data/v62.0/query?q=SELECT%20Score__c%20FROM%20Account%20WHERE%20Score__c%20%3E%3D%204",
    ),
  )
  assert_true(with_exact_int_comparison(broad, "Other__c", Equal, 4) is None)
  assert_true(
    with_exact_int_comparison(
      with_row_limit(broad, 5).unwrap(),
      "Score__c",
      Less,
      8,
    )
    is None,
  )
  let limited = prepare_read_projection(
    observed,
    binding,
    "Account",
    ["Score__c"],
    "SELECT Score__c FROM Account".length(),
  ).unwrap()
  assert_true(with_exact_int_comparison(limited, "Score__c", Less, 4) is None)
}

///|
test "row-limited preview appends one LIMIT and admits no later filter" {
  let (observation, binding) = read_test_observation()
  let plan = prepare_read_projection(
    observation,
    binding,
    "Account",
    ["Id"],
    100,
  ).unwrap()
  assert_true(read_projection_row_limit(plan) is None)
  let preview = with_row_limit(plan, 5).unwrap()
  assert_eq(read_projection_soql(preview), "SELECT Id FROM Account LIMIT 5")
  assert_eq(read_projection_row_limit(preview), Some(5))
  assert_true(with_row_limit(preview, 3) is None)
  assert_true(with_row_limit(plan, 0) is None)
  assert_true(with_row_limit(plan, 2001) is None)
  let tight = prepare_read_projection(
    observation,
    binding,
    "Account",
    ["Id"],
    "SELECT Id FROM Account".length(),
  ).unwrap()
  assert_true(with_row_limit(tight, 5) is None)
  assert_eq(
    query_read_next_path(
      begin_query_read(preview, "v62.0", query_test_limits(), 1, 10L).unwrap(),
    ).unwrap(),
    Some(
      "/services/data/v62.0/query?q=SELECT%20Id%20FROM%20Account%20LIMIT%205",
    ),
  )
}

///|
test "read projection rechecks a new observation without reusing its dispatch" {
  let (observation, binding) = read_test_observation()
  let plan = prepare_read_projection(
    observation,
    binding,
    "Account",
    ["Id"],
    100,
  ).unwrap()
  let sync = observation_test_sync()
  finish_catalog_sync(sync).unwrap()
  let response_digest = match catalog_sync_outcome(sync, "Account") {
    Some(Described(resource)) => resource.response_sha256
    _ => abort("expected described Account")
  }
  let refreshed = prepare_catalog_observation(
    sync,
    {
      ..binding,
      dispatch_request_cid: "sha256:" + "e".repeat(64),
      sync_occurrence: "refresh-b",
    },
    "sha256:" + "f".repeat(64),
    [Some("sha256:" + "1".repeat(64))],
    [Some(response_digest)],
    4096,
  ).unwrap()
  assert_true(recheck_read_projection(plan, refreshed) is Ok(_))
  let foreign = prepare_catalog_observation(
    sync,
    {
      ..binding,
      connection_revision: "connection-revision-b",
      sync_occurrence: "refresh-c",
    },
    "sha256:" + "f".repeat(64),
    [Some("sha256:" + "1".repeat(64))],
    [Some(response_digest)],
    4096,
  ).unwrap()
  assert_true(
    recheck_read_projection(plan, foreign) is Err(ForeignCurrentObservation),
  )
}

///|
test "read projection preserves missing-field and foreign-binding diagnostics" {
  let (observation, binding) = read_test_observation()
  assert_true(
    prepare_read_projection(
      observation,
      binding,
      "Account",
      ["Hidden_Field__c"],
      100,
    )
    is Err(Requirement(FieldUnconfirmed("Hidden_Field__c"))),
  )
  assert_true(
    prepare_read_projection(
      observation,
      { ..binding, site_generation: 5, },
      "Account",
      ["Id"],
      100,
    )
    is Err(Observation(ForeignBinding)),
  )
  assert_true(
    prepare_read_projection(observation, binding, "Contact", ["Id"], 100)
    is Err(Observation(Resource(NotVisible))),
  )
}

///|
test "read projection does not infer nullability from partial metadata" {
  let listing = project_resource_listing(
    @utf8.encode(
      (
        #|{"sobjects":[{"name":"Account","queryable":true}]}
      ),
    ),
    {
      max_bytes: 1000,
      max_nodes: 100,
      max_depth: 10,
      max_resources: 10,
      max_selected: 10,
      max_name_units: 100,
    },
  ).unwrap()
  let sync = begin_catalog_sync(listing)
  let description =
    #|{"name":"Account","queryable":true,"fields":[{"name":"Name","type":"string"}]}
  catalog_sync_describe(sync, "Account", @utf8.encode(description), {
    max_bytes: 1000,
    max_nodes: 100,
    max_depth: 10,
    max_fields: 10,
    max_name_units: 100,
  }).unwrap()
  finish_catalog_sync(sync).unwrap()
  let binding = observation_test_binding()
  let observation = prepare_catalog_observation(
    sync,
    binding,
    "sha256:" + "c".repeat(64),
    [Some("sha256:" + "d".repeat(64))],
    [Some(@sha.hex(@utf8.encode(description)))],
    4096,
  ).unwrap()
  assert_true(
    prepare_read_projection(observation, binding, "Account", ["Name"], 100)
    is Err(UnconfirmedNullability("Name")),
  )
}

///|
fn account_observation(
  id_field : String,
  occurrence : String,
) -> (CatalogObservation, CatalogObservationBinding) {
  let listing = project_resource_listing(
    @utf8.encode(
      (
        #|{"sobjects":[{"name":"Account","queryable":true}]}
      ),
    ),
    {
      max_bytes: 1000,
      max_nodes: 100,
      max_depth: 10,
      max_resources: 10,
      max_selected: 10,
      max_name_units: 100,
    },
  ).unwrap()
  let sync = begin_catalog_sync(listing)
  catalog_sync_describe(
    sync,
    "Account",
    @utf8.encode(
      "{\"name\":\"Account\",\"queryable\":true,\"fields\":[" + id_field + "]}",
    ),
    {
      max_bytes: 1000,
      max_nodes: 100,
      max_depth: 10,
      max_fields: 10,
      max_name_units: 100,
    },
  ).unwrap()
  finish_catalog_sync(sync).unwrap()
  let binding = { ..observation_test_binding(), sync_occurrence: occurrence, }
  let response_digest = match catalog_sync_outcome(sync, "Account") {
    Some(Described(resource)) => resource.response_sha256
    _ => abort("expected described Account")
  }
  let observation = prepare_catalog_observation(
    sync,
    binding,
    "sha256:" + "c".repeat(64),
    [Some("sha256:" + "d".repeat(64))],
    [Some(response_digest)],
    4096,
  ).unwrap()
  (observation, binding)
}

///|
test "Id order applies only to a described sortable Id and is rechecked" {
  let sortable = "{\"name\":\"Id\",\"type\":\"id\",\"nillable\":false,\"sortable\":true}"
  let unsorted = "{\"name\":\"Id\",\"type\":\"id\",\"nillable\":false}"
  let (observation, binding) = account_observation(sortable, "a")
  let plan = prepare_read_projection(
    observation,
    binding,
    "Account",
    ["Id"],
    100,
  ).unwrap()
  let ordered = with_id_order(plan).unwrap()
  assert_true(read_projection_ordered_by_id(ordered))
  assert_true(with_id_order(ordered) is None)
  let preview = with_row_limit(ordered, 5).unwrap()
  assert_eq(
    read_projection_soql(preview),
    "SELECT Id FROM Account ORDER BY Id LIMIT 5",
  )
  // Order precedes the limit and admits no later filter.
  assert_true(with_id_order(with_row_limit(plan, 5).unwrap()) is None)
  assert_true(with_exact_int_comparison(ordered, "Id", Equal, 1) is None)
  let tight = prepare_read_projection(
    observation,
    binding,
    "Account",
    ["Id"],
    "SELECT Id FROM Account".length(),
  ).unwrap()
  assert_true(read_projection_id_sortable(tight))
  assert_true(with_id_order(tight) is None)
  let (plain, plain_binding) = account_observation(unsorted, "b")
  let unordered = prepare_read_projection(
    plain,
    plain_binding,
    "Account",
    ["Id"],
    100,
  ).unwrap()
  assert_false(read_projection_id_sortable(unordered))
  assert_true(with_id_order(unordered) is None)
  // A refresh that no longer reports Id as sortable rejects a plan ordered
  // by Id even when Id is not projected; the unordered plan is admitted.
  let name = ",{\"name\":\"Name\",\"type\":\"string\",\"nillable\":false}"
  let (named, named_binding) = account_observation(sortable + name, "c")
  let by_name = prepare_read_projection(
    named,
    named_binding,
    "Account",
    ["Name"],
    100,
  ).unwrap()
  let by_name_ordered = with_id_order(by_name).unwrap()
  let (refreshed, _) = account_observation(unsorted + name, "d")
  assert_true(
    recheck_read_projection(by_name_ordered, refreshed)
    is Err(SchemaChanged("Id")),
  )
  assert_true(recheck_read_projection(by_name, refreshed) is Ok(_))
  let (still, _) = account_observation(sortable + name, "e")
  assert_true(recheck_read_projection(by_name_ordered, still) is Ok(_))
}
