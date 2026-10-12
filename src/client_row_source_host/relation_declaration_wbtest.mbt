///|
fn saved_relation_view() -> RowRelationViewSpec {
  {
    resource: "rows",
    resource_kind: "table",
    schema_wire: (
      #|{"id":{"nullable":false,"type":"number"},"p":{"contract":{"max_utf8_bytes":32,"nullable":true,"type":"string"},"presence":"conditional"}}
    ),
    // Independently authored field-map bytes hashed with Node SHA-256.
    schema_cid: "sha256:326b7ad79f0904551619945e3eef1915cd61ac943ee05bb8e74f2ef61eea9ee5",
    request_schema_wire: None,
    facts_wire: None,
    acquisition_wire: None,
  }
}

///|
test "installed source classification is sealed in policy and matching source evidence" {
  let view = saved_relation_view()
  let original = generate_relation_row_declaration(
    "content-fixture",
    "fixture",
    "fixture/0.1",
    [view],
    declaration_limits,
  ).unwrap()
  let unknown = generate_relation_row_declaration(
    "content-fixture",
    "fixture",
    "fixture/0.1",
    [view],
    declaration_limits,
    classifications=Some([@environment.Unknown]),
  ).unwrap()
  assert_eq(unknown.catalog, original.catalog)
  for
    (classification, expected) in [
      (@environment.Public, "public"),
      (@environment.Internal, "internal"),
      (@environment.Confidential, "confidential"),
      (@environment.Restricted, "restricted"),
    ] {
    let declared = generate_relation_row_declaration(
      "content-fixture",
      "fixture",
      "fixture/0.1",
      [view],
      declaration_limits,
      classifications=Some([classification]),
    ).unwrap()
    let policy = declared.contracts.filter(wire => {
      wire.contains("\"kind\":\"data_policy\"")
    })
    assert_eq(policy.length(), 1)
    assert_true(
      policy[0].contains(
        "\"body\":{\"classification\":\"" +
        expected +
        "\",\"source_ref\":\"connector://content-fixture/rows#records\",\"version\":\"actql-source-data-policy/0.1\"}",
      ),
    )
    let (snapshots, _) = row_declaration_evidence_members(declared)
    assert_eq(snapshots.length(), 1)
    assert_true(
      snapshots[0].contains("\"data_classification\":\"" + expected + "\""),
    )
    assert_true(snapshots[0].contains(declared.views[0].data_policy_cid))
    let saved = (
      {
        "views": [
          {
            "resource": view.resource,
            "resource_kind": view.resource_kind,
            "schema_wire": view.schema_wire,
            "schema_cid": view.schema_cid,
            "data_classification": expected,
          },
        ],
      } : Json).stringify()
    let restored = restore_relation_row_declaration(
      "content-fixture",
      "fixture",
      "fixture/0.1",
      saved,
      Some(declared.catalog_cid),
    ).unwrap()
    assert_eq(restored.catalog, declared.catalog)
    assert_true(
      restore_relation_row_declaration(
        "content-fixture",
        "fixture",
        "fixture/0.1",
        saved,
        Some(original.catalog_cid),
      )
      is Err(ForeignDeclaration),
    )
  }
  for
    invalid in [
      Json::null(),
      Json::boolean(true),
      Json::string("INTERNAL"),
      Json::string("other"),
    ] {
    let saved = (
      {
        "views": [
          {
            "resource": view.resource,
            "resource_kind": view.resource_kind,
            "schema_wire": view.schema_wire,
            "schema_cid": view.schema_cid,
            "data_classification": invalid,
          },
        ],
      } : Json).stringify()
    assert_true(
      restore_relation_row_declaration(
        "content-fixture",
        "fixture",
        "fixture/0.1",
        saved,
        None,
      )
      is Err(InvalidSpecification),
    )
  }
  assert_true(
    generate_relation_row_declaration(
      "content-fixture",
      "fixture",
      "fixture/0.1",
      [view],
      declaration_limits,
      classifications=Some([]),
    )
    is Err(Declaration(InvalidView)),
  )
}

