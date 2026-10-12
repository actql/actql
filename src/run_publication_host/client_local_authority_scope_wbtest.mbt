///|
fn local_scope_test_account() -> @authorization.AdmittedAccountConfiguration {
  // Independent existing Account corpus input and its frozen identity.
  @authorization.admit_account_configuration_json(
    "{\"version\":\"actql-execution-account-config/0.1\",\"account_id\":\"local:operator\",\"entries\":[{\"entry_id\":\"files\",\"outcome\":\"allow\",\"principal\":{\"any_of\":[\"operator\"]},\"connection\":{\"any_of\":[\"local-files\"]},\"resource\":{\"all\":true},\"operation\":{\"all\":true},\"exclusions\":[]}]}",
  ).unwrap()
}

///|
let local_scope_test_adoption : String = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

///|
test "shared Local scope retains the original Native preimage and grants no authority" {
  let account = local_scope_test_account()
  assert_eq(
    account.configuration_cid(),
    "sha256:e240525257340428cc9117b0b0e84a000996791f43b230abdb553e55223bec12",
  )
  let body = client_local_authority_scope_body(
    account, local_scope_test_adoption, "operator", "local",
  ).unwrap()
  assert_eq(
    body, b"{\"account_configuration_cid\":\"sha256:e240525257340428cc9117b0b0e84a000996791f43b230abdb553e55223bec12\",\"adoption_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"connection\":\"local\",\"principal\":\"operator\",\"version\":\"actql-native-local-authority-scope/0.1\"}",
  )
  assert_eq(
    @sha.hex(body),
    "c435610485b439971dc17e8d382d82f3cc45ec690a4d3381ef616a275e4b3cfe",
  )
  assert_true(
    @authorization.evaluate_account(account, {
      principal: "operator",
      connection: "local",
      resource: "run",
      operation: "publish",
    })
    is @authorization.Deny(_),
  )
}

///|
test "shared Local scope preserves distinct Unicode and original CRLF" {
  // Fixed hashes independently calculated over literal original preimages.
  for
    (principal, expected) in [
      (
        "e\u{0301}", "be3287541fde119d60e5835a79107be64b2fea49ec5e2b4341cd1054095f3cb7",
      ),
      ("é", "ba53cc6b37d4c3e7989943e4da7bc4908664d1de72f9852091bf9459a350a6e2"),
    ] {
    let body = client_local_authority_scope_body(
      local_scope_test_account(),
      local_scope_test_adoption,
      principal,
      "line\r\nend",
    ).unwrap()
    assert_eq(@sha.hex(body), expected)
  }
}

///|
test "shared Local scope keeps original principal and connection limits" {
  for
    (principal, connection) in [
      ("", "local"),
      ("operator", ""),
      ("x".repeat(513), "local"),
      ("operator", "x".repeat(513)),
    ] {
    assert_true(
      client_local_authority_scope_body(
        local_scope_test_account(),
        local_scope_test_adoption,
        principal,
        connection,
      )
      is Err(InvalidInput),
    )
  }
  assert_true(
    client_local_authority_scope_body(
      local_scope_test_account(),
      local_scope_test_adoption,
      "x".repeat(512),
      "x".repeat(512),
    )
    is Ok(_),
  )
}

///|
test "shared Local scope separates changed adoption account and caller material" {
  let account = local_scope_test_account()
  let original = client_local_authority_scope_body(
    account, local_scope_test_adoption, "operator", "local",
  ).unwrap()
  let other = @authorization.admit_account_configuration_json(
    "{\"version\":\"actql-execution-account-config/0.1\",\"account_id\":\"foreign\",\"entries\":[]}",
  ).unwrap()
  for
    body in [
      client_local_authority_scope_body(
        account,
        "sha256:" + "b".repeat(64),
        "operator",
        "local",
      ).unwrap(),
      client_local_authority_scope_body(
        other, local_scope_test_adoption, "operator", "local",
      ).unwrap(),
      client_local_authority_scope_body(
        account, local_scope_test_adoption, "foreign", "local",
      ).unwrap(),
      client_local_authority_scope_body(
        account, local_scope_test_adoption, "operator", "remote",
      ).unwrap(),
    ] {
    assert_true(body != original)
  }
}
