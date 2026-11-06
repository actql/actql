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

///|
test "Salesforce retained metadata values stay literal while normalized keys do not escape" {
  let bytes = @utf8.encode(
    (
      #|{"na\u006de":"Account","fields":[{"name":"Id","type":"id"},{"name":"Kind__c","type":"e\u0301\ud83d\ude00\r\n"}]}
    ),
  )
  let resource = project_describe(bytes, "Account", local_catalog_test_limits()).unwrap()
  // JsonString normalizes keys only. The returned metadata owns literal
  // values, including decomposed text and CR/LF, not normalized key strings.
  assert_eq(resource.fields[1].native_type, "e\u{301}😀\r\n")
  let mut text = resource.name.length() + resource.response_sha256.length()
  for field in resource.fields {
    text += field.name.length() + field.native_type.length()
    for reference in field.reference_to {
      text += reference.length()
    }
    if field.compound_field_name is Some(name) {
      text += name.length()
    }
  }
  // Output values plus a complete possible substring source backing and the
  // independently computed SHA fit the closed, input-bound text envelope.
  assert_true(text + bytes.length() <= 2 * bytes.length() + 71)
}
