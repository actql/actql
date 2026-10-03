///|
// Independently authored canonical inputs and Node/Python SHA-256 identities.
// The expected wire and references do not come from product serialization.
test "effective and response policy dependencies preserve exact identities and closure" {
  let response = "{\"classification\":\"public\",\"minimum_classification\":null,\"source_data_policy_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"source_ref\":\"connector://fixture/rows\",\"source_view_contract_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"version\":\"actql-source-response-policy/0.1\"}"
  let effective = "{\"classification\":\"unknown\",\"source_data_policy_cids\":[\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"sha256:2222222222222222222222222222222222222222222222222222222222222222\"],\"source_response_policy_cids\":[\"sha256:265c083ea20b8e64985c3b6f945e0ee9b6eb941aae6c5acd243cd082fe0deb23\"],\"unknown_provenance\":true,\"version\":\"actql-effective-data-policy/0.1\"}"
  let response_body = admit_captured_effect_dependency_body(
    "data_policy",
    Some(
      "sha256:265c083ea20b8e64985c3b6f945e0ee9b6eb941aae6c5acd243cd082fe0deb23",
    ),
    response,
    10000,
    1000,
    32,
  ).unwrap()
  let effective_body = admit_captured_effect_dependency_body(
    "data_policy",
    Some(
      "sha256:0af844e27e3b83484a035029e215d6d53bd002bcec552a508e79acee18e49325",
    ),
    effective,
    10000,
    1000,
    32,
  ).unwrap()
  assert_eq(response_body.node.references.length(), 2)
  assert_eq(effective_body.node.references.length(), 3)
  assert_eq(
    effective_body.node.references[2].identity,
    "sha256:265c083ea20b8e64985c3b6f945e0ee9b6eb941aae6c5acd243cd082fe0deb23",
  )
  assert_true(
    validate_captured_effect_dependency_bodies(
      [effective_body, response_body],
      [effective_body],
      0,
      {
        max_entries: 10,
        max_total_bytes: 10000,
        max_depth: 8,
        max_references: 20,
      },
    )
    is Err(MissingDependency),
  )
  assert_true(
    admit_captured_effect_dependency_body(
      "data_policy",
      Some(
        "sha256:0af844e27e3b83484a035029e215d6d53bd002bcec552a508e79acee18e49325",
      ),
      effective.replace(old="unknown", new="public"),
      10000,
      1000,
      32,
    )
    is Err(InvalidBody),
  )
  // Without an asserted CID, shape/ordering checks must still reject these.
  for
    invalid in [
      effective.replace(
        old="1111111111111111111111111111111111111111111111111111111111111111",
        new="3333333333333333333333333333333333333333333333333333333333333333",
      ),
      effective.replace(
        old="2222222222222222222222222222222222222222222222222222222222222222",
        new="1111111111111111111111111111111111111111111111111111111111111111",
      ),
      effective.replace(old="true", new="null"),
      response.replace(old="null", new="true"),
      response + " ",
    ] {
    assert_true(
      admit_captured_effect_dependency_body(
        "data_policy",
        None,
        invalid,
        10000,
        1000,
        32,
      )
      is Err(InvalidBody),
    )
  }
  assert_true(
    admit_captured_effect_dependency_body(
      "data_policy",
      None,
      effective,
      32,
      1000,
      32,
    )
    is Err(InvalidBody),
  )
}
