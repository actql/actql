///|
// These are independent synthetic originals, not a production upload selector.
// Existing fixture sealing hashes authored preimages, never binding output.
fn store_command_fixture(
  relationship? : Json? = None,
  omit? : Bool = false,
  operation? : String = "store",
  foreign? : Bool = false,
) -> (WireEnvironment, String) raise {
  let connector = if foreign { "other" } else { "crm" }
  let command = @json.parse(
    command_target_fixture(
      connector, "command:crm.upload.v1", "{\"cardinality\":\"single\",\"resource_kind\":\"crm/collection\"}",
    ),
  )
  let catalog = @json.parse(
    catalog_fixture(connector, [], commands=[canonical_fixture(command)]),
  )
  guard command is Object(command_fields) && catalog is Object(catalog_fields) else {
    abort("fixture objects")
  }
  let entry : Json = {
    "connector": "crm",
    "connector_id": "crm",
    "connector_version": "external-7",
  }
  let manifest_cid = "sha256:" +
    @sha.hex(@utf8.encode(canonical_fixture(entry)))
  let mapping = @json.parse(mapping_shape_preimage())
  guard mapping is Object(fields) else { abort("fixture mapping") }
  fields["connector_manifest_cid"] = manifest_cid.to_json()
  fields["permission_rules"] = [
    {
      "effect_kind": operation,
      "permissions": ["scope:write"],
      "selector_class": "none",
      "write_fields": ["Name"],
    },
  ]
  if !omit {
    fields["store_command"] = relationship.unwrap_or({
      "catalog_cid": catalog_fields["catalog_cid"],
      "command_ref": "command:crm.upload.v1",
      "command_contract_cid": command_fields["contract_cid"],
    })
  }
  let body = @json.parse(sealed_fixture(mapping, "mapping_contract_cid"))
  let environment : Json = {
    "version": "actql-check-environment/0.1",
    "schema_snapshots": [],
    "connector_capabilities": [],
    "mapping_contracts": [body],
    "source_views": [],
    "command_contracts": [command],
    "model_task_contracts": [],
    "contract_registry": [],
    "connector_catalogs": @json.parse(
      sorted_body_array(
        if foreign {
          [canonical_fixture(catalog), catalog_fixture("crm", [])]
        } else {
          [canonical_fixture(catalog)]
        },
      ),
    ),
    "host_policy_profile": {},
    "connector_manifest": {
      "version": "actql-connectors/0.1",
      "connectors": [entry],
    },
  }
  let wire = sealed_fixture(environment, "evidence_bundle_cid")
  guard @json.parse(wire) is Object(wire_fields) &&
    wire_fields["evidence_bundle_cid"] is String(cid) else {
    abort("fixture environment")
  }
  (read(@utf8.encode(wire), cid, mapping_shape_limits()).unwrap(), wire)
}

///|
fn store_command_fixture_catalogs(
  environment : WireEnvironment,
) -> CatalogContents {
  check_catalog_contents(
    check_contract_registry(environment, mapping_shape_limits()).unwrap(),
    mapping_shape_limits(),
  ).unwrap()
}

///|
test "STORE relationship binds original Mapping and exact Command with bounded work" {
  let (environment, _) = store_command_fixture()
  let mappings = check_mapping_contract_shapes(
    environment,
    mapping_shape_limits(),
    100,
  ).unwrap()
  let mapping = mapping_shape_at(mappings, 0).unwrap()
  let catalogs = store_command_fixture_catalogs(environment)
  let bound = bind_store_command(mapping, catalogs, 100).unwrap()
  assert_true(physical_equal(store_command_mapping(bound), mapping))
  let command = store_command_target(bound)
  assert_eq(command_target_id(command), "command:crm.upload.v1")
  assert_eq(command_target_resource_kind(command), "crm/collection")
  assert_true(
    physical_equal(
      command_target_catalog(command),
      catalog_at(catalogs, 0).unwrap(),
    ),
  )
  assert_true(
    physical_equal(
      member_environment(command_target_member(command)),
      environment,
    ),
  )
  let work = store_command_work(bound)
  assert_true(bind_store_command(mapping, catalogs, work) is Ok(_))
  assert_true(
    bind_store_command(mapping, catalogs, work - 1)
    is Err(StoreCommandIssue::WorkLimit),
  )
  assert_true(
    bind_store_command(mapping, catalogs, -1)
    is Err(StoreCommandIssue::InvalidLimit),
  )
}

