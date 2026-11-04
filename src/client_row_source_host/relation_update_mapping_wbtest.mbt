///|
fn relation_update_write_wire() -> String {
  "{\"writes\":[{\"resource\":\"records\",\"primary_identity\":\"id\",\"update\":{\"fields\":[\"choices\",\"amount\",\"label\"],\"permission\":\"fixture:update\",\"approval\":\"required\"}}]}"
}

///|
test "installed UPDATE mapping continuation reuses the original complete typed constructor" {
  let declaration = relation_mapping_declaration()
  let sources = relation_mapping_sources()
  let continued = prepare_row_update_mapping(
    declaration,
    relation_update_write_wire(),
    "records",
    sources,
  ).unwrap()
  let expected = prepare_relation_row_write_mapping(
    declaration,
    "records",
    "id",
    relation_mapping_spec(RelationUpdate),
    sources,
    { ..declaration_limits, max_fields: 1024, },
  ).unwrap()
  assert_eq(continued.body, expected.body)
  assert_eq(continued.mapping_ref, expected.mapping_ref)
  assert_eq(continued.mapping_cid, expected.mapping_cid)
  assert_eq(continued.write_fields, ["amount", "choices"])
  assert_true(continued.body.contains("\"effect_kind\":\"update\""))
  assert_true(continued.body.contains("\"selector_class\":\"id\""))
  assert_true(continued.body.contains("\"precision\":18"))
  assert_true(continued.body.contains("\"type\":\"array\""))
  assert_true(continued.body.contains("\"minimum_approval\":\"required\""))
}

///|
test "installed UPDATE continuation preserves typed null and omission rules" {
  let declaration = relation_mapping_declaration()
  let mapping = prepare_row_update_mapping(
    declaration,
    relation_update_write_wire(),
    "records",
    [
      { target: "amount", field: "newAmount", null_behavior: "write_null", },
      { target: "label", field: "newLabel", null_behavior: "omit", },
    ],
  ).unwrap()
  assert_eq(mapping.omittable, ["label"])
  for
    source in [
      { target: "choices", field: "newChoices", null_behavior: "write_null", },
      { target: "id", field: "newId", null_behavior: "reject", },
      { target: "label", field: "", null_behavior: "reject", },
    ] {
    assert_true(
      prepare_row_update_mapping(
        declaration,
        relation_update_write_wire(),
        "records",
        [source],
      )
      is Err(_),
    )
  }
  assert_true(
    prepare_row_update_mapping(
      declaration,
      relation_update_write_wire(),
      "records",
      [],
    )
    is Err(EmptyWrite),
  )
  assert_true(
    prepare_row_update_mapping(
      declaration,
      relation_update_write_wire(),
      "records",
      [
        { target: "label", field: "a", null_behavior: "reject", },
        { target: "label", field: "b", null_behavior: "reject", },
      ],
    )
    is Err(DuplicateField("label")),
  )
}

///|
test "installed UPDATE continuation refuses open duplicate foreign or malformed write facts" {
  let declaration = relation_mapping_declaration()
  let wire = relation_update_write_wire()
  for
    invalid in [
      "{}",
      "{\"writes\":[]}",
      wire.replace(old="{\"writes\":", new="{\"extra\":true,\"writes\":"),
      wire.replace(
        old="\"primary_identity\":\"id\"",
        new="\"primary_identity\":\"id\",\"fields\":[]",
      ),
      wire.replace(
        old="\"primary_identity\":\"id\"",
        new="\"primary_identity\":null",
      ),
      wire.replace(
        old="\"fields\":[\"choices\",\"amount\",\"label\"]",
        new="\"fields\":[\"choices\",\"choices\"]",
      ),
      wire.replace(
        old="\"fields\":[\"choices\",\"amount\",\"label\"]",
        new="\"fields\":[\"id\"]",
      ),
      wire.replace(
        old="\"permission\":\"fixture:update\"",
        new="\"permission\":\"\"",
      ),
      wire.replace(
        old="\"approval\":\"required\"",
        new="\"approval\":\"sometimes\"",
      ),
      wire.replace(
        old="\"approval\":\"required\"",
        new="\"approval\":\"required\",\"required\":[]",
      ),
      wire.replace(
        old="\"resource\":\"records\"",
        new="\"resource\":\"records\",\"resource\":\"records\"",
      ),
      wire.replace(
        old="\"primary_identity\":\"id\"",
        new="\"primary_identity\":\"missing\"",
      ),
    ] {
    assert_true(
      prepare_row_update_mapping(
        declaration,
        invalid,
        "records",
        relation_mapping_sources(),
      )
      is Err(_),
    )
  }
  assert_true(
    prepare_row_update_mapping(
      declaration,
      wire,
      "other",
      relation_mapping_sources(),
    )
    is Err(NotWritable("other")),
  )
}

///|
test "installed UPDATE validates every sibling specification before selecting a mapping" {
  let declaration = relation_mapping_declaration()
  let first = relation_update_write_wire()
  let duplicate = first.replace(
    old="]}",
    new=",{\"resource\":\"records\",\"primary_identity\":\"id\",\"update\":{\"fields\":[\"label\"],\"permission\":\"fixture:update\",\"approval\":\"required\"}}]}",
  )
  let foreign = first.replace(
    old="]}",
    new=",{\"resource\":\"foreign\",\"primary_identity\":\"id\",\"update\":{\"fields\":[\"label\"],\"permission\":\"fixture:update\",\"approval\":\"required\"}}]}",
  )
  assert_true(
    prepare_row_update_mapping(
      declaration,
      duplicate,
      "records",
      relation_mapping_sources(),
    )
    is Err(InvalidSpecification),
  )
  assert_true(
    prepare_row_update_mapping(
      declaration,
      foreign,
      "records",
      relation_mapping_sources(),
    )
    is Err(NotWritable("foreign")),
  )
}

///|
test "existing CREATE mapping remains separate and unchanged by UPDATE continuation" {
  let declaration = github_declaration()
  let mapping = prepare_row_mapping(
    declaration,
    writes_json,
    "issue_comments",
    sources(),
  ).unwrap()
  assert_true(mapping.body.contains("\"effect_kind\":\"create\""))
  assert_true(mapping.body.contains("\"selector_class\":\"none\""))
  assert_true(
    prepare_row_update_mapping(
      declaration,
      writes_json,
      "issue_comments",
      sources(),
    )
    is Err(_),
  )
  assert_true(
    prepare_row_mapping(
      relation_mapping_declaration(),
      relation_update_write_wire(),
      "records",
      relation_mapping_sources(),
    )
    is Err(_),
  )
}
