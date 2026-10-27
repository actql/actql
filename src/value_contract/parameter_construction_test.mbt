///|
test "Parameter type quantities retain only original type positions and enum roles" {
  let body = "{\"type\":\"array\",\"items\":{\"type\":\"object\",\"fields\":{\"v\":{\"type\":\"string\",\"enum\":[\"a\",\"b\"]}}},\"default\":[{\"v\":\"a\"}],\"meta\":{\"note\":{\"type\":\"object\",\"fields\":{\"fake\":{\"type\":\"number\"}}}}}"
  let original = cursor(body)
  let g = @value_contract.observe_parameter_read_construction_geometry(original)
  assert_eq(
    (g.types, g.arrays, g.objects, g.fields, g.enumerants),
    (3, 1, 1, 1, 2),
  )
  assert_eq(g.max_view_fields, 4)
  assert_true(g.work > 0L)
  // Actual reader remains final; metadata/default checking belongs to binding.
  assert_true(
    @value_contract.read_parameter_syntax(original, limits()) is Ok(_),
  )
  let huge = String::make(10000, 'x')
  let changed = cursor(
    body.replace(
      old="\"fake\":{\"type\":\"number\"}",
      new="\"" +
        huge +
        "\":{\"type\":\"array\",\"items\":{\"type\":\"number\"}}",
    ),
  )
  let same = @value_contract.observe_parameter_read_construction_geometry(
    changed,
  )
  assert_eq(same, g)
}

///|
test "Parameter quantity inspection does not admit malformed type syntax or normalize enum DATA" {
  let huge = String::make(10000, 'x')
  let original = cursor("{\"type\":\"string\",\"enum\":[\"" + huge + "\"]}")
  let g = @value_contract.observe_parameter_read_construction_geometry(original)
  assert_eq((g.types, g.enumerants), (1, 1))
  assert_eq(g.max_identifier_units, 6)
  let invalid = cursor("{\"type\":\"unknown\",\"items\":{\"type\":\"number\"}}")
  let observed = @value_contract.observe_parameter_read_construction_geometry(
    invalid,
  )
  assert_eq(observed.types, 1)
  assert_true(
    @value_contract.read_parameter_syntax(invalid, limits()) is Err(_),
  )
}
