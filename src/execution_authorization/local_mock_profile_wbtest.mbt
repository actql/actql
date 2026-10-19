///|
fn mock_profile_subjects() -> LocalMockAccountSubjects {
  {
    account_id: "mock-account",
    principal: "local-operator",
    control_connection: "local-host",
    sources: [("salesforce", "Account"), ("snowflake", "usage_30d")],
    model_tasks: ["sha256:" + "a".repeat(64)],
    request_target: Some(("local-host", "mock-realization")),
    update_target: Some(("salesforce", "Account")),
    signing_key_resource: Some("key:reviewer"),
  }
}

///|
fn mock_profile_at(
  connection : String,
  resource : String,
  operation : String,
) -> AccessTuple {
  { principal: "local-operator", connection, resource, operation, }
}

///|
test "Local Mock profile and concrete configuration match independent canonical preimages" {
  // Independently authored profile/configuration objects and canonical SHA256,
  // not expectations regenerated from this implementation's emitted bytes.
  let profile = local_mock_profile_identity()
  assert_eq(profile.profile_id, "actql-local-mock")
  assert_eq(profile.profile_version, "0.1")
  assert_eq(
    profile.profile_cid,
    "sha256:fe8f88f3465a18456678bf9bf32943dcc4e4a8654b6d449f0c6af174fffd7e3a",
  )
  let wire = local_mock_account_configuration(mock_profile_subjects()).unwrap()
  let admitted = admit_account_configuration_json(wire).unwrap()
  assert_eq(
    admitted.configuration_cid(),
    "sha256:47fd6896d828109c3961e5183b1dfa1376aa1a1782fb454ca786601518d93f3a",
  )
  assert_eq(admitted.bootstrap_profile(), Some(profile))
  assert_true(
    bind_bootstrap_adoption(admitted, {
      record_id: "original-initialization",
      account_id: "mock-account",
      profile,
    })
    is Ok(_),
  )
  assert_true(
    bind_bootstrap_adoption(admitted, {
      record_id: "original-initialization",
      account_id: "other-account",
      profile,
    })
    is Err(AccountMismatch),
  )
}

///|
test "Local Mock reads inference request and key scopes remain finite and UPDATE delegates" {
  let config = admit_account_configuration_json(
    local_mock_account_configuration(mock_profile_subjects()).unwrap(),
  ).unwrap()
  for
    tuple in [
      mock_profile_at("salesforce", "Account", "read"),
      mock_profile_at("snowflake", "usage_30d", "read"),
      mock_profile_at("mock", "sha256:" + "a".repeat(64), "infer"),
      mock_profile_at("mock", "sha256:" + "a".repeat(64), "model_raw_capture"),
      mock_profile_at("local-host", "mock-realization", "write"),
      mock_profile_at("local-host", "run", "read"),
      mock_profile_at("local-host", "run", "resolve"),
      mock_profile_at("local-host", "key:reviewer", "sign"),
    ] {
    assert_true(evaluate_account(config, tuple) is Allow(_))
  }
  let update = mock_profile_at("salesforce", "Account", "effect")
  let outcome = evaluate_account(config, update)
  assert_true(outcome is Delegate(_))
  assert_eq(runtime_action_for(outcome), None)
  assert_true(
    bind_dispatch_authorization(
      config,
      update,
      EffectCommit,
      "sha256:" + "b".repeat(64),
      "sha256:" + "c".repeat(64),
    )
    is Err(UnresolvedDelegation),
  )
  for
    tuple in [
      mock_profile_at("salesforce", "Account", "write"),
      mock_profile_at("salesforce", "Contact", "read"),
      mock_profile_at("snowflake", "other_table", "read"),
      mock_profile_at("live", "sha256:" + "a".repeat(64), "infer"),
      mock_profile_at("mock", "sha256:" + "b".repeat(64), "infer"),
      mock_profile_at("local-host", "live-realization", "write"),
      mock_profile_at("local-host", "other-key", "sign"),
      mock_profile_at("credential", "issuer", "issue"),
      { ..update, principal: "other-operator", },
    ] {
    assert_true(evaluate_account(config, tuple) is Deny(NoMatch))
  }
}

///|
test "Local Mock missing signer does not grant signing or block permitted reads" {
  let subjects = { ..mock_profile_subjects(), signing_key_resource: None, }
  let config = admit_account_configuration_json(
    local_mock_account_configuration(subjects).unwrap(),
  ).unwrap()
  assert_true(
    evaluate_account(config, mock_profile_at("salesforce", "Account", "read"))
    is Allow(_),
  )
  assert_true(
    evaluate_account(
      config,
      mock_profile_at("local-host", "key:reviewer", "sign"),
    )
    is Deny(NoMatch),
  )
  assert_true(
    evaluate_account_state(
      Missing,
      mock_profile_at("salesforce", "Account", "read"),
    )
    is Deny(ConfigurationMissing),
  )
}

///|
test "Local Mock provenance does not override a current operator restriction" {
  let original = decode_account_configuration_json(
    local_mock_account_configuration(mock_profile_subjects()).unwrap(),
  ).unwrap()
  let before = admit_account_configuration(original).unwrap()
  let entries = original.entries.map(entry => {
    if entry.entry_id == "mock-read-0" {
      { ..entry, outcome: Deny, }
    } else {
      entry
    }
  })
  let current = admit_account_configuration({ ..original, entries, }).unwrap()
  let tuple = mock_profile_at("salesforce", "Account", "read")
  assert_true(evaluate_account(before, tuple) is Allow(_))
  assert_true(evaluate_account(current, tuple) is Deny(Explicit("mock-read-0")))
  assert_eq(current.bootstrap_profile(), before.bootstrap_profile())
  assert_true(current.configuration_cid() != before.configuration_cid())
  let admitted = bind_dispatch_authorization(
    before,
    tuple,
    Acquisition,
    "sha256:" + "b".repeat(64),
    "sha256:" + "c".repeat(64),
  ).unwrap()
  assert_false(
    dispatch_authorization_matches(
      admitted,
      current,
      tuple,
      Acquisition,
      "sha256:" + "b".repeat(64),
      "sha256:" + "c".repeat(64),
    ),
  )
}

///|
test "Local Mock profile refuses malformed repeated unselected and excessive subjects" {
  let original = mock_profile_subjects()
  for
    subjects in [
      { ..original, principal: "", },
      {
        ..original,
        sources: [("salesforce", "Account"), ("salesforce", "Account")],
      },
      {
        ..original,
        model_tasks: ["sha256:" + "a".repeat(64), "sha256:" + "a".repeat(64)],
      },
      { ..original, model_tasks: ["not-a-task-cid"], },
      { ..original, model_tasks: Array::make(65, "sha256:" + "a".repeat(64)), },
      { ..original, sources: Array::make(129, ("source", "resource")), },
      { ..original, update_target: Some(("salesforce", "Contact")), },
      { ..original, signing_key_resource: Some(""), },
      { ..original, request_target: Some(("salesforce", "Account")), },
    ] {
    assert_true(
      local_mock_account_configuration(subjects) is Err(InvalidSubjects),
    )
  }
}
