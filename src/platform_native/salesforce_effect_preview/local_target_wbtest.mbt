///|
// Pure matching adapter boundary fixtures, not current adopted Host authority
// or an operational preparation Work. The Native consumer compiles these;
// actual Provider/credential use is a separate physical acceptance.
fn local_target_test_cid(value : String) -> String {
  "sha256:" + value.repeat(64)
}

///|
fn local_target_test_materials() -> (
  @catalog.LocalTargetReadRequest,
  @credential.LocalPreparationCredentialScope,
) {
  let binding : @catalog.LocalCatalogObservationBinding = {
    account_configuration_cid: local_target_test_cid("1"),
    account_id: "account-a",
    authority_scope_cid: local_target_test_cid("2"),
    client_request_intent_cid: local_target_test_cid("3"),
    client_request_scope_cid: local_target_test_cid("4"),
    connection_revision: "connection-a",
    connector_registration: "salesforce",
    connector_revision: "salesforce/0.1",
    environment: "local",
    host_adoption_cid: local_target_test_cid("5"),
    namespace_id: "namespace-a",
    org_id: "00D000000000001EAA",
    principal: "operator",
    resource_origin: "https://example.invalid",
    run_invocation_cid: local_target_test_cid("6"),
    sync_occurrence: "describe-original",
  }
  let sync = @catalog.begin_named_catalog_sync(["Account"]).unwrap()
  let description = @utf8.encode(
    (
      #|{"name":"Account","queryable":true,"updateable":true,"fields":[{"name":"Id","type":"id","nillable":false,"sortable":true},{"name":"Name","type":"string","nillable":false,"defaultedOnCreate":false,"updateable":true}]}
    ),
  )
  @catalog.catalog_sync_describe(sync, "Account", description, {
    max_bytes: 4096,
    max_nodes: 100,
    max_depth: 10,
    max_fields: 10,
    max_name_units: 100,
  }).unwrap()
  @catalog.finish_catalog_sync(sync).unwrap()
  let observation = @catalog.prepare_local_catalog_observation(
    sync,
    binding,
    "",
    [Some(local_target_test_cid("7"))],
    [Some("3dbc19793840e93f26d2da63a0333e72af8f1c6d9f5f79548c71f614fbb2ff9e")],
    8192,
  ).unwrap()
  let projection = @catalog.prepare_local_write_projection(
    observation,
    binding,
    "Account",
    @catalog.WriteUpdateById,
    ["Name"],
    1,
  ).unwrap()
  let body = @catalog.prepare_write_body(projection, b"{\"Name\":\"new\"}", {
    max_bytes: 1000,
    max_nodes: 100,
    max_depth: 10,
  }).unwrap()
  let candidate = @catalog.prepare_single_write_request(
    body,
    "v66.0",
    @catalog.RecordId("001000000000001"),
    { max_path_bytes: 500, max_target_bytes: 100, max_body_bytes: 1000, },
  ).unwrap()
  let request = @catalog.prepare_local_target_read_request(
    candidate,
    binding,
    observation,
    binding.org_id,
    4096,
  ).unwrap()
  let fence = @credential.prepare_local_preparation_fence_identity({
    client_request_intent_cid: binding.client_request_intent_cid,
    client_request_scope_cid: binding.client_request_scope_cid,
    operation_occurrence_cid: local_target_test_cid("8"),
    run_invocation_cid: binding.run_invocation_cid,
    unit_definition_cid: local_target_test_cid("9"),
  }).unwrap()
  let scope : @credential.LocalPreparationCredentialScope = {
    account_configuration_cid: binding.account_configuration_cid,
    account_id: binding.account_id,
    attempt_id: "observe-original",
    authority_scope_cid: binding.authority_scope_cid,
    connector_registration: binding.connector_registration,
    connector_revision: binding.connector_revision,
    preparation_fence: fence,
    host_adoption_cid: binding.host_adoption_cid,
    operation: "salesforce:record:observe",
    operation_occurrence_cid: local_target_test_cid("8"),
    principal: binding.principal,
    request_body_cid: "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    request_cid: "sha256:248299c85113e5888dc5636575b914f3a4e3dd836a8a74196d13a2116ac58d22",
    request_method: "GET",
    request_path: "/services/data/v66.0/sobjects/Account/001000000000001",
    resource_origin: binding.resource_origin,
    run_invocation_cid: binding.run_invocation_cid,
    submission_scope_cid: binding.client_request_scope_cid,
    unit_definition_cid: local_target_test_cid("9"),
  }
  (request, scope)
}

