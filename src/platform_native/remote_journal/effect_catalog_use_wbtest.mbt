///|
fn catalog_use_fixture(
  request : @remote.DispatchRequest,
  use_id : String,
) -> (@credential.RemoteCredentialGrant, @credential.RemoteCredentialUse) raise {
  let execution = @remote.dispatch_request_execution_scope(request)
  let route = @remote.dispatch_request_journal_key(request)
  let generation : Int = @string.from_str(execution[1]) catch {
    _ => fail("fixture generation required")
  }
  let attempt : Int = @string.from_str(route[6]) catch {
    _ => fail("fixture attempt required")
  }
  let invocation = "sha256:" + "a".repeat(64)
  let grant = @credential.prepare_grant(
    "catalog-issuer",
    "original-principal",
    "original-workspace",
    "test",
    execution[0],
    generation,
    execution[2],
    "crm/main",
    "original-revision",
    "https://catalog.invalid",
    "salesforce:catalog:describe",
    invocation,
    attempt,
    @remote.dispatch_request_identity(request),
    100000L,
    1,
  ).unwrap()
  let credential_use = @credential.prepare_credential_use(
    grant,
    use_id,
    1L,
    0,
    false,
    "original-principal",
    "original-workspace",
    "test",
    execution[0],
    generation,
    execution[2],
    "crm/main",
    "original-revision",
    "https://catalog.invalid",
    "salesforce:catalog:describe",
    invocation,
    attempt,
    @remote.dispatch_request_identity(request),
  ).unwrap()
  (grant, credential_use)
}

///|
fn catalog_binding_request(
  dispatch_id : String,
  attempt : Int,
  generation : Int,
) -> @remote.DispatchRequest {
  let cid = (fill : String) => "sha256:" + fill.repeat(64)
  @remote.prepare_dispatch_request(
    "original-coordinator",
    cid("0"),
    "consumer",
    attempt,
    dispatch_id,
    "original-site",
    generation,
    cid("a"),
    "local",
    "local/1",
    "strategy/1",
    cid("1"),
    cid("2"),
    cid("3"),
    cid("b"),
    cid("4"),
  ).unwrap()
}

///|
test "catalog use custody binding preserves exact dispatch attempt and Site generation" {
  let request = catalog_binding_request("original", 7, 4)
  let (grant, original) = catalog_use_fixture(request, "original-use")
  assert_true(catalog_use_matches_dispatch(request, grant, original))
  for
    foreign in [
      catalog_binding_request("foreign", 7, 4),
      catalog_binding_request("original", 8, 4),
      catalog_binding_request("original", 7, 5),
    ] {
    assert_false(catalog_use_matches_dispatch(foreign, grant, original))
    let (foreign_grant, foreign_use) = catalog_use_fixture(
      foreign, "original-use",
    )
    assert_false(
      catalog_use_matches_dispatch(request, foreign_grant, foreign_use),
    )
  }
}

///|
test "catalog use custody binding refuses another grant even when its use ID matches" {
  let request = catalog_binding_request("original", 7, 4)
  let foreign = catalog_binding_request("foreign", 7, 4)
  let (grant, original) = catalog_use_fixture(request, "same-use-id")
  let (foreign_grant, foreign_use) = catalog_use_fixture(foreign, "same-use-id")
  assert_false(catalog_use_matches_dispatch(request, grant, foreign_use))
  assert_false(catalog_use_matches_dispatch(request, foreign_grant, original))
}
