///|
let writes_json : String = "{\"writes\":[{\"resource\":\"issue_comments\",\"resource_kind\":\"issue_comment\",\"primary_identity\":\"id\"," +
  "\"fields\":[{\"name\":\"id\",\"type\":\"string\",\"nullable\":false},{\"name\":\"subject_id\",\"type\":\"string\",\"nullable\":false}," +
  "{\"name\":\"body\",\"type\":\"string\",\"nullable\":false}]," +
  "\"create\":{\"fields\":[\"subject_id\",\"body\"],\"required\":[\"subject_id\",\"body\"],\"permission\":\"github:issues:comment:create\"}}]}"

///|
fn github_declaration() -> RowDeclaration {
  generate_row_declaration(
    "gh-hello",
    "github",
    "github/0.1",
    [
      {
        resource: "issues",
        resource_kind: "issue",
        fields: [{ name: "node_id", value_type: "string", nullable: false, }],
      },
    ],
    declaration_limits,
  ).unwrap()
}

///|
fn sources() -> Array[RowMappingSource] {
  [
    { target: "subject_id", field: "node_id", null_behavior: "reject", },
    { target: "body", field: "comment", null_behavior: "reject", },
  ]
}

///|
test "a create Mapping is generated from the declared write" {
  let mapping = prepare_row_mapping(
    github_declaration(),
    writes_json,
    "issue_comments",
    sources(),
  ).unwrap()
  assert_true(
    mapping.mapping_ref.has_prefix("mapping:gh-hello/issue_comments/create-"),
  )
  assert_true(mapping.mapping_ref.has_suffix(".v1"))
  assert_eq(mapping.write_fields, ["body", "subject_id"])
  assert_eq(mapping.omittable, [])
  let body = mapping.body
  assert_true(body.contains("\"schema\":\"actql.mapping_contract/0.1\""))
  assert_true(
    body.contains("\"target_ref\":\"connector://gh-hello/issue_comments\""),
  )
  assert_true(
    body.contains(
      "\"connector_manifest_cid\":\"" +
      github_declaration().manifest_entry_cid +
      "\"",
    ),
  )
  assert_true(body.contains("\"primary_identity\":\"id\""))
  assert_true(
    body.contains("\"permissions\":[\"github:issues:comment:create\"]"),
  )
  assert_true(
    body.contains("\"mapping_contract_cid\":\"" + mapping.mapping_cid + "\""),
  )
  // Deterministic; a different source field is a different Mapping.
  let again = prepare_row_mapping(
    github_declaration(),
    writes_json,
    "issue_comments",
    sources(),
  ).unwrap()
  assert_eq(again.mapping_cid, mapping.mapping_cid)
  let other = prepare_row_mapping(
    github_declaration(),
    writes_json,
    "issue_comments",
    [
      { target: "subject_id", field: "issue", null_behavior: "reject", },
      { target: "body", field: "comment", null_behavior: "reject", },
    ],
  ).unwrap()
  assert_true(other.mapping_cid != mapping.mapping_cid)
  assert_true(other.mapping_ref != mapping.mapping_ref)
}

///|
test "undeclared, incomplete or invalid writes are refused" {
  let declaration = github_declaration()
  let refused = (resource : String, given : Array[RowMappingSource]) => {
    prepare_row_mapping(declaration, writes_json, resource, given)
  }
  assert_true(refused("issues", sources()) is Err(NotWritable("issues")))
  assert_true(refused("issue_comments", []) is Err(EmptyWrite))
  assert_true(
    refused("issue_comments", [
      { target: "body", field: "comment", null_behavior: "reject", },
    ])
    is Err(MissingRequiredField("subject_id")),
  )
  assert_true(
    refused(
      "issue_comments",
      [..sources(), { target: "id", field: "x", null_behavior: "reject", }],
    )
    is Err(FieldNotWritable("id")),
  )
  assert_true(
    refused("issue_comments", [
      { target: "subject_id", field: "node_id", null_behavior: "omit", },
      { target: "body", field: "comment", null_behavior: "reject", },
    ])
    is Err(InvalidNullBehavior("subject_id")),
  )
  assert_true(
    refused("issue_comments", [
      { target: "subject_id", field: "node_id", null_behavior: "write_null", },
      { target: "body", field: "comment", null_behavior: "reject", },
    ])
    is Err(InvalidNullBehavior("subject_id")),
  )
  assert_true(
    refused("issue_comments", [..sources(), ..sources()])
    is Err(DuplicateField("subject_id")),
  )
  assert_true(
    prepare_row_mapping(declaration, "{}", "issue_comments", sources())
    is Err(InvalidSpecification),
  )
}
