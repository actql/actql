///|
fn mapping_conversion_fixture(preimage : String) -> MappingContractShape {
  let shapes = check_mapping_contract_shapes(
    mapping_shape_fixture(mapping_shape_seal(preimage)),
    mapping_shape_limits(),
    100,
  ).unwrap()
  mapping_shape_at(shapes, 0).unwrap()
}

///|
fn mapping_conversion_preimage(target : String) -> String {
  mapping_shape_preimage().replace(
    old="\"conversions\":[]",
    new="\"conversions\":[{\"conversion_law_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"source_contract_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"target_field\":\"" +
      target +
      "\"}]",
  )
}

///|
test "Mapping conversion inventory retains exact source and law references" {
  let empty = mapping_conversion_fixture(mapping_shape_preimage())
  assert_eq(
    mapping_conversion_count(check_mapping_conversions(empty, 1).unwrap()),
    0,
  )
  let shape = mapping_conversion_fixture(mapping_conversion_preimage("Name"))
  let conversions = check_mapping_conversions(shape, 2).unwrap()
  assert_true(physical_equal(mapping_conversions_shape(conversions), shape))
  assert_eq(mapping_conversions_work(conversions), 2)
  assert_eq(mapping_conversion_count(conversions), 1)
  let selected = mapping_conversion_for(
    conversions, "Name", "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
  ).unwrap()
  assert_true(
    physical_equal(mapping_conversion_at(conversions, 0).unwrap(), selected),
  )
  assert_eq(mapping_conversion_target(selected), "Name")
  assert_eq(
    mapping_conversion_source_cid(selected),
    "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
  )
  assert_eq(
    mapping_conversion_law_cid(selected),
    "sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
  )
  assert_true(
    mapping_conversion_for(
      conversions,
      "Id",
      mapping_conversion_source_cid(selected),
    )
    is None,
  )
  assert_eq(check_mapping_conversions(shape, 1).unwrap_err(), WorkLimit)
}

///|
test "Mapping conversion inventory rejects foreign and duplicate targets" {
  let foreign = mapping_conversion_fixture(mapping_conversion_preimage("Id"))
  assert_eq(
    check_mapping_conversions(foreign, 2).unwrap_err(),
    UnknownTargetField("Id"),
  )
  let duplicate = mapping_conversion_preimage("Name").replace(
    old="\"target_field\":\"Name\"}]",
    new="\"target_field\":\"Name\"},{\"conversion_law_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"source_contract_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"target_field\":\"Name\"}]",
  )
  let shape = mapping_conversion_fixture(duplicate)
  assert_eq(
    check_mapping_conversions(shape, 3).unwrap_err(),
    DuplicateConversion(
      "Name", "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
    ),
  )
}

///|
test "Mapping conversion inventory rejects malformed law identity" {
  let malformed = mapping_conversion_preimage("Name").replace(
    old="sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
    new="sha256:CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC",
  )
  assert_eq(
    check_mapping_conversions(mapping_conversion_fixture(malformed), 2).unwrap_err(),
    InvalidConversion(0),
  )
}
