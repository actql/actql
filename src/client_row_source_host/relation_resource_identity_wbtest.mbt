///|
fn relation_resource_identity_fixture(identity : Json?) -> String raise {
  let fields =
    #|{"id":{"nullable":false,"type":"string"},"resource":{"nullable":false,"resource_kind":"file","type":"resource_ref"},"version":{"nullable":false,"type":"string"}}
  let schema = @identity.from_json(@json.parse(fields), 1000, 32, 100000)
  let view : Map[String, Json] = {
    "resource": "files".to_json(),
    "resource_kind": "file".to_json(),
    "schema_wire": fields.to_json(),
    "schema_cid": @identity.cid_value(schema, 100000, 1000, 32).to_json(),
  }
  if identity is Some(body) {
    view["resource_identity_wire"] = body.stringify().to_json()
  }
  ({ "views": [Json::object(view)] } : Json).stringify()
}

///|
fn relation_resource_identity_contract() -> Json {
  {
    "version": "actql.resource_identity/0.1",
    "provider_namespace": "drive",
    "resource_kind": "file",
    "provider_id_field": "id",
    "output_field": "resource",
    "boundary_topology": "connector_connection",
  }
}

///|
test "restored relation Source retains the original static Resource identity contract" {
  let contract = relation_resource_identity_contract()
  let without = restore_relation_row_declaration(
    "drive",
    "mock_drive",
    "mock_drive/0.1",
    relation_resource_identity_fixture(None),
    None,
  ).unwrap()
  let with_identity = restore_relation_row_declaration(
    "drive",
    "mock_drive",
    "mock_drive/0.1",
    relation_resource_identity_fixture(Some(contract)),
    None,
  ).unwrap()
  let body = @json.parse(with_identity.view_bodies[0])
  guard body is Object(body) else { fail("SourceView object") }
  assert_eq(body["resource_identity"], contract)
  assert_true(with_identity.catalog_cid != without.catalog_cid)
  assert_true(with_identity.views[0].view_cid != without.views[0].view_cid)
  assert_eq(with_identity.contracts, without.contracts)
  assert_true(
    restore_relation_row_declaration(
      "drive",
      "mock_drive",
      "mock_drive/0.1",
      relation_resource_identity_fixture(Some(contract)),
      Some(without.catalog_cid),
    )
    is Err(ForeignDeclaration),
  )
  let restored = restore_relation_row_declaration(
    "drive",
    "mock_drive",
    "mock_drive/0.1",
    relation_resource_identity_fixture(Some(contract)),
    Some(with_identity.catalog_cid),
  ).unwrap()
  assert_eq(restored.catalog, with_identity.catalog)
}

///|
test "relation Resource identity refuses changed fields kinds topology and extra DATA" {
  for
    (field, value) in [
      ("version", "other"),
      ("provider_namespace", ""),
      ("resource_kind", "folder"),
      ("provider_id_field", "missing"),
      ("output_field", "id"),
      ("output_field", "missing"),
      ("boundary_topology", "view"),
      ("extra", "ignored"),
    ] {
    let contract = relation_resource_identity_contract()
    guard contract is Object(entries) else { fail("identity object") }
    entries[field] = value.to_json()
    assert_true(
      restore_relation_row_declaration(
        "drive",
        "mock_drive",
        "mock_drive/0.1",
        relation_resource_identity_fixture(Some(contract)),
        None,
      )
      is Err(InvalidSpecification),
    )
  }
}

///|
test "relation Resource identity validates its complete bounded wire without evaluating authority" {
  let contract = relation_resource_identity_contract()
  for bad in [Json::null(), Json::boolean(true), Json::array([])] {
    assert_true(
      restore_relation_row_declaration(
        "drive",
        "mock_drive",
        "mock_drive/0.1",
        relation_resource_identity_fixture(Some(bad)),
        None,
      )
      is Err(InvalidSpecification),
    )
  }
  guard contract is Object(entries) else { fail("identity object") }
  entries["provider_namespace"] = String::make(
    declaration_limits.max_bytes + 1,
    'a',
  ).to_json()
  assert_true(
    restore_relation_row_declaration(
      "drive",
      "mock_drive",
      "mock_drive/0.1",
      relation_resource_identity_fixture(Some(contract)),
      None,
    )
    is Err(InvalidSpecification),
  )
}

///|
test "relation Resource identity refuses duplicate and nontext saved wire fields" {
  let saved = relation_resource_identity_fixture(
    Some(relation_resource_identity_contract()),
  )
  let duplicate = saved.replace(
    old="\\\"provider_namespace\\\":\\\"drive\\\"",
    new="\\\"provider_namespace\\\":\\\"drive\\\",\\\"provider_namespace\\\":\\\"drive\\\"",
  )
  assert_true(duplicate != saved)
  assert_true(
    restore_relation_row_declaration(
      "drive",
      "mock_drive",
      "mock_drive/0.1",
      duplicate,
      None,
    )
    is Err(InvalidSpecification),
  )
  let parsed = @json.parse(saved)
  guard parsed is Object(root) &&
    root["views"] is Array(views) &&
    views[0] is Object(view) else {
    fail("saved view object")
  }
  view["resource_identity_wire"] = Json::boolean(true)
  assert_true(
    restore_relation_row_declaration(
      "drive",
      "mock_drive",
      "mock_drive/0.1",
      parsed.stringify(),
      None,
    )
    is Err(InvalidSpecification),
  )
}