///|
fn keyed_acquisition_wire() -> String {
  (
    #|{"kind":"fetch","authority":"read_content","correlation":{"request_fields":["resource","version"],"response_fields":["resource","version"],"identity":["resource","version"],"cardinality":"one"}}
  )
}

///|
test "installed acquisition seals the actual Request and preserves ordered correlation roles" {
  let view = {
    ..saved_relation_view(),
    request_schema_wire: Some(
      (
        #|{"type":"object","nullable":false,"additional_properties":false,"fields":{"resource":{"type":"resource_ref","resource_kind":"table","nullable":false},"version":{"type":"string","nullable":false}}}
      ),
    ),
    acquisition_wire: Some(keyed_acquisition_wire()),
  }
  let declaration = generate_relation_row_declaration(
    "content-fixture",
    "fixture",
    "fixture/0.1",
    [view],
    declaration_limits,
  ).unwrap()
  let catalog = @json.parse(declaration.catalog)
  guard catalog is Object(catalog) else { abort("catalog fixture") }
  guard catalog.get("source_views") is Some(Array(views)) else {
    abort("views fixture")
  }
  guard views[0] is Object(source_view) else { abort("view fixture") }
  guard source_view.get("acquisition") is Some(Object(acquisition)) else {
    abort("acquisition fixture")
  }
  assert_eq(acquisition.get("kind"), Some(Json::string("fetch")))
  assert_eq(acquisition.get("authority"), Some(Json::string("read_content")))
  let request = acquisition.get("request_schema").unwrap()
  guard request is Object(reference) else { abort("reference fixture") }
  let mut matched = false
  for wire in declaration.contracts {
    if @json.parse(wire) is Object(envelope) &&
      envelope.get("kind") == Some(Json::string("request_schema")) {
      assert_eq(envelope.get("cid"), reference.get("cid"))
      assert_eq(envelope.get("id"), reference.get("id"))
      assert_eq(envelope.get("version"), reference.get("version"))
      matched = true
    }
  }
  assert_true(matched)
  assert_true(
    declaration.catalog.contains("\"identity\":[\"resource\",\"version\"]"),
  )
  let restored = restore_relation_row_declaration(
    "content-fixture",
    "fixture",
    "fixture/0.1",
    (
      {
        "views": [
          {
            "resource": view.resource,
            "resource_kind": view.resource_kind,
            "schema_wire": view.schema_wire,
            "schema_cid": view.schema_cid,
            "request_schema_wire": view.request_schema_wire.unwrap(),
            "acquisition_wire": view.acquisition_wire.unwrap(),
          },
        ],
      } : Json).stringify(),
    Some(declaration.catalog_cid),
  ).unwrap()
  assert_eq(restored.catalog, declaration.catalog)
  assert_eq(restored.contracts, declaration.contracts)
  let reordered = generate_relation_row_declaration(
    "content-fixture",
    "fixture",
    "fixture/0.1",
    [
      {
        ..view,
        acquisition_wire: Some(
          (
            #|{"correlation":{"cardinality":"one","identity":["resource","version"],"response_fields":["resource","version"],"request_fields":["resource","version"]},"authority":"read_content","kind":"fetch"}
          ),
        ),
      },
    ],
    declaration_limits,
  ).unwrap()
  assert_eq(reordered.catalog, declaration.catalog)
  let reversed = generate_relation_row_declaration(
    "content-fixture",
    "fixture",
    "fixture/0.1",
    [
      {
        ..view,
        acquisition_wire: Some(
          (
            #|{"kind":"fetch","authority":"read_content","correlation":{"request_fields":["version","resource"],"response_fields":["version","resource"],"identity":["version","resource"],"cardinality":"one"}}
          ),
        ),
      },
    ],
    declaration_limits,
  ).unwrap()
  assert_true(reversed.catalog_cid != declaration.catalog_cid)
  assert_true(
    reversed.catalog.contains("\"identity\":[\"version\",\"resource\"]"),
  )
}

