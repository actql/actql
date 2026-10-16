///|
fn collection_pair(
  original : @environment.WireEnvironment,
) -> @environment.StoreCommandBinding {
  let mapping = @environment.mapping_shape_at(
    @environment.check_mapping_contract_shapes(original, caps(), 100000).unwrap(),
    0,
  ).unwrap()
  @environment.bind_store_command(mapping, catalogs(original), 100000).unwrap()
}

///|
fn reference_limits() -> @original.CollectionReferenceLimits {
  { max_bytes: 32768, max_nodes: 4096, max_depth: 32, max_work: 100000, }
}

///|
test "GCS original collection pair issues the existing checked ResourceRef and current closure" {
  let (environment, _, collection, declared) = upload_environment_details()
  let pair = collection_pair(environment)
  let wire = @gcs.object_collection_resource_json(collection)
  let current = Ref(true)
  let validations = Ref(0)
  // Explicit contract-control Host issuer, not installed Site admission.
  let issuer = @admitted.bind_reference_issuer(
    (contract, candidate) => {
      validations.val += 1
      @value.nonnull_resource_ref_kind(contract) == Some("file_collection") &&
      candidate == wire
    },
    candidate => current.val && candidate == wire,
  )
  let checked = @original.issue_collection_reference(
    collection,
    pair,
    declared,
    "exports",
    issuer,
    reference_limits(),
  ).unwrap()
  assert_eq(validations.val, 1)
  assert_eq(
    @value.nonnull_resource_ref_kind(checked.contract),
    Some("file_collection"),
  )
  guard checked.value is @admitted.Reference(reference) else {
    abort("not an original ResourceRef")
  }
  assert_eq(@admitted.reference_wire(reference), wire)
  assert_eq(
    @admitted.reference_identity_cid(reference),
    @gcs.object_collection_identity_cid(collection),
  )
  assert_true(@admitted.reference_available(reference))
  current.val = false
  assert_false(@admitted.reference_available(reference))
  assert_true(
    @original.issue_collection_reference(
      collection,
      pair,
      declared,
      "exports",
      issuer,
      reference_limits(),
    )
    is Err(@original.ReferenceRejected(@admitted.Unauthorized)),
  )
}

///|
test "GCS original collection rejects a different scope or complete Mapping before issuer use" {
  let (environment, wire, collection, declared) = upload_environment_details()
  let calls = Ref(0)
  let issuer = @admitted.bind_reference_issuer(
    (_, _) => {
      calls.val += 1
      true
    },
    _ => true,
  )
  let catalog_cid = @environment.catalog_identity(
      @environment.command_target_catalog(
        @environment.store_command_target(collection_pair(environment)),
      ),
    ).2
  let foreign = @gcs.prepare_object_collection_binding(
    "project",
    "bucket",
    "other/",
    "connector://exports/objects",
    "file_collection",
    catalog_cid,
    "sha256:" + "b".repeat(64),
    { max_bytes: 32768, max_nodes: 4096, max_depth: 32, },
  ).unwrap()
  assert_true(
    @original.issue_collection_reference(
      foreign,
      collection_pair(environment),
      declared,
      "exports",
      issuer,
      reference_limits(),
    )
    is Err(@original.ForeignSelection),
  )
  guard @json.parse(wire) is Object(body) &&
    body["mapping_contracts"] is Array(mappings) &&
    mappings[0] is Object(mapping) else {
    abort("fixture")
  }
  mapping["resource_identity_cid"] = ("sha256:" + "f".repeat(64)).to_json()
  ignore(mapping.remove("mapping_contract_cid"))
  mapping["mapping_contract_cid"] = cid(Json::object(mapping)).to_json()
  ignore(body.remove("evidence_bundle_cid"))
  let evidence = cid(Json::object(body))
  body["evidence_bundle_cid"] = evidence.to_json()
  let altered = @environment.read(
    @utf8.encode(canonical(Json::object(body))),
    evidence,
    caps(),
  ).unwrap()
  assert_true(
    @original.issue_collection_reference(
      collection,
      collection_pair(altered),
      declared,
      "exports",
      issuer,
      reference_limits(),
    )
    is Err(@original.ForeignSelection),
  )
  assert_eq(calls.val, 0)
}

///|
test "GCS reference comparison refuses exhausted work or byte capacity without issuer side effects" {
  let (environment, _, collection, declared) = upload_environment_details()
  let calls = Ref(0)
  let issuer = @admitted.bind_reference_issuer(
    (_, _) => {
      calls.val += 1
      true
    },
    _ => true,
  )
  for
    limits in [
      { ..reference_limits(), max_work: 1, },
      { ..reference_limits(), max_bytes: 100, },
    ] {
    assert_true(
      @original.issue_collection_reference(
        collection,
        collection_pair(environment),
        declared,
        "exports",
        issuer,
        limits,
      )
      is Err(@original.CapacityExceeded),
    )
  }
  assert_eq(calls.val, 0)
}

///|
test "GCS equal collection bytes never replace the original issuer authorization" {
  let (environment, _, collection, declared) = upload_environment_details()
  let pair = collection_pair(environment)
  let wire = @gcs.object_collection_resource_json(collection)
  let denied = @admitted.bind_reference_issuer(
    (_, candidate) => candidate == wire,
    _ => false,
  )
  assert_true(
    @original.issue_collection_reference(
      collection,
      pair,
      declared,
      "exports",
      denied,
      reference_limits(),
    )
    is Err(@original.ReferenceRejected(@admitted.Unauthorized)),
  )
  let foreign = @admitted.bind_reference_issuer((_, _) => false, _ => true)
  assert_true(
    @original.issue_collection_reference(
      collection,
      pair,
      declared,
      "exports",
      foreign,
      reference_limits(),
    )
    is Err(@original.ReferenceRejected(@admitted.IssuerRejected)),
  )
}
