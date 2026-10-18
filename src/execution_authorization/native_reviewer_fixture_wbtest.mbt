///|
// Preserve the exact malformed predecessor as a rejection vector. The two
// original role tuples are unchanged; the existing Account Owner requires
// entry_id order independently of a Native fixture's file or installation.
test "Native Reviewer fixture retains two independent roles and rejects the original entry permutation" {
  let original_permutation =
    #|{"version":"actql-execution-account-config/0.1","account_id":"operator","entries":[{"entry_id":"original-client-read","outcome":"allow","principal":{"any_of":["operator"]},"connection":{"any_of":["cli"]},"resource":{"any_of":["run"]},"operation":{"any_of":["read"]},"exclusions":[]},{"entry_id":"independent-reviewer-resolve","outcome":"allow","principal":{"any_of":["reviewer"]},"connection":{"any_of":["review-cli"]},"resource":{"any_of":["run"]},"operation":{"any_of":["resolve"]},"exclusions":[]}]}
  let canonical =
    #|{"version":"actql-execution-account-config/0.1","account_id":"operator","entries":[{"entry_id":"independent-reviewer-resolve","outcome":"allow","principal":{"any_of":["reviewer"]},"connection":{"any_of":["review-cli"]},"resource":{"any_of":["run"]},"operation":{"any_of":["resolve"]},"exclusions":[]},{"entry_id":"original-client-read","outcome":"allow","principal":{"any_of":["operator"]},"connection":{"any_of":["cli"]},"resource":{"any_of":["run"]},"operation":{"any_of":["read"]},"exclusions":[]}]}
  assert_eq(
    admit_account_configuration_json(original_permutation).map(_ => ()),
    Err(NonCanonicalOrder("$.entries[1].entry_id")),
  )
  let admitted = admit_account_configuration_json(canonical).unwrap()
  assert_eq(admitted.entry_count(), 2)
  let allowed : Array[AccessTuple] = [
    {
      principal: "operator",
      connection: "cli",
      resource: "run",
      operation: "read",
    },
    {
      principal: "reviewer",
      connection: "review-cli",
      resource: "run",
      operation: "resolve",
    },
  ]
  for tuple in allowed {
    assert_true(evaluate_account(admitted, tuple) is Allow(_))
  }
  let denied : Array[AccessTuple] = [
    {
      principal: "operator",
      connection: "cli",
      resource: "run",
      operation: "resolve",
    },
    {
      principal: "reviewer",
      connection: "review-cli",
      resource: "run",
      operation: "read",
    },
    {
      principal: "operator",
      connection: "review-cli",
      resource: "run",
      operation: "read",
    },
    {
      principal: "reviewer",
      connection: "cli",
      resource: "run",
      operation: "resolve",
    },
  ]
  for tuple in denied {
    assert_true(evaluate_account(admitted, tuple) is Deny(_))
  }
}
