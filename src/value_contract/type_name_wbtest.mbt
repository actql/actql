///|
test "canonical contract type names use the existing thirteen shape encodings" {
  for
    (body, expected) in [
      ("\"type\":\"string\"", "string"),
      ("\"type\":\"number\"", "number"),
      ("\"type\":\"boolean\"", "boolean"),
      ("\"type\":\"timestamp\"", "timestamp"),
      ("\"type\":\"date\"", "date"),
      ("\"type\":\"json\"", "json"),
      ("\"type\":\"decimal\",\"precision\":9,\"scale\":2", "decimal"),
      (
        "\"type\":\"array\",\"items\":{\"type\":\"number\",\"nullable\":false}",
        "array",
      ),
      (
        "\"type\":\"object\",\"additional_properties\":false,\"fields\":{}", "object",
      ),
      (
        "\"type\":\"vector\",\"dimensions\":3,\"element_type\":\"f32\"", "vector",
      ),
      (
        "\"type\":\"resource_ref\",\"resource_kind\":\"private-kind\"", "resource_ref",
      ),
      (
        "\"type\":\"content_ref\",\"media_type\":\"application/private\"", "content_ref",
      ),
      ("\"type\":\"int64\"", "int64"),
    ] {
    let original = enumeration_contract("{\"nullable\":false," + body + "}")
    assert_eq(contract_type_name(original), expected)
    assert_eq(contract_type_name(with_nullability(original, true)), expected)
  }
}

///|
test "canonical type name reveals no string bounds enumeration or structural payload" {
  let plain = primitive(StringType, nullable=false)
  let bounded = enumeration_contract(
    "{\"type\":\"string\",\"nullable\":true,\"max_utf8_bytes\":999,\"enum\":[\"PRIVATE-ENUM\"]}",
  )
  assert_eq(contract_type_name(plain), "string")
  assert_eq(contract_type_name(bounded), "string")
  let object = object_contract(
    [("PRIVATE-FIELD", bounded)],
    nullable=false,
    max_fields=1,
    max_name_bytes=13,
  ).unwrap()
  assert_eq(contract_type_name(object), "object")
  assert_eq(
    contract_type_name(
      array_contract(object, nullable=false, max_items=Some(999L)).unwrap(),
    ),
    "array",
  )
  assert_false(plain.nullable)
  assert_true(bounded.nullable)
}
