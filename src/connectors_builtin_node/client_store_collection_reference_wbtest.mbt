///|
fn store_collection_reference_pair() -> @check_environment.StoreCommandBinding {
  let environment = @program_check.checking_environment_wire(
    store_public_bridge_fixture("collection"),
  )
  let limits : @check_environment.Limits = {
    max_bytes: 100000,
    max_nodes: 10000,
    max_depth: 100,
    max_members: 1000,
  }
  let mappings = @check_environment.check_mapping_contract_shapes(
    environment, limits, 100000,
  ).unwrap()
  let registry = @check_environment.check_contract_registry(environment, limits).unwrap()
  let catalogs = @check_environment.check_catalog_contents(registry, limits).unwrap()
  @check_environment.bind_store_command(
    @check_environment.mapping_shape_at(mappings, 0).unwrap(),
    catalogs,
    100000,
  ).unwrap()
}

///|
fn store_collection_reference_wire() -> String {
  (
    #|{"$actql_ref":"resource","authority_scope_cid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","boundary_cid":"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","identity_cid":"sha256:e3d4f3b2c3b392c4c889b78ea6b4794bc6a715d39a740275ab3c936d20ec6759","provider_identity_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","provider_namespace":"fixture","resource_kind":"file_collection","version":"actql-resource-ref/0.1"}
  )
}

///|
test "STORE collection Reference retains original Mapping identity and live issuer" {
  let pair = store_collection_reference_pair()
  let selection = client_program_effect_store_command_selection(pair).unwrap()
  assert_eq(selection[0], "connector://storage/archive")
  assert_eq(selection[1], "mapping:fixture.archive.v1")
  assert_eq(selection[3], "command:fixture.upload.v1")
  assert_eq(selection[6], "file_collection")
  assert_eq(
    selection[7],
    "sha256:e3d4f3b2c3b392c4c889b78ea6b4794bc6a715d39a740275ab3c936d20ec6759",
  )
  let live = Ref(true)
  let wire = store_collection_reference_wire()
  let issuer = @admitted.bind_reference_issuer(
    (_, candidate) => candidate == wire,
    _ => live.val,
  )
  let checked = client_program_issue_store_collection_reference(
    pair, issuer, wire, 1024, 64, 8,
  ).unwrap()
  guard checked.value is @admitted.Reference(original) else {
    abort("the same original issuer owns the Reference")
  }
  assert_true(@admitted.reference_available(original))
  live.val = false
  assert_true(!@admitted.reference_available(original))
  assert_true(
    client_program_issue_store_collection_reference(
      pair, issuer, wire, 1024, 64, 8,
    )
    is Err(Unauthorized),
  )
}

///|
test "STORE collection Reference rejects substituted identity, unavailable issuer and finite limits" {
  let pair = store_collection_reference_pair()
  let wire = store_collection_reference_wire()
  let issuer = @admitted.bind_reference_issuer((_, _) => true, _ => true)
  let wrong = wire.replace(
    old="e3d4f3b2c3b392c4c889b78ea6b4794bc6a715d39a740275ab3c936d20ec6759",
    new="dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
  )
  assert_true(
    client_program_issue_store_collection_reference(
      pair, issuer, wrong, 1024, 64, 8,
    )
    is Err(InvalidIdentity),
  )
  assert_true(
    client_program_issue_store_collection_reference(
      pair,
      @admitted.bind_reference_issuer((_, _) => false, _ => true),
      wire,
      1024,
      64,
      8,
    )
    is Err(IssuerRejected),
  )
  for (bytes, nodes, depth) in [(0, 64, 8), (1024, 0, 8), (1024, 64, 0)] {
    assert_true(
      client_program_issue_store_collection_reference(
        pair, issuer, wire, bytes, nodes, depth,
      )
      is Err(InvalidLimits),
    )
  }
}
