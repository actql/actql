///|
fn assert_carrier_dependencies(
  schemas : CarrierSchemas,
  kind : String,
) -> Unit raise {
  let schema = carrier_schema_at(schemas, 0).unwrap()
  let envelope = carrier_schema_envelope(schema)
  let dependencies = check_catalog_body_dependencies(schemas, envelope).unwrap()
  assert_true(physical_equal(catalog_body_contract(dependencies), envelope))
  guard catalog_body_admission(dependencies) is CarrierBody(retained) else {
    abort("carrier admission")
  }
  assert_true(physical_equal(retained, schema))
  let n = if kind == "graph" { 4 } else { 2 }
  assert_eq(catalog_body_dependency_count(dependencies), n)
  let grammar = catalog_body_dependency_at(dependencies, 0).unwrap()
  assert_eq(grammar.role, GoverningGrammar)
  assert_eq(
    grammar.cid,
    "sha256:123b23f425df95044e74f4fd4773e790f45a8443ebee5741fb0dabc76de24761",
  )
  let value = catalog_body_dependency_at(dependencies, 1).unwrap()
  assert_eq(value.role, ValueGrammar)
  assert_eq(
    value.cid,
    "sha256:02859499357530af0ae58e4f2958d1c8fa48f957b86b0a2976dad43bed99b551",
  )
  if kind == "graph" {
    let identity = catalog_body_dependency_at(dependencies, 2).unwrap()
    let value = catalog_body_dependency_at(dependencies, 3).unwrap()
    assert_eq(identity.role, GraphIdentityLaw)
    assert_eq(value.role, GraphValueLaw)
    assert_eq(identity.cid, value.cid)
    assert_eq(
      identity.cid,
      "sha256:ab1ae472462b96ac48e56d3ce0544213cab5d422e6bb198bc9acd5e4d90e0fe4",
    )
  }
  for i in [-2147483648, -1, n, 2147483647] {
    assert_true(catalog_body_dependency_at(dependencies, i) is None)
  }
}

///|
test "Catalog dependency dispatch retains admitted owners and rejects uninterpreted bodies" {
  for kind in ["relation", "events", "vectors"] {
    let schemas = check_carrier_schemas(
      carrier_modes(role_body(kind), kind),
      carrier_limits(),
    ).unwrap()
    assert_carrier_dependencies(schemas, kind)
    let modes = carrier_schema_modes(schemas)
    let values = source_view_shape_values(read_mode_shapes(modes))
    let policies = value_contract_policies(values)
    let registry = catalog_registry(
      reference_contents(data_policy_references(policies)),
    )
    let foreign = check_carrier_schemas(
      carrier_modes(role_body(kind), kind),
      carrier_limits(),
    ).unwrap()
    let mut accepted = 0
    let mut unsupported = 0
    for i in 0..<contract_registry_usage(registry).2 {
      let envelope = contract_at(registry, i).unwrap()
      assert_true(
        check_catalog_body_dependencies(foreign, envelope)
        is Err(ForeignEnvironment),
      )
      match check_catalog_body_dependencies(schemas, envelope) {
        Err(issue) => {
          assert_eq(issue, UnsupportedBodyGrammar(contract_role(envelope)))
          unsupported += 1
        }
        Ok(dependencies) => {
          accepted += 1
          for j in 0..<catalog_body_dependency_count(dependencies) {
            let dependency = catalog_body_dependency_at(dependencies, j).unwrap()
            let grammar = catalog_dependency_grammar(dependency).unwrap()
            assert_eq(catalog_grammar_cid(grammar), dependency.cid)
          }
          assert_true(
            physical_equal(catalog_body_contract(dependencies), envelope),
          )
          match catalog_body_admission(dependencies) {
            LookupFactsBody(_) | PushdownBody(_) =>
              abort("lookup admission is a separate owned branch")
            ValueBody(value) => {
              assert_true(
                physical_equal(body_dependency_contract(value), envelope),
              )
              assert_eq(catalog_body_dependency_count(dependencies), 1)
              assert_eq(
                catalog_body_dependency_at(dependencies, 0).unwrap().cid,
                body_dependency_at(value, 0).unwrap(),
              )
            }
            CarrierBody(schema) =>
              assert_true(
                physical_equal(carrier_schema_envelope(schema), envelope),
              )
            DataPolicyBody(policy) => {
              assert_true(
                physical_equal(data_policy_envelope(policy), envelope),
              )
              assert_eq(catalog_body_dependency_count(dependencies), 1)
              assert_eq(
                catalog_body_dependency_at(dependencies, 0).unwrap().cid,
                "sha256:123b23f425df95044e74f4fd4773e790f45a8443ebee5741fb0dabc76de24761",
              )
            }
          }
          assert_true(catalog_body_dependency_at(dependencies, -1) is None)
          assert_true(
            catalog_body_dependency_at(
              dependencies,
              catalog_body_dependency_count(dependencies),
            )
            is None,
          )
        }
      }
    }
    assert_eq((accepted, unsupported), (10, 7))
  }
}
