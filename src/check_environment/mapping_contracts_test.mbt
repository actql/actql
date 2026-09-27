///|
fn mapping_shape_fixture(body : String) -> WireEnvironment {
  let before = "{\"command_contracts\":[],\"connector_capabilities\":[],\"connector_catalogs\":[{\"catalog_cid\":\"sha256:9faf09f5a3177d36dc7c9fab868f6fe4437e4597dd12bcdc051166ec2e6ad8fd\",\"commands\":[],\"connector_id\":\"crm\",\"connector_version\":\"fixture\",\"contracts\":[],\"schema\":\"actql.connector_catalog/0.1\",\"source_views\":[]}],\"connector_manifest\":{\"connectors\":[{\"connector\":\"crm\",\"connector_id\":\"crm\",\"connector_version\":\"fixture\"}],\"version\":\"actql-connectors/0.1\"},\"contract_registry\":[],"
  let after = "\"host_policy_profile\":{},\"mapping_contracts\":[" +
    body +
    "],\"model_task_contracts\":[],\"schema_snapshots\":[],\"source_views\":[],\"version\":\"actql-check-environment/0.1\"}"
  let cid = "sha256:" + @sha.hex(@utf8.encode(before + after))
  read(
    @utf8.encode(before + "\"evidence_bundle_cid\":\"" + cid + "\"," + after),
    cid,
    { max_bytes: 20000, max_nodes: 2000, max_depth: 100, max_members: 100, },
  ).unwrap()
}

///|
fn mapping_shape_preimage() -> String {
  "{\"connector_manifest_cid\":\"sha256:b1b75d3b468de053f98c678ec9eedfb2f1fe7b6fcb76562b0f392121378ec7c1\",\"conversions\":[]," +
  "\"mapping_ref\":\"mapping:crm.account.v1\",\"minimum_approval\":\"none\",\"permission_rules\":[{\"effect_kind\":\"create\",\"permissions\":[\"scope:create\"],\"selector_class\":\"none\",\"write_fields\":[\"Name\"]}]," +
  "\"primary_identity\":\"Id\",\"required_fields\":[],\"required_permissions\":[],\"resource_identity_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"," +
  "\"row_mapping\":{\"Name\":{\"field\":\"name\",\"null_behavior\":\"reject\"}},\"schema\":\"actql.mapping_contract/0.1\",\"target_ref\":\"connector://crm/account\"," +
  "\"target_schema\":{\"additional_properties\":false,\"fields\":{\"Id\":{\"nullable\":false,\"type\":\"string\"},\"Name\":{\"nullable\":true,\"type\":\"string\"}},\"nullable\":false,\"type\":\"object\"}," +
  "\"target_schema_identity\":\"sha256:bb7f22131b239944c4d7f01ddc3eaf675c34e38ca195527a90c6863668150e66\",\"version\":\"salesforce-v1\",\"writable_fields\":[\"Name\"]}"
}

///|
fn mapping_shape_seal(preimage : String) -> String {
  let cid = "sha256:" + @sha.hex(@utf8.encode(preimage))
  preimage.replace(
    old="\"mapping_ref\":",
    new="\"mapping_contract_cid\":\"" + cid + "\",\"mapping_ref\":",
  )
}

///|
fn mapping_shape_body() -> String {
  mapping_shape_seal(mapping_shape_preimage())
}

///|
fn mapping_shape_limits() -> Limits {
  { max_bytes: 20000, max_nodes: 2000, max_depth: 100, max_members: 100, }
}

