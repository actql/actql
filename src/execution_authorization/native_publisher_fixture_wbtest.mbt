///|
// The Native fixture producer must use the existing Account Owner's lexical
// ordering. Core String Compare is shortlex and is not the wire contract.
test "Native publisher Account fixtures preserve lexical entry order and original permissions" {
  let body = "{\"version\":\"actql-execution-account-config/0.1\",\"account_id\":\"operator\",\"entries\":[{\"entry_id\":\"publish\",\"outcome\":\"allow\",\"principal\":{\"any_of\":[\"operator\"]},\"connection\":{\"any_of\":[\"cli\"]},\"resource\":{\"any_of\":[\"run\"]},\"operation\":{\"any_of\":[\"publish\"]},\"exclusions\":[]},{\"entry_id\":\"submit\",\"outcome\":\"allow\",\"principal\":{\"any_of\":[\"operator\"]},\"connection\":{\"any_of\":[\"cli\"]},\"resource\":{\"any_of\":[\"run\"]},\"operation\":{\"any_of\":[\"submit\"]},\"exclusions\":[]}]}"
  let admitted = admit_account_configuration_json(body).unwrap()
  for operation in ["publish", "submit"] {
    assert_true(
      evaluate_account(admitted, {
        principal: "operator",
        connection: "cli",
        resource: "run",
        operation,
      })
      is Allow(_),
    )
  }
  assert_true(
    evaluate_account(admitted, {
      principal: "operator",
      connection: "cli",
      resource: "run",
      operation: "read",
    })
    is Deny(_),
  )
}

///|
test "Native publisher Account preserves the original unsorted refusal and submit-only isolation" {
  assert_eq(
    admit_account_configuration_json(
      "{\"version\":\"actql-execution-account-config/0.1\",\"account_id\":\"operator\",\"entries\":[{\"entry_id\":\"submit\",\"outcome\":\"allow\",\"principal\":{\"any_of\":[\"operator\"]},\"connection\":{\"any_of\":[\"cli\"]},\"resource\":{\"any_of\":[\"run\"]},\"operation\":{\"any_of\":[\"submit\"]},\"exclusions\":[]},{\"entry_id\":\"publish\",\"outcome\":\"allow\",\"principal\":{\"any_of\":[\"operator\"]},\"connection\":{\"any_of\":[\"cli\"]},\"resource\":{\"any_of\":[\"run\"]},\"operation\":{\"any_of\":[\"publish\"]},\"exclusions\":[]}]}",
    ).map(_ => ()),
    Err(NonCanonicalOrder("$.entries[1].entry_id")),
  )
  let admitted = admit_account_configuration_json(
    "{\"version\":\"actql-execution-account-config/0.1\",\"account_id\":\"operator\",\"entries\":[{\"entry_id\":\"submit\",\"outcome\":\"allow\",\"principal\":{\"any_of\":[\"operator\"]},\"connection\":{\"any_of\":[\"cli\"]},\"resource\":{\"any_of\":[\"run\"]},\"operation\":{\"any_of\":[\"submit\"]},\"exclusions\":[]}]}",
  ).unwrap()
  assert_true(
    evaluate_account(admitted, {
      principal: "operator",
      connection: "cli",
      resource: "run",
      operation: "submit",
    })
    is Allow(_),
  )
  assert_true(
    evaluate_account(admitted, {
      principal: "operator",
      connection: "cli",
      resource: "run",
      operation: "publish",
    })
    is Deny(_),
  )
}
