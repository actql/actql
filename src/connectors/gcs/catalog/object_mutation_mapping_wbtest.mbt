///|
fn mutation_mapping_fixture(
  kind : ObjectMutationKind,
  permissions? : Array[String] = [
    "storage.objects.get", "storage.objects.update", "storage.objects.delete",
  ],
) -> (ObjectMutationBinding, String) raise {
  // Structural Catalog DATA only: full SourceView role admission remains the
  // Common consumer's responsibility, not an assertion of installed custody.
  let limits = upload_limits()
  let cid = "sha256:" + "1".repeat(64)
  let view : Json = {
    "contract_cid": cid.to_json(),
    "connector_id": "exports",
    "connector_version": "gcs/0.1",
    "resource_kind": "file",
    "view_id": "records",
  }
  let catalog = upload_declaration_seal(
    {
      "schema": "actql.connector_catalog/0.1",
      "connector_id": "exports",
      "connector_version": "gcs/0.1",
      "commands": [],
      "contracts": [],
      "source_views": [view],
    },
    "catalog_cid",
    limits,
  ).unwrap()
  guard catalog is Object(fields) &&
    fields["catalog_cid"] is String(catalog_cid) &&
    @json.parse(upload_empty_catalog_fixture()) is Object(declared) else {
    abort("fixture DATA")
  }
  declared["catalog"] = upload_declaration_json(catalog, limits)
    .unwrap()
    .to_json()
  declared["catalog_cid"] = catalog_cid.to_json()
  declared["views"] = Json::array([
    {
      "source_ref": "connector://exports/objects#records",
      "view_cid": cid.to_json(),
    },
  ])
  let binding = prepare_object_mutation_binding(
    kind,
    "bucket",
    "in/",
    catalog_cid,
    "sha256:" + "2".repeat(64),
    "sha256:" + "3".repeat(64),
    permissions,
    mutation_limits(),
  ).unwrap()
  (binding, Json::object(declared).stringify())
}

///|
test "GCS mutation Mapping preserves nullable fields and independent identity preimages" {
  let (binding, original) = mutation_mapping_fixture(PatchMetadata)
  let wire = object_mutation_mapping_json(
    binding,
    original,
    "exports",
    upload_limits(),
  ).unwrap()
  guard @json.parse(wire) is Object(mapping) &&
    mapping["permission_rules"] is Array(rules) else {
    abort("Mapping DATA")
  }
  assert_eq(
    mapping["target_schema_identity"],
    "sha256:db60ce045432c3ae0123cb24519334355b498f29e13a72a3c9a40046f7df808a".to_json(),
  )
  assert_eq(
    mapping["resource_identity_cid"],
    "sha256:4295fd4519054f4972c3d274ad328c567cb768688d0cb969f4b3d54a910c3d7d".to_json(),
  )
  let expected =
    #|{"additional_properties":false,"fields":{"content_type":{"nullable":true,"type":"string"},"metadata":{"nullable":true,"type":"json"},"name":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"}
  assert_eq(mapping["target_schema"], @json.parse(expected))
  assert_eq(mapping["primary_identity"], "name".to_json())
  assert_eq(mapping["writable_fields"], ["content_type", "metadata"])
  assert_eq(mapping["minimum_approval"], "required".to_json())
  assert_eq(rules.length(), 3)
  for rule in rules {
    guard rule is Object(fields) else { abort("rule") }
    assert_eq(fields["effect_kind"], "update".to_json())
    assert_eq(fields["selector_class"], "id".to_json())
  }
  assert_false(mapping.contains("store_command"))
  assert_eq(
    object_mutation_mapping_json(binding, original, "exports", upload_limits()).unwrap(),
    wire,
  )
}

///|
test "GCS DELETE Mapping derives its own purpose and never accepts UPDATE permission alone" {
  let (binding, original) = mutation_mapping_fixture(DeleteObject)
  guard @json.parse(
      object_mutation_mapping_json(
        binding,
        original,
        "exports",
        upload_limits(),
      ).unwrap(),
    )
    is Object(mapping) else {
    abort("DELETE Mapping")
  }
  assert_eq(mapping["writable_fields"], [])
  assert_eq(mapping["permission_rules"], [
    {
      "effect_kind": "delete",
      "selector_class": "id",
      "write_fields": [],
      "permissions": Json::array(
        binding.permissions.map(value => value.to_json()),
      ),
    },
  ])
  let (foreign, wire) = mutation_mapping_fixture(DeleteObject, permissions=[
    "storage.objects.get", "storage.objects.update",
  ])
  assert_true(
    object_mutation_mapping_json(foreign, wire, "exports", upload_limits())
    is Err(InvalidBinding),
  )
  let (foreign, wire) = mutation_mapping_fixture(PatchMetadata, permissions=[
    "storage.objects.get", "storage.objects.delete",
  ])
  assert_true(
    object_mutation_mapping_json(foreign, wire, "exports", upload_limits())
    is Err(InvalidBinding),
  )
}

///|
test "GCS mutation Mapping refuses detached Catalog manifest registry and view substitution" {
  let (binding, original) = mutation_mapping_fixture(PatchMetadata)
  assert_true(
    object_mutation_mapping_json(binding, original, "other", upload_limits())
    is Err(_),
  )
  for key in ["catalog_cid", "manifest_entry_cid"] {
    guard @json.parse(original) is Object(fields) else { abort("fixture") }
    fields[key] = ("sha256:" + "f".repeat(64)).to_json()
    assert_true(
      object_mutation_mapping_json(
        binding,
        Json::object(fields).stringify(),
        "exports",
        upload_limits(),
      )
      is Err(_),
    )
  }
  for key in ["views", "contracts"] {
    guard @json.parse(original) is Object(fields) else { abort("fixture") }
    fields[key] = if key == "views" {
      Json::array([])
    } else {
      Json::array(["{}".to_json()])
    }
    assert_true(
      object_mutation_mapping_json(
        binding,
        Json::object(fields).stringify(),
        "exports",
        upload_limits(),
      )
      is Err(_),
    )
  }
  for wire in ["null", "{}", "{\"catalog\":{},\"catalog\":{}}"] {
    assert_true(
      object_mutation_mapping_json(binding, wire, "exports", upload_limits())
      is Err(InvalidDeclaration),
    )
  }
}

///|
test "GCS mutation Mapping bounds original parsing and complete output" {
  let (binding, original) = mutation_mapping_fixture(PatchMetadata)
  let wire = object_mutation_mapping_json(
    binding,
    original,
    "exports",
    upload_limits(),
  ).unwrap()
  let bytes = @utf8.encode(wire).length()
  assert_true(@utf8.encode(original).length() < bytes)
  assert_eq(
    object_mutation_mapping_json(binding, original, "exports", {
      ..upload_limits(),
      max_bytes: bytes,
    }).unwrap(),
    wire,
  )
  assert_true(
    object_mutation_mapping_json(binding, original, "exports", {
      ..upload_limits(),
      max_bytes: bytes - 1,
    })
    is Err(CapacityExceeded),
  )
  assert_true(
    object_mutation_mapping_json(binding, original, "exports", {
      ..upload_limits(),
      max_nodes: 1,
    })
    is Err(CapacityExceeded),
  )
  assert_true(
    object_mutation_mapping_json(binding, original, "exports", {
      ..upload_limits(),
      max_bytes: 0,
    })
    is Err(InvalidBinding),
  )
}
