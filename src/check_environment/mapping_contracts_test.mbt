///|
fn mapping_shape_fixture(body : String) -> WireEnvironment {
  let before = "{\"command_contracts\":[],\"connector_capabilities\":[],\"connector_catalogs\":[],\"contract_registry\":[],"
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
  "{\"connector_manifest_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"conversions\":[]," +
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
    "sha256:41bcd5581a4f02e507940c7aba8c0ee698904dd23c4533641d843f433379ce7e",
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
    "sha256:41bcd5581a4f02e507940c7aba8c0ee698904dd23c4533641d843f433379ce7e",
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