///|
test "resolved Mapping shape binds full target schema and exact body CID" {
  assert_eq(
    "sha256:" + @sha.hex(@utf8.encode(mapping_shape_preimage())),
    "sha256:07267191c48e2a8492eabdd29aa77f4ffbc00ade1878980bf5c2d30d004dea2e",
  )
  let environment = mapping_shape_fixture(mapping_shape_body())
  let shapes = check_mapping_contract_shapes(
    environment,
    mapping_shape_limits(),
    100,
  ).unwrap()
  assert_eq(mapping_shape_count(shapes), 1)
  assert_eq(mapping_shape_work(shapes), 2)
  assert_true(physical_equal(mapping_shape_environment(shapes), environment))
  let selected = mapping_shape_for(shapes, "mapping:crm.account.v1").unwrap()
  assert_true(physical_equal(mapping_shape_at(shapes, 0).unwrap(), selected))
  assert_eq(mapping_shape_reference(selected), "mapping:crm.account.v1")
  assert_eq(mapping_shape_target(selected), "connector://crm/account")
  assert_eq(
    mapping_shape_cid(selected),
    "sha256:07267191c48e2a8492eabdd29aa77f4ffbc00ade1878980bf5c2d30d004dea2e",
  )
  assert_eq(mapping_shape_primary_identity(selected), "Id")
  assert_eq(mapping_shape_writable_fields(selected), ["Name"])
  assert_eq(mapping_shape_required_fields(selected), [])
  assert_true(mapping_shape_for(shapes, "mapping:crm.other.v1") is None)
}

///|
test "Mapping shape rejects a foreign self CID before exposing a target" {
  let body = mapping_shape_body().replace(
    old="connector://crm/account",
    new="connector://crm/contact",
  )
  assert_eq(
    check_mapping_contract_shapes(
      mapping_shape_fixture(body),
      mapping_shape_limits(),
      100,
    ).unwrap_err(),
    IdentityMismatch(0),
  )
}

///|
test "Mapping shape rejects missing fields and bounded work exhaustion" {
  let body = mapping_shape_body()
  let missing = mapping_shape_seal(
    mapping_shape_preimage().replace(old="\"required_fields\":[],", new=""),
  )
  assert_eq(
    check_mapping_contract_shapes(
      mapping_shape_fixture(missing),
      mapping_shape_limits(),
      100,
    ).unwrap_err(),
    InvalidMapping(0),
  )
  assert_eq(
    check_mapping_contract_shapes(
      mapping_shape_fixture(body),
      mapping_shape_limits(),
      1,
    ).unwrap_err(),
    WorkLimit,
  )
}

///|
test "Mapping shape rejects a mismatched target schema and invalid primary" {
  let schema_mismatch = mapping_shape_seal(
    mapping_shape_preimage().replace(
      old="sha256:bb7f22131b239944c4d7f01ddc3eaf675c34e38ca195527a90c6863668150e66",
      new="sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
    ),
  )
  assert_eq(
    check_mapping_contract_shapes(
      mapping_shape_fixture(schema_mismatch),
      mapping_shape_limits(),
      100,
    ).unwrap_err(),
    TargetSchemaMismatch(0),
  )
  let bad_primary = mapping_shape_seal(
    mapping_shape_preimage().replace(
      old="\"primary_identity\":\"Id\"",
      new="\"primary_identity\":\"Missing\"",
    ),
  )
  assert_eq(
    check_mapping_contract_shapes(
      mapping_shape_fixture(bad_primary),
      mapping_shape_limits(),
      100,
    ).unwrap_err(),
    InvalidTargetSchema(0),
  )
}

///|
test "Mapping shape retains an external schema identity without claiming closure" {
  let external_cid = "sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
  let external = mapping_shape_seal(
    mapping_shape_preimage()
    .replace(
      old="sha256:bb7f22131b239944c4d7f01ddc3eaf675c34e38ca195527a90c6863668150e66",
      new=external_cid,
    )
    .replace(
      old=",\"version\":\"salesforce-v1\"",
      new=",\"target_schema_reference\":{\"cid\":\"" +
        external_cid +
        "\",\"id\":\"salesforce/account\",\"version\":\"1\"},\"version\":\"salesforce-v1\"",
    ),
  )
  assert_eq(
    mapping_shape_count(
      check_mapping_contract_shapes(
        mapping_shape_fixture(external),
        mapping_shape_limits(),
        100,
      ).unwrap(),
    ),
    1,
  )
}

