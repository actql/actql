///|
fn effect_catalog_test_binding() -> @catalog.CatalogObservationBinding {
  {
    namespace_id: "original-workspace",
    principal: "provider-not-reviewer",
    environment: "preview",
    connection_revision: "connection-original",
    org_id: "00D000000000001EAA",
    site_key: "original-site",
    site_generation: 4,
    connector_registration: "salesforce",
    connector_revision: "salesforce/0.1",
    resource_origin: "https://provider.example",
    run_invocation_cid: "sha256:" + "a".repeat(64),
    dispatch_request_cid: "sha256:" + "b".repeat(64),
    sync_occurrence: "original-read",
  }
}

///|
fn effect_catalog_test_limits() -> @catalog.DescribeLimits {
  {
    max_bytes: 4096,
    max_nodes: 100,
    max_depth: 10,
    max_fields: 2,
    max_name_units: 100,
  }
}

///|
fn effect_catalog_test_response() -> NativeEffectCatalogResponse {
  let body = @utf8.encode(
    "{\"name\":\"Account\",\"queryable\":true,\"createable\":true,\"label\":\"e\u0301\\r\\n\",\"fields\":[{\"name\":\"Name\",\"type\":\"string\",\"nillable\":true,\"defaultedOnCreate\":false,\"createable\":true,\"updateable\":true}]}\r\n",
  )
  let use_cid = "sha256:" + "e".repeat(64)
  let sync = @catalog.begin_named_catalog_sync(["Account"]).unwrap()
  @catalog.catalog_sync_describe(
    sync,
    "Account",
    body,
    effect_catalog_test_limits(),
  ).unwrap()
  @catalog.finish_catalog_sync(sync).unwrap()
  let catalog = @catalog.prepare_catalog_observation(
    sync,
    effect_catalog_test_binding(),
    "",
    [Some(use_cid)],
    [Some(@catalog.catalog_response_sha256(body))],
    16384,
  ).unwrap()
  effect_catalog_response(
    @catalog.catalog_observation_json(catalog),
    effect_catalog_test_binding(),
    "Account",
    use_cid,
    200,
    body,
    effect_catalog_test_limits(),
    16384,
  ).unwrap()
}

///|
test "original Catalog record restores exact describe bytes and original use without any read" {
  let evidence = effect_catalog_test_response()
  let binding = effect_catalog_test_binding()
  let authority = "sha256:" + "c".repeat(64)
  let wire = effect_catalog_record(
    evidence, binding, "Account", authority, 16384,
  ).unwrap()
  let restored = restore_effect_catalog_record(
    wire,
    binding,
    "Account",
    "sha256:" + "e".repeat(64),
    authority,
    effect_catalog_test_limits(),
    16384,
  ).unwrap()
  assert_eq(restored.body, evidence.body)
  assert_eq(restored.use_cid, "sha256:" + "e".repeat(64))
  assert_eq(restored.status, 200)
  assert_eq(
    @catalog.catalog_observation_json(restored.catalog),
    @catalog.catalog_observation_json(evidence.catalog),
  )
  assert_true(@utf8.decode_lossy(restored.body).has_suffix("\r\n"))
  assert_true(@utf8.decode_lossy(restored.body).contains("e\u0301"))
  let owned = effect_catalog_response(
    @catalog.catalog_observation_json(evidence.catalog),
    binding,
    "Account",
    evidence.use_cid,
    200,
    evidence.body,
    effect_catalog_test_limits(),
    16384,
  ).unwrap()
  assert_eq(owned.body, evidence.body)
}

