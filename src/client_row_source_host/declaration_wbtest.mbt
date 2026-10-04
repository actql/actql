///|
fn issues_view() -> RowViewSpec {
  {
    resource: "issues",
    resource_kind: "issue",
    fields: [
      { name: "number", value_type: "number", nullable: false, },
      { name: "title", value_type: "string", nullable: false, },
      { name: "body", value_type: "string", nullable: true, },
    ],
  }
}

///|
test "a row declaration names its view and seals stable contracts" {
  let declaration = generate_row_declaration(
    "github-octo-hello",
    "github",
    "github/0.1",
    [issues_view()],
    declaration_limits,
  ).unwrap()
  assert_eq(declaration.views.length(), 1)
  let view = declaration.views[0]
  assert_eq(view.resource, "issues")
  assert_eq(view.source_ref, "connector://github-octo-hello/issues#records")
  assert_eq(view.fields, ["number", "title", "body"])
  assert_true(view.view_cid.has_prefix("sha256:"))
  assert_true(declaration.catalog_cid.has_prefix("sha256:"))
  assert_eq(
    declaration.manifest_entry,
    "{\"connector\":\"github\",\"connector_id\":\"github-octo-hello\",\"connector_version\":\"github/0.1\"}",
  )
  // Generation is deterministic; any meaning change changes the Catalog.
  let again = generate_row_declaration(
    "github-octo-hello",
    "github",
    "github/0.1",
    [issues_view()],
    declaration_limits,
  ).unwrap()
  assert_eq(again.catalog_cid, declaration.catalog_cid)
  assert_eq(again.catalog, declaration.catalog)
  let nullable_title = generate_row_declaration(
    "github-octo-hello",
    "github",
    "github/0.1",
    [
      {
        ..issues_view(),
        fields: [
          { name: "number", value_type: "number", nullable: false, },
          { name: "title", value_type: "string", nullable: true, },
          { name: "body", value_type: "string", nullable: true, },
        ],
      },
    ],
    declaration_limits,
  ).unwrap()
  assert_true(nullable_title.catalog_cid != declaration.catalog_cid)
  assert_true(nullable_title.views[0].view_cid != view.view_cid)
  let other_connection = generate_row_declaration(
    "github-octo-other",
    "github",
    "github/0.1",
    [issues_view()],
    declaration_limits,
  ).unwrap()
  assert_true(other_connection.catalog_cid != declaration.catalog_cid)
  assert_true(declaration.catalog.contains("\"resource_kind\":\"issue\""))
  assert_true(declaration.catalog.contains("\"operations\":[\"projection\"]"))
}

///|
test "invalid views, names, types and registrations are refused" {
  let generate = (
    id : String,
    registration : String,
    version : String,
    views : Array[RowViewSpec],
  ) => {
    generate_row_declaration(
      id, registration, version, views, declaration_limits,
    )
  }
  assert_true(
    generate("", "github", "github/0.1", [issues_view()])
    is Err(InvalidConnectorId),
  )
  assert_true(
    generate("x", "github", "other/0.1", [issues_view()])
    is Err(InvalidRegistration),
  )
  assert_true(
    generate("x", "Git Hub", "Git Hub/0.1", [issues_view()])
    is Err(InvalidRegistration),
  )
  assert_true(generate("x", "github", "github/0.1", []) is Err(InvalidView))
  assert_true(
    generate("x", "github", "github/0.1", [issues_view(), issues_view()])
    is Err(DuplicateName("issues")),
  )
  assert_true(
    generate("x", "github", "github/0.1", [
      {
        ..issues_view(),
        fields: [
          { name: "a", value_type: "string", nullable: false, },
          { name: "a", value_type: "string", nullable: false, },
        ],
      },
    ])
    is Err(DuplicateName("a")),
  )
  assert_true(
    generate("x", "github", "github/0.1", [
      {
        ..issues_view(),
        fields: [{ name: "a", value_type: "decimal", nullable: false, }],
      },
    ])
    is Err(UnsupportedType("decimal")),
  )
  assert_true(
    generate("x", "github", "github/0.1", [
      {
        ..issues_view(),
        fields: [{ name: "1a", value_type: "string", nullable: false, }],
      },
    ])
    is Err(InvalidView),
  )
}

///|
test "a restore must reproduce the published Catalog exactly" {
  let spec = "{\"views\":[{\"resource\":\"issues\",\"resource_kind\":\"issue\",\"fields\":[" +
    "{\"name\":\"number\",\"type\":\"number\",\"nullable\":false}," +
    "{\"name\":\"title\",\"type\":\"string\",\"nullable\":false}," +
    "{\"name\":\"body\",\"type\":\"string\",\"nullable\":true}]}]}"
  let published = restore_row_declaration(
    "github-octo-hello",
    "github",
    "github/0.1",
    spec,
    None,
  ).unwrap()
  let expected = generate_row_declaration(
    "github-octo-hello",
    "github",
    "github/0.1",
    [issues_view()],
    declaration_limits,
  ).unwrap()
  assert_eq(published.catalog_cid, expected.catalog_cid)
  assert_true(
    restore_row_declaration(
      "github-octo-hello",
      "github",
      "github/0.1",
      spec,
      Some(expected.catalog_cid),
    )
    is Ok(_),
  )
  assert_true(
    restore_row_declaration(
      "github-octo-hello",
      "github",
      "github/0.1",
      spec,
      Some("sha256:" + "0".repeat(64)),
    )
    is Err(ForeignDeclaration),
  )
  for
    invalid in [
      "{}", "{\"views\":[{}]}", "{\"views\":[],\"extra\":1}", "not json", "{\"views\":[{\"resource\":\"issues\",\"resource_kind\":\"issue\",\"fields\":[{\"name\":\"a\",\"type\":\"string\",\"nullable\":\"no\"}]}]}",
    ] {
    assert_true(
      restore_row_declaration("x", "github", "github/0.1", invalid, None)
      is Err(InvalidSpecification),
    )
  }
}

///|
test "evidence members name each view's contracts" {
  let declaration = generate_row_declaration(
    "github-octo-hello",
    "github",
    "github/0.1",
    [issues_view()],
    declaration_limits,
  ).unwrap()
  let (schemas, capabilities) = row_declaration_evidence_members(declaration)
  assert_eq(schemas.length(), 1)
  assert_eq(capabilities.length(), 1)
  let view = declaration.views[0]
  assert_true(schemas[0].contains("\"source_ref\":\"" + view.source_ref + "\""))
  assert_true(
    schemas[0].contains(
      "\"carrier_schema_contract_cid\":\"" + view.carrier_schema_cid + "\"",
    ),
  )
  assert_true(
    capabilities[0].contains(@planning.query_evidence_contract_identity()),
  )
}