///|
test "installed acquisition rejects shape drift and connector supplied contract references" {
  for
    invalid in [
      "null", "[]", "{}", "{\"kind\":\"fetch\"}", "{\"kind\":\"query\",\"authority\":\"read_content\"}",
      "{\"kind\":\"fetch\",\"authority\":\"write\"}", "{\"kind\":\"fetch\",\"authority\":\"read_content\",\"request_schema\":{}}",
      "{\"kind\":\"fetch\",\"authority\":\"read_content\",\"cid\":\"sha256:fake\"}",
      "{\"kind\":\"fetch\",\"authority\":\"read_content\",\"modes\":[]}", "{\"kind\":\"fetch\",\"authority\":\"read_content\",\"correlation\":null}",
      "{\"kind\":\"fetch\",\"authority\":\"read_content\",\"correlation\":{}}", "{\"kind\":\"fetch\",\"authority\":\"read_content\",\"correlation\":{\"request_fields\":[\"version\",\"version\"],\"response_fields\":[\"version\"],\"identity\":[\"version\"],\"cardinality\":\"one\"}}",
      "{\"kind\":\"fetch\",\"authority\":\"read_content\",\"correlation\":{\"request_fields\":[\"version\"],\"response_fields\":[\"version\"],\"identity\":[\"version\"],\"cardinality\":\"one\",\"complete\":true}}",
      "{\"kind\":\"scan\",\"kind\":\"fetch\",\"authority\":\"read_content\"}",
    ] {
    assert_true(
      generate_relation_row_declaration(
        "content-fixture",
        "fixture",
        "fixture/0.1",
        [{ ..saved_relation_view(), acquisition_wire: Some(invalid), }],
        declaration_limits,
      )
      is Err(_),
    )
  }
}

///|
test "acquisition authority and kind are Catalog identity inputs not profile defaults" {
  let generate = (wire : String) => {
    generate_relation_row_declaration(
      "content-fixture",
      "fixture",
      "fixture/0.1",
      [{ ..saved_relation_view(), acquisition_wire: Some(wire), }],
      declaration_limits,
    ).unwrap()
  }
  let content = generate("{\"kind\":\"fetch\",\"authority\":\"read_content\"}")
  let binary = generate("{\"kind\":\"fetch\",\"authority\":\"read_binary\"}")
  let metadata = generate(
    "{\"kind\":\"fetch\",\"authority\":\"read_metadata\"}",
  )
  let scan = generate("{\"kind\":\"scan\",\"authority\":\"read_content\"}")
  assert_true(content.catalog_cid != binary.catalog_cid)
  assert_true(content.catalog_cid != metadata.catalog_cid)
  assert_true(content.catalog_cid != scan.catalog_cid)
}

///|
test "saved Relation declaration emits original presence and text extent contracts" {
  let view = saved_relation_view()
  let declaration = generate_relation_row_declaration(
    "table-local",
    "table",
    "table/0.1",
    [view],
    declaration_limits,
  ).unwrap()
  assert_eq(declaration.views[0].fields, ["id", "p"])
  assert_eq(
    declaration.views[0].source_ref,
    "connector://table-local/rows#records",
  )
  let body = "{\"fields\":" +
    view.schema_wire +
    ",\"version\":\"actql-relation-schema/0.1\"}"
  assert_true(declaration.contracts.any(wire => wire.contains(body)))
  assert_false(
    declaration.contracts.any(wire => wire.contains("\"type\":\"schema\"")),
  )
  let wire = (
    {
      "views": [
        {
          "resource": view.resource,
          "resource_kind": view.resource_kind,
          "schema_wire": view.schema_wire,
          "schema_cid": view.schema_cid,
        },
      ],
    } : Json).stringify()
  let restored = restore_relation_row_declaration(
    "table-local",
    "table",
    "table/0.1",
    wire,
    Some(declaration.catalog_cid),
  ).unwrap()
  assert_eq(restored.catalog, declaration.catalog)
  assert_eq(restored.contracts, declaration.contracts)
}