///|
test "original Catalog record rejects foreign Host and Provider scope" {
  let binding = effect_catalog_test_binding()
  let authority = "sha256:" + "c".repeat(64)
  let wire = effect_catalog_record(
    effect_catalog_test_response(),
    binding,
    "Account",
    authority,
    16384,
  ).unwrap()
  for
    foreign in [
      { ..binding, namespace_id: "foreign", },
      { ..binding, principal: "reviewer", },
      { ..binding, environment: "foreign", },
      { ..binding, connection_revision: "foreign", },
      { ..binding, org_id: "00D000000000002EAA", },
      { ..binding, site_key: "foreign", },
      { ..binding, site_generation: 5, },
      { ..binding, connector_registration: "foreign", },
      { ..binding, connector_revision: "foreign", },
      { ..binding, resource_origin: "https://foreign.example", },
      { ..binding, run_invocation_cid: "sha256:" + "d".repeat(64), },
      { ..binding, dispatch_request_cid: "sha256:" + "d".repeat(64), },
      { ..binding, sync_occurrence: "foreign", },
    ] {
    assert_true(
      restore_effect_catalog_record(
        wire,
        foreign,
        "Account",
        "sha256:" + "e".repeat(64),
        authority,
        effect_catalog_test_limits(),
        16384,
      )
      is Err(StateCollision),
    )
  }
  for
    (resource, owner) in [("Contact", authority), ("Account", "foreign-store")] {
    assert_true(
      restore_effect_catalog_record(
        wire,
        binding,
        resource,
        "sha256:" + "e".repeat(64),
        owner,
        effect_catalog_test_limits(),
        16384,
      )
      is Err(StateCollision),
    )
  }
}

///|
test "original Catalog record rejects changed response use hash body shape and bounds" {
  let binding = effect_catalog_test_binding()
  let evidence = effect_catalog_test_response()
  let authority = "sha256:" + "c".repeat(64)
  let wire = effect_catalog_record(
    evidence, binding, "Account", authority, 16384,
  ).unwrap()
  for
    bad in [
      wire.replace_all(old=evidence.use_cid, new="sha256:" + "f".repeat(64)),
      wire.replace_all(old="\"200\"", new="\"201\""),
      wire.replace_all(
        old=@catalog.catalog_response_sha256(evidence.body),
        new="0".repeat(64),
      ),
      wire.replace_all(
        old=@base64.encode(evidence.body),
        new=@base64.encode(@utf8.encode("{}")),
      ),
      wire + " ",
      wire.replace_all(old="]", new=",\"foreign\"]"),
    ] {
    assert_true(
      restore_effect_catalog_record(
        bad,
        binding,
        "Account",
        "sha256:" + "e".repeat(64),
        authority,
        effect_catalog_test_limits(),
        16384,
      )
      is Err(StateCollision),
    )
  }
  assert_true(
    restore_effect_catalog_record(
      wire,
      binding,
      "Account",
      "sha256:" + "e".repeat(64),
      authority,
      effect_catalog_test_limits(),
      128,
    )
    is Err(StateCollision),
  )
  assert_true(
    effect_catalog_response(
      @catalog.catalog_observation_json(evidence.catalog),
      binding,
      "Account",
      evidence.use_cid,
      503,
      evidence.body,
      effect_catalog_test_limits(),
      16384,
    )
    is Err(StateCollision),
  )
}

///|
test "original Catalog holding is stable across response changes and separates scope" {
  let binding = effect_catalog_test_binding()
  let authority = "sha256:" + "c".repeat(64)
  let first = effect_catalog_holding(binding, "Account", authority, 16384).unwrap()
  // Independent Node SHA-256 of the documented ordered private preimage.
  assert_eq(
    first, "sha256:46173aa832b64cce575a05506dfc7eabafb5efdf433ee61b7e837d03e10334f0",
  )
  assert_eq(
    first,
    effect_catalog_holding(binding, "Account", authority, 16384).unwrap(),
  )
  assert_false(
    first ==
    effect_catalog_holding(
      { ..binding, site_generation: 5, },
      "Account",
      authority,
      16384,
    ).unwrap(),
  )
  assert_false(
    first ==
    effect_catalog_holding(binding, "Contact", authority, 16384).unwrap(),
  )
}

///|
test "retired original Catalog restores only exact bounded reservation metadata" {
  let holding = "sha256:" + "a".repeat(64)
  let terminal = effect_catalog_terminal(holding, 512L)
  assert_eq(effect_catalog_terminal_bytes(terminal, holding, 1024), Some(512L))
  for
    bad in [
      effect_catalog_terminal(holding, 0L),
      effect_catalog_terminal(holding, -1L),
      effect_catalog_terminal(holding, 1025L),
      terminal.replace_all(old="512", new="0512"),
      terminal + " ",
      terminal.replace_all(old=holding, new="sha256:" + "b".repeat(64)),
    ] {
    assert_eq(effect_catalog_terminal_bytes(bad, holding, 1024), None)
  }
}
