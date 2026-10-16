///|
fn collection_limits() -> ObjectCollectionLimits {
  { max_bytes: 4096, max_nodes: 100, max_depth: 8, }
}

///|
fn collection_binding(
  prefix? : String = "in/é%2F/",
  target? : String = "connector://exports/objects",
  installation? : String = "sha256:" + "b".repeat(64),
  catalog? : String = "sha256:" + "a".repeat(64),
  kind? : String = "file_collection",
  limits? : ObjectCollectionLimits = collection_limits(),
) -> Result[ObjectCollectionBinding, ObjectCollectionIssue] {
  prepare_object_collection_binding(
    "project", "bucket", prefix, target, kind, catalog, installation, limits,
  )
}

///|
test "GCS collection uses the existing complete Mapping identity and exact provider scope" {
  let binding = collection_binding().unwrap()
  let identity =
    #|{"boundary_topology":"connector_connection","collection_identity":{"bucket":"bucket","prefix":"in/é%2F/","project":"project"},"provider_namespace":"gcs","resource_kind":"file_collection","target_ref":"connector://exports/objects","version":"actql.collection_resource_identity/0.1"}
  assert_eq(object_collection_identity_json(binding), identity)
  // Independent literal vectors are filled from the authored bytes, never
  // computed using the product's identity/projection API.
  assert_eq(
    object_collection_identity_cid(binding),
    "sha256:d0f85fdad35ae5bd456d1c37343895dd1ba0c1de01887c5de5bda439e9b13e62",
  )
  assert_eq(
    object_collection_resource_json(binding),
    (
      #|{"$actql_ref":"resource","authority_scope_cid":"sha256:43d874820e0b878c597abc58ac3795db2e39e66e54fe479ba8ee803532515bd2","boundary_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","identity_cid":"sha256:d0f85fdad35ae5bd456d1c37343895dd1ba0c1de01887c5de5bda439e9b13e62","provider_identity_cid":"sha256:bdef7723e3c39d7e7d6feb66d1bd8ab7a2b2f1c000d631f4370297e6832e110a","provider_namespace":"gcs","resource_kind":"file_collection","version":"actql-resource-ref/0.1"}
    ),
  )
}

///|
test "GCS collection opaque text and explicit target are not normalized or inferred" {
  let original = collection_binding().unwrap()
  for
    changed in [
      collection_binding(prefix="in/é%2F/"),
      collection_binding(prefix="in/é//"),
      collection_binding(target="connector://reader_alias/objects"),
      collection_binding(kind="file"),
    ] {
    assert_true(
      object_collection_identity_cid(original) !=
      object_collection_identity_cid(changed.unwrap()),
    )
  }
  let empty = collection_binding(prefix="").unwrap()
  assert_true(
    object_collection_identity_json(empty).contains("\"prefix\":\"\""),
  )
}

///|
test "GCS collection DATA cannot transfer original installation custody through equality" {
  let original = collection_binding().unwrap()
  assert_true(
    check_object_collection_binding(
      original,
      original,
      "sha256:" + "b".repeat(64),
      "connector://exports/objects",
    )
    is Ok(_),
  )
  let copy = collection_binding().unwrap()
  assert_eq(
    object_collection_resource_json(copy),
    object_collection_resource_json(original),
  )
  assert_true(
    check_object_collection_binding(
      original,
      copy,
      "sha256:" + "b".repeat(64),
      "connector://exports/objects",
    )
    is Err(ForeignBinding),
  )
  assert_true(
    check_object_collection_binding(
      original,
      original,
      "sha256:" + "c".repeat(64),
      "connector://exports/objects",
    )
    is Err(ForeignBinding),
  )
  assert_true(
    check_object_collection_binding(
      original,
      original,
      "sha256:" + "b".repeat(64),
      "connector://reader_alias/objects",
    )
    is Err(ForeignBinding),
  )
  let other_installation = collection_binding(
    installation="sha256:" + "c".repeat(64),
  ).unwrap()
  assert_eq(
    object_collection_identity_json(original),
    object_collection_identity_json(other_installation),
  )
  let other_catalog = collection_binding(catalog="sha256:" + "c".repeat(64)).unwrap()
  assert_eq(
    object_collection_identity_json(original),
    object_collection_identity_json(other_catalog),
  )
  assert_true(
    object_collection_resource_json(original) !=
    object_collection_resource_json(other_catalog),
  )
}

///|
test "GCS collection construction enforces explicit finite DATA bounds" {
  let original = collection_binding().unwrap()
  let needed = @utf8.encode(object_collection_resource_json(original)).length()
  assert_true(
    collection_binding(limits={ ..collection_limits(), max_bytes: needed, })
    is Ok(_),
  )
  assert_true(
    collection_binding(limits={ ..collection_limits(), max_bytes: needed - 1, })
    is Err(CapacityExceeded),
  )
  assert_true(
    collection_binding(limits={ ..collection_limits(), max_nodes: 1, })
    is Err(CapacityExceeded),
  )
  assert_true(
    collection_binding(limits={ ..collection_limits(), max_depth: 0, })
    is Err(InvalidBinding),
  )
  assert_true(
    collection_binding(installation="not-a-cid") is Err(InvalidBinding),
  )
  assert_true(
    collection_binding(target="exports.objects") is Err(InvalidBinding),
  )
  assert_true(collection_binding(target="connector://") is Err(InvalidBinding))
  assert_true(collection_binding(kind="") is Err(InvalidBinding))
}
