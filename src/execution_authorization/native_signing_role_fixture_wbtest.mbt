///|
// Native fixture input only: same two original rules, no Provider/key grant
// production. The malformed permutation is preserved as a typed refusal.
test "Native signing role Account fixture preserves canonical order and exact two tuples" {
  let original_permutation =
    #|{"version":"actql-execution-account-config/0.1","account_id":"operator","entries":[{"entry_id":"original-host-key-sign","outcome":"allow","principal":{"any_of":["host-signer"]},"connection":{"any_of":["host-cli"]},"resource":{"any_of":["key/host-attestation-2026"]},"operation":{"any_of":["sign"]},"exclusions":[]},{"entry_id":"independent-reviewer-resolve","outcome":"allow","principal":{"any_of":["reviewer"]},"connection":{"any_of":["review-cli"]},"resource":{"any_of":["run"]},"operation":{"any_of":["resolve"]},"exclusions":[]}]}
  let canonical =
    #|{"version":"actql-execution-account-config/0.1","account_id":"operator","entries":[{"entry_id":"independent-reviewer-resolve","outcome":"allow","principal":{"any_of":["reviewer"]},"connection":{"any_of":["review-cli"]},"resource":{"any_of":["run"]},"operation":{"any_of":["resolve"]},"exclusions":[]},{"entry_id":"original-host-key-sign","outcome":"allow","principal":{"any_of":["host-signer"]},"connection":{"any_of":["host-cli"]},"resource":{"any_of":["key/host-attestation-2026"]},"operation":{"any_of":["sign"]},"exclusions":[]}]}
  assert_eq(
    admit_account_configuration_json(original_permutation).map(_ => ()),
    Err(NonCanonicalOrder("$.entries[1].entry_id")),
  )
  let admitted = admit_account_configuration_json(canonical).unwrap()
  assert_eq(admitted.entry_count(), 2)
  assert_true(
    evaluate_account(admitted, {
      principal: "host-signer",
      connection: "host-cli",
      resource: "key/host-attestation-2026",
      operation: "sign",
    })
    is Allow(_),
  )
  assert_true(
    evaluate_account(admitted, {
      principal: "reviewer",
      connection: "review-cli",
      resource: "run",
      operation: "resolve",
    })
    is Allow(_),
  )
  for
    tuple in [
      {
        principal: "operator",
        connection: "cli",
        resource: "run",
        operation: "read",
      },
      {
        principal: "reviewer",
        connection: "review-cli",
        resource: "key/host-attestation-2026",
        operation: "sign",
      },
      {
        principal: "host-signer",
        connection: "host-cli",
        resource: "run",
        operation: "resolve",
      },
    ] {
    assert_true(evaluate_account(admitted, tuple) is Deny(_))
  }
}