///|
/// The fixture's manifest entry and Catalog, with the entry CID computed
/// independently by the repository's JavaScript canonical JSON.
fn manifest_fixture_environment(
  mapping : String,
  catalogs? : String = "{\"catalog_cid\":\"sha256:9faf09f5a3177d36dc7c9fab868f6fe4437e4597dd12bcdc051166ec2e6ad8fd\",\"commands\":[],\"connector_id\":\"crm\",\"connector_version\":\"fixture\",\"contracts\":[],\"schema\":\"actql.connector_catalog/0.1\",\"source_views\":[]}",
  connectors? : String = "{\"connector\":\"crm\",\"connector_id\":\"crm\",\"connector_version\":\"fixture\"}",
) -> WireEnvironment {
  let before = "{\"command_contracts\":[],\"connector_capabilities\":[],\"connector_catalogs\":[" +
    catalogs +
    "],\"connector_manifest\":{\"connectors\":[" +
    connectors +
    "],\"version\":\"actql-connectors/0.1\"},\"contract_registry\":[],"
  let after = "\"host_policy_profile\":{},\"mapping_contracts\":[" +
    mapping +
    "],\"model_task_contracts\":[],\"schema_snapshots\":[],\"source_views\":[],\"version\":\"actql-check-environment/0.1\"}"
  let cid = "sha256:" + @sha.hex(@utf8.encode(before + after))
  read(
    @utf8.encode(before + "\"evidence_bundle_cid\":\"" + cid + "\"," + after),
    cid,
    mapping_shape_limits(),
  ).unwrap()
}

///|
test "a Mapping resolves its connector manifest entry, connection and Catalog" {
  let limits = mapping_shape_limits()
  let admitted = check_connector_manifest(
    manifest_fixture_environment(mapping_shape_body()),
    limits,
  ).unwrap()
  let entry = connector_manifest_entry(
    admitted, "sha256:b1b75d3b468de053f98c678ec9eedfb2f1fe7b6fcb76562b0f392121378ec7c1",
  ).unwrap()
  assert_eq(
    connector_manifest_entry_identity(entry),
    (
      "sha256:b1b75d3b468de053f98c678ec9eedfb2f1fe7b6fcb76562b0f392121378ec7c1",
      "crm", "crm", "fixture",
    ),
  )
  assert_true(
    check_mapping_contract_shapes(
      manifest_fixture_environment(mapping_shape_body()),
      limits,
      100,
    )
    is Ok(_),
  )
  // A reference to no entry of this manifest.
  let unresolved = mapping_shape_seal(
    mapping_shape_preimage().replace(
      old="sha256:b1b75d3b468de053f98c678ec9eedfb2f1fe7b6fcb76562b0f392121378ec7c1",
      new="sha256:" + "d".repeat(64),
    ),
  )
  assert_true(
    check_mapping_contract_shapes(
      manifest_fixture_environment(unresolved),
      limits,
      100,
    )
    is Err(ManifestUnresolved(0)),
  )
  // The referenced entry is another connection's.
  let foreign = mapping_shape_seal(
    mapping_shape_preimage().replace(
      old="connector://crm/account",
      new="connector://other/account",
    ),
  )
  assert_true(
    check_mapping_contract_shapes(
      manifest_fixture_environment(foreign),
      limits,
      100,
    )
    is Err(ForeignTarget(0)),
  )
  // A replaced entry (another version) has another CID and no Catalog.
  assert_true(
    check_mapping_contract_shapes(
      manifest_fixture_environment(
        mapping_shape_body(),
        connectors="{\"connector\":\"crm\",\"connector_id\":\"crm\",\"connector_version\":\"other\"}",
      ),
      limits,
      100,
    )
    is Err(Manifest(CatalogMismatch("crm"))),
  )
  // Entries are closed, and ordered by entry CID.
  assert_true(
    check_connector_manifest(
      manifest_fixture_environment(
        mapping_shape_body(),
        connectors="{\"connector\":\"crm\",\"connector_id\":\"crm\",\"connector_version\":\"fixture\",\"path\":\"x\"}",
      ),
      limits,
    )
    is Err(InvalidEntry(0)),
  )
  let high = "{\"connector\":\"crm\",\"connector_id\":\"crm\",\"connector_version\":\"fixture\"}"
  let low = "{\"connector\":\"zz\",\"connector_id\":\"zz\",\"connector_version\":\"fixture\"}"
  let (first, second) = if "sha256:" + @sha.hex(@utf8.encode(high)) <
    "sha256:" + @sha.hex(@utf8.encode(low)) {
    (low, high)
  } else {
    (high, low)
  }
  assert_true(
    check_connector_manifest(
      manifest_fixture_environment(
        mapping_shape_body(),
        connectors=first + "," + second,
      ),
      limits,
    )
    is Err(UnsortedEntries),
  )
}
