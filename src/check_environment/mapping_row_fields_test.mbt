///|
fn mapping_row_fields_fixture(preimage : String) -> MappingContractShape {
  let shapes = check_mapping_contract_shapes(
    mapping_shape_fixture(mapping_shape_seal(preimage)),
    mapping_shape_limits(),
    100,
  ).unwrap()
  mapping_shape_at(shapes, 0).unwrap()
}

///|
test "result-backed Mapping retains explicit target fields" {
  let shape = mapping_row_fields_fixture(mapping_shape_preimage())
  let rows = check_mapping_row_fields(shape, 2).unwrap()
  assert_true(physical_equal(mapping_row_fields_shape(rows), shape))
  assert_eq(mapping_row_fields_names(rows), ["Name"])
  assert_eq(mapping_row_fields_source_at(rows, 0), Some(("Name", Some("name"))))
  assert_true(mapping_row_fields_literal_at(rows, 0) is None)
  assert_eq(mapping_row_fields_null_behavior_at(rows, 0), Some("reject"))
  assert_true(mapping_row_fields_source_at(rows, 1) is None)
  assert_true(mapping_row_fields_literal_at(rows, 1) is None)
  assert_true(mapping_row_fields_null_behavior_at(rows, 1) is None)
  assert_eq(mapping_row_fields_work(rows), 2)
  assert_eq(check_mapping_row_fields(shape, 1).unwrap_err(), WorkLimit)
}

///|
test "Mapping row fields retain literal and null behavior without coercion" {
  let source = mapping_shape_preimage().replace(
    old="\"row_mapping\":{\"Name\":{\"field\":\"name\",\"null_behavior\":\"reject\"}}",
    new="\"row_mapping\":{\"Name\":{\"literal\":null,\"null_behavior\":\"omit\"}}",
  )
  let rows = check_mapping_row_fields(mapping_row_fields_fixture(source), 2).unwrap()
  assert_eq(mapping_row_fields_source_at(rows, 0), Some(("Name", None)))
  assert_true(@decode.is_null(mapping_row_fields_literal_at(rows, 0).unwrap()))
  assert_eq(mapping_row_fields_null_behavior_at(rows, 0), Some("omit"))
}

///|
test "Mapping row fields require writable complete targets" {
  let required = mapping_shape_preimage().replace(
    old="\"required_fields\":[]",
    new="\"required_fields\":[\"Name\"]",
  )
  let shape = mapping_row_fields_fixture(required)
  assert_eq(
    mapping_row_fields_names(check_mapping_row_fields(shape, 3).unwrap()),
    ["Name"],
  )
  let absent = required.replace(
    old="\"row_mapping\":{\"Name\":{\"field\":\"name\",\"null_behavior\":\"reject\"}}",
    new="\"row_mapping\":{}",
  )
  let shape = mapping_row_fields_fixture(absent)
  assert_eq(
    check_mapping_row_fields(shape, 2).unwrap_err(),
    MissingRequiredField("Name"),
  )
  let nonwritable = mapping_shape_preimage().replace(
    old="\"row_mapping\":{\"Name\":",
    new="\"row_mapping\":{\"Id\":",
  )
  let shape = mapping_row_fields_fixture(nonwritable)
  assert_eq(
    check_mapping_row_fields(shape, 2).unwrap_err(),
    NonWritableField("Id"),
  )
}

///|
test "Mapping row fields reject implicit or malformed source and null behavior" {
  for
    (old, replacement) in [
      ("\"field\":\"name\",", ""),
      ("\"null_behavior\":\"reject\"", "\"null_behavior\":\"other\""),
      ("\"field\":\"name\"", "\"field\":\"\""),
    ] {
    let shape = mapping_row_fields_fixture(
      mapping_shape_preimage().replace(old~, new=replacement),
    )
    assert_eq(
      check_mapping_row_fields(shape, 2).unwrap_err(),
      InvalidRowMapping,
    )
  }
}