///|
test "saved Relation declarations refuse CID drift and never default schema metadata" {
  let view = saved_relation_view()
  for
    changed in [
      { ..view, schema_wire: view.schema_wire + " ", },
      { ..view, schema_wire: "{}", },
      { ..view, schema_cid: "sha256:" + "0".repeat(64), },
    ] {
    assert_true(
      generate_relation_row_declaration(
        "table-local",
        "table",
        "table/0.1",
        [changed],
        declaration_limits,
      )
      is Err(InvalidContracts),
    )
  }
  assert_true(
    restore_relation_row_declaration(
      "table-local",
      "table",
      "table/0.1",
      "{\"views\":[{\"resource\":\"rows\",\"resource_kind\":\"table\",\"schema_cid\":\"sha256:" +
      "0".repeat(64) +
      "\"}]}",
      None,
    )
    is Err(InvalidSpecification),
  )
  assert_true(
    generate_relation_row_declaration(
      "table-local",
      "table",
      "table/0.1",
      [view, view],
      { ..declaration_limits, max_nodes: 10, },
    )
    is Err(_),
  )
}

///|
test "row Request and facts are sealed in the same Relation declaration owner" {
  let request = "{\"type\":\"object\",\"nullable\":false,\"additional_properties\":false,\"fields\":{\"prefix\":{\"type\":\"string\",\"nullable\":false}}}"
  let facts = "{\"fixture\":\"exact-request\"}"
  let view = {
    ..saved_relation_view(),
    request_schema_wire: Some(request),
    facts_wire: Some(facts),
  }
  let declaration = generate_relation_row_declaration(
    "file-fixture",
    "fixture",
    "fixture/0.1",
    [view],
    declaration_limits,
  ).unwrap()
  let reordered = generate_relation_row_declaration(
    "file-fixture",
    "fixture",
    "fixture/0.1",
    [
      {
        ..view,
        request_schema_wire: Some(
          (
            #|{"fields":{"prefix":{"nullable":false,"type":"string"}},"additional_properties":false,"nullable":false,"type":"object"}
          ),
        ),
      },
    ],
    declaration_limits,
  ).unwrap()
  assert_eq(reordered.catalog, declaration.catalog)
  assert_eq(reordered.contracts, declaration.contracts)
  assert_true(declaration.contracts.any(wire => wire.contains("\"prefix\"")))
  assert_true(declaration.contracts.any(wire => wire.contains(facts)))
  let ordinary = generate_relation_row_declaration(
    "file-fixture",
    "fixture",
    "fixture/0.1",
    [saved_relation_view()],
    declaration_limits,
  ).unwrap()
  assert_true(ordinary.catalog_cid != declaration.catalog_cid)
  let wire = (
    {
      "views": [
        {
          "resource": view.resource,
          "resource_kind": view.resource_kind,
          "schema_wire": view.schema_wire,
          "schema_cid": view.schema_cid,
          "request_schema_wire": request,
          "facts_wire": facts,
        },
      ],
    } : Json).stringify()
  let restored = restore_relation_row_declaration(
    "file-fixture",
    "fixture",
    "fixture/0.1",
    wire,
    Some(declaration.catalog_cid),
  ).unwrap()
  assert_eq(restored.catalog, declaration.catalog)
  assert_eq(restored.contracts, declaration.contracts)
  for
    invalid in [
      "null", "[]", "{\"type\":\"string\",\"nullable\":false}", "{\"type\":\"object\",\"nullable\":true,\"additional_properties\":false,\"fields\":{}}",
    ] {
    assert_true(
      generate_relation_row_declaration(
        "file-fixture",
        "fixture",
        "fixture/0.1",
        [{ ..view, request_schema_wire: Some(invalid), }],
        declaration_limits,
      )
      is Err(_),
    )
  }
  for invalid in ["null", "[]", "7"] {
    assert_true(
      generate_relation_row_declaration(
        "file-fixture",
        "fixture",
        "fixture/0.1",
        [{ ..view, facts_wire: Some(invalid), }],
        declaration_limits,
      )
      is Err(_),
    )
  }
  assert_true(
    generate_relation_row_declaration(
      "file-fixture",
      "fixture",
      "fixture/0.1",
      [view],
      { ..declaration_limits, max_bytes: 128, },
    )
    is Err(_),
  )
}
