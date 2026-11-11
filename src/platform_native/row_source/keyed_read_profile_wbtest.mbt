///|
test "Native file read profile retains same provider roles and refuses missing projections" {
  let (old, _, fields) = file_listing_page_fixture()
  let selected = { ..old.selection, key_path: Some(["id"]), }
  let physical = prepare_native_relation_file_provider(
    old.declaration,
    selected,
    old.limits,
  ).unwrap_or_else(() => abort("profile physical"))
  let schema : Json = {
    "content": { "type": "content_ref", "nullable": false },
    "resource": {
      "type": "resource_ref",
      "resource_kind": "file",
      "nullable": false,
    },
    "version": { "type": "string", "nullable": false },
  }
  let canonical = @identity.from_json(schema, 1024, 20, 16384)
  let declaration = @rows.generate_relation_row_declaration(
    "profile-fixture",
    "fixture",
    "fixture/0.1",
    [
      {
        resource: "contents",
        resource_kind: "file",
        schema_wire: @identity.stringify_value(canonical, 16384, 1024, 20),
        schema_cid: @identity.cid_value(canonical, 16384, 1024, 20),
        request_schema_wire: Some(
          (
            #|{"type":"object","nullable":false,"additional_properties":false,"fields":{"resource":{"type":"resource_ref","resource_kind":"file","nullable":false},"version":{"type":"string","nullable":false}}}
          ),
        ),
        facts_wire: None,
        acquisition_wire: Some(
          (
            #|{"kind":"fetch","authority":"read_content","correlation":{"request_fields":["resource","version"],"response_fields":["resource","version"],"identity":["resource","version"],"cardinality":"one"}}
          ),
        ),
      },
    ],
    {
      max_bytes: 65536,
      max_nodes: 4096,
      max_depth: 32,
      max_views: 1,
      max_fields: 8,
    },
  ).unwrap_or_else(() => abort("profile declaration"))
  let source = declaration.views[0].source_ref
  let profile = prepare_native_relation_file_keyed_read_profile(
    declaration, source, physical, fields, "body",
  ).unwrap_or_else(() => abort("profile binding"))
  assert_true(physical_equal(profile.physical, physical))
  assert_true(physical_equal(profile.declaration, declaration))
  assert_true(
    native_file_keyed_read_profile_matches(
      profile, declaration, source, physical, fields, "body",
    ),
  )
  assert_false(
    native_file_keyed_read_profile_matches(
      profile, declaration, source, old, fields, "body",
    ),
  )
  assert_false(
    native_file_keyed_read_profile_matches(
      profile, declaration, source, physical, fields, "different",
    ),
  )
  assert_false(
    native_file_keyed_read_profile_matches(
      profile, declaration, "foreign", physical, fields, "body",
    ),
  )
  let wire = @publication.publication_contract_json(profile.contract())
  assert_true(wire.contains(declaration.views[0].view_cid))
  assert_true(wire.contains(physical.declaration.views[0].view_cid))
  assert_true(wire.contains("\"content_utf8_field\":\"body\""))
  assert_true(
    prepare_native_relation_file_keyed_read_profile(
      declaration, source, old, fields, "body",
    )
    is Err(InvalidInput),
  )
  assert_true(
    prepare_native_relation_file_keyed_read_profile(
      declaration, source, physical, fields, "missing",
    )
    is Err(InvalidInput),
  )
  assert_true(
    prepare_native_relation_file_keyed_read_profile(
      declaration, "foreign", physical, fields, "body",
    )
    is Err(InvalidInput),
  )
}

///|
test "Native file read profile preserves admitted long physical paths" {
  let (old, _, fields) = file_listing_page_fixture()
  let selected = {
    ..old.selection,
    items_path: Array::make(16, "a".repeat(4096)),
    key_path: Some(Array::make(16, "b".repeat(4096))),
  }
  let physical = prepare_native_relation_file_provider(
    old.declaration,
    selected,
    old.limits,
  ).unwrap_or_else(() => abort("long profile physical"))
  let schema : Json = {
    "resource": {
      "type": "resource_ref",
      "resource_kind": "file",
      "nullable": false,
    },
    "version": { "type": "string", "nullable": false },
    "content": { "type": "content_ref", "nullable": false },
  }
  let canonical = @identity.from_json(schema, 1024, 20, 16384)
  let declaration = @rows.generate_relation_row_declaration(
    "profile-long",
    "fixture",
    "fixture/0.1",
    [
      {
        resource: "contents",
        resource_kind: "file",
        schema_wire: @identity.stringify_value(canonical, 16384, 1024, 20),
        schema_cid: @identity.cid_value(canonical, 16384, 1024, 20),
        request_schema_wire: Some(
          (
            #|{"type":"object","nullable":false,"additional_properties":false,"fields":{"resource":{"type":"resource_ref","resource_kind":"file","nullable":false},"version":{"type":"string","nullable":false}}}
          ),
        ),
        facts_wire: None,
        acquisition_wire: Some(
          (
            #|{"kind":"fetch","authority":"read_content","correlation":{"request_fields":["resource","version"],"response_fields":["resource","version"],"identity":["resource","version"],"cardinality":"one"}}
          ),
        ),
      },
    ],
    {
      max_bytes: 65536,
      max_nodes: 4096,
      max_depth: 32,
      max_views: 1,
      max_fields: 8,
    },
  ).unwrap_or_else(() => abort("long profile declaration"))
  let profile = prepare_native_relation_file_keyed_read_profile(
    declaration,
    declaration.views[0].source_ref,
    physical,
    fields,
    "body",
  ).unwrap_or_else(() => abort("long profile refused"))
  assert_true(
    @publication.publication_contract_json(profile.contract()).length() > 16384,
  )
  assert_true(
    prepare_native_relation_file_keyed_read_profile(
      old.declaration,
      old.declaration.views[0].source_ref,
      physical,
      fields,
      "body",
    )
    is Err(InvalidInput),
  )
}
