///|
fn standard_profile_subjects() -> LocalStandardAccountSubjects {
  {
    account_id: "local-account",
    principal: "local-operator",
    control_connection: "local-host",
    configured_connections: ["files", "crm"],
    model_tasks: [("provider", "sha256:" + "a".repeat(64))],
    request_target: Some(("local-host", "original-realization")),
    signing_key_resource: None,
  }
}

///|
fn standard_at(
  connection : String,
  resource : String,
  operation : String,
) -> AccessTuple {
  { principal: "local-operator", connection, resource, operation, }
}

///|
test "standard Local bootstrap covers pure configured reads registered Tasks and delegated Effects" {
  let config = admit_account_configuration_json(
    local_standard_account_configuration(standard_profile_subjects()).unwrap(),
  ).unwrap()
  for
    tuple in [
      standard_at("local-host", "run", "submit"),
      standard_at("local-host", "run", "publish"),
      standard_at("local-host", "result/main", "read"),
      standard_at("local-host", "result/authored-name", "read"),
      standard_at("local-host", "original-realization", "write"),
      standard_at("files", "future-configured-resource", "read"),
      standard_at("crm", "Account", "read"),
      standard_at("provider", "sha256:" + "a".repeat(64), "infer"),
      standard_at("provider", "sha256:" + "a".repeat(64), "model_raw_capture"),
    ] {
    assert_true(evaluate_account(config, tuple) is Allow(_))
  }
  for
    tuple in [
      standard_at("crm", "Account", "effect"),
      standard_at("other", "another-target", "effect"),
    ] {
    assert_true(evaluate_account(config, tuple) is Delegate(_))
    assert_eq(runtime_action_for(evaluate_account(config, tuple)), None)
  }
  for
    tuple in [
      standard_at("foreign", "Account", "read"),
      standard_at("provider", "sha256:" + "b".repeat(64), "infer"),
      standard_at("foreign", "sha256:" + "a".repeat(64), "infer"),
      standard_at("crm", "Account", "write"),
      standard_at("local-host", "key:reviewer", "sign"),
    ] {
    assert_true(evaluate_account(config, tuple) is Deny(NoMatch))
  }
  assert_true(
    evaluate_account(config, {
      ..standard_at("files", "x", "read"),
      principal: "foreign",
    })
    is Deny(NoMatch),
  )
}

///|
test "standard profile has no implicit adoption or authored Account merge" {
  let config = admit_account_configuration_json(
    local_standard_account_configuration(standard_profile_subjects()).unwrap(),
  ).unwrap()
  let profile = local_standard_profile_identity()
  assert_eq(
    profile.profile_cid,
    "sha256:8c28b41c2fc824e43c77de4726337661b651287d2ac627770dc106e972afd60e",
  )
  assert_eq(
    config.configuration_cid(),
    "sha256:8f48bc9c35f800722a1d50815c282d38d05ef80edeb17e023c8324cc2bdfaa0d",
  )
  assert_eq(config.bootstrap_profile(), Some(profile))
  assert_true(
    bind_bootstrap_adoption(config, {
      record_id: "original-initialization",
      account_id: "foreign",
      profile,
    })
    is Err(AccountMismatch),
  )
  assert_true(
    bind_bootstrap_adoption(config, {
      record_id: "original-initialization",
      account_id: "local-account",
      profile,
    })
    is Ok(_),
  )
  let explicit = admit_account_configuration({
    account_id: "local-account",
    bootstrap: None,
    entries: [
      local_standard_entry(
        "operator-deny",
        standard_profile_subjects(),
        All,
        All,
        ["read"],
        Deny,
      ),
    ],
  }).unwrap()
  assert_true(
    evaluate_account(explicit, standard_at("files", "x", "read"))
    is Deny(Explicit("operator-deny")),
  )
  assert_true(
    evaluate_account(explicit, standard_at("local-host", "run", "submit"))
    is Deny(NoMatch),
  )
}

///|
test "standard bootstrap rejects malformed duplicate and oversized subjects" {
  let subjects = standard_profile_subjects()
  for
    changed in [
      { ..subjects, account_id: "", },
      { ..subjects, principal: "", },
      { ..subjects, control_connection: "", },
      { ..subjects, configured_connections: ["files", "files"], },
      { ..subjects, configured_connections: [""], },
      { ..subjects, configured_connections: Array::make(129, "files"), },
      { ..subjects, model_tasks: [("provider", "not-a-cid")], },
      { ..subjects, model_tasks: [("", "sha256:" + "a".repeat(64))], },
      { ..subjects, model_tasks: subjects.model_tasks + subjects.model_tasks, },
      { ..subjects, request_target: Some(("", "x")), },
      { ..subjects, signing_key_resource: Some(""), },
    ] {
    assert_eq(
      local_standard_account_configuration(changed),
      Err(InvalidSubjects),
    )
  }
}
