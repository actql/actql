///|
fn upload_limits() -> ObjectUploadDeclarationLimits {
  { max_bytes: 32768, max_nodes: 4096, max_depth: 32, }
}

///|
test "GCS upload declares exact optional presence and independent role preimages" {
  let wire = object_upload_command_json("exports", upload_limits()).unwrap()
  guard @json.parse(wire) is Object(bundle) &&
    bundle["command"] is Object(command) &&
    bundle["contracts"] is Array(contracts) &&
    contracts.length() == 2 &&
    contracts[0] is Object(input) &&
    contracts[1] is Object(output) else {
    abort("upload declaration shape")
  }
  let expected =
    #|{"additional_properties":false,"fields":{"content":{"nullable":false,"type":"content_ref"},"content_type":{"nullable":false,"type":"string"},"name":{"nullable":false,"type":"string"},"overwrite":{"nullable":false,"type":"boolean"}},"required_fields":["content","name"]}
  assert_eq(command["input_contract"], @json.parse(expected))
  assert_eq(input["body"], @json.parse(expected))
  assert_eq(input["kind"], "command_input".to_json())
  assert_eq(input["id"], "exports.gcs.upload.command_input".to_json())
  // Independently hashed authored preimages, not output-derived expectations.
  assert_eq(
    input["cid"],
    "sha256:d15b2d1c7b0555836d28a967fa895f56ced810a056e4045c500e760181fa5fac".to_json(),
  )
  assert_eq(
    output["cid"],
    "sha256:57da33bdf9e0d3470e4c6436b26c9fb1162cc3200c0e0c331ee28d8ab2afe5ad".to_json(),
  )
  assert_eq(
    command["contract_cid"],
    "sha256:faa1d52507efc3722752d36a72aef759e84fedfa14ddcd9528ace59d9ba4ace2".to_json(),
  )
  assert_eq(command["input_schema"], upload_declaration_reference(contracts[0]))
  assert_eq(command["target"], {
    "resource_kind": "file_collection",
    "cardinality": "single",
  })
  assert_true(command.get("minimum_approval") is None)
  assert_eq(command["permissions"], [
    "storage.objects.create", "storage.objects.delete", "storage.objects.get",
  ])
}

///|
test "GCS upload does not fabricate optional inputs or narrow Content to a string" {
  let wire = object_upload_command_json("exports", upload_limits()).unwrap()
  assert_false(wire.contains("\"default\""))
  assert_false(wire.contains("\"overwrite\":false"))
  assert_false(wire.contains("\"overwrite\":null"))
  assert_false(wire.contains("\"$actql_ref\""))
  assert_true(wire.contains("\"type\":\"content_ref\""))
  assert_false(wire.contains("\"media_type\""))
}

///|
test "GCS upload declaration validates selection and bounds complete output" {
  let wire = object_upload_command_json("exports", upload_limits()).unwrap()
  let length = @utf8.encode(wire).length()
  assert_eq(
    object_upload_command_json("exports", {
      ..upload_limits(),
      max_bytes: length,
    }).unwrap(),
    wire,
  )
  assert_true(
    object_upload_command_json("exports", {
      ..upload_limits(),
      max_bytes: length - 1,
    })
    is Err(CapacityExceeded),
  )
  for
    limits in [
      { ..upload_limits(), max_bytes: 0, },
      { ..upload_limits(), max_nodes: 0, },
      { ..upload_limits(), max_depth: 0, },
    ] {
    assert_true(
      object_upload_command_json("exports", limits) is Err(InvalidBinding),
    )
  }
  for name in ["", "has space", "has:colon", "x".repeat(129)] {
    assert_true(
      object_upload_command_json(name, upload_limits()) is Err(InvalidBinding),
    )
  }
  assert_true(
    object_upload_command_json("other", upload_limits()).unwrap() != wire,
  )
}

///|
fn upload_empty_catalog_fixture() -> String {
  // Independent empty GCS Catalog preimage and SHA256, not a product output.
  let catalog =
    #|{"catalog_cid":"sha256:74765512d8f6e59d807f87de33f97bf1bea07b40a7719731d6bbe33347e7786a","commands":[],"connector_id":"exports","connector_version":"gcs/0.1","contracts":[],"schema":"actql.connector_catalog/0.1","source_views":[]}
  let value : Json = {
    "connector_id": "exports",
    "connector_registration": "gcs",
    "connector_version": "gcs/0.1",
    "catalog": catalog.to_json(),
    "catalog_cid": "sha256:74765512d8f6e59d807f87de33f97bf1bea07b40a7719731d6bbe33347e7786a",
    "contracts": [],
    "views": [],
    "view_bodies": [],
    "manifest_entry": "{\"connector\":\"gcs\",\"connector_id\":\"exports\",\"connector_version\":\"gcs/0.1\"}",
    "manifest_entry_cid": "sha256:770110acd081a211ff71ba28f48fcd784e388ca4d5207e9a7a43402c1bd3e6a0",
    "evidence_schemas": [],
    "evidence_capabilities": [],
  }
  value.stringify()
}

