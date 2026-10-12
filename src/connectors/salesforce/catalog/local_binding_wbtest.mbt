///|
// Test-only extraction of the original Site fixture. Production Local paths
// never convert their identity to a Site or fill missing Site fields.
fn site_catalog_test_binding(
  binding : CatalogExecutionBinding,
) -> CatalogObservationBinding {
  match binding {
    SiteCatalog(value) => value
    DirectLocalCatalog(_) => abort("Site fixture required")
  }
}

///|
fn local_catalog_test_cid(value : String) -> String {
  "sha256:" + value.repeat(64)
}

///|
fn local_catalog_test_binding() -> LocalCatalogObservationBinding {
  {
    account_configuration_cid: local_catalog_test_cid("1"),
    account_id: "account-a",
    authority_scope_cid: local_catalog_test_cid("2"),
    client_request_intent_cid: local_catalog_test_cid("3"),
    client_request_scope_cid: local_catalog_test_cid("4"),
    connection_revision: "connection-a",
    connector_registration: "salesforce",
    connector_revision: "salesforce/0.1",
    environment: "local",
    host_adoption_cid: local_catalog_test_cid("5"),
    namespace_id: "namespace-a",
    org_id: "00D000000000001EAA",
    principal: "operator",
    resource_origin: "https://example.invalid",
    run_invocation_cid: local_catalog_test_cid("6"),
    sync_occurrence: "describe-original",
  }
}

///|
fn local_catalog_test_description() -> Bytes {
  @utf8.encode(
    (
      #|{"name":"Account","queryable":true,"updateable":true,"fields":[{"name":"Id","type":"id","nillable":false,"sortable":true},{"name":"Name","type":"string","nillable":false,"defaultedOnCreate":false,"updateable":true}]}
    ),
  )
}

///|
fn local_catalog_test_limits() -> DescribeLimits {
  {
    max_bytes: 4096,
    max_nodes: 100,
    max_depth: 10,
    max_fields: 10,
    max_name_units: 100,
  }
}

///|
fn local_catalog_test_sync() -> CatalogSync {
  let sync = begin_named_catalog_sync(["Account"]).unwrap()
  catalog_sync_describe(
    sync,
    "Account",
    local_catalog_test_description(),
    local_catalog_test_limits(),
  ).unwrap()
  finish_catalog_sync(sync).unwrap()
  sync
}

///|
fn local_catalog_test_observation(
  binding? : LocalCatalogObservationBinding = local_catalog_test_binding(),
) -> CatalogObservation {
  prepare_local_catalog_observation(
    local_catalog_test_sync(),
    binding,
    "",
    [Some(local_catalog_test_cid("7"))],
    [Some("3dbc19793840e93f26d2da63a0333e72af8f1c6d9f5f79548c71f614fbb2ff9e")],
    8192,
  ).unwrap()
}

///|
fn local_catalog_test_write(
  observation : CatalogObservation,
  binding : LocalCatalogObservationBinding,
  value? : String = "{\"Name\":\"new\"}",
) -> SingleWriteRequest {
  let projection = prepare_local_write_projection(
    observation,
    binding,
    "Account",
    WriteUpdateById,
    ["Name"],
    1,
  ).unwrap()
  let body = prepare_write_body(
    projection,
    @utf8.encode(value),
    write_body_test_limits(),
  ).unwrap()
  prepare_single_write_request(
    body,
    "v66.0",
    RecordId("001000000000001"),
    write_request_test_limits(),
  ).unwrap()
}

///|
test "Local catalog observation has independent exact bytes identity without a Site or Dispatch" {
  let observation = local_catalog_test_observation()
  assert_eq(
    catalog_observation_identity(observation),
    "sha256:adee78befffb35c87829d82e737be7b22030f470783d8031359b0f9ddb48e25b",
  )
  let body = catalog_observation_json(observation)
  assert_false(body.contains("site_key"))
  assert_false(body.contains("site_generation"))
  assert_false(body.contains("dispatch_request_cid"))
  assert_true(
    catalog_observation_matches_local_binding(
      observation,
      local_catalog_test_binding(),
    ),
  )
  // Named describe remains incomplete for the namespace; a usable Resource
  // does not assert that every resource has been listed or is absent.
  assert_false(catalog_observation_is_complete(observation))
  assert_true(
    catalog_observation_local_resource(
      observation,
      local_catalog_test_binding(),
      "Account",
    )
    is Ok(_),
  )
  assert_true(
    catalog_observation_local_resource(
      observation,
      local_catalog_test_binding(),
      "Unseen",
    )
    is Err(Resource(ListingTruncated)),
  )
}