///|
test "Local preparation target scope binds the checked GET original and rejects foreign authority or mutation" {
  let (request, scope) = local_target_test_materials()
  assert_true(
    local_target_read_matches_preparation_scope(
      request, scope, "00D000000000001EAA",
    ),
  )
  assert_false(
    local_target_read_matches_preparation_scope(
      request, scope, "00D000000000002EAA",
    ),
  )
  for
    foreign in [
      { ..scope, account_configuration_cid: local_target_test_cid("a"), },
      { ..scope, account_id: "other", },
      { ..scope, authority_scope_cid: local_target_test_cid("a"), },
      { ..scope, submission_scope_cid: local_target_test_cid("a"), },
      { ..scope, connector_registration: "other", },
      { ..scope, connector_revision: "other", },
      { ..scope, host_adoption_cid: local_target_test_cid("a"), },
      { ..scope, principal: "other", },
      { ..scope, resource_origin: "https://other.invalid", },
      { ..scope, run_invocation_cid: local_target_test_cid("a"), },
      { ..scope, operation: "salesforce:record:update", },
      { ..scope, request_method: "PATCH", },
      { ..scope, request_path: scope.request_path + "-foreign", },
      { ..scope, request_cid: local_target_test_cid("a"), },
      { ..scope, request_body_cid: local_target_test_cid("a"), },
      { ..scope, operation_occurrence_cid: local_target_test_cid("a"), },
      { ..scope, unit_definition_cid: local_target_test_cid("a"), },
    ] {
    assert_false(
      local_target_read_matches_preparation_scope(
        request, foreign, "00D000000000001EAA",
      ),
    )
  }
  let fields = @credential.local_preparation_fence_fields(
    scope.preparation_fence,
  )
  for
    foreign in [
      { ..fields, client_request_intent_cid: local_target_test_cid("a"), },
      { ..fields, client_request_scope_cid: local_target_test_cid("a"), },
      { ..fields, run_invocation_cid: local_target_test_cid("a"), },
    ] {
    assert_false(
      local_target_read_matches_preparation_scope(
        request,
        {
          ..scope,
          preparation_fence: @credential.prepare_local_preparation_fence_identity(
            foreign,
          ).unwrap(),
        },
        "00D000000000001EAA",
      ),
    )
  }
}

///|
test "Local preparation target projects original Unicode and rejects missing or NULL required field" {
  let (request, _) = local_target_test_materials()
  let candidate = @catalog.local_target_read_request_candidate(request)
  let limits : @catalog.TargetObservationLimits = {
    max_bytes: 4096,
    max_nodes: 100,
    max_depth: 10,
    max_identity_bytes: 4096,
  }
  let original = native_salesforce_target_preview(
    candidate,
    {
      use_cid: local_target_test_cid("7"),
      status: 200,
      body: @utf8.encode(
        "{\"Id\":\"001000000000001AAA\",\"Name\":\"e\u0301\\r\\n\"}",
      ),
    },
    limits,
  ).unwrap()
  assert_eq(original.0, local_target_test_cid("7"))
  assert_eq(
    @catalog.target_observation_before_value_wire(original.1),
    "{\"Name\":\"e\u0301\\r\\n\"}",
  )
  assert_eq(
    @catalog.target_preview_row_after_wire(original.2),
    "{\"Name\":\"new\"}",
  )
  for
    body in [
      b"{\"Id\":\"001000000000001AAA\"}", b"{\"Id\":\"001000000000001AAA\",\"Name\":null}",
    ] {
    assert_true(
      native_salesforce_target_preview(
        candidate,
        { use_cid: local_target_test_cid("7"), status: 200, body, },
        limits,
      )
      is Err(Observation(@catalog.InvalidRecord)),
    )
  }
  assert_false(
    native_salesforce_target_limits_valid({ ..limits, max_bytes: 1000001, }),
  )
  assert_false(
    native_salesforce_target_limits_valid({ ..limits, max_depth: 65, }),
  )
}

///|
test "Local preparation target retains received originals even when semantic projection refuses" {
  let (request, _) = local_target_test_materials()
  let bytes = b"{\"Id\":\"001000000000001AAA\",\"Name\":null}"
  let original = native_local_target_observation_from_response(
    request,
    { use_cid: local_target_test_cid("7"), status: 200, body: bytes, },
    {
      max_bytes: 4096,
      max_nodes: 100,
      max_depth: 10,
      max_identity_bytes: 4096,
    },
  )
  assert_true(original.projection is Err(Observation(@catalog.InvalidRecord)))
  assert_eq(original.response.body, bytes)
  assert_eq(
    original.response_sha256,
    "d391a384f1ebfbbd36038e17d26e12456ff8ec1381b4b6b6f72d0e46bb70401b",
  )
  assert_eq(original.response.status, 200)
  assert_eq(original.response.use_cid, local_target_test_cid("7"))
  assert_eq(
    @catalog.local_target_read_request_cid(original.request),
    "sha256:248299c85113e5888dc5636575b914f3a4e3dd836a8a74196d13a2116ac58d22",
  )
  // This HTTP status is not semantic success, a durable capture receipt, or
  // permission to re-enter the original GET after acknowledgement loss.
}
