///|
test "lookup component admission does not silently interpret fact extensions" {
  let component =
    #|"lookup_capacity":{"version":"actql-lookup-capacity/0.1","completeness":"hard_limit_only","max_rows_per_key":2,"max_pages_per_request":3,"max_response_bytes_per_page":4}
  for text in ["{}", "{" + component + "}"] {
    for extension in [false, true] {
      let text = if extension {
        "{\"extension\":{\"cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"}" +
        (if text == "{}" { "}" } else { "," + component + "}" })
      } else {
        text
      }
      let contents = reference_fixture(
        bodies=Map([("carrier_facts", @json.parse(text))]),
      )
      let refs = check_catalog_references(contents, reference_caps()).unwrap()
      let admitted = check_lookup_capacities(refs, {
        max_work: 100000,
        max_facts: 10,
      }).unwrap()
      let facts = lookup_facts_at(admitted, 0).unwrap()
      let envelope = lookup_facts_envelope(facts)
      let result = check_lookup_body_dependencies(admitted, envelope)
      if extension {
        // Valid extensible facts are not a malformed lookup component. Their
        // remaining semantics simply have not been admitted by this interpreter.
        assert_true(result is Err(UnsupportedBodyGrammar("carrier_facts")))
      } else {
        let dependencies = result.unwrap()
        assert_true(
          physical_equal(catalog_body_contract(dependencies), envelope),
        )
        guard catalog_body_admission(dependencies) is LookupFactsBody(retained) else {
          abort("retained lookup facts")
        }
        assert_true(physical_equal(retained, facts))
        assert_eq(catalog_body_dependency_count(dependencies), 1)
        let dependency = catalog_body_dependency_at(dependencies, 0).unwrap()
        assert_eq(dependency.role, GoverningGrammar)
        assert_eq(
          dependency.cid,
          "sha256:b6dd6fb12235ad2a40a484d5229699bd674d4095932d81bc40eeaca604dcbf21",
        )
        for index in [-2147483648, -1, 1, 2147483647] {
          assert_true(catalog_body_dependency_at(dependencies, index) is None)
        }
      }
      let foreign_refs = check_catalog_references(
        reference_fixture(bodies=Map([("carrier_facts", @json.parse(text))])),
        reference_caps(),
      ).unwrap()
      let foreign = check_lookup_capacities(foreign_refs, {
        max_work: 100000,
        max_facts: 10,
      }).unwrap()
      assert_true(
        check_lookup_body_dependencies(foreign, envelope)
        is Err(ForeignEnvironment),
      )
      let registry = catalog_registry(reference_contents(refs))
      for i in 0..<contract_registry_usage(registry).2 {
        let other = contract_at(registry, i).unwrap()
        if contract_role(other) != "carrier_facts" {
          guard check_lookup_body_dependencies(admitted, other) is Err(issue) else {
            fail("wrong body kind admitted")
          }
          assert_eq(issue, UnsupportedBodyGrammar(contract_role(other)))
          assert_true(
            check_lookup_body_dependencies(foreign, other)
            is Err(ForeignEnvironment),
          )
        }
      }
    }
  }
}