///|
test "Local catalog binding never accepts an equal-resource Site observation" {
  let local_observation = local_catalog_test_observation()
  let site = prepare_catalog_observation(
    local_catalog_test_sync(),
    observation_test_binding(),
    "",
    [Some(local_catalog_test_cid("7"))],
    [Some("3dbc19793840e93f26d2da63a0333e72af8f1c6d9f5f79548c71f614fbb2ff9e")],
    8192,
  ).unwrap()
  assert_true(
    catalog_observation_local_resource(
      site,
      local_catalog_test_binding(),
      "Account",
    )
    is Err(ForeignBinding),
  )
  assert_true(
    catalog_observation_resource(
      local_observation,
      observation_test_binding(),
      "Account",
    )
    is Err(ForeignBinding),
  )
  assert_false(
    catalog_observation_matches_binding(
      local_observation,
      observation_test_binding(),
    ),
  )
  assert_false(
    catalog_observation_matches_local_binding(
      site,
      local_catalog_test_binding(),
    ),
  )
}

///|
test "Local catalog refuses invalid original identity missing evidence and finite budget exhaustion" {
  let binding = local_catalog_test_binding()
  for
    invalid in [
      { ..binding, account_configuration_cid: "invalid", },
      { ..binding, account_id: "", },
      { ..binding, authority_scope_cid: "invalid", },
      { ..binding, client_request_intent_cid: "invalid", },
      { ..binding, client_request_scope_cid: "invalid", },
      { ..binding, host_adoption_cid: "invalid", },
      { ..binding, run_invocation_cid: "invalid", },
      { ..binding, org_id: "invalid", },
      { ..binding, principal: "", },
      { ..binding, sync_occurrence: "", },
    ] {
    assert_true(
      prepare_local_catalog_observation(
        local_catalog_test_sync(),
        invalid,
        "",
        [Some(local_catalog_test_cid("7"))],
        [
          Some(
            "3dbc19793840e93f26d2da63a0333e72af8f1c6d9f5f79548c71f614fbb2ff9e",
          ),
        ],
        8192,
      )
      is Err(InvalidBinding),
    )
  }
  assert_true(
    prepare_local_catalog_observation(
      local_catalog_test_sync(),
      binding,
      "",
      [None],
      [None],
      8192,
    )
    is Err(InvalidUseEvidence),
  )
  assert_true(
    prepare_local_catalog_observation(
      local_catalog_test_sync(),
      binding,
      "",
      [Some(local_catalog_test_cid("7"))],
      [Some("3dbc19793840e93f26d2da63a0333e72af8f1c6d9f5f79548c71f614fbb2ff9e")],
      1,
    )
    is Err(OutputLimit),
  )
}

///|
test "Local catalog request refuses foreign Host account authority original request and Run" {
  let binding = local_catalog_test_binding()
  let original = local_catalog_test_observation()
  let request = local_catalog_test_write(original, binding)
  for
    foreign in [
      { ..binding, account_configuration_cid: local_catalog_test_cid("9"), },
      { ..binding, account_id: "other", },
      { ..binding, authority_scope_cid: local_catalog_test_cid("9"), },
      { ..binding, client_request_intent_cid: local_catalog_test_cid("9"), },
      { ..binding, client_request_scope_cid: local_catalog_test_cid("9"), },
      { ..binding, host_adoption_cid: local_catalog_test_cid("9"), },
      { ..binding, run_invocation_cid: local_catalog_test_cid("9"), },
      { ..binding, connector_revision: "other", },
      { ..binding, connection_revision: "other", },
      { ..binding, principal: "other", },
      { ..binding, namespace_id: "other", },
      { ..binding, org_id: "00D000000000002EAA", },
      { ..binding, resource_origin: "https://other.invalid", },
    ] {
    assert_false(single_write_request_matches_local_binding(request, foreign))
    assert_true(
      catalog_observation_local_resource(original, foreign, "Account")
      is Err(ForeignBinding),
    )
    assert_true(
      recheck_single_write_request(
        request,
        local_catalog_test_observation(binding=foreign),
      )
      is Err(ForeignCurrentObservation),
    )
    assert_true(
      prepare_local_target_read_request(
        request,
        foreign,
        local_catalog_test_observation(binding=foreign),
        foreign.org_id,
        4096,
      )
      is Err(InvalidTarget),
    )
  }
}

///|
test "Local catalog derives the exact target GET independently of the PATCH body" {
  let binding = local_catalog_test_binding()
  let observation = local_catalog_test_observation()
  let request = local_catalog_test_write(observation, binding)
  let read = prepare_local_target_read_request(
    request,
    binding,
    observation,
    binding.org_id,
    4096,
  ).unwrap()
  assert_eq(
    local_target_read_request_cid(read),
    "sha256:248299c85113e5888dc5636575b914f3a4e3dd836a8a74196d13a2116ac58d22",
  )
  assert_eq(
    local_target_read_request_path(read),
    "/services/data/v66.0/sobjects/Account/001000000000001",
  )
  assert_eq(
    single_write_request_method(local_target_read_request_candidate(read)),
    "PATCH",
  )
  let changed_body = local_catalog_test_write(
    observation,
    binding,
    value="{\"Name\":\"é\\r\\n\"}",
  )
  assert_eq(
    local_target_read_request_cid(
      prepare_local_target_read_request(
        changed_body,
        binding,
        observation,
        binding.org_id,
        4096,
      ).unwrap(),
    ),
    local_target_read_request_cid(read),
  )
  assert_true(
    single_write_request_cid(changed_body, binding.resource_origin, 4096).unwrap() !=
    local_target_read_request_cid(read),
  )
  assert_true(
    prepare_local_target_read_request(
      request, binding, observation, "00D000000000002EAA", 4096,
    )
    is Err(InvalidTarget),
  )
  assert_true(
    prepare_local_target_read_request(
      request,
      binding,
      observation,
      binding.org_id,
      0,
    )
    is Err(InvalidLimits),
  )
  assert_true(
    prepare_local_target_read_request(
      request,
      binding,
      observation,
      binding.org_id,
      1,
    )
    is Err(Encoding),
  )
}