///|
test "GCS upload adds its complete closed role and Command to the same Catalog DATA" {
  let original = upload_empty_catalog_fixture()
  let wire = object_upload_catalog_json(original, "exports", upload_limits()).unwrap()
  guard @json.parse(wire) is Object(declared) &&
    declared["catalog"] is String(catalog_wire) &&
    @json.parse(catalog_wire) is Object(catalog) &&
    catalog["commands"] is Array(commands) &&
    catalog["contracts"] is Array(contracts) &&
    declared["command_bodies"] is Array(command_bodies) &&
    declared["contracts"] is Array(contract_wires) &&
    @json.parse(original) is Object(before) else {
    abort("extended upload Catalog DATA")
  }
  assert_eq(commands.length(), 1)
  assert_eq(contracts.length(), 2)
  assert_eq(command_bodies.length(), 1)
  assert_eq(contract_wires.length(), 2)
  guard command_bodies[0] is String(command_wire) else { abort("command wire") }
  assert_eq(@json.parse(command_wire), commands[0])
  for index in 0..<contracts.length() {
    guard contract_wires[index] is String(contract_wire) else {
      abort("role wire")
    }
    assert_eq(@json.parse(contract_wire), contracts[index])
  }
  for
    key in [
      "views", "view_bodies", "manifest_entry", "evidence_schemas", "evidence_capabilities",
    ] {
    assert_eq(declared[key], before[key])
  }
  assert_true(declared["catalog_cid"] != before["catalog_cid"])
  assert_eq(
    object_upload_catalog_json(wire, "exports", upload_limits()).unwrap(),
    wire,
  )
}

///|
test "GCS upload refuses foreign or malformed original Catalog data without replacement" {
  let original = upload_empty_catalog_fixture()
  assert_true(
    object_upload_catalog_json(original, "other", upload_limits())
    is Err(InvalidDeclaration),
  )
  for
    broken in [
      "{}", "null", "{\"catalog\":1}", "{\"catalog\":{},\"catalog\":{}}",
    ] {
    assert_true(
      object_upload_catalog_json(broken, "exports", upload_limits())
      is Err(InvalidDeclaration),
    )
  }
  guard @json.parse(original) is Object(fields) else { abort("fixture") }
  fields["catalog_cid"] = ("sha256:" + "a".repeat(64)).to_json()
  assert_true(
    object_upload_catalog_json(
      Json::object(fields).stringify(),
      "exports",
      upload_limits(),
    )
    is Err(InvalidDeclaration),
  )
}

///|
fn upload_mapping_fixture(
  kind? : String = "file_collection",
  target? : String = "connector://exports/objects",
  foreign_catalog? : Bool = false,
) -> (ObjectCollectionBinding, String) raise {
  let wire = object_upload_catalog_json(
    upload_empty_catalog_fixture(),
    "exports",
    upload_limits(),
  ).unwrap()
  guard @json.parse(wire) is Object(declared) &&
    declared["catalog_cid"] is String(cid) else {
    abort("Catalog fixture")
  }
  let binding = prepare_object_collection_binding(
    "project",
    "bucket",
    "exports/",
    target,
    kind,
    if foreign_catalog {
      "sha256:" + "a".repeat(64)
    } else {
      cid
    },
    "sha256:" + "b".repeat(64),
    { max_bytes: 32768, max_nodes: 4096, max_depth: 32, },
  ).unwrap()
  (binding, wire)
}

///|
test "GCS upload Mapping preserves full ContentRef contract and exact original Command relation" {
  let (binding, declared_wire) = upload_mapping_fixture()
  let wire = object_upload_mapping_json(
    binding,
    declared_wire,
    "exports",
    upload_limits(),
  ).unwrap()
  guard @json.parse(wire) is Object(mapping) &&
    mapping["target_schema"] is Object(schema) &&
    schema["fields"] is Object(fields) &&
    fields["content"] is Object(content) &&
    mapping["permission_rules"] is Array(rules) &&
    mapping["store_command"] is Object(pair) &&
    @json.parse(declared_wire) is Object(declared) else {
    abort("Mapping fixture")
  }
  assert_eq(content["type"], "content_ref".to_json())
  assert_eq(content["nullable"], false.to_json())
  assert_eq(mapping["primary_identity"], Json::null())
  assert_eq(mapping["required_fields"], ["content", "name"])
  assert_eq(mapping["resource_identity_cid"], binding.identity_cid.to_json())
  assert_eq(mapping["target_ref"], binding.target_ref.to_json())
  assert_eq(pair["catalog_cid"], declared["catalog_cid"])
  assert_eq(pair["command_ref"], "command:exports.gcs.upload.v1".to_json())
  assert_eq(
    pair["command_contract_cid"],
    "sha256:faa1d52507efc3722752d36a72aef759e84fedfa14ddcd9528ace59d9ba4ace2".to_json(),
  )
  assert_eq(rules.length(), 4)
  for rule in rules {
    guard rule is Object(fields) else { abort("rule fixture") }
    assert_eq(fields["effect_kind"], "create".to_json())
    assert_eq(fields["selector_class"], "none".to_json())
  }
  assert_false(wire.contains("\"$actql_ref\""))
}

///|
test "GCS upload Mapping refuses foreign Catalog kind target and manifest" {
  for
    pair in [
      upload_mapping_fixture(kind="file"),
      upload_mapping_fixture(target="connector://exports/reader_alias"),
      upload_mapping_fixture(foreign_catalog=true),
    ] {
    assert_true(
      object_upload_mapping_json(pair.0, pair.1, "exports", upload_limits())
      is Err(InvalidBinding),
    )
  }
  let (binding, wire) = upload_mapping_fixture()
  guard @json.parse(wire) is Object(declared) else { abort("fixture") }
  declared["manifest_entry_cid"] = ("sha256:" + "a".repeat(64)).to_json()
  assert_true(
    object_upload_mapping_json(
      binding,
      Json::object(declared).stringify(),
      "exports",
      upload_limits(),
    )
    is Err(InvalidBinding),
  )
}
