///|
test "Salesforce construction dimensions come from the same fully admitted observation" {
  let observation = local_catalog_test_observation()
  let body = catalog_observation_json(observation)
  let cid = observation.cid
  // Original fixture: Id/id and Name/string, no references or compound text.
  assert_eq(catalog_observation_construction_dimensions(observation), [2, 14])
  assert_eq(catalog_observation_json(observation), body)
  assert_eq(observation.cid, cid)
  let binding = local_catalog_test_binding()
  assert_true(
    catalog_observation_local_resource(observation, binding, "Account") is Ok(_),
  )
  assert_true(
    catalog_observation_local_resource(
      observation,
      { ..binding, connection_revision: "changed", },
      "Account",
    )
    is Err(_),
  )
}
