///|
// Identity-only Native definitions, not an operational Work or Host permit.
test "Native Local preparation Catalog matching requires all original request and Run projections" {
  let cid = (value : String) => "sha256:" + value.repeat(64)
  let identity = @credential.prepare_local_preparation_fence_identity({
    client_request_intent_cid: cid("1"),
    client_request_scope_cid: cid("2"),
    operation_occurrence_cid: cid("3"),
    run_invocation_cid: cid("4"),
    unit_definition_cid: cid("5"),
  }).unwrap()
  let binding : @catalog.LocalCatalogObservationBinding = {
    account_configuration_cid: cid("6"),
    account_id: "account-a",
    authority_scope_cid: cid("7"),
    client_request_intent_cid: cid("1"),
    client_request_scope_cid: cid("2"),
    connection_revision: "connection-a",
    connector_registration: "salesforce",
    connector_revision: "salesforce/0.1",
    environment: "local",
    host_adoption_cid: cid("8"),
    namespace_id: "namespace-a",
    org_id: "00D000000000001EAA",
    principal: "operator",
    resource_origin: "https://example.invalid",
    run_invocation_cid: cid("4"),
    sync_occurrence: "describe-original",
  }
  assert_true(local_preparation_catalog_matches_original(identity, binding))
  for
    foreign in [
      { ..binding, client_request_intent_cid: cid("9"), },
      { ..binding, client_request_scope_cid: cid("9"), },
      { ..binding, run_invocation_cid: cid("9"), },
    ] {
    assert_false(local_preparation_catalog_matches_original(identity, foreign))
  }
  // Matching these three immutable identities says nothing about actual Host
  // adoption, current Account/read/issuer authority or protected entry.
}
