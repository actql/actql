///|
fn mapping_permission_fixture(preimage : String) -> MappingContractShape {
  let shapes = check_mapping_contract_shapes(
    mapping_shape_fixture(mapping_shape_seal(preimage)),
    mapping_shape_limits(),
    100,
  ).unwrap()
  mapping_shape_at(shapes, 0).unwrap()
}

///|
test "Mapping permission rule matches kind selector and exact field set" {
  let shape = mapping_permission_fixture(mapping_shape_preimage())
  let selected = select_mapping_permissions(
    shape,
    "create",
    "none",
    ["Name"],
    10,
  ).unwrap()
  assert_true(physical_equal(mapping_permission_shape(selected), shape))
  assert_eq(mapping_permission_rule(selected), ("create", "none", ["Name"]))
  assert_eq(mapping_permission_names(selected), ["scope:create"])
  assert_eq(mapping_permission_required_names(selected), [])
  assert_eq(mapping_permission_work(selected), 5)
  assert_eq(
    select_mapping_permissions(shape, "update", "id", ["Name"], 10).unwrap_err(),
    NoMatchingRule,
  )
  assert_eq(
    select_mapping_permissions(shape, "create", "none", [], 10).unwrap_err(),
    NoMatchingRule,
  )
}

///|
test "Mapping permission rule compares write fields as a complete set" {
  let preimage = mapping_shape_preimage()
    .replace(
      old="\"writable_fields\":[\"Name\"]",
      new="\"writable_fields\":[\"Id\",\"Name\"]",
    )
    .replace(
      old="\"write_fields\":[\"Name\"]",
      new="\"write_fields\":[\"Name\",\"Id\"]",
    )
  let shape = mapping_permission_fixture(preimage)
  let selected = select_mapping_permissions(
    shape,
    "create",
    "none",
    ["Id", "Name"],
    20,
  ).unwrap()
  assert_eq(mapping_permission_names(selected), ["scope:create"])
  assert_eq(
    select_mapping_permissions(shape, "create", "none", ["Name"], 20).unwrap_err(),
    NoMatchingRule,
  )
  assert_eq(
    select_mapping_permissions(shape, "create", "none", ["Id", "Id"], 20).unwrap_err(),
    InvalidRequest,
  )
}

///|
test "Mapping permission admission rejects ambiguous and malformed rules" {
  let duplicate = mapping_shape_preimage().replace(
    old="\"permission_rules\":[{\"effect_kind\":\"create\",\"permissions\":[\"scope:create\"],\"selector_class\":\"none\",\"write_fields\":[\"Name\"]}]",
    new="\"permission_rules\":[{\"effect_kind\":\"create\",\"permissions\":[\"scope:create\"],\"selector_class\":\"none\",\"write_fields\":[\"Name\"]},{\"effect_kind\":\"create\",\"permissions\":[\"scope:other\"],\"selector_class\":\"none\",\"write_fields\":[\"Name\"]}]",
  )
  let duplicate_shape = mapping_permission_fixture(duplicate)
  assert_eq(
    select_mapping_permissions(duplicate_shape, "create", "none", ["Name"], 20).unwrap_err(),
    AmbiguousRules,
  )
  let malformed = mapping_shape_preimage().replace(
    old="\"permissions\":[\"scope:create\"]",
    new="\"permissions\":[]",
  )
  let malformed_shape = mapping_permission_fixture(malformed)
  assert_eq(
    select_mapping_permissions(malformed_shape, "create", "none", ["Name"], 20).unwrap_err(),
    InvalidRule(0),
  )
}

///|
test "Mapping permission selection charges before bounded traversal" {
  let shape = mapping_permission_fixture(mapping_shape_preimage())
  for budget in 0..<5 {
    assert_eq(
      select_mapping_permissions(shape, "create", "none", ["Name"], budget).unwrap_err(),
      WorkLimit,
    )
  }
  assert_eq(
    select_mapping_permissions(shape, "create", "none", ["Name"], 5) is Ok(_),
    true,
  )
}
