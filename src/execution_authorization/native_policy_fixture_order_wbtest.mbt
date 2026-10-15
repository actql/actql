///|
// The old Native positive fixture is retained as an independent refusal.
let native_policy_fixture_old_order : String =
  #|{"version":"actql-execution-account-config/0.1","account_id":"operator","entries":[{"entry_id":"explicit-policy-operations","outcome":"allow","principal":{"any_of":["operator"]},"connection":{"any_of":["cli"]},"resource":{"any_of":["run","result/answer"]},"operation":{"any_of":["submit","read"]},"exclusions":[]}]}

///|
let native_policy_fixture_canonical_order : String =
  #|{"version":"actql-execution-account-config/0.1","account_id":"operator","entries":[{"entry_id":"explicit-policy-operations","outcome":"allow","principal":{"any_of":["operator"]},"connection":{"any_of":["cli"]},"resource":{"any_of":["result/answer","run"]},"operation":{"any_of":["read","submit"]},"exclusions":[]}]}

///|
test "Native policy fixture original selector permutations remain NonCanonicalOrder refusals" {
  assert_eq(
    admit_account_configuration_json(native_policy_fixture_old_order).map(_ => {
      ()
    }),
    Err(NonCanonicalOrder("$.entries[0].resource.any_of[1]")),
  )
  let operations_only = native_policy_fixture_old_order.replace(
    old="[\"run\",\"result/answer\"]",
    new="[\"result/answer\",\"run\"]",
  )
  assert_eq(
    admit_account_configuration_json(operations_only).map(_ => ()),
    Err(NonCanonicalOrder("$.entries[0].operation.any_of[1]")),
  )
}

///|
test "Canonical Native policy fixture keeps exactly its original resource and operation sets" {
  let configuration = admit_account_configuration_json(
    native_policy_fixture_canonical_order,
  ).unwrap()
  for resource in ["result/answer", "run"] {
    for operation in ["read", "submit"] {
      assert_true(
        evaluate_account(configuration, {
          principal: "operator",
          connection: "cli",
          resource,
          operation,
        })
        is Allow(_),
      )
    }
  }
}
