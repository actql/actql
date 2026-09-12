///|
test "body dependencies require admitted grammar and preserve exact envelope owners" {
  let checked = check_protocol_value_contracts(
    value_policies(value_bodies("{\"type\":\"number\",\"nullable\":false}")),
    protocol_value_limits(),
  ).unwrap()
  let registry = catalog_registry(
    reference_contents(data_policy_references(value_contract_policies(checked))),
  )
  let (_, _, count) = contract_registry_usage(registry)
  let mut admitted = 0
  let mut unsupported = 0
  for i in 0..<count {
    let envelope = contract_at(registry, i).unwrap()
    match check_body_dependencies(checked, envelope) {
      Ok(dependencies) => {
        admitted += 1
        assert_true(
          physical_equal(body_dependency_contract(dependencies), envelope),
        )
        assert_true(
          physical_equal(
            body_dependency_value(dependencies),
            protocol_value_for(checked, envelope).unwrap(),
          ),
        )
        assert_eq(body_dependency_count(dependencies), 1)
        assert_eq(
          body_dependency_at(dependencies, 0),
          Some(
            "sha256:02859499357530af0ae58e4f2958d1c8fa48f957b86b0a2976dad43bed99b551",
          ),
        )
        for index in [-2147483648, -1, 1, 2147483647] {
          assert_true(body_dependency_at(dependencies, index) is None)
        }
      }
      Err(error) => {
        unsupported += 1
        assert_eq(error, UnsupportedBodyGrammar(contract_role(envelope)))
      }
    }
  }
  assert_eq((admitted, unsupported), (8, 9))
  let other = check_protocol_value_contracts(
    value_policies(value_bodies("{\"type\":\"number\",\"nullable\":false}")),
    protocol_value_limits(),
  ).unwrap()
  for i in 0..<count {
    // Environment mismatch precedes grammar dispatch, even for unsupported kinds.
    assert_true(
      check_body_dependencies(other, contract_at(registry, i).unwrap())
      is Err(ForeignEnvironment),
    )
  }
}

///|
test "typed business names and Ref identifiers are not discovered as contract references" {
  let bodies = value_bodies(
    (
      #|{"type":"object","nullable":false,"additional_properties":false,"fields":{"literal":{"type":"resource_ref","nullable":false,"resource_kind":"sha256:0000000000000000000000000000000000000000000000000000000000000000"},"$param":{"type":"string","nullable":false}}}
    ),
  )
  let checked = check_protocol_value_contracts(
    value_policies(bodies),
    protocol_value_limits(),
  ).unwrap()
  for i in 0..<8 {
    let value = protocol_value_at(checked, i).unwrap()
    let dependencies = check_body_dependencies(
      checked,
      protocol_value_envelope(value),
    ).unwrap()
    assert_eq(body_dependency_count(dependencies), 1)
    assert_true(body_dependency_at(dependencies, 1) is None)
  }
}