///|
test "STORE relationship refuses absent selection and equal-CID replacement environment" {
  let (environment, wire) = store_command_fixture()
  let mapping = mapping_shape_at(
    check_mapping_contract_shapes(environment, mapping_shape_limits(), 100).unwrap(),
    0,
  ).unwrap()
  let copied = read(
    @utf8.encode(wire),
    cid(environment),
    mapping_shape_limits(),
  ).unwrap()
  assert_true(
    bind_store_command(mapping, store_command_fixture_catalogs(copied), 100)
    is Err(StoreCommandIssue::ForeignEnvironment),
  )
  let (old, _) = store_command_fixture(omit=true)
  let old_mapping = mapping_shape_at(
    check_mapping_contract_shapes(old, mapping_shape_limits(), 100).unwrap(),
    0,
  ).unwrap()
  assert_true(
    bind_store_command(old_mapping, store_command_fixture_catalogs(old), 100)
    is Err(StoreCommandIssue::MissingRelationship),
  )
  let (create, _) = store_command_fixture(operation="create")
  let create_mapping = mapping_shape_at(
    check_mapping_contract_shapes(create, mapping_shape_limits(), 100).unwrap(),
    0,
  ).unwrap()
  assert_true(
    bind_store_command(
      create_mapping,
      store_command_fixture_catalogs(create),
      100,
    )
    is Err(StoreCommandIssue::UnsupportedMapping),
  )
}

///|
test "STORE relationship is closed and a malformed present component never defaults" {
  for
    invalid in [
      Json::null(),
      {},
      { "catalog_cid": "sha256:" + "a".repeat(64) },
      {
        "catalog_cid": "sha256:" + "a".repeat(64),
        "command_ref": "upload",
        "command_contract_cid": "sha256:" + "b".repeat(64),
      },
      {
        "catalog_cid": "sha256:" + "a".repeat(64),
        "command_ref": "command:crm.upload.v1",
        "command_contract_cid": null,
      },
      {
        "catalog_cid": "sha256:" + "a".repeat(64),
        "command_ref": "command:crm.upload.v1",
        "command_contract_cid": "sha256:" + "b".repeat(64),
        "extra": true,
      },
    ] {
    let (environment, _) = store_command_fixture(relationship=Some(invalid))
    assert_true(
      check_mapping_contract_shapes(environment, mapping_shape_limits(), 100)
      is Err(InvalidMapping(0)),
    )
  }
}

///|
test "STORE relationship cannot substitute a compatible foreign Catalog Command or CID" {
  let (_, wire) = store_command_fixture()
  guard @json.parse(wire) is Object(environment_fields) &&
    environment_fields["mapping_contracts"] is Array(mappings) &&
    mappings[0] is Object(mapping_fields) else {
    abort("fixture originals")
  }
  let relationship = mapping_fields["store_command"]
  for
    (field, replacement, expected) in [
      (
        "catalog_cid",
        "sha256:" + "a".repeat(64),
        StoreCommandIssue::ForeignCatalog,
      ),
      (
        "command_contract_cid",
        "sha256:" + "b".repeat(64),
        StoreCommandIssue::ForeignCommand,
      ),
      (
        "command_ref",
        "command:crm.other.v1",
        StoreCommandIssue::Command(MissingCommand("command:crm.other.v1")),
      ),
    ] {
    let value = @json.parse(canonical_fixture(relationship))
    guard value is Object(fields) else { abort("fixture relationship") }
    fields[field] = replacement.to_json()
    let (environment, _) = store_command_fixture(relationship=Some(value))
    let mapping = mapping_shape_at(
      check_mapping_contract_shapes(environment, mapping_shape_limits(), 100).unwrap(),
      0,
    ).unwrap()
    assert_eq(
      bind_store_command(
        mapping,
        store_command_fixture_catalogs(environment),
        100,
      ).unwrap_err(),
      expected,
    )
  }
}

///|
test "STORE relationship rejects a real foreign connection even when its exact Command resolves" {
  let (environment, _) = store_command_fixture(foreign=true)
  let mapping = mapping_shape_at(
    check_mapping_contract_shapes(environment, mapping_shape_limits(), 100).unwrap(),
    0,
  ).unwrap()
  let catalogs = store_command_fixture_catalogs(environment)
  assert_true(
    select_command_target(catalogs, "command:crm.upload.v1", 100) is Ok(_),
  )
  assert_true(
    bind_store_command(mapping, catalogs, 100)
    is Err(StoreCommandIssue::ForeignCatalog),
  )
}

///|
test "STORE relationship changes cannot retain the old Mapping self identity" {
  let (_, wire) = store_command_fixture()
  guard @json.parse(wire) is Object(environment_fields) &&
    environment_fields["mapping_contracts"] is Array(mappings) &&
    mappings[0] is Object(mapping_fields) &&
    mapping_fields["store_command"] is Object(relationship) else {
    abort("fixture originals")
  }
  relationship["catalog_cid"] = ("sha256:" + "a".repeat(64)).to_json()
  ignore(environment_fields.remove("evidence_bundle_cid"))
  let changed = sealed_fixture(
    Json::object(environment_fields),
    "evidence_bundle_cid",
  )
  guard @json.parse(changed) is Object(changed_fields) &&
    changed_fields["evidence_bundle_cid"] is String(changed_cid) else {
    abort("fixture environment identity")
  }
  let environment = read(
    @utf8.encode(changed),
    changed_cid,
    mapping_shape_limits(),
  ).unwrap()
  assert_true(
    check_mapping_contract_shapes(environment, mapping_shape_limits(), 100)
    is Err(IdentityMismatch(0)),
  )
}
