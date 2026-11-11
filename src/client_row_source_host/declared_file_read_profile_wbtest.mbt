///|
fn declared_file_profile_test_declaration() -> RowDeclaration raise {
  let physical =
    #|{"body":{"nullable":false,"type":"string"},"id":{"nullable":false,"type":"string"},"mime":{"nullable":false,"type":"string"},"name":{"nullable":false,"type":"string"},"version":{"nullable":false,"type":"string"}}
  let logical =
    #|{"content":{"nullable":false,"type":"content_ref"},"resource":{"nullable":false,"resource_kind":"file","type":"resource_ref"},"version":{"nullable":false,"type":"string"}}
  let views = []
  for (resource, wire) in [("records", physical), ("contents", logical)] {
    let body = @identity.from_json(@json.parse(wire), 1024, 20, 16384)
    views.push({
      resource,
      resource_kind: "file",
      schema_wire: wire,
      schema_cid: @identity.cid_value(body, 16384, 1024, 20),
      request_schema_wire: if resource == "contents" {
        Some(
          (
            #|{"additional_properties":false,"fields":{"resource":{"nullable":false,"resource_kind":"file","type":"resource_ref"},"version":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"}
          ),
        )
      } else {
        None
      },
      facts_wire: None,
      acquisition_wire: if resource == "contents" {
        Some(
          (
            #|{"authority":"read_content","correlation":{"cardinality":"one","identity":["resource","version"],"request_fields":["resource","version"],"response_fields":["resource","version"]},"kind":"fetch"}
          ),
        )
      } else {
        None
      },
    })
  }
  generate_relation_row_declaration(
    "declared-file-fixture",
    "fixture",
    "fixture/0.1",
    views,
    {
      max_bytes: 65536,
      max_nodes: 4096,
      max_depth: 32,
      max_views: 2,
      max_fields: 10,
    },
  ).unwrap()
}

///|
fn declared_file_profile_test_fields() -> DeclaredFileReadFields {
  {
    identity: "id",
    name: "name",
    version: "version",
    media_type: "mime",
    content_utf8: "body",
    path: None,
    items_path: ["files"],
    key_path: ["id"],
  }
}

///|
test "declared-file profile binds actual original physical roles and canonical capability before IO" {
  let original = declared_file_profile_test_declaration()
  let view = original.views
    .iter()
    .find_first(view => view.resource == "contents")
    .unwrap()
  let fields = declared_file_profile_test_fields()
  assert_true(
    row_declaration_file_read_profile(original, view.source_ref) is None,
  )
  let quantity = declared_file_read_profile_construction_inventory(
    original, original, fields,
  ).unwrap()
  assert_true(
    @execution.preparation_representation_cost(quantity).unwrap() > 0L,
  )
  let bound = bind_declared_file_read_profile(
    original,
    view.source_ref,
    original,
    "records",
    fields,
  ).unwrap()
  assert_true(physical_equal(original.views[0], bound.views[0]))
  assert_eq(bound.catalog, original.catalog)
  let profile = row_declaration_file_read_profile(bound, view.source_ref).unwrap()
  assert_eq(
    @publication.publication_contract_name(profile),
    "declared_file_content_read",
  )
  assert_true(
    @publication.native_file_read_profile_contract_bindings(profile) is None,
  )
  assert_true(
    @publication.file_read_profile_contract_bindings(profile) is Some(_),
  )
  assert_true(
    row_declaration_file_read_profile_matches(
      bound,
      view.source_ref,
      bound,
      "records",
      fields,
    ),
  )
  let foreign = declared_file_profile_test_declaration()
  assert_eq(foreign.catalog_cid, bound.catalog_cid)
  assert_false(
    row_declaration_file_read_profile_matches(
      bound,
      view.source_ref,
      foreign,
      "records",
      fields,
    ),
  )
  let (_, capabilities) = row_declaration_evidence_members(bound)
  let capability = capabilities
    .iter()
    .find_first(wire => wire.contains(view.source_ref))
    .unwrap()
  assert_true(
    capability.contains(@publication.publication_contract_identity(profile)),
  )
  let parsed = @json.parse(capability)
  guard parsed is Object(root) &&
    root["capability_contract_cids"] is Array(cids) else {
    fail("capability list")
  }
  assert_eq(cids.length(), 2)
  assert_true(cids[0].stringify() < cids[1].stringify())
  fields.items_path[0] = "changed"
  assert_false(
    row_declaration_file_read_profile_matches(
      bound,
      view.source_ref,
      original,
      "records",
      fields,
    ),
  )
  assert_true(
    row_declaration_file_read_profile_matches(
      bound,
      view.source_ref,
      original,
      "records",
      declared_file_profile_test_fields(),
    ),
  )
}

///|
test "declared-file profile refuses foreign role projection and duplicate installation without IO" {
  let original = declared_file_profile_test_declaration()
  let view = original.views
    .iter()
    .find_first(view => view.resource == "contents")
    .unwrap()
  let fields = declared_file_profile_test_fields()
  assert_true(
    bind_declared_file_read_profile(
      original,
      view.source_ref,
      original,
      "records",
      { ..fields, content_utf8: "missing", },
    )
    is Err(_),
  )
  assert_true(
    bind_declared_file_read_profile(
      original,
      view.source_ref,
      original,
      "missing",
      fields,
    )
    is Err(_),
  )
  assert_true(
    bind_declared_file_read_profile(
      original, "foreign", original, "records", fields,
    )
    is Err(_),
  )
  let bound = bind_declared_file_read_profile(
    original,
    view.source_ref,
    original,
    "records",
    fields,
  ).unwrap()
  assert_true(
    bind_declared_file_read_profile(
      bound,
      view.source_ref,
      original,
      "records",
      fields,
    )
    is Err(_),
  )
}