///|
test "Local catalog retains shared declaration schema checks and distinct capability identity" {
  let binding = local_catalog_test_binding()
  let observation = local_catalog_test_observation()
  let declaration = generate_local_static_declaration(
    observation,
    binding,
    salesforce_implementation("salesforce/0.1").unwrap(),
    "crm-local",
    ["Account"],
    declaration_limits(),
  ).unwrap()
  let mapping = prepare_execution_mapping(
    declaration,
    "Account",
    UpdateById(["Name"]),
    declaration_limits(),
  ).unwrap()
  let request = local_catalog_test_write(observation, binding)
  assert_true(check_execution_single_write(mapping, request) is Ok(_))
  let capability = prepare_write_capability_evidence(
    request,
    local_catalog_test_cid("8"),
    SerialRows,
    8192,
  ).unwrap()
  assert_eq(
    write_capability_identity(capability),
    "sha256:d4ced2cbfa48faa4ce8ad7a49f5c5961dcad1728d030c9a6048cfb3116e1fcc3",
  )
  assert_false(write_capability_body(capability).contains("site_key"))
  let other = { ..binding, host_adoption_cid: local_catalog_test_cid("9"), }
  let foreign = local_catalog_test_write(
    local_catalog_test_observation(binding=other),
    other,
  )
  assert_true(
    check_execution_single_write(mapping, foreign) is Err(ForeignDeclaration),
  )
  assert_true(
    check_write_capability_request(
      capability,
      foreign,
      local_catalog_test_cid("8"),
    )
    is Err(ForeignRequest),
  )
  let another_run = {
    ..binding,
    client_request_intent_cid: local_catalog_test_cid("9"),
    run_invocation_cid: local_catalog_test_cid("9"),
  }
  let another = local_catalog_test_write(
    local_catalog_test_observation(binding=another_run),
    another_run,
  )
  assert_true(check_execution_single_write(mapping, another) is Ok(_))
  let profile = prepare_write_capability_evidence(
    another,
    local_catalog_test_cid("8"),
    SerialRows,
    8192,
  ).unwrap()
  assert_eq(
    write_capability_identity(profile),
    write_capability_identity(capability),
  )
  assert_true(
    check_write_capability_request(
      capability,
      another,
      local_catalog_test_cid("8"),
    )
    is Err(ForeignRequest),
  )
}

///|
test "Local catalog restores exact retained metadata without refreshing or replacing originals" {
  let observation = local_catalog_test_observation()
  let binding = local_catalog_test_binding()
  let body = catalog_observation_json(observation)
  let restore = binding => {
    recover_local_named_catalog_observation(
      body,
      ["Account"],
      [Some(local_catalog_test_description())],
      [1],
      binding,
      [Some(local_catalog_test_cid("7"))],
      [Some("3dbc19793840e93f26d2da63a0333e72af8f1c6d9f5f79548c71f614fbb2ff9e")],
      local_catalog_test_limits(),
      8192,
    )
  }
  assert_eq(
    catalog_observation_identity(restore(binding).unwrap()),
    "sha256:adee78befffb35c87829d82e737be7b22030f470783d8031359b0f9ddb48e25b",
  )
  assert_true(
    restore({
      ..binding,
      client_request_intent_cid: local_catalog_test_cid("9"),
    })
    is Err(ForeignObservation),
  )
  assert_true(
    recover_local_named_catalog_observation(
      body,
      ["Account"],
      [None],
      [1],
      binding,
      [Some(local_catalog_test_cid("7"))],
      [Some("3dbc19793840e93f26d2da63a0333e72af8f1c6d9f5f79548c71f614fbb2ff9e")],
      local_catalog_test_limits(),
      8192,
    )
    is Err(ResponseMismatch),
  )
  assert_true(
    recover_local_named_catalog_observation(
      body + " ",
      ["Account"],
      [Some(local_catalog_test_description())],
      [1],
      binding,
      [Some(local_catalog_test_cid("7"))],
      [Some("3dbc19793840e93f26d2da63a0333e72af8f1c6d9f5f79548c71f614fbb2ff9e")],
      local_catalog_test_limits(),
      8192,
    )
    is Err(ForeignObservation),
  )
}
