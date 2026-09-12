///|
fn value_roles() -> Array[String] {
  [
    "request_schema", "command_input", "command_output", "idempotency_key", "checkpoint",
    "lookup_request_key", "lookup_batch_request", "lookup_response_key",
  ]
}

///|
fn value_bodies(text : String) -> Map[String, Json] raise {
  let bodies : Map[String, Json] = Map([])
  for kind in value_roles() {
    bodies[kind] = @json.parse(text)
  }
  bodies
}

///|
fn value_policies(
  bodies : Map[String, Json],
  unused? : Json? = None,
) -> SourceDataPolicies raise {
  let contents = reference_fixture(
    policy_body=Some(policy_body_fixture("unknown")),
    bodies~,
    unused_value=unused,
  )
  let references = check_catalog_references(contents, reference_caps()).unwrap()
  check_source_data_policies(references, policy_limits()).unwrap()
}

///|
fn protocol_value_limits() -> ValueContractLimits {
  {
    max_envelopes: 100,
    contracts: { max_nodes: 10000, max_depth: 1000, max_text_bytes: 100000, },
  }
}

///|
test "eight value-contract roles share exact reader budgets and preserve envelope ownership" {
  let policies = value_policies(
    value_bodies("{\"type\":\"number\",\"nullable\":false}"),
  )
  let checked = check_protocol_value_contracts(
    policies,
    protocol_value_limits(),
  ).unwrap()
  assert_true(physical_equal(value_contract_policies(checked), policies))
  let (nodes, text, count) = protocol_value_usage(checked)
  assert_eq((nodes, text, count), (8, 48, 8))
  for i in 0..<count {
    let value = protocol_value_at(checked, i).unwrap()
    let envelope = protocol_value_envelope(value)
    assert_true(value_roles().contains(contract_role(envelope)))
    assert_true(
      physical_equal(protocol_value_for(checked, envelope).unwrap(), value),
    )
    assert_eq(
      @value_contract.stringify_checked(
        protocol_value_type(value),
        1000,
        100,
        10,
      ),
      "{\"nullable\":false,\"type\":\"number\"}",
    )
  }
  let exact : ValueContractLimits = {
    max_envelopes: 17,
    contracts: { max_nodes: nodes, max_depth: 0, max_text_bytes: text, },
  }
  assert_true(check_protocol_value_contracts(policies, exact) is Ok(_))
  assert_true(
    check_protocol_value_contracts(policies, { ..exact, max_envelopes: 16, })
    is Err(EnvelopeLimit),
  )
  assert_true(
    check_protocol_value_contracts(policies, {
      ..exact,
      contracts: { ..exact.contracts, max_nodes: nodes - 1, },
    })
    is Err(InvalidContract(_, _)),
  )
  assert_true(
    check_protocol_value_contracts(policies, {
      ..exact,
      contracts: { ..exact.contracts, max_text_bytes: text - 1, },
    })
    is Err(InvalidContract(_, _)),
  )
  assert_true(
    check_protocol_value_contracts(policies, { ..exact, max_envelopes: -1, })
    is Err(InvalidLimits),
  )
  assert_true(protocol_value_at(checked, -1) is None)
  assert_true(protocol_value_at(checked, count) is None)
  let other = check_protocol_value_contracts(
    value_policies(value_bodies("{\"type\":\"number\",\"nullable\":false}")),
    exact,
  ).unwrap()
  assert_true(
    protocol_value_for(
      checked,
      protocol_value_envelope(protocol_value_at(other, 0).unwrap()),
    )
    is None,
  )
  assert_true(
    protocol_value_for(
      checked,
      data_policy_envelope(data_policy_at(policies, 0).unwrap()),
    )
    is None,
  )
}

///|
test "each value role rejects malformed checked contracts including unused contracts" {
  let scalar = "{\"type\":\"number\",\"nullable\":false}"
  for kind in value_roles() {
    for
      invalid in [
        "null", "{}", "{\"type\":\"number\"}", "{\"type\":\"object\",\"nullable\":false,\"fields\":{}}",
        "{\"type\":\"object\",\"properties\":{},\"required\":[]}", "{\"type\":\"decimal\",\"nullable\":false,\"precision\":1,\"scale\":2}",
        "{\"type\":\"vector\",\"nullable\":false,\"dimensions\":2}", "{\"type\":\"number\",\"nullable\":false,\"default\":0}",
      ] {
      let bodies = value_bodies(scalar)
      bodies[kind] = @json.parse(invalid)
      assert_true(
        check_protocol_value_contracts(
          value_policies(bodies),
          protocol_value_limits(),
        )
        is Err(InvalidContract(_, _)),
      )
    }
  }
  assert_true(
    check_protocol_value_contracts(
      value_policies(value_bodies(scalar), unused=Some(Json::null())),
      protocol_value_limits(),
    )
    is Err(InvalidContract(_, _)),
  )
  let checked = check_protocol_value_contracts(
    value_policies(value_bodies(scalar), unused=Some(@json.parse(scalar))),
    protocol_value_limits(),
  ).unwrap()
  assert_eq(protocol_value_usage(checked), (9, 54, 9))
}

///|
test "recursive checked object array decimal and reference types are retained without issuer claims" {
  let text = "{\"type\":\"object\",\"nullable\":false,\"additional_properties\":false,\"fields\":{\"amount\":{\"type\":\"decimal\",\"precision\":38,\"scale\":19,\"nullable\":true},\"items\":{\"type\":\"array\",\"nullable\":false,\"max_items\":0,\"items\":{\"type\":\"resource_ref\",\"nullable\":false,\"resource_kind\":\"record\"}}}}"
  let checked = check_protocol_value_contracts(
    value_policies(value_bodies(text)),
    protocol_value_limits(),
  ).unwrap()
  let expected = canonical_fixture(@json.parse(text))
  for i in 0..<8 {
    assert_eq(
      @value_contract.stringify_checked(
        protocol_value_type(protocol_value_at(checked, i).unwrap()),
        10000,
        100,
        10,
      ),
      expected,
    )
  }
  let empty = check_catalog_contents(catalog_environment([], []), caps()).unwrap()
  let refs = check_catalog_references(empty, reference_caps()).unwrap()
  let policies = check_source_data_policies(refs, policy_limits()).unwrap()
  assert_true(
    check_protocol_value_contracts(policies, {
      max_envelopes: 0,
      contracts: { max_nodes: 0, max_depth: 0, max_text_bytes: 0, },
    })
    is Ok(v) &&
    protocol_value_usage(v) == (0, 0, 0),
  )
}
